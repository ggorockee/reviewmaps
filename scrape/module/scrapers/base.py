from __future__ import annotations
from abc import ABC, abstractmethod
from typing import List
import pandas as pd
from selenium import webdriver
from selenium.webdriver.chrome.options import Options as ChromeOptions
import sys, os, time

from module.config import Settings
from module.logger import get_logger
from module.db import get_engine, upsert_rows_psycopg2

log = get_logger("scraper.base")

class BaseScraper(ABC):
    """모든 스크레이퍼의 기반이 되는 추상 클래스"""

    @property
    @abstractmethod
    def PLATFORM_NAME(self) -> str:
        """스크레이퍼가 수집하는 플랫폼의 이름 (예: '인플렉서', '리뷰노트')"""
        pass

    @property
    @abstractmethod
    def BASE_URL(self) -> str:
        """스크레이핑 대상 사이트의 기본 URL"""
        pass

    RESULT_TABLE_COLUMNS = [
        "platform", "company", "company_link", "offer",
        "apply_from", "apply_deadline", "review_deadline", "search_text",
        "address", "lat", "lng", "img_url",
    ]
    CONFLICT_COLS = ["platform", "company", "offer"]

    def __init__(self, settings: Settings):
        self.settings = settings
        self.engine = get_engine(settings)
        self.driver = self._init_driver()

    def _init_driver(self) -> webdriver.Chrome:
        log.info(f"[{self.PLATFORM_NAME}] ChromeDriver 초기화…")
        options = ChromeOptions()
        if sys.platform.startswith("linux"):
            options.binary_location = os.getenv("CHROME_BIN", "/usr/bin/chromium")
        if self.settings.headless:
            options.add_argument("--headless=new")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_experimental_option("excludeSwitches", ["enable-logging"])
        return webdriver.Chrome(options=options)

    @abstractmethod
    def _search(self, keyword: str):
        """사이트별 검색 로직 (반드시 구현 필요)"""
        pass

    @abstractmethod
    def _extract_dataframe(self, search_text: str) -> pd.DataFrame:
        """사이트별 데이터 추출 로직 (반드시 구현 필요)"""
        pass

    def _parse_dates(self, df: pd.DataFrame) -> pd.DataFrame:
        from pandas import Timestamp, to_datetime
        current_year = str(Timestamp.now(tz="Asia/Seoul").year)

        for col in ["apply_from", "apply_deadline", "review_deadline"]:
            if col in df.columns and not df[col].isnull().all():
                s = df[col].dropna().astype(str).str.lstrip("~").str.strip()
                s_with_year = current_year + "/" + s
                dt_series = to_datetime(s_with_year, format="%Y/%m/%d", errors="coerce")
                dt_series = dt_series.dt.tz_localize("Asia/Seoul")
                df[col] = dt_series.astype("object").where(dt_series.notna(), None)
        return df

    def _clean_dataframe(self, df: pd.DataFrame) -> pd.DataFrame:
        if df.empty: return df
        df = df.copy()
        
        # [수정] 날짜 파싱 로직을 별도 메서드로 분리하여 호출
        df = self._parse_dates(df)

        for c in self.RESULT_TABLE_COLUMNS:
            if c not in df.columns:
                df[c] = None
        
        return df[self.RESULT_TABLE_COLUMNS]


    def _assign_platform(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        데이터프레임에 플랫폼 이름을 할당합니다.
        기본 동작은 PLATFORM_NAME을 일괄 지정하는 것입니다.
        """
        df['platform'] = self.PLATFORM_NAME
        return df



    def run_once(self, keywords: List[str], table_name: str) -> int:
        self.driver.get(self.BASE_URL)
        all_df = []
        for kw in keywords:
            try:
                self._search(kw)
                part = self._extract_dataframe(search_text=kw)
                if not part.empty:
                    all_df.append(part)
                time.sleep(1)
            except Exception as e:
                log.error(f"[{self.PLATFORM_NAME}] 키워드 '{kw}' 처리 중 오류: {e}")
                self.driver.get(self.BASE_URL)

        if not all_df:
            log.warning(f"[{self.PLATFORM_NAME}] 수집된 데이터가 없습니다.")
            return 0
        
        final_df = pd.concat(all_df, ignore_index=True)
        final_df = self._assign_platform(final_df)
        final_df = self._clean_dataframe(final_df)

        log.info(f"[{self.PLATFORM_NAME}] 중복 제거 전 {len(final_df)}건")
        final_df.sort_values(by='apply_deadline', ascending=False, na_position='last', inplace=True)
        final_df.drop_duplicates(subset=self.CONFLICT_COLS, keep='first', inplace=True)
        log.info(f"[{self.PLATFORM_NAME}] 중복 제거 후 {len(final_df)}건")
        
        affected = upsert_rows_psycopg2(
            self.engine, table=table_name, rows=final_df,
            conflict_cols=self.CONFLICT_COLS,
            update_cols=[c for c in self.RESULT_TABLE_COLUMNS if c not in self.CONFLICT_COLS],
        )
        return affected

    def close(self):
        try: self.driver.quit()
        except Exception: pass

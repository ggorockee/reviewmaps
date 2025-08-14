from __future__ import annotations
from typing import List, Optional
import time
import pandas as pd

# Selenium
from selenium import webdriver
from selenium.webdriver.chrome.service import Service as ChromeService
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options as ChromeOptions
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager
from selenium.common.exceptions import TimeoutException, NoSuchElementException


from .config import Settings
from .logger import get_logger
from .db import get_engine, upsert_rows_psycopg2

log = get_logger("scraper")

class AdvancedScraper:
    """키워드로 검색 → 표 추출 → 정제 → DB UPSERT"""

    RESULT_TABLE_COLUMNS = [
        "platform","company","company_link","offer",
        "apply_deadline","review_deadline","search_text",
        "address","lat","lng","img_url",
    ]
    CONFLICT_COLS = ["platform", "company", "offer"]

    def __init__(self, settings: Settings):
        self.settings = settings
        self.engine = get_engine(settings)
        self.driver = self._init_driver()

    def _init_driver(self) -> webdriver.Chrome:
        log.info("ChromeDriver 초기화…")
        options = ChromeOptions()
        # 컨테이너 chromium 바이너리 지정
        options.binary_location = os.getenv("CHROME_BIN", "/usr/bin/chromium")
        if self.settings.headless:
            options.add_argument("--headless=new")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_experimental_option("excludeSwitches", ["enable-logging"])
        # Service를 넘기지 않으면 Selenium Manager가 드라이버를 자동 설치/선택
        return webdriver.Chrome(options=options)

    # ---------- 브라우저 조작 ----------
    def _go(self, path: str = "/"):
        url = f"{self.settings.base_url}{path}"
        log.info(f"이동: {url}")
        self.driver.get(url)

    def _search(self, keyword: str):
        log.info(f"검색: {keyword}")
        try:
            wait = WebDriverWait(self.driver, 10)
            search_box = wait.until(EC.presence_of_element_located(
                (By.CSS_SELECTOR, "#root > div > section.main > div.input_container > input[type=text]")
            ))
            search_box.clear()
            search_box.send_keys(keyword)
            self.driver.find_element(By.CSS_SELECTOR, "#search").click()
            wait.until(EC.presence_of_element_located((By.ID, "result_table")))
        except TimeoutException:
            log.warning("검색 결과 로딩 지연")
        except NoSuchElementException as e:
            log.error(f"검색 요소 없음: {e}")
            raise

    def _extract_dataframe(self, search_text: Optional[str]) -> pd.DataFrame:
        try:
            wait = WebDriverWait(self.driver, 10)
            tbody = wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, "#result_table > tbody")))
            rows = tbody.find_elements(By.TAG_NAME, "tr")
            data = []
            for r in rows:
                tds = r.find_elements(By.TAG_NAME, "td")
                if len(tds) < 5:
                    continue
                platform = tds[0].text.strip()
                company = tds[1].text.strip()
                offer = tds[2].text.strip()
                apply_deadline = tds[3].text.strip()
                review_deadline = tds[4].text.strip()
                try:
                    company_link = tds[1].find_element(By.TAG_NAME, "a").get_attribute("href")
                except NoSuchElementException:
                    company_link = None
                data.append({
                    "platform": platform,
                    "company": company,
                    "company_link": company_link,
                    "offer": offer,
                    "apply_deadline": apply_deadline,
                    "review_deadline": review_deadline,
                    "search_text": search_text,
                })
            return self._clean_dataframe(pd.DataFrame(data))
        except TimeoutException:
            log.warning("테이블 로딩 실패 (Timeout)")
            return pd.DataFrame()

    # ---------- 정제 ----------
    def _clean_dataframe(self, df: pd.DataFrame) -> pd.DataFrame:
        if df.empty:
            return df

        df = df.copy()

        # 텍스트 컬럼 정리
        for c in ["platform", "company", "offer"]:
            if c in df.columns:
                df[c] = df[c].astype(str).str.strip().fillna("")

        # 날짜 → aware datetime (Asia/Seoul) → None 처리
        from pandas import Timestamp, to_datetime
        current_year = Timestamp.now(tz="Asia/Seoul").year

        for c in ["apply_deadline", "review_deadline"]:
            if c in df.columns:
                s = to_datetime(f"{current_year}/" + df[c].astype(str).str.lstrip("~").str.strip(),
                                format="%Y/%m/%d", errors="coerce")
                s = s.dt.tz_localize("Asia/Seoul")
                df[c] = s.astype("object").where(s.notna(), None)

        # DB 전용 기본 컬럼 추가
        for c in ["address", "lat", "lng", "img_url"]:
            if c not in df.columns:
                df[c] = None

        # 컬럼 순서 고정
        df = df[[*self.RESULT_TABLE_COLUMNS]]
        # 중복 제거 (키 기준)
        df.drop_duplicates(subset=self.CONFLICT_COLS, keep="last", inplace=True)
        return df

    # ---------- 실행 ----------
    def run_once(self, keywords: List[str], table_name: str) -> int:
        self._go("/")
        all_df = []
        for kw in keywords:
            self._search(kw)
            part = self._extract_dataframe(search_text=kw)
            if not part.empty:
                all_df.append(part)
            # 메인으로 되돌아갈 필요가 없으면 주석 처리 OK
            self._go("/")
            time.sleep(1)

        if not all_df:
            log.warning("수집된 데이터가 없습니다.")
            return 0

        final_df = pd.concat(all_df, ignore_index=True)
        # UPSERT
        affected = upsert_rows_psycopg2(
            self.engine,
            table=table_name,
            rows=final_df,
            conflict_cols=self.CONFLICT_COLS,
            update_cols=[c for c in self.RESULT_TABLE_COLUMNS if c not in self.CONFLICT_COLS],
        )
        return affected

    def close(self):
        try:
            self.driver.quit()
        except Exception:
            pass

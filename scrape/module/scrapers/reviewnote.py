from __future__ import annotations
from typing import List
import pandas as pd
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException, NoSuchElementException
import time
import re


from .base import BaseScraper
from module.logger import get_logger
from module.db import get_engine, upsert_rows_psycopg2

log = get_logger("scraper.reviewnote")

class ReviewNoteScraper(BaseScraper):
    PLATFORM_NAME = "리뷰노트"
    BASE_URL = "https://www.reviewnote.co.kr/campaigns"

    def _parse_dates(self, df: pd.DataFrame) -> pd.DataFrame:
        """리뷰노트의 날짜 형식('M/D (요일)')을 파싱합니다."""
        from pandas import Timestamp, to_datetime
        current_year = str(Timestamp.now(tz="Asia/Seoul").year)

        for col in ["apply_from", "apply_deadline", "review_deadline"]:
            if col in df.columns and not df[col].isnull().all():
                # '8/29 (금)' -> '8/29' 로 (요일) 부분을 제거
                s = df[col].dropna().astype(str).str.split(' ').str[0]
                
                s_with_year = current_year + "/" + s
                dt_series = to_datetime(s_with_year, format="%Y/%m/%d", errors="coerce")
                dt_series = dt_series.dt.tz_localize("Asia/Seoul")
                df[col] = dt_series.astype("object").where(dt_series.notna(), None)
        return df

    def _search(self, keyword: str):
        # 이 스크레이퍼는 키워드 검색 대신 run_once에서 직접 지역 필터링을 수행합니다.
        pass

    def _extract_dataframe(self, search_text: str) -> pd.DataFrame:
        # 이 스크레이퍼는 run_once에서 모든 로직을 처리합니다.
        return pd.DataFrame()
    
    def _extract_detail_data(self, wait: WebDriverWait) -> dict:
        """상세 페이지에서 개별 캠페인 정보를 추출합니다."""
        data = {}
        try:
            # XPath를 사용하여 텍스트 레이블을 기준으로 안정적으로 요소를 찾습니다.
            text_xpath = '//*[@id="__next"]/div/div[2]/div/div[1]/div[1]/div[1]/div[1]'
            data['company'] = wait.until(EC.presence_of_element_located((By.XPATH, text_xpath))).text.strip()
            
            # 제공내역: '제공서비스/물품' 제목을 가진 div의 형제 div에서 p 태그를 찾음
            offer_xpath = '//*[@id="__next"]/div/div[2]/div/div[1]/div[1]/div[7]/div[1]/div[1]/div[2]/p'
            data['offer'] = wait.until(EC.presence_of_element_located((By.XPATH, offer_xpath))).text.strip()

            # 주소: '방문 주소' 제목을 가진 div의 형제 div를 찾음
            address_xpath = '//*[@id="__next"]/div/div[2]/div/div[1]/div[1]/div[7]/div[1]/div[4]/div[2]'
            address_elements = self.driver.find_elements(By.XPATH, address_xpath)
            data['address'] = address_elements[0].text.strip() if address_elements else None

            # 날짜 정보 추출
            # 2. 신청 기간 텍스트 추출 및 파싱
            # apply_period_xpath = "//div[div[text()='체험단 신청기간']]/following-sibling::div"
            self._expand_schedule_section(wait)
            apply_period_xpath='//*[@id="__next"]/div/div[2]/div/div[1]/div[2]/div[2]/div[1]/div[1]/div/div[1]/div[2]'
            
            apply_period_text = wait.until(EC.presence_of_element_located((By.XPATH, apply_period_xpath))).text.strip()
            
            # 정규표현식으로 모든 날짜(M/D)를 찾음
            apply_dates = re.findall(r'(\d{1,2}/\d{1,2})', apply_period_text)
            if len(apply_dates) >= 2:
                data['apply_from'] = apply_dates[0]
                data['apply_deadline'] = apply_dates[1]
            elif len(apply_dates) == 1:
                data['apply_from'] = apply_dates[0]
                data['apply_deadline'] = apply_dates[0]
            else:
                data['apply_from'] = None
                data['apply_deadline'] = None

            # 3. 리뷰 마감일 텍스트 추출 및 파싱
            # review_deadline_xpath = "//div[div[text()='리뷰 마감']]/following-sibling::div"
            review_deadline_xpath='//*[@id="__next"]/div/div[2]/div/div[1]/div[2]/div[2]/div[1]/div[1]/div/div[4]/div[2]'
            review_deadline_text = wait.until(EC.presence_of_element_located((By.XPATH, review_deadline_xpath))).text.strip()
            
            match = re.search(r'(\d{1,2}/\d{1,2})', review_deadline_text)
            data['review_deadline'] = match.group(1) if match else None
            # --- 날짜 추출 로직 끝 ---

        except (TimeoutException, NoSuchElementException) as e:
            log.warning(f"상세 정보 일부 추출 실패: {e}")
        
        return data
    
    region_map = {
            # "서울": 4,
            # "경기": 5,
            # "인천": 6,
            # "강원": 7,
            # "대전": 8,
            "세종": 9,
            # "충남": 10,
            # "충북": 11,
            # "부산": 12,
            # "울산": 13,
            # "경남": 14,
            # "경북": 15,
            # "대구": 16,
            # "광주": 17,
            # "전남": 18,
            # "전북": 19,
            # "제주": 20,
        }

    def run_once(self, keywords: List[str], table_name: str) -> int:
        # BaseScraper의 run_once를 오버라이드하여 리뷰노트 전용 로직을 구현합니다.
        self.driver.get(self.BASE_URL)
        wait = WebDriverWait(self.driver, 15)
        all_data = []
        
        # region_map = {
        #     # "서울": 4,
        #     # "경기": 5,
        #     # "인천": 6,
        #     # "강원": 7,
        #     # "대전": 8,
        #     "세종": 9,
        #     # "충남": 10,
        #     # "충북": 11,
        #     # "부산": 12,
        #     # "울산": 13,
        #     # "경남": 14,
        #     # "경북": 15,
        #     # "대구": 16,
        #     # "광주": 17,
        #     # "전남": 18,
        #     # "전북": 19,
        #     # "제주": 20,
        # }
        
        for key, value in self.region_map.items():
            
            try:
                log.info(f"'{key}'지역 필터링을 시작합니다.")
                local_button = wait.until(EC.element_to_be_clickable(
                    (By.XPATH, f'//*[@id="__next"]/div/div[2]/div[1]/div[1]/div/div[2]/div[2]/div/div[1]/div/div/div[{value}]')
                ))
                local_button.click()
                time.sleep(2)
                
                log.info("모든 캠페인 목록을 불러오기 위해 페이지를 스크롤합니다...")

                # 스크롤 대상 탐색 (컨테이너 우선)
                container = None
                for sel in ("main", "[role='main']", ".infinite-scroll", ".scroll-container"):
                    try:
                        container = self.driver.find_element(By.CSS_SELECTOR, sel)
                        break
                    except Exception:
                        pass

                def get_height():
                    if container:
                        return self.driver.execute_script("return arguments[0].scrollHeight;", container)
                    return self.driver.execute_script("return document.body.scrollHeight")

                def do_scroll():
                    if container:
                        self.driver.execute_script("arguments[0].scrollTop = arguments[0].scrollHeight;", container)
                    else:
                        self.driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")


                last_height = get_height()

                 # --- 무한 스크롤 로직 시작 ---
                scroll_number = 0
                while True:
                    do_scroll()
                    scroll_number += 1
                    time.sleep(1.5)
                    new_height = get_height()
                    if new_height == last_height:
                        log.info("페이지 맨 끝에 도달했습니다.")
                        break
                    last_height = new_height
                # --- 무한 스크롤 로직 끝 ---

                log.info("모든 캠페인 URL 수집 시작")
                campaign_links = wait.until(EC.presence_of_all_elements_located(
                    (By.CSS_SELECTOR, "a[href^='/campaigns/']")
                ))
                
                detail_urls = []
                for link_element in campaign_links:
                    url = link_element.get_attribute("href")
                    if url and url != self.BASE_URL and url not in detail_urls:
                        detail_urls.append(url)
                
                log.info(f"총 {len(detail_urls)}개의 상세 페이지 URL 수집 완료.")

                for url in detail_urls:
                    log.info(f"상세 페이지 방문: {url} ({detail_urls.index(url) + 1}/{len(detail_urls)})")
                    self.driver.get(url)
                    
                    detail_data = self._extract_detail_data(wait)
                    if detail_data.get("company"):
                        detail_data['platform'] = self.PLATFORM_NAME
                        detail_data['company_link'] = url
                        detail_data['search_text'] = key
                        all_data.append(detail_data)
                        log.info(f"추출 성공: {detail_data['company']}")
                        # log.info(f"추출 성공: {detail_data['platform']}")
                        # log.info(f"추출 성공: {detail_data['company_link']}")
                        # log.info(f"추출 성공: {detail_data['search_text']}")
                        # log.info(f"추출 성공: {detail_data['apply_from']}")
                        # log.info(f"추출 성공: {detail_data['apply_deadline']}")
                        # log.info(f"=====================================")
                    else:
                        log.warning(f"데이터 추출 실패: {url}")
                    time.sleep(1)

            except (TimeoutException, NoSuchElementException) as e:
                log.error(f"리뷰노트 크롤링 중 오류 발생: {e}", exc_info=True)
                return 0

        if not all_data:
            return 0

        # 6. 데이터프레임 변환 및 DB 저장
        df = pd.DataFrame(all_data)
        final_df = self._clean_dataframe(df)
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

    def _expand_schedule_section(self, wait: WebDriverWait) -> None:
        """
        상세 페이지에서 '체험단 일정' 섹션이 접혀 있으면 펼칩니다.
        - 버튼/토글 텍스트가 '체험단 일정'인 영역을 찾아 클릭
        - 클릭이 가려지면 스크롤 후 JS 클릭 시도
        - 이미 펼쳐져 있으면 조용히 통과
        """
       
        toggle_xpath = '//*[@id="__next"]/div/div[2]/div/div[1]/div[2]/div[2]/div[1]/div[1]/button'
        toggle_btn = wait.until(EC.element_to_be_clickable((By.XPATH, toggle_xpath)))
        self.driver.execute_script("arguments[0].scrollIntoView({block: 'center'});", toggle_btn)
        toggle_btn.click()
        log.info("체험단 일정 버튼 클릭 완료 (토글 펼침)")
        time.sleep(0.5)  # 약간의 대기 (애니메이션 반영)
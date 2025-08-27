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
            apply_period_xpath='//*[@id="__next"]/div/div[2]/div/div[1]/div[1]/div[3]/div[3]/div[1]/div[1]/div[2]'
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
            review_deadline_xpath='//*[@id="__next"]/div/div[2]/div/div[1]/div[1]/div[3]/div[3]/div[1]/div[4]/div[2]'
            review_deadline_text = wait.until(EC.presence_of_element_located((By.XPATH, review_deadline_xpath))).text.strip()
            
            match = re.search(r'(\d{1,2}/\d{1,2})', review_deadline_text)
            data['review_deadline'] = match.group(1) if match else None
            # --- 날짜 추출 로직 끝 ---

        except (TimeoutException, NoSuchElementException) as e:
            log.warning(f"상세 정보 일부 추출 실패: {e}")
        
        return data

    def run_once(self, keywords: List[str], table_name: str) -> int:
        # BaseScraper의 run_once를 오버라이드하여 리뷰노트 전용 로직을 구현합니다.
        self.driver.get(self.BASE_URL)
        wait = WebDriverWait(self.driver, 15)
        all_data = []

        target_region = "서울"
        log.info(f"'{target_region}' 지역 필터링을 시작합니다.")


        try:
            # 1. '체험단 검색' 버튼 클릭 (더 안정적인 Selector로 변경)
            # search_filter_button = wait.until(EC.element_to_be_clickable(
            #     (By.XPATH, "//div[contains(text(), '체험단 검색')]")
            # ))
            # search_filter_button.click()
            # time.sleep(1)

            # 2. '서울' 버튼 클릭
            seoul_button = wait.until(EC.element_to_be_clickable(
                (By.XPATH, f"//div[text()='{target_region}']")
            ))
            seoul_button.click()
            time.sleep(2)

            # 3. 필터링된 목록에서 상위 10개 캠페인의 상세 페이지 URL 수집
            log.info(f"'{target_region}' 지역 상위 10개 캠페인 URL 수집 시작")
            campaign_cards = wait.until(EC.presence_of_all_elements_located(
                (By.CSS_SELECTOR, "a[href^='/campaigns/']")
            ))
            
            detail_urls = []
            for card_link in campaign_cards[:10]:
                url = card_link.get_attribute("href")
                if url and url not in detail_urls:
                    detail_urls.append(url)
            
            log.info(f"총 {len(detail_urls)}개의 상세 페이지 URL 수집 완료.")

            # 4. 각 상세 페이지를 방문하여 정보 추출
            for url in detail_urls:
                log.info(f"상세 페이지 방문: {url}")
                self.driver.get(url)
                
                detail_data = self._extract_detail_data(wait)
                if detail_data.get("company"):
                    detail_data['platform'] = self.PLATFORM_NAME
                    detail_data['company_link'] = url
                    detail_data['search_text'] = target_region
                    all_data.append(detail_data)
                    log.info(f"추출 성공: {detail_data['company']}")
                else:
                    log.warning(f"데이터 추출 실패: {url}")
                time.sleep(1)

        except (TimeoutException, NoSuchElementException) as e:
            log.error(f"리뷰노트 크롤링 중 오류 발생: {e}", exc_info=True)
            return 0
        
        # 5. 최종 결과 출력
        log.info("---------- 최종 크롤링 결과 (상위 10개) ----------")
        for item in all_data:
            print(item)
        log.info("-------------------------------------------------")

        if not all_data:
            return 0

        # 6. 데이터프레임 변환 및 DB 저장
        df = pd.DataFrame(all_data)
        clean_df = self._clean_dataframe(df)

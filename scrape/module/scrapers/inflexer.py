from __future__ import annotations
import pandas as pd
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException, NoSuchElementException

from .base import BaseScraper
from module.logger import get_logger

log = get_logger("scraper.inflexer")

class InflexerScraper(BaseScraper):
    PLATFORM_NAME = "인플렉서"
    BASE_URL = "https://inflexer.net"

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
        except (TimeoutException, NoSuchElementException) as e:
            log.error(f"검색 요소 처리 중 오류: {e}")
            raise

    def _extract_dataframe(self, search_text: str) -> pd.DataFrame:
        try:
            wait = WebDriverWait(self.driver, 10)
            tbody = wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, "#result_table > tbody")))
            rows = tbody.find_elements(By.TAG_NAME, "tr")
            data = []
            for r in rows:
                tds = r.find_elements(By.TAG_NAME, "td")
                if len(tds) < 5: continue
                
                company_link_element = tds[1].find_element(By.TAG_NAME, "a")
                
                data.append({
                    "platform": tds[0].text.strip(),
                    "company": tds[1].text.strip(),
                    "company_link": company_link_element.get_attribute("href"),
                    "offer": tds[2].text.strip(),
                    "apply_deadline": tds[3].text.strip(),
                    "review_deadline": tds[4].text.strip(),
                    "search_text": search_text,
                })
            return pd.DataFrame(data)
        except TimeoutException:
            log.warning("테이블 로딩 실패 (Timeout)")
            return pd.DataFrame()

    def _assign_platform(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Inflexer는 이미 platform 컬럼을 개별적으로 수집했으므로,
        BaseScraper의 일괄 할당 로직을 덮어써서 아무 작업도 하지 않도록 합니다.
        """
        log.info("개별 수집된 플랫폼 이름 유지.")
        df = df.copy()
        df["source"] = self.PLATFORM_NAME  # '인플렉서'
        
        return df

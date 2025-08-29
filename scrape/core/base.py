from abc import ABC, abstractmethod
from typing import Any, List, Dict
from core.logger import get_logger
from core.config import settings
from selenium import webdriver
from selenium.webdriver.chrome.options import Options as ChromeOptions
import sys, os, time

from selenium.webdriver.remote.webelement import WebElement
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException
from typing import Tuple, Callable, Optional

log = get_logger("scraper.base")


class BaseScraper(ABC):
    """
    모든 스크레이퍼를 위한 추상 기본 클래스입니다.
    공통적인 구조와 실행 흐름을 정의합니다.
    """

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
        # ======== 수정할 수 없는 영역 =======
        "source",
        "platform",
        "company",
        "company_link",
        "category_id",
        "offer",
        "apply_from",
        "apply_deadline",
        "review_deadline",
        "search_text",
        "address",
        "lat",
        "lng",
        "img_url",
        # ================================
        # source -> 기존 것 사용
        "title",  # 작성하면서 company에도 데이터 추가, 기존 안정성유지
        "content_link",  # 작성하면서 company_link에도 데이터추가, 기존 안정성유지
        # "offer", # 기존거 사용
        # "platform", # 기존거 사용
        "campaign_type",
        "region",
        "campaign_channel",
        # "days_left", # apply_deadline 추가
    ]

    def __init__(self):
        self.settings = settings
        self.logger = get_logger(f"scraper.{self.PLATFORM_NAME}")
        self.driver = self._init_driver()

    def _init_driver(self) -> webdriver.Chrome:
        log.info(f"[{self.PLATFORM_NAME}] ChromeDriver 초기화…")
        options = ChromeOptions()
        if sys.platform.startswith("linux"):
            options.binary_location = os.getenv("CHROME_BIN", "/usr/bin/chromium")
        if self.settings.HEADLESS:
            options.add_argument("--headless=new")
        # ✅ 리눅스 컨테이너에서 필수급
        options.add_argument("--window-size=1920,1080")  # 헤드리스에서도 적용됨
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")

        # ✅ 약간의 위장 (일부 사이트가 headless에 소극적일 때)
        options.add_argument(
            "--user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
        )
        options.add_argument("--disable-blink-features=AutomationControlled")
        options.add_experimental_option(
            "excludeSwitches", ["enable-logging", "enable-automation"]
        )
        options.add_experimental_option("useAutomationExtension", False)

        driver = webdriver.Chrome(options=options)
        try:
            # headless라도 한번 더 안전하게
            driver.set_window_size(1920, 1080)
        except Exception:
            pass
        return driver

    def _wait_and_find_element(
        self,
        locator: Tuple[By, str],
        timeout: int = 10,
        condition: Callable = EC.presence_of_element_located,
    ) -> Optional[WebElement]:
        """
        지정된 locator의 요소가 특정 조건(condition)을 만족할 때까지 기다린 후,
        해당 요소를 반환합니다.
        """
        try:
            wait = WebDriverWait(self.driver, timeout)
            element = wait.until(condition(locator))
            return element
        except TimeoutException:
            self.logger.error(
                f"요소를 찾는 데 실패했습니다 (시간 초과). Locator: {locator}"
            )
            return None

    def _click_element(self, locator: Tuple[By, str], timeout: int = 10) -> bool:
        """
        요소가 '클릭 가능한 상태'가 될 때까지 기다린 후 클릭합니다.
        """
        element = self._wait_and_find_element(
            locator, timeout, condition=EC.element_to_be_clickable
        )
        if element:
            element.click()
            self.logger.info(f"요소를 클릭했습니다: {locator}")
            return True
        self.logger.error(f"요소를 클릭하는 데 실패했습니다: {locator}")
        return False

    def _send_keys_to_element(
        self, locator: Tuple[By, str], text: str, timeout: int = 10
    ) -> bool:
        """
        요소가 나타날 때까지 기다린 후, 텍스트를 입력합니다.
        """
        element = self._wait_and_find_element(locator, timeout)
        if element:
            element.clear()  # 기존 텍스트 삭제
            element.send_keys(text)
            self.logger.info(
                f"요소에 텍스트를 입력했습니다: {locator}, text: {text[:30]}"
            )
            return True
        self.logger.error(f"요소에 텍스트를 입력하는 데 실패했습니다: {locator}")
        return False

    @abstractmethod
    def scrape(self) -> Any:
        """
        대상 웹사이트에서 원본 데이터(HTML, JSON 등)를 가져옵니다.
        """
        raise NotImplementedError

    @abstractmethod
    def parse(self, raw_data: Any) -> List[Dict[str, Any]]:
        """
        가져온 원본 데이터를 파싱하여 딕셔너리 리스트와 같은 구조화된 형태로 가공합니다.
        """
        raise NotImplementedError

    @abstractmethod
    def save(self, data: List[Dict[str, Any]]) -> None:
        """
        구조화된 데이터를 데이터베이스나 다른 저장소에 저장합니다.
        """
        raise NotImplementedError

    def enrich(self, data: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        [선택적] 파싱된 데이터를 데이터프레임 변환, 정제 등 보강하는 단계입니다.
        기본적으로는 아무 작업도 하지 않고 데이터를 그대로 반환합니다.
        필요한 스크레이퍼에서 이 메서드를 오버라이드(재정의)하여 사용합니다.
        """
        self.logger.info("Enrich 단계는 구현되지 않아 건너뜁니다.")
        return data

    def run(self) -> None:
        """
        스크레이핑 전체 파이프라인 (Scrape -> Parse -> Enrich -> Save)을 실행합니다.
        """
        self.logger.info(f"===== {self.PLATFORM_NAME} 스크레이핑 시작 =====")
        try:
            # 1. Scrape: 웹에서 HTML 데이터 가져오기
            html_content = self.scrape()
            if not html_content:
                self.logger.warning("scrape 단계에서 데이터를 가져오지 못했습니다.")
                return

            # 2. Parse: HTML을 파싱하여 데이터 리스트로 변환
            parsed_data = self.parse(html_content)
            if not parsed_data:
                self.logger.warning("parse 단계에서 데이터가 파싱되지 않았습니다.")
                return
            self.logger.info(f"총 {len(parsed_data)}개의 아이템을 파싱했습니다.")

            # 3. Enrich: 파싱된 데이터 정제 및 보강
            enriched_data = self.enrich(parsed_data)
            # log.info(f"save 메서드로 전달될 데이터의 타입: {type(enriched_data)}")

            # if enriched_data and isinstance(enriched_data, list) and len(enriched_data) > 0:
            #     log.info(f"리스트 첫 번째 요소의 타입: {type(enriched_data[0])}")

            # 4. Save: 최종 데이터를 DB 등에 저장
            self.save(enriched_data)

        except Exception as e:
            self.logger.error(f"스크레이핑 실행 중 에러 발생: {e}", exc_info=True)
        finally:
            if self.driver:
                self.driver.quit()
            self.logger.info(f"===== {self.PLATFORM_NAME} 스크레이핑 종료 =====")

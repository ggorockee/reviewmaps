# core/base.py (API 중심 최종 버전)

from abc import ABC, abstractmethod
from typing import Any, List, Dict, Optional
from core.logger import get_logger
from core.config import settings

log = get_logger("scraper.base")

class BaseScraper(ABC):
    """
    모든 스크레이퍼를 위한 추상 기본 클래스입니다.
    API 기반 스크레이핑에 최적화되었습니다.
    """

    @property
    @abstractmethod
    def PLATFORM_NAME(self) -> str:
        """스크레이퍼가 수집하는 플랫폼의 이름"""
        pass

    @property
    @abstractmethod
    def BASE_URL(self) -> str:
        """스크레이핑 대상 사이트의 기본 URL 또는 API Endpoint"""
        pass

    # 최종 DB 스키마를 정의하는 부분은 그대로 유지합니다.
    RESULT_TABLE_COLUMNS = [
        "platform", 
        "title",
        "offer",
        "campaign_channel",
        "source", 
        "company", 
        "company_link", 
        "category_id",
        "apply_from", 
        "apply_deadline", 
        "review_deadline",
        "search_text", 
        "address", 
        "lat", 
        "lng", 
        "img_url", 
        "content_link", 
        "campaign_type", 
        "region", 
    ]

    def __init__(self):
        self.settings = settings
        self.logger = get_logger(f"scraper.{self.PLATFORM_NAME}")

    @abstractmethod
    def scrape(self, keyword: Optional[str] = None) -> List[Dict[str, Any]]:
        raise NotImplementedError

    @abstractmethod
    def parse(self, raw_data: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        raise NotImplementedError

    def enrich(self, parsed_data: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        파싱된 데이터를 보강합니다. (예: 주소/좌표 채우기)
        """
        self.logger.info("Enrich 단계는 구현되지 않아 건너뜁니다.")
        return parsed_data

    @abstractmethod
    def save(self, data: List[Dict[str, Any]]) -> None:
        """
        최종 데이터를 데이터베이스에 저장합니다.
        """
        raise NotImplementedError

    def run(self, keyword: Optional[str] = None) -> None:
        """
        스크레이핑 전체 파이프라인 (Scrape -> Parse -> Enrich -> Save)을 실행합니다.
        """
        self.logger.info(f"===== {self.PLATFORM_NAME} 스크레이핑 시작 (키워드: {keyword or '전체'}) =====")
        try:
            raw_data = self.scrape(keyword=keyword)
            if not raw_data:
                self.logger.warning("scrape 단계에서 데이터를 가져오지 못했습니다.")
                return

            parsed_data = self.parse(raw_data)
            if not parsed_data:
                self.logger.warning("parse 단계에서 데이터가 파싱되지 않았습니다.")
                return
            self.logger.info(f"총 {len(parsed_data)}개의 아이템을 파싱했습니다.")

            enriched_data = self.enrich(parsed_data)
            
            self.save(enriched_data)

        except Exception as e:
            self.logger.error(f"스크레이핑 실행 중 에러 발생: {e}", exc_info=True)
        finally:
            self.logger.info(f"===== {self.PLATFORM_NAME} 스크레이핑 종료 =====")
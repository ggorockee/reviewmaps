# core/base.py (API 중심 최종 버전)

from abc import ABC, abstractmethod
from typing import Any, List, Dict, Optional
from core.logger import get_logger
from core.config import settings

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
import math

log = get_logger("scraper.base")

DRIFT_METERS = 50  # 필요시 per-scraper override 가능

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

    BASE_DATA_TYPES = {
        "source": "string",
        "platform": "string",
        "company": "string",
        "title": "string",
        "offer": "string",
        "campaign_channel": "string",
        "content_link": "string",
        "company_link": "string",
        "campaign_type": "string",
        "region": "string",
        "address": "string",
        "apply_deadline": "datetime64[ns]",
        "review_deadline": "datetime64[ns]",
        "img_url": "string",
        "apply_from": "datetime64[ns]",
        "search_text": "string",
    }

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

    def save(self, data: List[Dict[str, Any]]) -> None:
        """
        최종 데이터를 데이터베이스에 저장합니다.
        """
        if not data:
            log.warning("저장할 최종 데이터가 없습니다.")
            return

        log.info(f"정제된 최종 데이터 {len(data)}건을 DB에 저장 시작...")
        engine = create_engine(self.settings.db.url)
        Session = sessionmaker(bind=engine)
        
        with Session() as session:
            try:
                upsert_sql = text(f"""
                    INSERT INTO campaign (
                        platform, title, offer, campaign_channel, company, content_link, 
                        company_link, source, campaign_type, region, apply_deadline, 
                        review_deadline, address, lat, lng, category_id, img_url
                    ) VALUES (
                        :platform, :title, :offer, :campaign_channel, :company, :content_link, 
                        :company_link, :source, :campaign_type, :region, :apply_deadline, 
                        :review_deadline, :address, :lat, :lng, :category_id, :img_url
                    )
                    ON CONFLICT (platform, title, offer, campaign_channel) DO UPDATE SET
                        company = EXCLUDED.company, source = EXCLUDED.source,
                        content_link = EXCLUDED.content_link, company_link = EXCLUDED.company_link,
                        campaign_type = EXCLUDED.campaign_type, region = EXCLUDED.region,
                        apply_deadline = EXCLUDED.apply_deadline, review_deadline = EXCLUDED.review_deadline,
                        address = EXCLUDED.address, lat = EXCLUDED.lat, lng = EXCLUDED.lng,
                        category_id = EXCLUDED.category_id, img_url = EXCLUDED.img_url,
                        updated_at = NOW();
                """)
                session.execute(upsert_sql, data)
                session.commit()
                log.info(f"DB 저장 완료. 총 {len(data)}건의 데이터가 성공적으로 처리되었습니다.")
            except Exception as e:
                log.error(f"DB 저장 중 에러 발생: {e}", exc_info=True)
                session.rollback()

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

    def get_api_keys(self) -> list:
        keys = []
        if self.settings.naver_api.SEARCH_CLIENT_ID and self.settings.naver_api.SEARCH_CLIENT_SECRET:
            keys.append((self.settings.naver_api.SEARCH_CLIENT_ID, self.settings.naver_api.SEARCH_CLIENT_SECRET))
        if self.settings.naver_api.SEARCH_CLIENT_ID_2 and self.settings.naver_api.SEARCH_CLIENT_SECRET_2:
            keys.append((self.settings.naver_api.SEARCH_CLIENT_ID_2, self.settings.naver_api.SEARCH_CLIENT_SECRET_2))
        if self.settings.naver_api.SEARCH_CLIENT_ID_3 and self.settings.naver_api.SEARCH_CLIENT_SECRET_3:
            keys.append((self.settings.naver_api.SEARCH_CLIENT_ID_3, self.settings.naver_api.SEARCH_CLIENT_SECRET_3))
        return keys
    
    @staticmethod
    def _safe_float(x):
        try:
            return float(x)
        except Exception:
            return None
        
    @classmethod
    def _from_mapxy(cls, place: dict):
        """
        네이버 Local API 응답에서 mapx/mapy를 위경도로 변환.
        - mapx: 경도(longitude)
        - mapy: 위도(latitude)
        - 반환: (lat, lng) or (None, None)
        """
        mx = cls._safe_float(place.get("mapx"))
        my = cls._safe_float(place.get("mapy"))
        if mx is None or my is None:
            return None, None

        lon = mx / 1e7
        lat = my / 1e7

        # 한국 좌표 대략 범위 체크
        if not (33.0 <= lat <= 39.5 and 124.0 <= lon <= 132.0):
            return None, None

        return lat, lon
    
    @staticmethod
    def _haversine(lat1, lng1, lat2, lng2):
        """두 좌표 사이 거리(meter)"""
        if None in (lat1, lng1, lat2, lng2):
            return None
        R = 6371000.0
        dlat = math.radians(lat2 - lat1)
        dlng = math.radians(lng2 - lng1)
        a = (
            math.sin(dlat / 2) ** 2
            + math.cos(math.radians(lat1))
            * math.cos(math.radians(lat2))
            * math.sin(dlng / 2) ** 2
        )
        return 2 * R * math.asin(math.sqrt(a))
    
    def _load_existing_map(self):
        """현재 캠페인 테이블의 핵심 컬럼만 키로 로딩."""
        engine = create_engine(self.settings.db.url)
        with engine.begin() as conn:
            rows = conn.execute(text("""
                SELECT platform, title, offer, campaign_channel, address, lat, lng, category_id
                FROM campaign
            """)).mappings().all()
        return {
            (r['platform'], r['title'], r['offer'], r['campaign_channel']): r
            for r in rows
        }
    
    def _get_geocode_cache(self, address: str):
        if not address:
            return None
        engine = create_engine(self.settings.db.url)
        with engine.begin() as conn:
            row = conn.execute(
                text("""SELECT lat, lng FROM geocode_cache WHERE address_hash = sha1(:addr)"""),
                {"addr": address.strip()}
            ).mappings().first()
        if row:
            self.logger.info(f"[geocode_cache] HIT {address} → ({row['lat']}, {row['lng']})")
        else:
            self.logger.info(f"[geocode_cache] MISS {address}")
        return (row["lat"], row["lng"]) if row else None


    def _put_geocode_cache(self, address: str, lat: float, lng: float):
        if not address or lat is None or lng is None:
            self.logger.debug(f"[geocode_cache] SKIP {address} lat={lat}, lng={lng}")
            return
        engine = create_engine(self.settings.db.url)
        with engine.begin() as conn:
            conn.execute(text("""
                INSERT INTO geocode_cache (address_hash, address, lat, lng, updated_at)
                VALUES (sha1(:addr), :addr, :lat, :lng, NOW())
                ON CONFLICT (address_hash) DO UPDATE
                SET address = EXCLUDED.address, lat = EXCLUDED.lat, lng = EXCLUDED.lng, updated_at = NOW()
            """), {"addr": address.strip(), "lat": lat, "lng": lng})
        self.logger.info(f"[geocode_cache] PUT {address} → ({lat}, {lng})")

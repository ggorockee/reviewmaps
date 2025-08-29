from __future__ import annotations
import os
from pydantic_settings import BaseSettings
from dotenv import load_dotenv
from zoneinfo import ZoneInfo

load_dotenv()


class DatabaseSettings(BaseSettings):
    """데이터베이스 관련 설정"""

    USER: str = os.getenv("POSTGRES_USER", "")
    PASSWORD: str = os.getenv("POSTGRES_PASSWORD", "")
    HOST: str = os.getenv("POSTGRES_HOST", "localhost")
    PORT: str = os.getenv("POSTGRES_PORT", "5432")
    DB: str = os.getenv("POSTGRES_DB", "")

    @property
    def url(self) -> str:
        """SQLAlchemy 접속을 위한 데이터베이스 URL을 생성합니다."""
        return f"postgresql+psycopg2://{self.USER}:{self.PASSWORD}@{self.HOST}:{self.PORT}/{self.DB}"


class NaverAPISettings(BaseSettings):
    """네이버 API 관련 클라이언트 ID 및 시크릿 설정"""

    MAP_CLIENT_ID: str = os.getenv("NAVER_MAP_CLIENT_ID", "")
    MAP_CLIENT_SECRET: str = os.getenv("NAVER_MAP_CLIENT_SECRET", "")

    SEARCH_CLIENT_ID: str = os.getenv("NAVER_SEARCH_CLIENT_ID", "")
    SEARCH_CLIENT_SECRET: str = os.getenv("NAVER_SEARCH_CLIENT_SECRET", "")
    SEARCH_CLIENT_ID_2: str = os.getenv("NAVER_SEARCH_CLIENT_ID_2", "")
    SEARCH_CLIENT_SECRET_2: str = os.getenv("NAVER_SEARCH_CLIENT_SECRET_2", "")
    SEARCH_CLIENT_ID_3: str = os.getenv("NAVER_SEARCH_CLIENT_ID_3", "")
    SEARCH_CLIENT_SECRET_3: str = os.getenv("NAVER_SEARCH_CLIENT_SECRET_3", "")


class BatchSettings(BaseSettings):
    """배치(Batch) 작업 실행 관련 설정"""

    # 배치 모드: "daily" 또는 "interval"
    MODE: str = os.getenv("BATCH_MODE", "daily").lower()
    # daily 모드일 때 실행 시각 (HH:MM)
    TIME_HHMM: str = os.getenv("BATCH_TIME", "01:00")
    # interval 모드일 때 주기 (초)
    INTERVAL_SECONDS: int = int(os.getenv("BATCH_INTERVAL_SECONDS", "300"))
    # 타임존
    TIMEZONE: str = os.getenv("TIMEZONE", "Asia/Seoul")
    # 프로세스 시작 직후 한 번 즉시 실행할지 여부
    RUN_AT_START: bool = os.getenv("RUN_AT_START", "false").lower() == "true"

    # WAIT_TIMEOUT
    WAIT_TIMEOUT: int = os.getenv("WAIT_TIMEOUT", 15)

    @property
    def tz(self) -> ZoneInfo:
        """설정된 타임존을 ZoneInfo 객체로 변환합니다."""
        try:
            return ZoneInfo(self.TIMEZONE)
        except Exception:
            # 설정값이 잘못되었을 경우 기본값으로 서울 타임존을 사용합니다.
            return ZoneInfo("Asia/Seoul")


class Settings(BaseSettings):
    """애플리케이션의 모든 설정을 통합 관리하는 메인 클래스"""

    # 일반 설정
    BASE_URL: str = os.getenv("BASE_URL", "https://mymilky.co.kr/")
    HEADLESS: bool = os.getenv("HEADLESS", "true").lower() == "true"
    TABLE_NAME: str = os.getenv("TABLE_NAME", "campaign")

    # 클래스로 그룹화된 설정들을 포함시킵니다.
    db: DatabaseSettings = DatabaseSettings()
    naver_api: NaverAPISettings = NaverAPISettings()
    batch: BatchSettings = BatchSettings()


# 다른 파일에서 임포트하여 사용할 설정 객체
settings = Settings()

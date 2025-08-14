from __future__ import annotations
import os
from dataclasses import dataclass
from dotenv import load_dotenv
from zoneinfo import ZoneInfo

load_dotenv()

@dataclass(frozen=True)
class Settings:
    base_url: str = os.getenv("BASE_URL", "https://inflexer.net")
    headless: bool = os.getenv("HEADLESS", "true").lower() == "true"

    # DB
    pg_user: str = os.getenv("POSTGRES_USER", "")
    pg_password: str = os.getenv("POSTGRES_PASSWORD", "")
    pg_host: str = os.getenv("POSTGRES_HOST", "localhost")
    pg_port: str = os.getenv("POSTGRES_PORT", "5432")
    pg_db: str = os.getenv("POSTGRES_DB", "")

    # Naver
    naver_map_client_id: str = os.getenv("NAVER_MAP_CLIENT_ID", "")
    naver_map_client_secret: str = os.getenv("NAVER_MAP_CLIENT_SECRET", "")
    naver_search_client_id: str = os.getenv("NAVER_SEARCH_CLIENT_ID", "")
    naver_search_client_secret: str = os.getenv("NAVER_SEARCH_CLIENT_SECRET", "")

    # Table
    table_name: str = os.getenv("TABLE_NAME", "campaign")

    # ===== Batch control =====
    # 배치 모드: "daily" 또는 "interval"
    batch_mode: str = os.getenv("BATCH_MODE", "daily").lower()
    # daily 모드일 때 실행 시각(HH:MM)
    batch_time_hhmm: str = os.getenv("BATCH_TIME", "01:00")
    # interval 모드일 때 주기(초)
    batch_interval_seconds: int = int(os.getenv("BATCH_INTERVAL_SECONDS", "300"))
    # 타임존
    timezone: str = os.getenv("TIMEZONE", "Asia/Seoul")
    # 프로세스 시작 직후 한 번 즉시 실행할지
    run_at_start: bool = os.getenv("RUN_AT_START", "false").lower() == "true"

    @property
    def db_url(self) -> str:
        return (
            f"postgresql+psycopg2://{self.pg_user}:{self.pg_password}"
            f"@{self.pg_host}:{self.pg_port}/{self.pg_db}"
        )
        
    @property
    def tz(self) -> ZoneInfo:
        try:
            return ZoneInfo(self.timezone)
        except Exception:
            return ZoneInfo("Asia/Seoul")



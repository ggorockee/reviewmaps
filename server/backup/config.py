from __future__ import annotations
from pydantic_settings import BaseSettings
from pydantic import Field
from dotenv import load_dotenv
import os


load_dotenv()

class Settings(BaseSettings):
    
    
    app_name: str = "ReviewMaps API (async)"
    api_prefix: str = "/v1"
    
    # DB
    database_url: str = Field(default="")
    pg_user: str = Field(default=os.getenv("POSTGRES_USER"))
    pg_password: str = Field(default=os.getenv("POSTGRES_PASSWORD"))
    pg_host: str = Field(default=os.getenv("POSTGRES_HOST"))
    pg_port: str = Field(default=os.getenv("POSTGRES_PORT"))
    pg_db: str = Field(default=os.getenv("POSTGRES_DB"))
    
    cors_allow_origins: list[str] = Field(default=["*"])
    
    # secret
    API_SECRET_KEY: str = os.getenv("API_SECRET_KEY", "")
    
    def _compose_sync_url(self) -> str:
        port = (self.pg_port or "5432").strip() or "5432"
        return (
            f"postgresql+psycopg2://{self.pg_user}:{self.pg_password}"
            f"@{self.pg_host}:{port}/{self.pg_db}"
        )
    
    @property
    def db_url_async(self) -> str:
        """DATABASE_URL 우선. sync 스킴이면 async 스킴으로 변환."""
        url = (self.database_url or "").strip()
        if not url:
            url = self._compose_sync_url()

        # 안전 보정: host에 http:// 들어온 실수 방지
        if "@" in url:
            userinfo, hostpart = url.split("@", 1)
            if hostpart.startswith(("http://", "https://")):
                raise ValueError("DATABASE_URL host에 http/https 스킴을 넣지 마세요.")

        # 스킴 보정
        return (
            url.replace("postgresql+psycopg2://", "postgresql+asyncpg://")
               .replace("postgresql://", "postgresql+asyncpg://")
        )
        
    class Config:
        env_file = ".env"
        extra = "ignore"
        
settings = Settings()

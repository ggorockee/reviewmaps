from __future__ import annotations
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy import event
from core.config import settings

engine = create_async_engine(settings.db_url_async, pool_pre_ping=True, future=True)


@event.listens_for(engine.sync_engine, "connect")
def _set_kst_timezone(dbapi_connection, connection_record):
    cur = dbapi_connection.cursor()
    try:
        cur.execute("SET TIME ZONE 'Asia/Seoul'")
    finally:
        cur.close()
        
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    expire_on_commit=False,
    autoflush=False,
    autocommit=False,
    class_=AsyncSession,
)

async def get_async_db():
    async with AsyncSessionLocal() as session:
        yield session
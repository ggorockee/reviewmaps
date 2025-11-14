from __future__ import annotations
from fastapi import Depends, Header, HTTPException, Request
from sqlalchemy.orm import Session
from db.session import get_async_db
from core.config import settings
import hmac


def get_db_session(db: Session = Depends(get_async_db)) -> Session:
    return db

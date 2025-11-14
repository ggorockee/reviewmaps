# app/api/security.py
from __future__ import annotations
import hmac
from fastapi import HTTPException, Security
from fastapi.security.api_key import APIKeyHeader, APIKeyQuery
from core.config import settings

# Swagger에 노출될 보안 스키마 2종: 헤더/쿼리
api_key_header = APIKeyHeader(name="X-API-KEY", auto_error=False)
# api_key_query  = APIKeyQuery(name="key", auto_error=False)

async def require_api_key(
    key_from_header: str | None = Security(api_key_header),
):
    client_key = key_from_header
    expected = settings.API_SECRET_KEY
    if not expected:
        raise HTTPException(500, "Server is not configured with API secret.")
    if not client_key or not hmac.compare_digest(client_key, expected):
        raise HTTPException(401, "Unauthorized")
    # 통과 시 아무것도 반환 안 해도 OK

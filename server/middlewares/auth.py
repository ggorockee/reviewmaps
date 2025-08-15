import os
from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware

class SecretKeyMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, secret_key: str):
        super().__init__(app)
        self.secret_key = secret_key

    async def dispatch(self, request: Request, call_next):
        # ✅ 여기서는 헤더 기반 검사 (X-API-KEY)
        client_key = request.headers.get("X-API-KEY")
        
        if client_key != self.secret_key:
            raise HTTPException(status_code=401, detail="Unauthorized")

        return await call_next(request)

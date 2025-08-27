# middlewares/access.py
from __future__ import annotations
import time
import logging
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

log = logging.getLogger("middlewares.access")  # 이름 고정

class AccessLogMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start = time.perf_counter()

        # 사전 추출
        client_host = request.client.host if request.client else "-"
        method = request.method
        url_path = request.url.path
        ua = request.headers.get("user-agent", "-")

        status_code = None
        try:
            response = await call_next(request)
            status_code = response.status_code
            return response
        finally:
            process_time_ms = round((time.perf_counter() - start) * 1000, 2)
            # ⚠️ extra 로 포맷 필드 공급
            log.info(
                f'{client_host} - "{method} {url_path}" {status_code if status_code is not None else "-"} | {process_time_ms}ms',
                extra={
                    "client_host": client_host,
                    "method": method,
                    "url_path": url_path,
                    "status_code": status_code,
                    "process_time_ms": process_time_ms,
                    "user_agent": ua,  # 원하면 포맷에 추가
                },
            )

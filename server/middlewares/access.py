from __future__ import annotations
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
import time
from core.logging import setup_logging
import logging

# 로거 설정이 이미 되어있으므로, 이름으로 가져오기만 합니다.
# main.py에서 설정한 로거를 사용합니다.
log = logging.getLogger(__name__)
setup_logging()


class AccessLogMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start_time = time.time()
        
        # 다음 미들웨어 또는 API 로직 실행
        response = await call_next(request)
        
        process_time = (time.time() - start_time) * 1000  # 밀리초 단위로 변환
        
        client_host = request.client.host
        method = request.method
        url_path = request.url.path
        status_code = response.status_code
        user_agent = request.headers.get("user-agent", "N/A")

        # Uvicorn의 기본 액세스 로그 형식과 유사하게 맞춤
        log.info(
            f'{client_host} - "{method} {url_path}" {status_code} | {process_time:.2f}ms'
        )
        
        return response
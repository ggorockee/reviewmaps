# middlewares/metrics.py
import time
from typing import Callable
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from prometheus_client import Histogram, Counter, Gauge

# 16110에서 자주 쓰는 이름들
REQUESTS_DURATION = Histogram(
    "fastapi_requests_duration_seconds",
    "Histogram of request processing time by path (seconds)",
    ["method", "path", "app_name"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)
REQUESTS_TOTAL = Counter(
    "fastapi_requests_total", "Total count of requests by method and path",
    ["method", "path", "app_name"]
)
RESPONSES_TOTAL = Counter(
    "fastapi_responses_total", "Total count of responses by method, path and status",
    ["method", "path", "status_code", "app_name"]
)
# INFLIGHT = Gauge(
#     "fastapi_requests_in_progress", "Requests currently being processed",
#     ["method", "path", "app_name"]
# )
INFLIGHT = Gauge(
    "fastapi_requests_in_progress",
    "Requests currently being processed",
    ["method", "path", "app_name"],
    multiprocess_mode="livesum",   # ★ 멀티프로세스에서 워커 합산
)

class FastAPIMetricsMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, app_name: str):
        super().__init__(app)
        self.app_name = app_name

    async def dispatch(self, request: Request, call_next: Callable):
        # /metrics는 측정 제외
        if request.url.path == "/metrics":
            return await call_next(request)

        route = request.scope.get("route")
        path = getattr(route, "path", request.url.path)  # 템플릿 경로 우선
        method = request.method

        INFLIGHT.labels(method, path, self.app_name).inc()
        REQUESTS_TOTAL.labels(method, path, self.app_name).inc()

        start = time.perf_counter()
        try:
            response: Response = await call_next(request)
            status = response.status_code
            return response
        finally:
            elapsed = time.perf_counter() - start
            REQUESTS_DURATION.labels(method, path, self.app_name).observe(elapsed)
            RESPONSES_TOTAL.labels(method, path, str(status), self.app_name).inc()
            INFLIGHT.labels(method, path, self.app_name).dec()

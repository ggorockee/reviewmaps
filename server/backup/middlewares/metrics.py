# middlewares/metrics.py
import time
from typing import Callable
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from prometheus_client import Histogram, Counter, Gauge, REGISTRY

def _get_or_create_metric(name, ctor, *args, **kwargs):
    c = REGISTRY._names_to_collectors.get(name)
    if c is not None:
        return c
    try:
        return ctor(name, *args, **kwargs)
    except ValueError:
        return REGISTRY._names_to_collectors.get(name)  # 경합 대비 재조회

REQUESTS_DURATION = _get_or_create_metric(
    "fastapi_requests_duration_seconds",
    Histogram,
    "Histogram of request processing time by path (seconds)",
    ["method", "path", "app_name"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)
REQUESTS_TOTAL = _get_or_create_metric(
    "fastapi_requests_total",
    Counter,
    "Total count of requests by method and path",
    ["method", "path", "app_name"],
)
RESPONSES_TOTAL = _get_or_create_metric(
    "fastapi_responses_total",
    Counter,
    "Total count of responses by method, path and status",
    ["method", "path", "status_code", "app_name"],
)
EXCEPTIONS = _get_or_create_metric(
    "fastapi_exceptions_total",
    Counter,
    "Total exceptions by method, path and type",
    ["method", "path", "exception_type", "app_name"],
)
INFLIGHT = _get_or_create_metric(
    "fastapi_requests_in_progress",
    Gauge,
    "Requests currently being processed",
    ["method", "path", "app_name"],
    multiprocess_mode="livesum",
)

class FastAPIMetricsMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, app_name: str):
        super().__init__(app)
        self.app_name = app_name

    async def dispatch(self, request: Request, call_next: Callable):
        # /metrics는 계측 제외
        if request.url.path == "/metrics":
            return await call_next(request)

        route = request.scope.get("route")
        path = getattr(route, "path", request.url.path)  # 템플릿 경로 우선
        method = request.method

        INFLIGHT.labels(method, path, self.app_name).inc()
        REQUESTS_TOTAL.labels(method, path, self.app_name).inc()

        start = time.perf_counter()
        status = 500  # ← 예외 시 기본값으로 깔아둠
        try:
            response: Response = await call_next(request)
            status = response.status_code
            return response
        except Exception as e:
            EXCEPTIONS.labels(method, path, type(e).__name__, self.app_name).inc()
            raise
        finally:
            elapsed = time.perf_counter() - start
            REQUESTS_DURATION.labels(method, path, self.app_name).observe(elapsed)
            RESPONSES_TOTAL.labels(method, path, str(status), self.app_name).inc()
            INFLIGHT.labels(method, path, self.app_name).dec()

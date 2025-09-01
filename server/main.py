from __future__ import annotations
from fastapi import FastAPI, Depends, Security
from fastapi.middleware.cors import CORSMiddleware

from core.config import settings
from core.logging import setup_logging
from api.routers.campaigns import router as campaigns_router
from api.routers.categories import router as categories_router
from api.routers.health import router as healthcheck_router
from middlewares.access import AccessLogMiddleware


from api.security import require_api_key
from prometheus_fastapi_instrumentator import Instrumentator
# from prometheus_client import Gauge
# import psutil
# from contextlib import asynccontextmanager




setup_logging()


# @asynccontextmanager
# async def lifespan(app: FastAPI):
#     # 애플리케이션 시작 시 실행될 코드
#     print("Application startup...")
#     # /metrics 엔드포인트를 FastAPI 앱에 노출시킵니다.
#     instrumentator.expose(app)
#     print("Metrics endpoint exposed at /metrics")
#     yield
#     # 애플리케이션 종료 시 실행될 코드 (현재는 필요 없음)
#     print("Application shutdown.")


v1_app = FastAPI(
        title=settings.app_name, 
        version="1.0.0", 
        # docs_url=f"{settings.api_prefix}/docs", 
        # openapi_url=f"{settings.api_prefix}/openapi.json",
    )
# Access Log 미들웨어를 가장 먼저 등록
v1_app.add_middleware(AccessLogMiddleware)


v1_app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

v1_app.include_router(healthcheck_router)
v1_app.include_router(categories_router, dependencies=[Depends(require_api_key)])
v1_app.include_router(campaigns_router, dependencies=[Depends(require_api_key)])
# v1_app.add_middleware(SecretKeyMiddleware, secret_key=settings.API_SECRET_KEY)


app = FastAPI()
app.mount(f"{settings.api_prefix}", v1_app)

Instrumentator().instrument(app).expose(app)


# 2. 시스템/프로세스 메트릭을 위한 Gauge 생성
# CPU_USAGE = Gauge('process_cpu_percent', 'Total CPU percentage usage of the process')
# MEMORY_USAGE_BYTES = Gauge('process_virtual_memory_bytes', 'Virtual memory usage of the process in bytes')
# DISK_USAGE_PERCENT = Gauge('disk_usage_percent', 'Disk usage percentage of the root directory')

# 5. 메트릭 업데이트를 위한 콜백 함수 등록
# def update_system_metrics():
#     """현재 프로세스와 시스템의 리소스 사용량을 가져와 Gauge 메트릭을 업데이트합니다."""
#     process = psutil.Process(os.getpid())
#     CPU_USAGE.set(process.cpu_percent(interval=0.1))
#     MEMORY_USAGE_BYTES.set(process.memory_info().vms)
#     DISK_USAGE_PERCENT.set(psutil.disk_usage('/').percent)

# instrumentator.add(update_system_metrics)

@app.get("/health", tags=["health"])
async def health():
    return {"status": "ok"}
from __future__ import annotations
from fastapi import FastAPI, Depends, Security
from fastapi.middleware.cors import CORSMiddleware

from core.config import settings
from core.logging import setup_logging
from api.routers.campaigns import router as campaigns_router
from api.routers.health import router as healthcheck_router


from api.security import require_api_key



setup_logging()

v1_app = FastAPI(
        title=settings.app_name, 
        version="1.0.0", 
        # docs_url=f"{settings.api_prefix}/docs", 
        # openapi_url=f"{settings.api_prefix}/openapi.json",
    )

v1_app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

v1_app.include_router(healthcheck_router)
v1_app.include_router(campaigns_router, dependencies=[Depends(require_api_key)])
# v1_app.add_middleware(SecretKeyMiddleware, secret_key=settings.API_SECRET_KEY)


app = FastAPI()
app.mount(f"{settings.api_prefix}", v1_app)

@app.get("/health", tags=["health"])
async def health():
    return {"status": "ok"}
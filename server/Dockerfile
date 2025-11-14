# --- 1. 기반 이미지
FROM python:3.12-slim-bookworm

# --- 2. 환경 변수
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=config.settings

# --- 3. 시스템 의존성 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    tini \
    postgresql-client \
    libpq-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# --- 4. 작업 디렉토리
WORKDIR /app

# --- 5. uv 설치 (Python 패키지 관리자)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# --- 6. 의존성 파일 복사 및 설치
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

# --- 7. 소스 복사
COPY . .

# --- 8. 엔트리포인트 스크립트 권한
RUN chmod +x /app/entrypoint.sh

# --- 9. 포트
EXPOSE 8000

# --- 10. 실행
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/entrypoint.sh"]

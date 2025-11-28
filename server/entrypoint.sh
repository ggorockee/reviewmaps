#!/usr/bin/env bash
set -euo pipefail

# 환경 변수 기본값 설정
WORKERS=${WORKERS:-2}
PORT=${PORT:-8000}
export PROMETHEUS_MULTIPROC_DIR=${PROMETHEUS_MULTIPROC_DIR:-/tmp/metrics}

# Prometheus 멀티프로세스 디렉토리 설정 (Gunicorn 사용 시 필수)
echo "Setting up Prometheus multiprocess directory: ${PROMETHEUS_MULTIPROC_DIR}"
mkdir -p "${PROMETHEUS_MULTIPROC_DIR}"
rm -rf "${PROMETHEUS_MULTIPROC_DIR}"/*  # 시작 시 기존 메트릭 파일 정리
chmod 777 "${PROMETHEUS_MULTIPROC_DIR}"

# Django 마이그레이션 실행
echo "Running Django migrations..."
/app/.venv/bin/python manage.py migrate --noinput

# Static 파일 수집 (Django Ninja Swagger UI 등)
echo "Collecting static files..."
/app/.venv/bin/python manage.py collectstatic --noinput

# Gunicorn + Uvicorn으로 Django ASGI 서버 실행
echo "Starting Django server with Gunicorn (workers: ${WORKERS}, port: ${PORT})..."
exec /app/.venv/bin/gunicorn \
  -w "${WORKERS}" \
  -k uvicorn.workers.UvicornWorker \
  -b "0.0.0.0:${PORT}" \
  --access-logfile - \
  --error-logfile - \
  --log-level info \
  config.asgi:application

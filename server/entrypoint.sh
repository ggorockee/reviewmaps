#!/usr/bin/env bash
set -euo pipefail

# 환경 변수 기본값 설정
WORKERS=${WORKERS:-2}
PORT=${PORT:-8000}

# Django 마이그레이션 실행
echo "Running Django migrations..."
/app/.venv/bin/python manage.py migrate --noinput

# Static 파일 수집 (필요한 경우)
if [[ "${COLLECT_STATIC:-false}" == "true" ]]; then
  echo "Collecting static files..."
  /app/.venv/bin/python manage.py collectstatic --noinput
fi

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

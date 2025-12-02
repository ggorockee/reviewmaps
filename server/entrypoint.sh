#!/usr/bin/env bash
set -euo pipefail

# ===== 환경 변수 기본값 설정 =====
PORT=${PORT:-8000}
export PROMETHEUS_MULTIPROC_DIR=${PROMETHEUS_MULTIPROC_DIR:-/tmp/metrics}

# ===== Gunicorn Worker 설정 (성능 최적화) =====
# CPU 코어 수 기반 Worker 수 계산 (권장: 2*CPU + 1)
# 컨테이너 환경에서는 cgroup 제한을 고려해야 함
CPU_CORES=$(nproc --all 2>/dev/null || echo 2)
# Worker 수: 환경변수 우선, 없으면 자동 계산 (최소 2, 최대 8)
if [ -z "${WORKERS:-}" ]; then
    CALCULATED_WORKERS=$((CPU_CORES * 2 + 1))
    WORKERS=$(( CALCULATED_WORKERS > 8 ? 8 : (CALCULATED_WORKERS < 2 ? 2 : CALCULATED_WORKERS) ))
fi

# Gunicorn 추가 설정
WORKER_CONNECTIONS=${WORKER_CONNECTIONS:-1000}
WORKER_TIMEOUT=${WORKER_TIMEOUT:-60}
KEEPALIVE=${KEEPALIVE:-5}
MAX_REQUESTS=${MAX_REQUESTS:-10000}
MAX_REQUESTS_JITTER=${MAX_REQUESTS_JITTER:-1000}

# Prometheus 멀티프로세스 디렉토리 설정 (Gunicorn 사용 시 필수)
echo "Setting up Prometheus multiprocess directory: ${PROMETHEUS_MULTIPROC_DIR}"
mkdir -p "${PROMETHEUS_MULTIPROC_DIR}"
rm -rf "${PROMETHEUS_MULTIPROC_DIR}"/*  # 시작 시 기존 메트릭 파일 정리
chmod 777 "${PROMETHEUS_MULTIPROC_DIR}"

# Django 마이그레이션 생성 및 실행
echo "Creating Django migrations (if any)..."
/app/.venv/bin/python manage.py makemigrations --noinput

echo "Running Django migrations..."
/app/.venv/bin/python manage.py migrate --noinput

# Static 파일 수집 (Django Ninja Swagger UI 등)
echo "Collecting static files..."
/app/.venv/bin/python manage.py collectstatic --noinput

# Gunicorn + Uvicorn으로 Django ASGI 서버 실행 (성능 최적화)
echo "Starting Django server with Gunicorn..."
echo "  - Workers: ${WORKERS}"
echo "  - Port: ${PORT}"
echo "  - Worker Timeout: ${WORKER_TIMEOUT}s"
echo "  - Keepalive: ${KEEPALIVE}s"
echo "  - Max Requests: ${MAX_REQUESTS} (jitter: ${MAX_REQUESTS_JITTER})"

exec /app/.venv/bin/gunicorn \
  -w "${WORKERS}" \
  -k uvicorn.workers.UvicornWorker \
  -b "0.0.0.0:${PORT}" \
  --access-logfile - \
  --error-logfile - \
  --log-level info \
  --timeout "${WORKER_TIMEOUT}" \
  --keep-alive "${KEEPALIVE}" \
  --max-requests "${MAX_REQUESTS}" \
  --max-requests-jitter "${MAX_REQUESTS_JITTER}" \
  --graceful-timeout 30 \
  --worker-tmp-dir /dev/shm \
  config.asgi:application

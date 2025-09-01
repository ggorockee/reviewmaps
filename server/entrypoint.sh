#!/usr/bin/env bash
set -euo pipefail

# multiprocess 디렉토리 초기화 (안 비우면 예전 워커 파일이 남아서 합산이 꼬임)
if [[ -n "${PROMETHEUS_MULTIPROC_DIR:-}" ]]; then
  rm -rf "${PROMETHEUS_MULTIPROC_DIR}" || true
  mkdir -p "${PROMETHEUS_MULTIPROC_DIR}"
fi

# gunicorn 실행 (워커 수는 환경에 맞춰 조절)
exec gunicorn -w 2 -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000 main:app

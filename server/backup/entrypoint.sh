#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${PROMETHEUS_MULTIPROC_DIR:-}" ]]; then
  rm -rf "${PROMETHEUS_MULTIPROC_DIR}" || true
  mkdir -p "${PROMETHEUS_MULTIPROC_DIR}"
fi

exec gunicorn -w 2 -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000 main:app

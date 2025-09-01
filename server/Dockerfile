# --- 1. 기반 이미지
FROM python:3.12-slim-bookworm

# --- 2. 환경 변수
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PROMETHEUS_MULTIPROC_DIR=/tmp/metrics

RUN mkdir ${PROMETHEUS_MULTIPROC_DIR}

# (선택) tini로 좀 더 안전한 신호처리
RUN apt-get update && apt-get install -y --no-install-recommends tini && rm -rf /var/lib/apt/lists/*

# --- 3. 작업 디렉토리
WORKDIR /app

# --- 4. 의존성
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- 5. 소스 복사
COPY . .

# --- 6. 엔트리포인트 스크립트 권한
RUN chmod +x /app/entrypoint.sh

# --- 7. 포트
EXPOSE 8000

# --- 8. 실행
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/entrypoint.sh"]

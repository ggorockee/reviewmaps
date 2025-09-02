# --- 1) Base Image ---
FROM python:3.12-slim-bookworm

# --- 2) Env ---
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# --- 3) 시스템 패키지 (필수 최소만) ---
# - ca-certificates: HTTPS 통신
# - tzdata: 타임존 (Asia/Seoul 등)
# - tini: 신호 전달/좀비 프로세스 방지 (권장)
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates tzdata tini \
    && rm -rf /var/lib/apt/lists/*

# --- 4) 작업 디렉토리 ---
WORKDIR /app

# --- 5) 파이썬 의존성 ---
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- 6) 애플리케이션 소스 ---
COPY . .
RUN chmod +x entrypoint.sh

# --- 7) 엔트리포인트 ---
# tini를 통해 신호전달/종료처리 깔끔히
ENTRYPOINT ["/usr/bin/tini", "--", "./entrypoint.sh"]

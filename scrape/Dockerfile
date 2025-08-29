# --- 1. 기반 이미지 설정 (Base Image) ---
FROM python:3.12-slim-bookworm

# --- 2. 환경 변수 설정 (Environment Variables) ---
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    CHROME_BIN=/usr/bin/chromium

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    chromium \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libnspr4 libnss3 \
    libx11-6 libx11-xcb1 libxcomposite1 libxcursor1 libxdamage1 libxi6 \
    libxrandr2 libxrender1 libxss1 libxtst6 libgbm1 \
    tzdata ca-certificates curl gnupg unzip \
    && rm -rf /var/lib/apt/lists/*

# --- 3. 작업 디렉토리 설정 (Work Directory) ---
WORKDIR /app

# --- 4. 파이썬 의존성 설치 (Install Dependencies) ---
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- 5. 소스 코드 및 스크립트 복사 (Copy Source Code & Scripts) ---
# .dockerignore에 명시된 파일을 제외하고 모든 파일을 복사합니다.
COPY . .

# entrypoint.sh 스크립트에 실행 권한을 부여합니다.
RUN chmod +x entrypoint.sh


# entrypoint.sh 스크립트가 실행된 후, 이 gunicorn 명령어가 실행됩니다.
ENTRYPOINT ["./entrypoint.sh"]
# --- 1. 기반 이미지 설정 (Base Image) ---
FROM python:3.12-slim-bookworm

# --- 2. 환경 변수 설정 (Environment Variables) ---
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# --- 3. 작업 디렉토리 설정 (Work Directory) ---
WORKDIR /app

# --- 4. 파이썬 의존성 설치 (Install Dependencies) ---
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- 5. 소스 코드 및 스크립트 복사 (Copy Source Code & Scripts) ---
# .dockerignore에 명시된 파일을 제외하고 모든 파일을 복사합니다.
COPY . .

# --- 6. 시작 스크립트 실행 권한 부여 (Add Execute Permissions) ---
# 컨테이너가 시작될 때 실행될 entrypoint.sh 파일에 실행 권한을 줍니다.
# "이 스크립트, 믿고 실행해도 좋아!" 라는 허가증을 발급하는 셈이죠.
# RUN chmod +x /app/entrypoint.sh

# --- 7. 포트 노출 (Expose Port) ---
EXPOSE 8000

# --- 8. 컨테이너 실행 명령어 (Entrypoint & Command) ---
# 컨테이너가 시작되면 entrypoint.sh 스크립트를 먼저 실행합니다.
ENTRYPOINT ["/app/entrypoint.sh"]

# entrypoint.sh 스크립트가 실행된 후, 이 gunicorn 명령어가 실행됩니다.
CMD ["gunicorn", "-w", "2", "-k", "uvicorn.workers.UvicornWorker", "-b", "0.0.0.0:8000", "main:app"]
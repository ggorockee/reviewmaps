# 환경변수 설정 가이드 (Environment Variables Guide)

ReviewMaps 서버 환경변수 설정 및 관리 가이드입니다.

## 📋 목차

1. [개요](#개요)
2. [환경별 설정 방법](#환경별-설정-방법)
3. [필수 환경변수](#필수-환경변수)
4. [SNS 로그인 설정](#sns-로그인-설정)
5. [보안 주의사항](#보안-주의사항)
6. [트러블슈팅](#트러블슈팅)

---

## 개요

ReviewMaps는 환경변수를 통해 민감한 정보(Secret Key, API Key 등)를 관리합니다. 이를 통해:

- **보안 강화**: Secret 정보가 소스 코드에 하드코딩되지 않음
- **환경별 설정**: 개발/스테이징/프로덕션 환경마다 다른 설정 가능
- **유연한 배포**: Docker, Kubernetes 등 다양한 환경에서 쉽게 배포

---

## 환경별 설정 방법

### 1. 로컬 개발 환경

**방법 1: `.env` 파일 사용 (권장)**

프로젝트 루트에 `.env` 파일을 생성하고 환경변수를 설정합니다.

```bash
# .env 파일 생성
cd /home/woohaen88/reviewmaps/server
cp .env.example .env  # .env.example이 있는 경우
```

**방법 2: 직접 환경변수 설정**

```bash
export SECRET_KEY="your-secret-key-here"
export POSTGRES_USER="test"
export POSTGRES_PASSWORD="test1234"
```

### 2. Docker 환경

**docker-compose.yml에서 환경변수 설정:**

```yaml
version: '3.8'

services:
  web:
    build: .
    environment:
      - SECRET_KEY=${SECRET_KEY}
      - POSTGRES_HOST=db
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    env_file:
      - .env  # 또는 .env 파일 사용
```

### 3. Kubernetes 환경

**Secret 리소스 생성:**

```bash
# K8s Secret 생성
kubectl create secret generic reviewmaps-secrets \
  --from-literal=SECRET_KEY='your-secret-key' \
  --from-literal=POSTGRES_PASSWORD='your-password' \
  --from-literal=APPLE_PRIVATE_KEY='-----BEGIN PRIVATE KEY-----...'
```

**Deployment에서 Secret 참조:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reviewmaps-server
spec:
  template:
    spec:
      containers:
      - name: server
        env:
        - name: SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: reviewmaps-secrets
              key: SECRET_KEY
        - name: APPLE_PRIVATE_KEY
          valueFrom:
            secretKeyRef:
              name: reviewmaps-secrets
              key: APPLE_PRIVATE_KEY
```

---

## 필수 환경변수

### Django 설정

| 환경변수 | 설명 | 기본값 | 필수 여부 |
|---------|------|--------|---------|
| `SECRET_KEY` | Django Secret Key (암호화에 사용) | - | ✅ 프로덕션 필수 |
| `DEBUG` | 디버그 모드 (True/False) | `False` | 개발 환경에서만 True |
| `ALLOWED_HOSTS` | 허용된 호스트 (콤마로 구분) | `*` | ✅ 프로덕션 필수 |

**예시:**
```bash
SECRET_KEY="django-insecure-zfqoeu-c3^ciy0f98qadcng#l-do0f)w$)sctm)m196*&$-&ia"
DEBUG=True
ALLOWED_HOSTS="localhost,127.0.0.1,review-maps.com"
```

### 데이터베이스 설정

| 환경변수 | 설명 | 기본값 | 필수 여부 |
|---------|------|--------|---------|
| `POSTGRES_DB` | PostgreSQL 데이터베이스 이름 | `test` | ✅ |
| `POSTGRES_USER` | PostgreSQL 사용자명 | `test` | ✅ |
| `POSTGRES_PASSWORD` | PostgreSQL 비밀번호 | `test1234` | ✅ |
| `POSTGRES_HOST` | PostgreSQL 호스트 | `localhost` | ✅ |
| `POSTGRES_PORT` | PostgreSQL 포트 | `5432` | ✅ |

**예시:**
```bash
POSTGRES_DB=reviewmaps
POSTGRES_USER=postgres
POSTGRES_PASSWORD=secure_password_here
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
```

### JWT 인증 설정

| 환경변수 | 설명 | 기본값 | 필수 여부 |
|---------|------|--------|---------|
| `JWT_SECRET_KEY` | JWT 토큰 서명용 Secret Key | `SECRET_KEY` 값 사용 | ✅ 프로덕션 필수 |
| `JWT_ALGORITHM` | JWT 알고리즘 | `HS256` | ❌ |
| `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` | Access Token 만료 시간 (분) | `60` | ❌ |
| `JWT_REFRESH_TOKEN_EXPIRE_DAYS` | Refresh Token 만료 시간 (일) | `7` | ❌ |

**예시:**
```bash
JWT_SECRET_KEY="your-jwt-secret-key-different-from-django-secret"
JWT_ALGORITHM=HS256
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=60
JWT_REFRESH_TOKEN_EXPIRE_DAYS=7
```

---

## SNS 로그인 설정

ReviewMaps는 Kakao, Google, Apple 소셜 로그인을 지원합니다. 모바일 앱에서 SDK를 통해 로그인하고, 서버에서 토큰을 검증하는 방식입니다.

### Kakao OAuth

| 환경변수 | 설명 | 필수 여부 |
|---------|------|---------|
| `KAKAO_REST_API_KEY` | Kakao REST API Key | ✅ |

**설정 방법:**

1. [Kakao Developers](https://developers.kakao.com/)에서 앱 생성
2. 앱 설정 → 앱 키 → REST API 키 복사
3. 플랫폼 설정 → Android/iOS 추가

**예시:**
```bash
KAKAO_REST_API_KEY="b64bd3b7f45b07189a68b360212b9adb"
```

**참고:**
- 현재는 모바일 SDK 방식을 사용하므로 `KAKAO_CLIENT_SECRET`, `KAKAO_REDIRECT_URI`는 불필요
- 향후 서버측 OAuth 흐름 구현 시 추가 필요

### Google OAuth

| 환경변수 | 설명 | 필수 여부 |
|---------|------|---------|
| `GOOGLE_CLIENT_ID_IOS` | Google Client ID (iOS) | ✅ |
| `GOOGLE_CLIENT_ID_ANDROID` | Google Client ID (Android) | ✅ |
| `GOOGLE_PROJECT_ID` | Google Cloud 프로젝트 ID | ✅ |

**설정 방법:**

1. [Google Cloud Console](https://console.cloud.google.com/)에서 프로젝트 생성
2. API 및 서비스 → 사용자 인증 정보 → OAuth 2.0 클라이언트 ID 생성
3. iOS 클라이언트: Bundle ID 입력 (`com.reviewmaps.mobile`)
4. Android 클라이언트: 패키지 이름 + SHA-1 인증서 지문 입력

**예시:**
```bash
GOOGLE_CLIENT_ID_IOS="966129856796-7f4f5j9mtf5g2c5ovjv8qg8mkov4rjuc.apps.googleusercontent.com"
GOOGLE_CLIENT_ID_ANDROID="966129856796-tnbd5ujd591j9erl0d59sf7lk4sovpnc.apps.googleusercontent.com"
GOOGLE_PROJECT_ID="reviewmaps-478704"
```

**참고:**
- 모바일 SDK 사용 시 `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI`는 불필요

### Apple Sign In

| 환경변수 | 설명 | 필수 여부 |
|---------|------|---------|
| `APPLE_CLIENT_ID` | Apple Client ID (Bundle ID) | ✅ |
| `APPLE_TEAM_ID` | Apple 개발자 팀 ID | ✅ |
| `APPLE_KEY_ID` | Apple Sign In Key ID | ✅ |
| `APPLE_PRIVATE_KEY` | Apple Private Key (PEM 형식) | ✅ (K8s 권장) |
| `APPLE_PRIVATE_KEY_PATH` | Apple Private Key 파일 경로 | ✅ (로컬 개발) |

**설정 방법:**

1. [Apple Developer](https://developer.apple.com/)에서 App ID 생성
2. Sign In with Apple 기능 활성화
3. Keys → Sign In with Apple 키 생성 (.p8 파일 다운로드)
4. Team ID, Key ID 확인

**예시 (로컬 개발):**
```bash
APPLE_CLIENT_ID="com.reviewmaps.mobile"
APPLE_TEAM_ID="KSSVSPN647"
APPLE_KEY_ID="L5X5MR634"
APPLE_PRIVATE_KEY_PATH="/home/woohaen88/reviewmaps/server/secret_files/AuthKey_L5X5MR6345.p8"
```

**예시 (K8s 배포):**
```bash
APPLE_CLIENT_ID="com.reviewmaps.mobile"
APPLE_TEAM_ID="KSSVSPN647"
APPLE_KEY_ID="L5X5MR634"
APPLE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgShN27Vz1Nxx+JqTq
H232NTssC7u4qiC9Wv46gur58LmgCgYIKoZIzj0DAQehRANCAARb/7LamrgZYb7k
Yvef5ccavsQrRNRatmznGO+6MDGn///aBWKsw7CVPrEsz1cwBNXSPOzleat0NXyZ
GdTOHLv+
-----END PRIVATE KEY-----"
```

**중요:**
- `APPLE_PRIVATE_KEY`는 K8s Secret으로 주입하는 것이 안전 (환경변수로 직접 설정)
- 로컬 개발은 `APPLE_PRIVATE_KEY_PATH` 사용 (파일 경로)
- `.p8` 파일은 절대 Git에 커밋하지 말 것 (`.gitignore`에 추가됨)

---

## 보안 주의사항

### 1. Secret 정보 관리

**✅ 해야 할 것:**
- `.env` 파일을 `.gitignore`에 추가
- K8s Secret 사용 (환경변수 직접 주입)
- 프로덕션 환경에서는 강력한 Secret Key 사용
- 주기적으로 Secret Key 교체

**❌ 하지 말아야 할 것:**
- Secret 정보를 소스 코드에 하드코딩
- `.env` 파일을 Git에 커밋
- 프로덕션 환경에서 `DEBUG=True` 사용
- `ALLOWED_HOSTS=*` 프로덕션 사용

### 2. 환경변수 검증

Django `settings.py`에서 프로덕션 환경의 필수 환경변수를 검증합니다:

```python
if not DEBUG:
    SECRET_KEY = os.getenv('SECRET_KEY')
    if not SECRET_KEY:
        raise ValueError("SECRET_KEY environment variable is required in production")

    JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY')
    if not JWT_SECRET_KEY:
        raise ValueError("JWT_SECRET_KEY environment variable is required in production")
```

### 3. CORS 및 CSRF 설정

**개발 환경:**
```bash
CORS_ALLOW_ALL_ORIGINS=True  # 모바일 앱 개발용
```

**프로덕션 환경:**
```python
# settings.py에서 특정 도메인만 허용
CORS_ALLOWED_ORIGINS = [
    "https://review-maps.com",
    "https://www.review-maps.com",
]

CSRF_TRUSTED_ORIGINS = [
    'https://api.review-maps.com',
    'https://review-maps.com',
]
```

---

## 트러블슈팅

### 1. Apple Private Key 로드 실패

**증상:**
```
WARNING:users.services.apple:Apple private key not found
```

**해결 방법:**
- `APPLE_PRIVATE_KEY` 환경변수가 설정되어 있는지 확인
- 또는 `APPLE_PRIVATE_KEY_PATH` 파일 경로가 올바른지 확인
- PEM 형식이 올바른지 확인 (`-----BEGIN PRIVATE KEY-----`로 시작)

### 2. 데이터베이스 연결 실패

**증상:**
```
django.db.utils.OperationalError: could not connect to server
```

**해결 방법:**
```bash
# PostgreSQL 서비스 확인
sudo systemctl status postgresql

# 환경변수 확인
echo $POSTGRES_HOST
echo $POSTGRES_USER

# 연결 테스트
psql -h localhost -U test -d test
```

### 3. JWT 토큰 검증 실패

**증상:**
```
401 Unauthorized - Invalid token
```

**해결 방법:**
- `JWT_SECRET_KEY`가 토큰 발급 시와 검증 시 동일한지 확인
- 토큰 만료 시간 확인
- 알고리즘 일치 확인 (`HS256`)

### 4. SNS 로그인 토큰 검증 실패

**Kakao:**
```bash
# 토큰 유효성 직접 확인
curl -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  https://kapi.kakao.com/v2/user/me
```

**Google:**
```bash
# 토큰 유효성 직접 확인
curl https://www.googleapis.com/oauth2/v2/userinfo \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

**Apple:**
- JWT 서명 검증 실패: Apple 공개 키 캐시 확인
- audience 불일치: `APPLE_CLIENT_ID` 확인

---

## 환경변수 템플릿

### .env 템플릿 (로컬 개발)

```bash
# Django Secret Key
SECRET_KEY="django-insecure-your-secret-key-here"

# API Key
API_SECRET_KEY=your-api-secret-key-here

# Debug
DEBUG=True

# Database
POSTGRES_USER=test
POSTGRES_PASSWORD=test1234
POSTGRES_DB=test
POSTGRES_HOST=localhost
POSTGRES_PORT=5432

# JWT 인증 설정
JWT_SECRET_KEY="your-jwt-secret-key-here"
JWT_ALGORITHM=HS256
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=60
JWT_REFRESH_TOKEN_EXPIRE_DAYS=7

# Kakao OAuth
KAKAO_REST_API_KEY=your-kakao-rest-api-key

# Google OAuth
GOOGLE_CLIENT_ID_IOS=your-google-client-id-ios
GOOGLE_CLIENT_ID_ANDROID=your-google-client-id-android
GOOGLE_PROJECT_ID=your-google-project-id

# Apple OAuth
APPLE_CLIENT_ID=com.reviewmaps.mobile
APPLE_TEAM_ID=YOUR_TEAM_ID
APPLE_KEY_ID=YOUR_KEY_ID
APPLE_PRIVATE_KEY_PATH=/path/to/AuthKey_XXXXX.p8
```

### K8s Secret 템플릿

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: reviewmaps-secrets
  namespace: default
type: Opaque
stringData:
  API_SECRET_KEY: 9e53ccafd6e993152e01e9e7a8ca66d1c2224bb5b21c78cf076f6e45dcbc0d12
  JWT_SECRET_KEY: "django-insecure-your-jwt-secret-key"
  SECRET_KEY: "django-insecure-your-django-secret-key"
  KAKAO_REST_API_KEY: "your-kakao-rest-api-key"
  GOOGLE_CLIENT_ID_IOS: "your-google-client-id-ios"
  GOOGLE_CLIENT_ID_ANDROID: "your-google-client-id-android"
  GOOGLE_PROJECT_ID: "your-google-project-id"
  APPLE_CLIENT_ID: "com.reviewmaps.mobile"
  APPLE_TEAM_ID: YOUR_TEAM_ID
  APPLE_KEY_ID: YOUR_KEY_ID
  APPLE_PRIVATE_KEY: |
    -----BEGIN PRIVATE KEY-----
    YOUR_APPLE_PRIVATE_KEY_HERE
    -----END PRIVATE KEY-----
```

---

## 참고 자료

- [Django Settings 공식 문서](https://docs.djangoproject.com/en/5.2/ref/settings/)
- [Kakao Developers](https://developers.kakao.com/)
- [Google Cloud Console](https://console.cloud.google.com/)
- [Apple Developer](https://developer.apple.com/)
- [Twelve-Factor App (환경변수 관리 원칙)](https://12factor.net/config)

---

**최종 업데이트:** 2025-11-19
**작성자:** Claude Code
**버전:** 1.0.0

# SNS 로그인 시스템 배포 가이드 및 문제 해결

**작성일**: 2025-11-20
**버전**: 1.0
**대상**: 서버 운영자, 개발자

## 📋 개요

이 문서는 SNS 로그인 시스템(Kakao, Google, Apple)의 서버 배포 및 문제 해결 가이드입니다.

**핵심 개념**:
- ✅ **email은 중복 가능**
- ✅ **email + login_method가 unique key**
- ✅ 같은 이메일로 4개의 별도 계정 생성 가능 (email, kakao, google, apple)
- ✅ username은 `{email}_{login_method}` 형식으로 자동 생성

## 🚀 서버 배포 체크리스트

### 1단계: 코드 배포 확인
```bash
# 서버에 접속
ssh user@your-server

# 프로젝트 디렉토리 이동
cd /path/to/reviewmaps/server

# 최신 코드 pull
git checkout main
git pull origin main

# 최신 커밋 확인
git log -1 --oneline
# 예상: 4964c8f feat: SNS 로그인 API 이메일 정규화 및 통합 테스트 추가
```

### 2단계: 의존성 설치
```bash
# uv를 사용하여 의존성 동기화
uv sync

# 또는 pip 사용
source .venv/bin/activate
pip install -r requirements.txt
```

### 3단계: 데이터베이스 마이그레이션 실행 (중요!)
```bash
# 마이그레이션 파일 확인
python manage.py showmigrations users

# 예상 출력 (모두 [X] 표시되어야 함):
# users
#  [X] 0001_initial
#  [X] 0002_user_login_method
#  [X] 0003_socialaccount
#  [X] 0004_user_username_alter_user_email_and_more

# 마이그레이션 실행
python manage.py migrate

# 성공 메시지:
# Applying users.0004_user_username_alter_user_email_and_more... OK
```

**⚠️ 중요**: Migration 0004가 가장 핵심입니다. 이 마이그레이션이 적용되지 않으면 SNS 로그인이 작동하지 않습니다!

### 4단계: Django 서버 재시작
```bash
# Gunicorn 사용 시
sudo systemctl restart gunicorn

# 또는 Docker 사용 시
docker-compose restart

# 또는 프로세스 직접 재시작
pkill -f "python manage.py runserver"
python manage.py runserver 0.0.0.0:8000
```

### 5단계: 배포 검증
```bash
# 데이터베이스 스키마 확인
python manage.py dbshell

-- users 테이블 스키마 확인
\d users;

-- 예상 결과: username 필드 존재, email+login_method unique constraint 존재
```

## 🔍 문제 해결 가이드

### 문제 1: "kakao로 회원가입이 안된다" (401 에러)

**증상**:
```json
{
  "detail": "유효하지 않은 토큰입니다"
}
```

**원인**: 서버에서 migration이 실행되지 않아 DB 스키마가 이전 버전

**해결방법**:
```bash
# 1. Migration 상태 확인
python manage.py showmigrations users

# 2. Migration 실행
python manage.py migrate

# 3. 서버 재시작
sudo systemctl restart gunicorn

# 4. 테스트
curl -X POST https://your-api.com/v1/auth/sns/kakao \
  -H "Content-Type: application/json" \
  -d '{"access_token": "YOUR_KAKAO_TOKEN"}'
```

### 문제 2: Migration이 이미 적용되었다고 나오는데 여전히 에러

**증상**: `showmigrations`에서 [X] 표시되지만 SNS 로그인 실패

**원인**: 서버가 재시작되지 않아 이전 코드 실행 중

**해결방법**:
```bash
# 1. Django 프로세스 완전 종료
ps aux | grep "python manage.py"
kill -9 [PID]

# 2. 서버 재시작
python manage.py runserver 0.0.0.0:8000

# 또는 Gunicorn 재시작
sudo systemctl restart gunicorn
```

### 문제 3: Database IntegrityError - email must be unique

**증상**:
```
IntegrityError: duplicate key value violates unique constraint "users_email_key"
```

**원인**: Migration 0004가 적용되지 않아 email에 unique constraint가 남아있음

**해결방법**:
```bash
# 1. Migration 롤백 후 재적용
python manage.py migrate users 0003
python manage.py migrate users 0004

# 2. DB 직접 확인
python manage.py dbshell

-- unique constraint 확인
SELECT conname FROM pg_constraint
WHERE conrelid = 'users'::regclass;

-- 예상: users_email_login_method_unique 존재
--      users_email_key 없어야 함
```

### 문제 4: username already exists 에러

**증상**:
```
IntegrityError: duplicate key value violates unique constraint "users_username_key"
```

**원인**: 기존 사용자의 username이 제대로 생성되지 않음

**해결방법**:
```bash
# Django shell로 수동 수정
python manage.py shell

# Python shell에서:
from users.models import User

# 모든 사용자의 username 재생성
for user in User.objects.all():
    user.username = f"{user.email}_{user.login_method}"
    user.save()
    print(f"Updated: {user.username}")

exit()
```

## 🧪 테스트 가이드

### 로컬 테스트
```bash
# 모든 테스트 실행
python manage.py test users.tests

# SNS API 통합 테스트만 실행
python manage.py test users.tests.test_api_social -v 2

# 예상 결과: 6/6 통과
# - test_same_email_creates_separate_accounts_for_different_providers
# - test_get_or_create_with_existing_account
# - test_realistic_woohaen88_scenario
# - test_social_account_unique_constraint
# - test_user_can_have_multiple_social_accounts
# - test_email_domain_normalization
```

### API 테스트 (Postman/cURL)

#### 1. Kakao 로그인 테스트
```bash
curl -X POST https://your-api.com/v1/auth/sns/kakao \
  -H "Content-Type: application/json" \
  -d '{
    "access_token": "REAL_KAKAO_ACCESS_TOKEN"
  }'

# 성공 응답:
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "token_type": "bearer",
  "user": {
    "id": 1,
    "email": "user@example.com",
    "login_method": "kakao",
    "is_active": true,
    "date_joined": "2025-11-20T..."
  }
}
```

#### 2. Google 로그인 테스트
```bash
curl -X POST https://your-api.com/v1/auth/sns/google \
  -H "Content-Type: application/json" \
  -d '{
    "access_token": "REAL_GOOGLE_ACCESS_TOKEN"
  }'
```

#### 3. Apple 로그인 테스트
```bash
curl -X POST https://your-api.com/v1/auth/sns/apple \
  -H "Content-Type: application/json" \
  -d '{
    "identity_token": "REAL_APPLE_IDENTITY_TOKEN",
    "authorization_code": "REAL_APPLE_AUTH_CODE"
  }'
```

### 계정 분리 검증 테스트

같은 이메일(woohaen88@gmail.com)로 4개 계정이 생성되는지 확인:

```bash
# Django shell
python manage.py shell

from users.models import User

email = "woohaen88@gmail.com"
users = User.objects.filter(email=email)

print(f"총 계정 수: {users.count()}")  # 예상: 4

for user in users:
    print(f"- {user.username} (login_method: {user.login_method})")

# 예상 출력:
# - woohaen88@gmail.com_email (login_method: email)
# - woohaen88@gmail.com_kakao (login_method: kakao)
# - woohaen88@gmail.com_google (login_method: google)
# - woohaen88@gmail.com_apple (login_method: apple)
```

## 📊 데이터베이스 스키마

### users 테이블
| 컬럼 | 타입 | 제약 | 설명 |
|------|------|------|------|
| id | integer | PK | 사용자 ID |
| username | varchar(255) | UNIQUE | email_loginmethod 형식 |
| email | varchar(254) | - | 이메일 (중복 가능) |
| login_method | varchar(20) | - | email/kakao/google/apple |
| password | varchar(128) | - | 해시된 비밀번호 |
| is_active | boolean | - | 활성 상태 |
| is_staff | boolean | - | 관리자 권한 |
| is_superuser | boolean | - | 슈퍼유저 권한 |
| date_joined | timestamptz | - | 가입일시 |

**Unique Constraints**:
- `users_username_key`: username UNIQUE
- `users_email_login_method_unique`: (email, login_method) UNIQUE

**Indexes**:
- `idx_email_login_method`: (email, login_method)

### social_accounts 테이블
| 컬럼 | 타입 | 제약 | 설명 |
|------|------|------|------|
| id | integer | PK | SocialAccount ID |
| user_id | integer | FK → users | 사용자 ID |
| provider | varchar(20) | - | kakao/google/apple |
| provider_user_id | varchar(255) | - | SNS 제공자의 사용자 ID |
| email | varchar(254) | - | SNS에서 받은 이메일 |
| name | varchar(100) | - | SNS에서 받은 이름 |
| profile_image | text | - | 프로필 이미지 URL |
| access_token | text | - | 액세스 토큰 |
| refresh_token | text | - | 리프레시 토큰 |
| token_expires_at | timestamptz | - | 토큰 만료 시간 |
| created_at | timestamptz | - | 생성일시 |
| updated_at | timestamptz | - | 수정일시 |

**Unique Constraints**:
- `social_accounts_provider_provider_user_id_unique`: (provider, provider_user_id) UNIQUE

**Indexes**:
- `idx_provider_user`: (provider, provider_user_id)
- `idx_user_provider`: (user_id, provider)

## 🔐 보안 고려사항

### 1. 토큰 저장
- ⚠️ **현재 상태**: access_token과 refresh_token이 평문 저장
- 🔒 **권장사항**: Django의 `cryptography` 라이브러리를 사용하여 암호화 저장
- 📝 **TODO**: 향후 구현 필요

### 2. API 키 관리
```bash
# .env 파일에 환경변수로 관리
KAKAO_API_KEY=your_kakao_api_key
GOOGLE_CLIENT_ID=your_google_client_id
APPLE_CLIENT_ID=your_apple_client_id

# settings.py에서 사용
KAKAO_API_KEY = os.getenv('KAKAO_API_KEY')
```

### 3. CORS 설정
```python
# config/settings.py
CORS_ALLOWED_ORIGINS = [
    "https://your-app.com",
    "https://www.your-app.com",
]
```

## 📝 변경 이력

### PR #38 (2025-11-20)
- **제목**: feat: SNS 로그인 API 이메일 정규화 및 통합 테스트 추가
- **변경사항**:
  - Kakao/Google/Apple API에 이메일 정규화 추가
  - 6개의 통합 테스트 추가
  - RFC 5321 준수 (domain만 소문자 변환)

### PR #37 (2025-11-20)
- **제목**: feat: Django Admin에 login_method 표시 추가
- **변경사항**:
  - UserAdmin에 login_method 필드 추가
  - SocialAccountAdmin 등록

### PR #35, #36 (2025-11-20)
- **제목**: feat: 로그인 방식별 계정 분리 시스템 구현
- **변경사항**:
  - username 필드 추가 (email_loginmethod)
  - unique_together = [['email', 'login_method']]
  - Migration 0004 추가

### PR #33 (2025-11-20)
- **제목**: fix: SNS 로그인 비동기 트랜잭션 처리 오류 수정
- **변경사항**:
  - `transaction.aget()` → `sync_to_async()` 수정

## 🆘 긴급 롤백 절차

만약 배포 후 심각한 문제가 발생하면:

```bash
# 1. Migration 롤백
python manage.py migrate users 0003

# 2. 이전 코드로 롤백
git checkout [이전_커밋_해시]

# 3. 서버 재시작
sudo systemctl restart gunicorn

# 4. 문제 확인 후 다시 배포 계획 수립
```

## 📞 지원

- **문제 발생 시**: GitHub Issues에 리포트
- **긴급 문의**: 개발팀 Slack 채널
- **로그 확인**: `/var/log/django/` 또는 Docker logs

## ✅ 최종 체크리스트

배포 전 다음 항목을 모두 확인하세요:

- [ ] 코드 최신화 완료 (`git pull`)
- [ ] 의존성 설치 완료 (`uv sync`)
- [ ] Migration 0004 적용 확인 (`python manage.py showmigrations`)
- [ ] 서버 재시작 완료
- [ ] 로컬 테스트 통과 (13/13)
- [ ] API 테스트 통과 (Kakao/Google/Apple)
- [ ] DB 스키마 확인 (username 필드, unique constraints)
- [ ] 모니터링 설정 확인
- [ ] 롤백 절차 숙지

---

**작성자**: Claude
**검토자**: -
**최종 업데이트**: 2025-11-20

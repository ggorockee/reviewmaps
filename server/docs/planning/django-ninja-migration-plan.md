# FastAPI → Django Ninja 마이그레이션 계획서

**작성일**: 2025-11-11
**프로젝트**: ReviewMaps API 서버
**목적**: FastAPI 기반 서버를 Django Ninja로 전환하며 새로운 기능 추가

---

## 📋 목차

1. [현재 상태 분석](#1-현재-상태-분석)
2. [마이그레이션 목표](#2-마이그레이션-목표)
3. [새로운 기능 요구사항](#3-새로운-기능-요구사항)
4. [기술 스택 변경](#4-기술-스택-변경)
5. [단계별 마이그레이션 계획](#5-단계별-마이그레이션-계획)
6. [데이터베이스 마이그레이션](#6-데이터베이스-마이그레이션)
7. [API 엔드포인트 매핑](#7-api-엔드포인트-매핑)
8. [테스트 전략](#8-테스트-전략)
9. [배포 전략](#9-배포-전략)
10. [체크리스트](#10-체크리스트)

---

## 1. 현재 상태 분석

### 1.1 FastAPI 프로젝트 구조

```
server/
├── api/
│   ├── routers/
│   │   ├── campaigns.py      # 캠페인 API (비동기)
│   │   ├── categories.py     # 카테고리 API (비동기)
│   │   ├── health.py         # 헬스체크
│   │   └── performance.py    # 성능 모니터링
│   ├── deps.py               # 의존성 주입
│   └── security.py           # API 키 인증
├── core/
│   ├── config.py             # 설정 관리 (Pydantic)
│   ├── logging.py            # 로깅 설정
│   └── utils.py              # 유틸리티
├── db/
│   ├── models.py             # SQLAlchemy 모델
│   ├── crud.py               # CRUD 로직 (비동기)
│   └── session.py            # 비동기 DB 세션
├── middlewares/
│   ├── access.py             # 액세스 로그
│   ├── auth.py               # 인증 미들웨어
│   └── metrics.py            # 메트릭 수집
├── schemas/
│   ├── campaign.py           # Pydantic 스키마
│   └── category.py
└── main.py                   # FastAPI 앱 진입점
```

### 1.2 핵심 비즈니스 로직

**비동기 처리가 필수인 부분**:
- 캠페인 목록 조회 (복잡한 필터링, 지리 기반 정렬)
- 카테고리 관리
- 성능 모니터링 쿼리 (EXPLAIN ANALYZE)

**현재 비동기 패턴**:
```python
# FastAPI + SQLAlchemy 2.0 비동기
async def list_campaigns(db: AsyncSession, ...):
    stmt = select(Campaign).where(...)
    result = await db.execute(stmt)
    return result.scalars().all()
```

### 1.3 Mobile 앱 하드코딩 분석

**발견된 하드코딩 부분**:

1. **광고 ID** (`lib/services/ad_service.dart`):
   ```dart
   // AdMob 앱 ID
   static const String _androidAppId = 'ca-app-pub-3219791135582658~5531424356';
   static const String _iosAppId = 'ca-app-pub-3219791135582658~2537889532';

   // 광고 단위 ID
   static const String _androidBannerAdId = 'ca-app-pub-3219791135582658/5314633015';
   static const String _iosBannerAdId = 'ca-app-pub-3219791135582658/7554300460';
   static const String _androidInterstitialAdId = 'ca-app-pub-3219791135582658/4509350635';
   static const String _iosInterstitialAdId = 'ca-app-pub-3219791135582658/6241218794';
   static const String _androidNativeAdId = 'ca-app-pub-3219791135582658/2361166614';
   static const String _iosNativeAdId = 'ca-app-pub-3219791135582658/9682496708';
   ```

2. **API 엔드포인트** (`lib/config/config.dart`):
   ```dart
   // .env에서 로드하지만 앱 재배포 필요
   static final String ReviewMapbaseUrl = _getEnv('REVIEWMAPS_BASE_URL');
   static final String ReviewMapApiKey = _getEnv('REVIEWMAPS_X_API_KEY');
   ```

3. **앱 버전 체크 로직 없음**:
   - 현재 앱 버전 강제 업데이트 메커니즘 부재

---

## 2. 마이그레이션 목표

### 2.1 기술적 목표

- ✅ **비동기 성능 유지**: Django 4.2+ 비동기 ORM 활용
- ✅ **기존 API 호환성**: 기존 v1 API 엔드포인트 그대로 유지
- ✅ **타입 안정성**: Django Ninja의 Pydantic 기반 스키마 활용
- ✅ **성능 기준 유지**: 캠페인 목록 조회 < 500ms
- ✅ **PostgreSQL 비동기 연결**: asyncpg + Django ORM

### 2.2 비즈니스 목표

- ✅ **앱 재배포 최소화**: 광고 설정을 API로 관리
- ✅ **버전 관리 자동화**: 앱 버전 체크 및 강제 업데이트
- ✅ **사용자 인증 강화**: 이메일 기반 인증 + 이메일 인증
- ✅ **관리자 친화적**: Django Admin으로 광고/앱버전 관리

---

## 3. 새로운 기능 요구사항

### 3.1 사용자 인증 시스템

**요구사항**:
- Django의 기본 User 모델 대신 Custom User 모델 사용
- 이메일 + 비밀번호 기반 인증 (username 대신 email)
- 이메일 인증 로직 (회원가입 시 인증 이메일 발송)
- JWT 토큰 기반 인증 (django-rest-framework-simplejwt)

**구현 방안**:
```python
# accounts/models.py
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin
from django.db import models

class User(AbstractBaseUser, PermissionsMixin):
    email = models.EmailField(unique=True)
    is_email_verified = models.BooleanField(default=False)
    email_verification_token = models.CharField(max_length=255, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []
```

**API 엔드포인트**:
- `POST /v1/auth/register` - 회원가입 (이메일 인증 메일 발송)
- `GET /v1/auth/verify-email?token=xxx` - 이메일 인증
- `POST /v1/auth/login` - 로그인 (JWT 발급)
- `POST /v1/auth/refresh` - 토큰 갱신
- `POST /v1/auth/logout` - 로그아웃

### 3.2 앱 버전 관리

**요구사항**:
- 서버에서 최소 지원 버전, 최신 버전 관리
- 앱 시작 시 버전 체크 API 호출
- 최소 버전보다 낮으면 강제 업데이트 팝업
- 최신 버전보다 낮으면 선택적 업데이트 팝업

**데이터 모델**:
```python
# core/models.py
class AppVersion(models.Model):
    PLATFORM_CHOICES = [
        ('android', 'Android'),
        ('ios', 'iOS'),
    ]

    platform = models.CharField(max_length=10, choices=PLATFORM_CHOICES)
    current_version = models.CharField(max_length=20)  # 예: "1.2.3"
    minimum_version = models.CharField(max_length=20)  # 최소 지원 버전
    update_message = models.TextField()
    force_update = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ['platform']
```

**API 엔드포인트**:
- `GET /v1/app/version?platform=android&version=1.0.0`
  ```json
  {
    "current_version": "1.2.3",
    "minimum_version": "1.1.0",
    "force_update": false,
    "update_required": true,
    "update_message": "새로운 기능이 추가되었습니다."
  }
  ```

### 3.3 광고 플랫폼 관리

**요구사항**:
- AdMob 광고 ID를 서버에서 관리
- 플랫폼(Android/iOS), 광고 타입(배너/전면/네이티브)별 관리
- 앱 재배포 없이 광고 ID 변경 가능

**데이터 모델**:
```python
# ads/models.py
class AdConfig(models.Model):
    PLATFORM_CHOICES = [
        ('android', 'Android'),
        ('ios', 'iOS'),
    ]

    AD_TYPE_CHOICES = [
        ('banner', 'Banner Ad'),
        ('interstitial', 'Interstitial Ad'),
        ('native', 'Native Ad'),
        ('rewarded', 'Rewarded Ad'),
    ]

    platform = models.CharField(max_length=10, choices=PLATFORM_CHOICES)
    ad_type = models.CharField(max_length=20, choices=AD_TYPE_CHOICES)
    ad_unit_id = models.CharField(max_length=255)
    is_test = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ['platform', 'ad_type']
```

**API 엔드포인트**:
- `GET /v1/ads/config?platform=android`
  ```json
  {
    "banner": {
      "ad_unit_id": "ca-app-pub-xxx",
      "is_active": true
    },
    "interstitial": {
      "ad_unit_id": "ca-app-pub-yyy",
      "is_active": true
    },
    "native": {
      "ad_unit_id": "ca-app-pub-zzz",
      "is_active": true
    }
  }
  ```

---

## 4. 기술 스택 변경

### 4.1 Before (FastAPI)

```
FastAPI 0.115.0
├── Uvicorn (ASGI 서버)
├── SQLAlchemy 2.0 (비동기 ORM)
├── asyncpg (PostgreSQL 비동기 드라이버)
├── Pydantic 2.11 (데이터 검증)
└── python-dotenv (환경 변수)
```

### 4.2 After (Django Ninja)

```
Django 5.0+
├── Django Ninja 1.3+ (FastAPI 스타일 API)
├── Django ORM (비동기 지원)
├── asyncpg (PostgreSQL 비동기 드라이버)
├── Pydantic 2.x (Django Ninja 내장)
├── djangorestframework-simplejwt (JWT 인증)
├── django-cors-headers (CORS)
├── celery (비동기 작업 - 이메일 발송)
└── redis (Celery 브로커)
```

### 4.3 주요 차이점

| 항목 | FastAPI | Django Ninja |
|------|---------|--------------|
| **ORM** | SQLAlchemy 2.0 | Django ORM |
| **비동기 지원** | Native async/await | Django 4.2+ async views |
| **Admin** | 없음 (수동 구현 필요) | Django Admin (기본 제공) |
| **인증** | 수동 구현 | Django Auth + JWT |
| **마이그레이션** | Alembic | Django Migrations |
| **설정 관리** | Pydantic Settings | Django Settings + environ |

---

## 5. 단계별 마이그레이션 계획

### Phase 1: Django 프로젝트 초기 설정 (1-2일)

**작업 내용**:
1. Django 프로젝트 생성 (`django-admin startproject reviewmaps`)
2. 필수 앱 생성:
   - `accounts` - 사용자 인증
   - `campaigns` - 캠페인 관리
   - `categories` - 카테고리 관리
   - `ads` - 광고 설정
   - `core` - 공통 기능 (앱 버전 등)
3. Django Ninja 설정
4. 비동기 데이터베이스 설정 (asyncpg)
5. CORS, 미들웨어 설정

**설정 파일**:
```python
# settings.py
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': env('POSTGRES_DB'),
        'USER': env('POSTGRES_USER'),
        'PASSWORD': env('POSTGRES_PASSWORD'),
        'HOST': env('POSTGRES_HOST'),
        'PORT': env('POSTGRES_PORT'),
        'CONN_MAX_AGE': 600,
        'OPTIONS': {
            'server_side_binding': True,
        }
    }
}

# 비동기 지원
ASGI_APPLICATION = 'reviewmaps.asgi.application'

# Custom User 모델
AUTH_USER_MODEL = 'accounts.User'

# JWT 설정
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(hours=1),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=7),
}
```

### Phase 2: 데이터 모델 마이그레이션 (2-3일)

**작업 내용**:
1. SQLAlchemy 모델 → Django 모델 변환
2. Custom User 모델 구현
3. AppVersion, AdConfig 모델 추가
4. 인덱스 정의 (기존 성능 최적화 인덱스 유지)
5. Django 마이그레이션 생성 및 적용

**모델 변환 예시**:
```python
# Before (SQLAlchemy)
class Campaign(Base):
    __tablename__ = "campaign"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    promotion_level: Mapped[int | None] = mapped_column(Integer)

    __table_args__ = (
        Index('idx_campaign_promo_deadline_lat_lng',
              'promotion_level', 'apply_deadline', 'lat', 'lng'),
    )

# After (Django)
class Campaign(models.Model):
    promotion_level = models.IntegerField(null=True, default=0)

    class Meta:
        indexes = [
            models.Index(fields=['promotion_level', 'apply_deadline', 'lat', 'lng'],
                        name='idx_campaign_promo_deadline_lat_lng'),
        ]
```

### Phase 3: 비동기 CRUD 로직 마이그레이션 (3-4일)

**작업 내용**:
1. `db/crud.py`의 비동기 함수를 Django ORM으로 변환
2. 복잡한 쿼리 (지리 기반, 추천 알고리즘) 최적화
3. 성능 테스트 (< 500ms 목표 유지)

**비동기 쿼리 예시**:
```python
# Django Ninja에서 비동기 쿼리
from django.db import models
from asgiref.sync import sync_to_async

async def alist_campaigns(
    region: str | None = None,
    category_id: int | None = None,
    limit: int = 20,
    offset: int = 0,
):
    # Django 4.2+ 비동기 쿼리
    queryset = Campaign.objects.select_related('category')

    if region:
        queryset = queryset.filter(region=region)
    if category_id:
        queryset = queryset.filter(category_id=category_id)

    # 비동기 실행
    campaigns = await queryset.aorder_by('-promotion_level')[offset:offset+limit]

    return list(campaigns)
```

### Phase 4: API 엔드포인트 마이그레이션 (3-4일)

**작업 내용**:
1. FastAPI 라우터 → Django Ninja API로 변환
2. 기존 v1 엔드포인트 호환성 유지
3. 새로운 인증 API 추가
4. 앱 버전 체크 API 추가
5. 광고 설정 API 추가

**Django Ninja API 예시**:
```python
# campaigns/api.py
from ninja import Router
from typing import Optional

router = Router()

@router.get("/campaigns", response=List[CampaignOutV2])
async def list_campaigns(
    request,
    region: Optional[str] = None,
    category_id: Optional[int] = None,
    limit: int = 20,
    offset: int = 0,
):
    campaigns = await alist_campaigns(
        region=region,
        category_id=category_id,
        limit=limit,
        offset=offset,
    )
    return campaigns
```

### Phase 5: 인증 시스템 구현 (2-3일)

**작업 내용**:
1. Custom User 모델 구현
2. 회원가입 API (이메일 인증 메일 발송)
3. 이메일 인증 로직
4. 로그인/로그아웃 API (JWT)
5. Celery 설정 (비동기 이메일 발송)

**이메일 인증 플로우**:
```
1. 사용자 회원가입 → POST /v1/auth/register
2. 서버: User 생성 (is_email_verified=False)
3. 서버: 인증 토큰 생성 및 이메일 발송 (Celery 비동기)
4. 사용자: 이메일의 링크 클릭
5. GET /v1/auth/verify-email?token=xxx
6. 서버: 토큰 검증 → is_email_verified=True
7. 사용자: 로그인 가능
```

### Phase 6: 새로운 기능 구현 (2-3일)

**작업 내용**:
1. 앱 버전 관리 API
2. 광고 설정 API
3. Django Admin 커스터마이징
4. Mobile 앱 하드코딩 제거

**Django Admin 설정**:
```python
# admin.py
@admin.register(AppVersion)
class AppVersionAdmin(admin.ModelAdmin):
    list_display = ['platform', 'current_version', 'minimum_version', 'force_update']
    list_filter = ['platform', 'force_update']

@admin.register(AdConfig)
class AdConfigAdmin(admin.ModelAdmin):
    list_display = ['platform', 'ad_type', 'ad_unit_id', 'is_active']
    list_filter = ['platform', 'ad_type', 'is_active']
```

### Phase 7: 테스트 및 성능 검증 (2-3일)

**작업 내용**:
1. 단위 테스트 작성
2. 통합 테스트 작성
3. 성능 테스트 (< 500ms)
4. 부하 테스트
5. 보안 테스트

### Phase 8: Mobile 앱 연동 및 배포 (2-3일)

**작업 내용**:
1. Mobile 앱 API 클라이언트 수정
2. 하드코딩 제거 (광고 ID, 버전 체크)
3. 스테이징 환경 배포
4. 통합 테스트
5. 프로덕션 배포

---

## 6. 데이터베이스 마이그레이션

### 6.1 기존 데이터 유지 전략

**옵션 1: Django 마이그레이션으로 변환** (권장)
- 기존 테이블 구조를 Django 모델로 정의
- `python manage.py makemigrations --empty`로 초기 마이그레이션 생성
- 기존 테이블과 동기화

**옵션 2: 데이터 마이그레이션 스크립트**
- 기존 데이터 덤프 (`pg_dump`)
- Django 마이그레이션 실행
- 데이터 복원

### 6.2 새로운 테이블

**추가할 테이블**:
1. `accounts_user` - Custom User 모델
2. `core_appversion` - 앱 버전 관리
3. `ads_adconfig` - 광고 설정

**마이그레이션 순서**:
```bash
# 1. Custom User 모델 먼저 생성
python manage.py makemigrations accounts

# 2. 다른 앱 마이그레이션
python manage.py makemigrations campaigns categories ads core

# 3. 마이그레이션 적용
python manage.py migrate
```

---

## 7. API 엔드포인트 매핑

### 7.1 기존 엔드포인트 (유지)

| FastAPI | Django Ninja | 메서드 | 설명 |
|---------|--------------|--------|------|
| `/v1/campaigns` | `/v1/campaigns` | GET | 캠페인 목록 조회 |
| `/v1/campaigns/{id}` | `/v1/campaigns/{id}` | GET | 캠페인 상세 조회 |
| `/v1/categories` | `/v1/categories` | GET | 카테고리 목록 조회 |
| `/v1/health` | `/v1/health` | GET | 헬스체크 |
| `/v1/performance/benchmark` | `/v1/performance/benchmark` | GET | 성능 벤치마크 |

### 7.2 새로운 엔드포인트

| 엔드포인트 | 메서드 | 설명 | 인증 필요 |
|-----------|--------|------|----------|
| `/v1/auth/register` | POST | 회원가입 | ❌ |
| `/v1/auth/verify-email` | GET | 이메일 인증 | ❌ |
| `/v1/auth/login` | POST | 로그인 | ❌ |
| `/v1/auth/refresh` | POST | 토큰 갱신 | ❌ |
| `/v1/auth/logout` | POST | 로그아웃 | ✅ |
| `/v1/auth/me` | GET | 사용자 정보 조회 | ✅ |
| `/v1/app/version` | GET | 앱 버전 체크 | ❌ |
| `/v1/ads/config` | GET | 광고 설정 조회 | ❌ |

---

## 8. 테스트 전략

### 8.1 단위 테스트

**테스트 대상**:
- 비동기 CRUD 함수
- 인증 로직 (이메일 인증, JWT)
- 앱 버전 체크 로직
- 광고 설정 조회 로직

**예시**:
```python
# tests/test_campaigns.py
import pytest
from django.test import AsyncClient

@pytest.mark.asyncio
async def test_list_campaigns():
    client = AsyncClient()
    response = await client.get('/v1/campaigns?limit=10')

    assert response.status_code == 200
    assert len(response.json()['items']) <= 10
```

### 8.2 성능 테스트

**목표**:
- 캠페인 목록 조회: < 500ms
- 앱 버전 체크: < 100ms
- 광고 설정 조회: < 100ms

**도구**:
- Locust (부하 테스트)
- Django Debug Toolbar (쿼리 분석)

### 8.3 통합 테스트

**시나리오**:
1. 회원가입 → 이메일 인증 → 로그인
2. 앱 시작 → 버전 체크 → 강제 업데이트
3. 광고 설정 조회 → AdMob 초기화

---

## 9. 배포 전략

### 9.1 Blue-Green 배포

**전략**:
1. 기존 FastAPI 서버 유지 (Blue)
2. Django Ninja 서버 배포 (Green)
3. 트래픽 일부를 Green으로 전환 (10% → 50% → 100%)
4. 문제 발생 시 Blue로 롤백

### 9.2 데이터베이스 마이그레이션

**전략**:
1. 읽기 전용 복제본에서 마이그레이션 테스트
2. 프로덕션 DB 백업
3. 마이그레이션 실행 (다운타임 최소화)
4. Django 서버 시작

### 9.3 Mobile 앱 배포

**전략**:
1. API 버전 체크 기능 먼저 배포
2. 광고 설정 API 배포
3. Mobile 앱 업데이트 (하드코딩 제거)
4. 구버전 앱도 동작하도록 호환성 유지

---

## 10. 체크리스트

### Phase 1: 프로젝트 초기 설정

- [ ] Django 5.0+ 프로젝트 생성
- [ ] Django Ninja 설치 및 설정
- [ ] PostgreSQL 비동기 연결 설정
- [ ] CORS 미들웨어 설정
- [ ] 환경 변수 관리 (django-environ)
- [ ] 로깅 설정
- [ ] Prometheus 메트릭 설정

### Phase 2: 데이터 모델

- [ ] Custom User 모델 구현
- [ ] Campaign 모델 변환
- [ ] Category 모델 변환
- [ ] AppVersion 모델 추가
- [ ] AdConfig 모델 추가
- [ ] 인덱스 정의 (성능 최적화)
- [ ] Django 마이그레이션 생성
- [ ] 마이그레이션 적용 및 검증

### Phase 3: 비즈니스 로직

- [ ] 캠페인 목록 조회 (비동기)
- [ ] 캠페인 상세 조회
- [ ] 카테고리 관리
- [ ] 추천 알고리즘 (promotion_level 정렬)
- [ ] 지리 기반 정렬 (Haversine 거리 계산)
- [ ] Offer 검색 (동의어 확장)
- [ ] 성능 벤치마크 함수

### Phase 4: API 엔드포인트 (기존)

- [ ] `GET /v1/campaigns` (비동기)
- [ ] `GET /v1/campaigns/{id}`
- [ ] `GET /v1/categories`
- [ ] `GET /v1/health`
- [ ] `GET /v1/performance/benchmark`
- [ ] API 키 인증 미들웨어

### Phase 5: 인증 시스템

- [ ] Custom User Manager 구현
- [ ] 회원가입 API (`POST /v1/auth/register`)
- [ ] 이메일 인증 토큰 생성
- [ ] 이메일 발송 (Celery 비동기)
- [ ] 이메일 인증 API (`GET /v1/auth/verify-email`)
- [ ] 로그인 API (`POST /v1/auth/login`)
- [ ] JWT 토큰 발급
- [ ] 토큰 갱신 API (`POST /v1/auth/refresh`)
- [ ] 로그아웃 API (`POST /v1/auth/logout`)
- [ ] 사용자 정보 조회 (`GET /v1/auth/me`)

### Phase 6: 앱 버전 관리

- [ ] AppVersion 모델 구현
- [ ] 앱 버전 체크 API (`GET /v1/app/version`)
- [ ] 강제 업데이트 로직
- [ ] 선택적 업데이트 로직
- [ ] Django Admin 설정

### Phase 7: 광고 설정 관리

- [ ] AdConfig 모델 구현
- [ ] 광고 설정 조회 API (`GET /v1/ads/config`)
- [ ] 플랫폼별 광고 ID 관리
- [ ] 광고 타입별 설정
- [ ] Django Admin 설정

### Phase 8: Mobile 앱 연동

- [ ] Mobile 앱 API 클라이언트 수정
- [ ] 광고 ID 하드코딩 제거
- [ ] 앱 버전 체크 로직 추가
- [ ] 강제 업데이트 팝업 구현
- [ ] 선택적 업데이트 팝업 구현
- [ ] API 엔드포인트 URL 업데이트

### Phase 9: 테스트

- [ ] 단위 테스트 (인증, CRUD)
- [ ] 통합 테스트 (API 엔드포인트)
- [ ] 성능 테스트 (< 500ms)
- [ ] 부하 테스트 (Locust)
- [ ] 보안 테스트 (인증, 권한)
- [ ] 이메일 발송 테스트
- [ ] 앱 버전 체크 테스트
- [ ] 광고 설정 조회 테스트

### Phase 10: 배포

- [ ] 스테이징 환경 구축
- [ ] Django 서버 배포 (스테이징)
- [ ] Mobile 앱 베타 테스트
- [ ] 프로덕션 DB 마이그레이션
- [ ] Django 서버 배포 (프로덕션)
- [ ] 트래픽 전환 (10% → 50% → 100%)
- [ ] 모니터링 및 로그 확인
- [ ] Mobile 앱 프로덕션 배포
- [ ] FastAPI 서버 종료

### Phase 11: 후속 작업

- [ ] 성능 모니터링 (Prometheus, Grafana)
- [ ] 에러 추적 (Sentry)
- [ ] API 문서 업데이트
- [ ] 사용자 가이드 작성
- [ ] 관리자 매뉴얼 작성

---

## 예상 일정

| Phase | 작업 내용 | 예상 기간 | 의존성 |
|-------|----------|----------|-------|
| 1 | 프로젝트 초기 설정 | 1-2일 | - |
| 2 | 데이터 모델 마이그레이션 | 2-3일 | Phase 1 |
| 3 | 비즈니스 로직 마이그레이션 | 3-4일 | Phase 2 |
| 4 | API 엔드포인트 마이그레이션 | 3-4일 | Phase 3 |
| 5 | 인증 시스템 구현 | 2-3일 | Phase 2 |
| 6 | 앱 버전 관리 구현 | 1-2일 | Phase 2 |
| 7 | 광고 설정 관리 구현 | 1-2일 | Phase 2 |
| 8 | Mobile 앱 연동 | 2-3일 | Phase 4-7 |
| 9 | 테스트 | 2-3일 | Phase 4-8 |
| 10 | 배포 | 2-3일 | Phase 9 |
| 11 | 후속 작업 | 1-2일 | Phase 10 |

**총 예상 기간**: 20-32일 (약 4-6주)

---

## 리스크 및 대응 방안

### 리스크 1: 비동기 성능 저하

**대응**:
- Django ORM 비동기 쿼리 최적화
- select_related, prefetch_related 적극 활용
- 필요시 Raw SQL 사용
- Redis 캐싱 도입

### 리스크 2: 데이터 마이그레이션 실패

**대응**:
- 프로덕션 DB 백업
- 스테이징 환경에서 충분한 테스트
- 롤백 계획 수립

### 리스크 3: Mobile 앱 호환성 문제

**대응**:
- 기존 API 엔드포인트 유지
- API 버전 관리 (v1, v2)
- 구버전 앱 지원 기간 설정

### 리스크 4: 이메일 발송 지연

**대응**:
- Celery 비동기 처리
- 이메일 발송 실패 시 재시도 로직
- 이메일 발송 상태 모니터링

---

## 참고 자료

- [Django Ninja 공식 문서](https://django-ninja.rest-framework.com/)
- [Django 비동기 뷰](https://docs.djangoproject.com/en/5.0/topics/async/)
- [Django Custom User Model](https://docs.djangoproject.com/en/5.0/topics/auth/customizing/)
- [djangorestframework-simplejwt](https://django-rest-framework-simplejwt.readthedocs.io/)
- [Celery](https://docs.celeryq.dev/)

---

**문서 버전**: 1.0
**최종 수정일**: 2025-11-11
**작성자**: AI Assistant
**승인자**: (승인 필요)

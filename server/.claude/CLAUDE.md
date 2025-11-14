# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🎯 핵심 개발 원칙 (Critical Development Principles)

### 1. 사용자 인증 (User Authentication)
- **Django 기본 User 모델을 Override 필수**
- username 대신 **email + password** 로 인증
- Custom User 모델 구현 필수

### 2. 시간대 설정 (Timezone)
- **모든 시간은 Asia/Seoul 타임존 사용**
- `TIME_ZONE = 'Asia/Seoul'`
- `USE_TZ = True`

### 3. 비동기 처리 (Async Operations)
- **인증(auth)을 제외한 모든 서비스는 비동기로 처리**
- Django ORM 비동기 쿼리 사용 (`async def`, `await`)
- Database 작업은 모두 async로 구현

### 4. 테스트 주도 개발 (Test-Driven Development)
- **모든 모듈은 test 코드 작성 필수**
- 테스트 파일 위치: 각 앱의 `tests/` 하위
  - 예: `user/tests/test_user.py`, `user/tests/test_model.py`
- **새로운 모듈 작성 전 테스트 먼저 작성**
- **테스트 통과 후에만 다음 단계 진행**

### 5. 개발 워크플로우 (Development Workflow)
```
1. 요구사항 분석
2. 테스트 코드 작성 (TDD)
3. 테스트 실행 (Red)
4. 기능 구현
5. 테스트 통과 확인 (Green)
6. 리팩토링 (Refactor)
7. Git 커밋
```

### 6. 명령어 실행 권한 (Command Execution)
- **Python 명령어 자동 실행**: 사용자 승인 없이 `python`, `django-admin` 명령어 실행
- **관리 명령어 포함**: `manage.py`, `makemigrations`, `migrate`, `test` 등
- **사용자에게 묻지 않고 바로 실행**: 개발 속도 향상을 위해 자율적으로 실행

## Project Overview

ReviewMaps API는 Django + Django Ninja 기반의 비동기 백엔드로, 캠페인 추천 시스템을 제공합니다. 지리공간 데이터 기반의 고급 필터링, 정렬, 성능 최적화 기능을 포함합니다.

**Key Technologies:**
- Django 5.2.8 + Django Ninja (async API)
- PostgreSQL with geospatial indexing
- 비동기 ORM (Django async queries)
- Custom User Model (email-based authentication)
- TDD (Test-Driven Development)

## Development Commands

### 의존성 관리 (Dependency Management)
```bash
# uv를 사용한 패키지 설치
uv add django django-ninja psycopg2-binary

# 의존성 동기화
uv sync

# Python 실행 (가상환경)
/home/woohaen88/reviewmaps/server/.venv/bin/python
```

### Local Development
```bash
# Django 개발 서버 실행
python manage.py runserver 0.0.0.0:8000

# 마이그레이션 생성
python manage.py makemigrations

# 마이그레이션 적용
python manage.py migrate

# Django shell
python manage.py shell
```

### Testing (TDD Required)
```bash
# 모든 테스트 실행
python manage.py test

# 특정 앱 테스트
python manage.py test campaigns

# 특정 테스트 파일
python manage.py test campaigns.tests.test_models

# Coverage와 함께 실행
coverage run --source='.' manage.py test
coverage report
coverage html
```

## Architecture Overview

### Application Structure

**Django 프로젝트 구조:**
```
reviewmaps/server/
├── config/              # Django 프로젝트 설정
│   ├── settings.py      # 메인 설정 파일
│   ├── urls.py          # 루트 URL 설정
│   ├── wsgi.py          # WSGI 설정
│   └── asgi.py          # ASGI 설정 (비동기)
├── campaigns/           # 캠페인 앱
│   ├── models.py        # 캠페인, 카테고리 모델
│   ├── views.py         # Django Ninja API 뷰
│   ├── tests/           # TDD 테스트
│   │   ├── test_models.py
│   │   └── test_views.py
│   └── admin.py         # Django Admin 설정
├── users/               # 사용자 인증 앱 (예정)
│   ├── models.py        # Custom User 모델
│   ├── views.py         # 인증 API
│   └── tests/           # 인증 테스트
├── manage.py            # Django 관리 스크립트
└── backup/              # FastAPI 레거시 코드
```

**Django Ninja API 구조:**
```
/api/v1/campaigns         → 캠페인 목록/생성
/api/v1/campaigns/{id}    → 캠페인 상세/수정/삭제
/api/v1/categories        → 카테고리 목록
/api/v1/auth/login        → 로그인 (email + password)
/api/v1/auth/register     → 회원가입
```

### Core Components

**`config/settings.py`** - Django Settings
- 환경변수 기반 설정 (`.env` 파일 사용)
- PostgreSQL 데이터베이스 설정
- Asia/Seoul 타임존
- Custom User 모델 등록 필수

**`campaigns/models.py`** - Django Models
- `Campaign` - 지리공간 좌표 및 프로모션 레벨을 포함한 메인 엔티티
- `Category` - 표시 순서를 가진 캠페인 카테고리
- `RawCategory`, `CategoryMapping` - 카테고리 매핑 시스템
- **성능 최적화 인덱스:**
  - `idx_campaign_promo_deadline_lat_lng` - 추천 쿼리용 복합 인덱스
  - `idx_campaign_created_at` - 기본 정렬용
  - `idx_campaign_category_id` - 카테고리 필터링용
  - `idx_campaign_apply_deadline` - 마감일 필터링용

**`campaigns/views.py`** - Django Ninja API Views (비동기)
- 모든 뷰는 `async def`로 구현
- Django ORM 비동기 쿼리 사용
- 동의어 매칭 및 정규화를 포함한 고급 검색
- Haversine 공식을 사용한 지리공간 거리 계산

**`users/models.py`** - Custom User Model
- **email을 primary identifier로 사용**
- username 필드 제거
- `AbstractBaseUser`, `PermissionsMixin` 상속
- Custom UserManager 구현

### Key Design Patterns

**Campaign Recommendation Algorithm (v2)**

The system implements a sophisticated multi-tier sorting strategy:

1. **Expired Campaign Filtering (Highest Priority)**
   ```python
   # Automatically excludes campaigns where apply_deadline < current_timestamp
   # NULL apply_deadline means "no deadline" and is included
   WHERE (apply_deadline IS NULL OR apply_deadline >= CURRENT_TIMESTAMP)
   ```

2. **Promotion Level Priority Sorting**
   ```python
   # Higher promotion_level campaigns appear first
   ORDER BY COALESCE(promotion_level, 0) DESC
   ```

3. **Pseudo-Random Distribution**
   ```python
   # Within same promotion_level, distribute evenly using ID-based hash
   # Avoids performance cost of random() while preventing same campaigns from dominating
   ORDER BY ABS(HASH(id)) % 1000
   ```

4. **User-Specified Sorting**
   ```python
   # Finally apply user's sort parameter (created_at, apply_deadline, distance, etc.)
   ORDER BY [user_sort_column] [ASC/DESC]
   ```

**Distance Sorting Special Case:**
- When `sort=distance`, requires `lat` and `lng` parameters
- Uses Haversine formula for accurate geospatial distance calculation
- Sort priority: promotion_level → distance → pseudo_random → created_at

**Offer Search Intelligence (`build_offer_predicates`)**

The system normalizes and expands search terms:
- Money normalization: "4만", "40000", "40,000" all match each other
- Quantity/period handling: "2개월" matches "2달", "2 개월", "2월"
- Synonym expansion: "헬스장" matches "헬스", "피트니스", "GYM", "fitness"
- "PT" matches "피티", "퍼스널트레이닝", "personal training"

### Configuration & Environment

**Required Environment Variables:**
```bash
# Database Configuration
POSTGRES_USER=your_user
POSTGRES_PASSWORD=your_password
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=reviewmaps

# Alternative: Full DATABASE_URL (will be converted to asyncpg)
DATABASE_URL=postgresql://user:pass@host:port/db

# Security
API_SECRET_KEY=your-secret-key-here

# Prometheus Metrics (for Gunicorn multi-process)
PROMETHEUS_MULTIPROC_DIR=/tmp/metrics
```

**CORS Configuration:**
- Default: `["*"]` (allow all origins)
- Production: Set `cors_allow_origins` in Settings for specific domains

### Performance Considerations

**Target Response Time:** < 500ms for campaign listing queries

**Optimization Strategies:**
1. Use composite indexes for common query patterns
2. Prefer ID-based pseudo-random over SQL `random()` function
3. Avoid N+1 queries with `selectinload(Campaign.category)`
4. Use subquery-based counting for filtered results
5. Calculate `is_new` and `distance` attributes in Python (ORM approach) vs SQL (legacy approach)

**Monitoring:**
- Prometheus metrics exposed at `/metrics` (multiprocess-safe)
- Access logs via `AccessLogMiddleware`
- OpenTelemetry tracing instrumentation configured
- Performance benchmarking endpoints in `/v1/performance` router

### Database Migration Notes

**When adding new indexes:**
```sql
-- Always create indexes CONCURRENTLY in production to avoid table locks
CREATE INDEX CONCURRENTLY idx_name ON table_name (column);
```

**Critical indexes for campaign recommendation:**
- Must have `idx_campaign_promo_deadline_lat_lng` for optimal performance
- GiST index on lat/lng for geospatial queries (if implemented)

### Testing Strategy

**Test File:** `tests/test_campaign_recommendation.py`

Tests cover:
1. Expired campaign exclusion (`apply_deadline` filtering)
2. Promotion level priority sorting
3. Pseudo-random distribution balance
4. Performance requirements (< 500ms)
5. V2 schema compatibility
6. Edge cases (NULL deadlines, missing coordinates)

### Common Development Tasks

**Adding a new filter parameter:**
1. Add parameter to router function in `api/routers/campaigns.py`
2. Pass parameter to `crud.list_campaigns()`
3. Add filtering logic in `crud.list_campaigns_optimized()` conditions list
4. Consider adding appropriate index to `db/models.py`
5. Update tests to cover new filtering scenario

**Modifying campaign sorting:**
1. Update `list_campaigns_optimized()` ORDER BY logic in `db/crud.py`
2. Maintain promotion_level priority as first sorting criterion
3. Update `list_campaigns_legacy()` if maintaining dual implementations
4. Run performance benchmarks to ensure < 500ms target

**Adding new API endpoints:**
1. Create router in `api/routers/`
2. Add router to `main.py` with `v1_app.include_router()`
3. Apply `Depends(require_api_key)` if authentication required
4. Define Pydantic schemas in `schemas/`

### API Versioning Strategy

Current approach:
- All endpoints under `/v1` prefix
- **NEVER modify v2 schemas** - maintain backward compatibility
- For breaking changes, create v3 endpoints rather than modifying v2
- Schemas in `schemas/campaign.py` distinguish v1 vs v2 models

### Security Best Practices

- API keys compared using `hmac.compare_digest()` to prevent timing attacks
- CORS configured per environment
- Sensitive data (API keys, DB credentials) via environment variables only
- No secrets in code or git repository

### Logging & Observability

**Logging Setup:** `core/logging.py`
- Uses `python-json-logger` for structured logging
- Configured at application startup via `setup_logging()`

**Metrics:**
- HTTP request metrics via Prometheus Instrumentator
- Custom application metrics via `FastAPIMetricsMiddleware`
- Multiprocess-safe metrics collection (Gunicorn compatible)

**Access Logs:**
- Request/response logging in `middlewares/access.py`
- Includes timing, status codes, client info

### Deployment Architecture

**Gunicorn + Uvicorn Workers:**
- 2 worker processes (configurable in `entrypoint.sh`)
- UvicornWorker for async support
- Managed by tini for proper signal handling
- Prometheus multiprocess metrics directory cleaned on startup

**Health Checks:**
- `/health` - Basic liveness check
- `/v1/health` - Versioned health endpoint
- Both return `{"status": "ok"}`

### Important Implementation Details

**Why two list_campaigns implementations exist:**
Based on `PERFORMANCE_OPTIMIZATION_REPORT.md`, the codebase maintains both:
- `list_campaigns_optimized()`: ORM-based with Python-side calculations (currently used)
- `list_campaigns_legacy()`: Raw SQL expression-based (kept for reference/rollback)

The ORM approach was chosen for better maintainability despite similar performance.

**Promotion Level System:**
- `promotion_level` is nullable integer field
- Higher values = higher priority in search results
- NULL treated as 0 (lowest priority)
- Used for featured/sponsored campaign placement

**Geospatial Queries:**
- Coordinates stored as Numeric(9,6) for lat/lng
- Distance calculations use Haversine formula (Earth radius = 6371 km)
- Results in kilometers
- NULL coordinates handled gracefully (sorted last in distance mode)

### Error Handling Patterns

- FastAPI automatic validation for Pydantic models
- HTTP 400 for invalid parameters (e.g., missing lat/lng for distance sort)
- HTTP 401 for authentication failures
- HTTP 404 for non-existent resources
- HTTP 500 for server configuration errors

## Documentation Organization

**Project documentation is organized in the `docs/` folder with the following structure:**

```
docs/
├── planning/          # 작업 계획 문서, 기능 설계 문서
├── reports/           # 구현 완료 보고서, 성능 분석 보고서
├── specifications/    # API 명세서, 기능 명세서, 요구사항 문서
└── architecture/      # 시스템 아키텍처, 설계 결정 문서
```

**Document Placement Guidelines:**

- **작업 계획 문서**: `docs/planning/`에 작성
  - 새 기능 개발 계획
  - 리팩토링 계획
  - 성능 개선 계획

- **완료 보고서**: `docs/reports/`에 작성
  - 구현 완료 보고서 (예: `IMPLEMENTATION_REPORT.md`)
  - 성능 최적화 보고서 (예: `PERFORMANCE_OPTIMIZATION_REPORT.md`)
  - 테스트 결과 보고서

- **명세서**: `docs/specifications/`에 작성
  - API 엔드포인트 명세
  - 데이터베이스 스키마 명세
  - 비즈니스 로직 명세

- **아키텍처 문서**: `docs/architecture/`에 작성
  - 시스템 구조 설계
  - 기술 스택 선정 이유
  - 아키텍처 의사결정 기록 (ADR)

**Important Notes:**
- 프로젝트 설정 파일은 `.claude/CLAUDE.md`에 작성 (현재 파일)
- Claude와의 작업 시 생성되는 모든 계획 문서는 `docs/` 하위 적절한 폴더에 배치
- 루트 디렉토리는 깨끗하게 유지 (핵심 설정 파일만)

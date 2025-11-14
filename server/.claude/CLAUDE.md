# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ReviewMaps API is a FastAPI-based async backend for a campaign recommendation system. The service provides geospatial campaign data with advanced filtering, sorting, and performance optimization features.

**Key Technologies:**
- FastAPI 0.115.0 + Uvicorn + Gunicorn (async ASGI)
- SQLAlchemy 2.0 (async ORM) + asyncpg
- PostgreSQL with geospatial indexing
- Prometheus metrics + OpenTelemetry tracing
- Docker deployment

## Development Commands

### Local Development
```bash
# Install dependencies
pip install -r requirements.txt

# Run development server (single worker)
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Run with Gunicorn (production-like, 2 workers)
gunicorn -w 2 -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000 main:app
```

### Docker Operations
```bash
# Build image
docker build -t reviewmaps-server .

# Run container
docker run -p 8000:8000 --env-file .env reviewmaps-server

# Container uses entrypoint.sh which:
# 1. Cleans up Prometheus multiprocess metrics directory
# 2. Starts Gunicorn with 2 UvicornWorker processes
```

### Testing
```bash
# Run all tests
pytest

# Run specific test file
pytest tests/test_campaign_recommendation.py

# Run with verbose output
pytest -v

# Run with coverage
pytest --cov=. --cov-report=html
```

## Architecture Overview

### Application Structure

**Entry Point:** `main.py`
- Creates two FastAPI apps: `app` (root) and `v1_app` (versioned API)
- `v1_app` is mounted at `{settings.api_prefix}` (default: `/v1`)
- Middleware chain: AccessLog → CORS → FastAPIMetrics
- All routers require API key authentication except `/health` and `/metrics`

**Middleware Chain (order matters):**
1. `AccessLogMiddleware` - Request/response logging
2. `CORSMiddleware` - Cross-origin resource sharing
3. `FastAPIMetricsMiddleware` - Custom metrics collection
4. Prometheus Instrumentator - Automatic HTTP metrics

**Router Organization:**
```
/v1/campaigns         → campaigns.py (requires API key)
/v1/campaigns/{id}    → campaigns.py (requires API key)
/v1/categories        → categories.py (requires API key)
/v1/health            → health.py (public)
/v1/performance       → performance.py (requires API key)
/metrics              → main.py (public, Prometheus format)
/health               → main.py (public)
```

### Core Components

**`core/config.py`** - Settings Management
- Uses `pydantic-settings` for configuration
- Automatically converts sync PostgreSQL URLs to async (`postgresql+asyncpg://`)
- Sources: environment variables, `.env` file
- **Critical:** Never put `http://` or `https://` in DATABASE_URL host portion

**`db/models.py`** - SQLAlchemy Models
- `Campaign` - Main entity with geospatial coordinates and promotion levels
- `Category` - Campaign categories with display ordering
- **Performance-critical indexes:**
  - `idx_campaign_promo_deadline_lat_lng` - Composite index for recommendation queries
  - `idx_campaign_created_at` - Default sorting
  - `idx_campaign_category_id` - Category filtering
  - `idx_campaign_apply_deadline` - Deadline filtering

**`db/crud.py`** - Database Operations
- **TWO implementations for campaign listing:**
  1. `list_campaigns_optimized()` - NEW: Uses ORM-based approach with Python-side calculations
  2. `list_campaigns_legacy()` - OLD: Uses raw SQL expressions for in-database calculations
  3. `list_campaigns()` - Router function calling `list_campaigns_optimized()`
- Contains advanced offer search with synonym matching and normalization
- Haversine distance calculations for geospatial queries
- Performance benchmarking utilities (`explain_analyze_campaign_query`, `benchmark_campaign_queries`)

**`api/security.py`** - Authentication
- API key validation via `X-API-KEY` header
- Uses `hmac.compare_digest()` for timing-attack-safe comparison
- Configured via `settings.API_SECRET_KEY` environment variable

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

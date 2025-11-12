# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ReviewMaps Server is a FastAPI-based async API service for campaign/review discovery. The server manages campaign data with geolocation support, category mappings, and recommendation features optimized for mobile clients.

**Tech Stack**: FastAPI, SQLAlchemy 2.0 (async), PostgreSQL (asyncpg), Prometheus metrics, OpenTelemetry tracing

## Development Commands

### Database Setup
```bash
# Start local PostgreSQL (Docker)
cd database && docker-compose up -d

# Verify database is running (port 5431)
docker ps | grep postgres
```

### Running the Application
```bash
# Install dependencies
pip install -r requirements.txt

# Run development server with auto-reload (single worker)
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Run production server with Gunicorn + Uvicorn workers
gunicorn main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

### Testing
```bash
# Run all tests
pytest tests/

# Run specific test file
pytest tests/test_campaign_recommendation.py

# Run with verbose output
pytest -v tests/

# Run specific test
pytest tests/test_campaign_recommendation.py::TestCampaignRecommendation::test_expired_campaigns_excluded
```

### Metrics and Monitoring
```bash
# View Prometheus metrics
curl http://localhost:8000/metrics

# Health check
curl http://localhost:8000/health
curl http://localhost:8000/v1/health
```

## Architecture

### Application Structure

**Main App (main.py:37-66)**:
- `v1_app`: Versioned FastAPI app at `/v1` prefix with all business routers
- `app`: Root FastAPI app that mounts v1_app and exposes metrics at `/metrics`

**Middleware Order** (critical for correct operation):
1. `AccessLogMiddleware` - Access logging (first)
2. `CORSMiddleware` - CORS handling
3. `FastAPIMetricsMiddleware` - Request metrics
4. All routers protected with `require_api_key` dependency (except health)

**API Endpoints**:
- `/v1/campaigns` - Campaign list with complex filtering (region, category, geolocation, deadline)
- `/v1/campaigns/{id}` - Campaign detail
- `/v1/categories` - Category management
- `/v1/performance/*` - Performance analysis endpoints (EXPLAIN ANALYZE, index stats, benchmarks)

### Database Layer

**Session Management (db/session.py)**:
- Async engine with `pool_pre_ping=True` for connection health checks
- Timezone set to 'Asia/Seoul' on every connection
- `AsyncSessionLocal` configured with `expire_on_commit=False` for detached object access
- `get_async_db()` dependency provides async session via context manager

**Models (db/models.py)**:
- `Campaign`: Main campaign entity with geolocation (lat/lng), promotion_level, deadlines
- `Category`: Standard categories with display_order
- `RawCategory` + `CategoryMapping`: Raw→standard category mapping system

**Performance Indexes**:
- `idx_campaign_promo_deadline_lat_lng`: Composite index for recommendation queries (promotion_level, apply_deadline, lat, lng)
- `idx_campaign_created_at`, `idx_campaign_category_id`, `idx_campaign_apply_deadline`: Additional filtering indexes

### CRUD Layer (db/crud.py)

**Critical Query Logic**:
- `list_campaigns_optimized()`: Primary campaign query function with ORM-based implementation
- `list_campaigns()`: Delegates to `list_campaigns_optimized()` for consistency
- `list_campaigns_legacy()`: Older raw SQL implementation (kept for reference)

**Recommendation Algorithm** (applies to all list queries):
1. Filter: `apply_deadline >= current_date` OR `apply_deadline IS NULL` (exclude expired)
2. Sort priority:
   - 1st: `promotion_level DESC` (COALESCE with 0 for NULL)
   - 2nd: Pseudo-random distribution (`ABS(HASH(id)) % 1000`) for balanced exposure within same level
   - 3rd: User-specified sort (created_at, apply_deadline, distance)

**Distance Sorting**: Haversine formula for geolocation queries, calculated in SQL and Python for consistency

**Offer Search**: `build_offer_predicates()` function normalizes money/quantity expressions:
- Money: "4만원", "40,000", "40000" → all matched
- Quantities: "2개월", "2 개월", "2달" → synonyms matched
- Keywords: "PT", "피티", "헬스장" → synonym expansion

### Configuration System

**Settings (core/config.py)**:
- Pydantic-based configuration with `.env` file support
- Database URL auto-composition from environment variables (POSTGRES_USER, POSTGRES_PASSWORD, etc.)
- Automatic conversion: `postgresql://` → `postgresql+asyncpg://` for async support
- API key authentication via `API_SECRET_KEY`
- CORS origins: `["*"]` by default (configure for production)

**Environment Variables Required**:
```
POSTGRES_USER=crawrling
POSTGRES_PASSWORD=crawrling
POSTGRES_HOST=localhost
POSTGRES_PORT=5431
POSTGRES_DB=crawrling
API_SECRET_KEY=your-secret-key
```

### Security

**API Key Authentication (api/security.py)**:
- Header-based: `X-API-KEY` header
- All `/v1` endpoints (except `/v1/health`) require valid API key
- Timing-safe comparison using `hmac.compare_digest()`

### Observability

**Logging (core/logging.py)**:
- JSON-formatted logs via `python-json-logger`
- KST timezone for all log timestamps

**Metrics (main.py:72-84, middlewares/metrics.py)**:
- Prometheus metrics via `prometheus-fastapi-instrumentator`
- Multiprocess-safe collection (`PROMETHEUS_MULTIPROC_DIR`)
- Custom `FastAPIMetricsMiddleware` for request tracking
- Metrics exposed at `/metrics` endpoint

**Tracing** (optional):
- OpenTelemetry instrumentation available (see requirements.txt)
- ASGI and FastAPI auto-instrumentation

## Key Implementation Patterns

### Async Database Operations
All database operations use async/await pattern:
```python
async def get_campaigns(db: AsyncSession):
    result = await db.execute(select(Campaign))
    return result.scalars().all()
```

### Dependency Injection
FastAPI dependencies for session and authentication:
```python
@router.get("/campaigns")
async def list_campaigns(
    db: AsyncSession = Depends(get_db_session),
    # api_key verified via router-level dependency
):
    return await crud.list_campaigns(db, ...)
```

### Schema Validation
Pydantic schemas in `schemas/` directory:
- `CampaignOutV2`: Response schema with computed fields (is_new, distance)
- `CampaignListV2`: Paginated list response
- Automatic validation and serialization

### Timezone Handling (core/utils.py)
- `KST = timezone(timedelta(hours=9))`
- `_parse_kst()`: Parse ISO8601 strings to KST-aware datetime
- Always use KST for Korean market operations

## Testing Strategy

**Unit Tests** (tests/test_campaign_recommendation.py):
- Mock-based testing for CRUD functions
- Scenarios: expired campaign exclusion, promotion_level sorting, balanced distribution
- Performance requirements validation (500ms target)
- V2 schema compatibility tests

**Performance Testing**:
- `crud.explain_analyze_campaign_query()`: SQL execution plan analysis
- `crud.get_index_usage_stats()`: Index utilization metrics
- `crud.benchmark_campaign_queries()`: Query performance benchmarks

## Performance Considerations

**Query Optimization**:
- Use ORM queries with proper indexes (see models.py table_args)
- `selectinload()` for eager loading of relationships (avoid N+1)
- Count queries optimized with subquery approach
- Haversine distance calculation done in SQL for efficiency

**Caching Strategy**:
- No built-in caching layer (consider adding Redis for frequently accessed data)
- Stateless API design allows horizontal scaling

**Database Connection Pool**:
- `pool_pre_ping=True` ensures connection health
- Configure pool size via SQLAlchemy engine params for production

## Common Development Patterns

### Adding a New Filter Parameter
1. Add parameter to router function (api/routers/campaigns.py)
2. Add parameter to CRUD function signature (db/crud.py)
3. Add WHERE condition in `list_campaigns_optimized()`
4. Update schemas if response format changes (schemas/campaign.py)

### Adding a New Index
1. Add index to `Campaign.__table_args__` in db/models.py
2. Generate migration or apply manually to database
3. Verify with `get_index_usage_stats()` endpoint

### Performance Profiling
1. Use `/v1/performance/explain-analyze` with query parameters
2. Check index usage: `/v1/performance/index-stats`
3. Run benchmarks: `/v1/performance/benchmark`

## Migration Notes

**SQLAlchemy 2.0 Style**:
- Use `select()` construct, not legacy query API
- Async sessions everywhere
- `result.scalars().all()` for ORM objects
- `result.scalar()` for single values

**FastAPI Best Practices**:
- Type hints required for automatic validation
- Pydantic v2 models for schemas
- Dependency injection for shared resources
- Router-level dependencies for authentication

## Database Schema Evolution

When modifying database schema:
1. Update models in db/models.py (SQLAlchemy declarative)
2. Consider index impact on query performance
3. Update CRUD functions if query logic changes
4. Update Pydantic schemas for API contract changes
5. Run tests to verify backward compatibility

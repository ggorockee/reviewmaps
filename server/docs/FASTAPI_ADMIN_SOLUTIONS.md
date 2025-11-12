# FastAPI Admin 솔루션 비교 분석

## 📋 FastAPI 진영 Admin 도구들

### 1. SQLAdmin ⭐⭐⭐ 가장 인기

**GitHub**: https://github.com/aminalaee/sqladmin
**Stars**: 1.7K+
**상태**: 활발히 유지보수 중

#### 특징
```python
from sqladmin import Admin, ModelView

admin = Admin(app, engine)

class CampaignAdmin(ModelView, model=Campaign):
    # 자동 CRUD 생성
    column_list = [Campaign.id, Campaign.company, Campaign.platform]
    column_searchable_list = [Campaign.company, Campaign.offer]
    column_sortable_list = [Campaign.created_at]
    column_filters = [Campaign.platform, Campaign.category_id]

    # 폼 설정
    form_excluded_columns = [Campaign.created_at, Campaign.updated_at]

admin.add_view(CampaignAdmin)
```

#### 장점
```
✅ SQLAlchemy 네이티브 지원 (기존 모델 그대로 사용)
✅ 자동 CRUD 생성
✅ 필터링, 검색, 정렬 내장
✅ 관계 지원 (ForeignKey, ManyToMany)
✅ 깔끔한 UI (Bootstrap 5)
✅ 비동기 지원
✅ 인증 통합 가능
```

#### 단점
```
❌ Django Admin보다 기능 제한적
❌ 커스터마이징 제약
❌ 인라인 편집 제한적
❌ 대시보드 기능 약함
```

#### 구현 복잡도
```json
{
  "설정": "쉬움",
  "커스터마이징": "중간",
  "개발 기간": "2-3일",
  "학습 곡선": "낮음"
}
```

---

### 2. FastAPI Admin ⭐⭐

**GitHub**: https://github.com/fastapi-admin/fastapi-admin
**Stars**: 2.7K+
**상태**: 유지보수 중 (느림)

#### 특징
```python
from fastapi_admin.app import app as admin_app
from fastapi_admin.resources import Model, Field

@app.on_event("startup")
async def startup():
    await admin_app.configure(
        logo_url="https://your-logo.png",
        template_folders=[],
        providers=[
            Provider(login_logo_url="", admin_secret_key=""),
        ],
    )

class CampaignResource(Model):
    label = "캠페인"
    model = Campaign
    icon = "fas fa-bullhorn"

    fields = [
        Field(name="id", label="ID", display=True),
        Field(name="company", label="회사", display=True),
        Field(name="platform", label="플랫폼", input_type="select"),
    ]

app.mount('/admin', admin_app)
```

#### 장점
```
✅ 풍부한 UI (AdminLTE 3)
✅ 대시보드 지원
✅ 차트 및 위젯
✅ 다국어 지원
✅ 역할 기반 권한
```

#### 단점
```
❌ 복잡한 설정
❌ 문서 부족
❌ 업데이트 느림
❌ 러닝 커브 높음
❌ Tortoise ORM 중심 (SQLAlchemy 제한적)
```

#### 구현 복잡도
```json
{
  "설정": "복잡",
  "커스터마이징": "어려움",
  "개발 기간": "5-7일",
  "학습 곡선": "높음"
}
```

---

### 3. Starlette Admin ⭐⭐⭐

**GitHub**: https://github.com/jowilf/starlette-admin
**Stars**: 500+
**상태**: 활발히 유지보수 중

#### 특징
```python
from starlette_admin.contrib.sqla import Admin, ModelView

admin = Admin(engine, title="ReviewMaps Admin")

class CampaignAdmin(ModelView):
    # 기본 설정
    exclude_fields_from_list = ['content_link', 'img_url']
    exclude_fields_from_create = ['id', 'created_at']
    exclude_fields_from_edit = ['id', 'created_at']

    # 검색
    search_builder = True

    # 페이지네이션
    page_size = 50
    page_size_options = [25, 50, 100]

admin.add_view(CampaignAdmin(Campaign, icon="fa fa-bullhorn"))
app.mount('/admin', admin.app)
```

#### 장점
```
✅ SQLAlchemy 완벽 지원
✅ 깔끔한 UI (Tabler)
✅ 고급 검색 빌더
✅ 배치 작업 지원
✅ Export (CSV, Excel)
✅ 비동기 지원
✅ 인증 플러그인
```

#### 단점
```
❌ 상대적으로 신생
❌ 커뮤니티 작음
❌ 일부 고급 기능 부족
```

#### 구현 복잡도
```json
{
  "설정": "쉬움",
  "커스터마이징": "중간",
  "개발 기간": "3-4일",
  "학습 곡선": "낮음"
}
```

---

### 4. Piccolo Admin ⭐⭐

**GitHub**: https://github.com/piccolo-orm/piccolo_admin
**Stars**: 300+
**상태**: 유지보수 중

#### 특징
```python
# Piccolo ORM 전용
from piccolo_admin.endpoints import create_admin

admin = create_admin(
    tables=[Campaign, Category],
    forms=[CampaignForm],
    auth_table=User,
    session_table=SessionsBase,
)

app.mount('/admin/', admin)
```

#### 장점
```
✅ 자체 ORM 최적화
✅ 빠른 성능
✅ 자동 API 생성
✅ 현대적 UI (Vue.js)
```

#### 단점
```
❌ Piccolo ORM 전용 (SQLAlchemy 지원 없음)
❌ ORM 변경 필요
❌ 생태계 작음
❌ 러닝 커브
```

#### 구현 복잡도
```json
{
  "설정": "어려움 (ORM 변경)",
  "커스터마이징": "중간",
  "개발 기간": "7-10일",
  "학습 곡선": "높음"
}
```

---

### 5. Reflex Admin (신생) ⭐

**GitHub**: Python 풀스택 프레임워크
**상태**: 실험적

#### 특징
- Python으로 프론트엔드/백엔드 모두 작성
- React 기반 (자동 생성)
- 아직 초기 단계

---

## 📊 종합 비교표

| 솔루션 | Stars | SQLAlchemy | UI 품질 | 기능 | 비동기 | 추천도 |
|-------|-------|-----------|---------|------|--------|--------|
| **SQLAdmin** | 1.7K+ | ✅ 완벽 | ⭐⭐⭐ | ⭐⭐⭐ | ✅ | ⭐⭐⭐ |
| **Starlette Admin** | 500+ | ✅ 완벽 | ⭐⭐⭐⭐ | ⭐⭐⭐ | ✅ | ⭐⭐⭐ |
| **FastAPI Admin** | 2.7K+ | ⚠️ 제한적 | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ✅ | ⭐⭐ |
| **Piccolo Admin** | 300+ | ❌ 없음 | ⭐⭐⭐ | ⭐⭐ | ✅ | ⭐ |

---

## 🏆 프로젝트 추천: SQLAdmin

### 이유

**1. 기존 코드와 완벽 호환**
```python
# 기존 SQLAlchemy 모델 그대로 사용
from db.models import Campaign, Category
from sqlalchemy import create_async_engine

# 3줄이면 Admin 추가
admin = Admin(app, engine)
admin.add_view(ModelView(Campaign))
admin.add_view(ModelView(Category))
```

**2. 빠른 구현 (2-3일)**
```
Day 1: SQLAdmin 설치 및 기본 설정
Day 2: 커스터마이징 (필터, 검색, 권한)
Day 3: 테스트 및 배포
```

**3. 충분한 기능**
```python
class CampaignAdmin(ModelView, model=Campaign):
    # 목록 표시
    column_list = [
        Campaign.id,
        Campaign.company,
        Campaign.platform,
        Campaign.promotion_level,
        Campaign.created_at
    ]

    # 검색
    column_searchable_list = [Campaign.company, Campaign.offer]

    # 정렬
    column_sortable_list = [Campaign.created_at, Campaign.promotion_level]

    # 필터
    column_filters = [
        Campaign.platform,
        Campaign.category_id,
        Campaign.promotion_level
    ]

    # 기본 정렬
    column_default_sort = [(Campaign.created_at, True)]  # DESC

    # 페이지당 항목
    page_size = 50
    page_size_options = [25, 50, 100, 200]

    # 폼에서 제외
    form_excluded_columns = [
        Campaign.created_at,
        Campaign.updated_at
    ]

    # 읽기 전용 필드
    form_readonly_columns = [
        Campaign.company,
        Campaign.offer,
        Campaign.apply_deadline
    ]

    # 관계 표시
    column_formatters = {
        Campaign.category: lambda m, a: m.category.name if m.category else "-"
    }

    # 커스텀 표시
    def _list_actions(self, model):
        return [
            # 커스텀 액션 추가 가능
        ]
```

**4. 비동기 지원**
```python
from sqlalchemy.ext.asyncio import create_async_engine

engine = create_async_engine(
    "postgresql+asyncpg://...",
    echo=True
)

admin = Admin(app, engine)  # 비동기 엔진 그대로 사용
```

---

## 🚀 실전 구현 가이드 (SQLAdmin)

### Phase 1: 설치 및 기본 설정 (1-2시간)

```bash
pip install sqladmin
```

```python
# main.py
from fastapi import FastAPI
from sqladmin import Admin, ModelView
from db.session import engine
from db.models import Campaign, Category

app = FastAPI()

# SQLAdmin 추가
admin = Admin(app, engine)

# 기본 ModelView 추가 (자동 CRUD)
admin.add_view(ModelView(Campaign))
admin.add_view(ModelView(Category))

# Admin UI: http://localhost:8000/admin
```

### Phase 2: 커스터마이징 (4-6시간)

```python
# admin/campaigns.py
from sqladmin import ModelView
from db.models import Campaign
from sqlalchemy import select

class CampaignAdmin(ModelView, model=Campaign):
    # 메타데이터
    name = "캠페인"
    name_plural = "캠페인 목록"
    icon = "fa-solid fa-bullhorn"

    # 목록 페이지
    column_list = [
        Campaign.id,
        Campaign.company,
        Campaign.platform,
        Campaign.category,
        Campaign.promotion_level,
        Campaign.created_at,
    ]

    # 상세 페이지
    column_details_list = [
        Campaign.id,
        Campaign.company,
        Campaign.platform,
        Campaign.offer,
        Campaign.apply_deadline,
        Campaign.review_deadline,
        Campaign.address,
        Campaign.lat,
        Campaign.lng,
        Campaign.img_url,
        Campaign.promotion_level,
        Campaign.category,
        Campaign.created_at,
        Campaign.updated_at,
    ]

    # 검색 (LIKE)
    column_searchable_list = [Campaign.company, Campaign.offer, Campaign.address]

    # 필터
    column_filters = [
        Campaign.platform,
        Campaign.category_id,
        Campaign.promotion_level,
        Campaign.created_at,
        Campaign.apply_deadline,
    ]

    # 정렬
    column_sortable_list = [
        Campaign.created_at,
        Campaign.promotion_level,
        Campaign.apply_deadline,
    ]

    # 기본 정렬
    column_default_sort = [(Campaign.created_at, True)]  # DESC

    # 폼 설정
    form_columns = [
        Campaign.company,
        Campaign.platform,
        Campaign.offer,
        Campaign.category_id,
        Campaign.promotion_level,
        Campaign.img_url,
    ]

    # 읽기 전용
    form_readonly_columns = [
        Campaign.company,
        Campaign.offer,
        Campaign.apply_deadline,
    ]

    # 제외
    form_excluded_columns = [
        Campaign.created_at,
        Campaign.updated_at,
    ]

    # 페이지네이션
    page_size = 50
    page_size_options = [25, 50, 100, 200]

    # 커스텀 쿼리 (성능 최적화)
    async def get_list(self, *args, **kwargs):
        # selectinload로 N+1 방지
        from sqlalchemy.orm import selectinload

        query = select(Campaign).options(
            selectinload(Campaign.category)
        )

        # 필터 적용
        return await super().get_list(*args, query=query, **kwargs)

    # 배치 삭제 비활성화
    can_delete = False

    # 생성 비활성화
    can_create = False

    # 커스텀 레이블
    column_labels = {
        Campaign.id: "ID",
        Campaign.company: "회사",
        Campaign.platform: "플랫폼",
        Campaign.offer: "오퍼",
        Campaign.promotion_level: "프로모션 레벨",
        Campaign.created_at: "생성일",
    }

# main.py에 등록
admin.add_view(CampaignAdmin)
```

### Phase 3: 인증 추가 (2-3시간)

```python
# admin/auth.py
from sqladmin.authentication import AuthenticationBackend
from starlette.requests import Request
from starlette.responses import RedirectResponse

class AdminAuth(AuthenticationBackend):
    async def login(self, request: Request) -> bool:
        form = await request.form()
        username = form.get("username")
        password = form.get("password")

        # 간단한 인증 (실제로는 DB 조회)
        if username == "admin" and password == "your-secure-password":
            # 세션에 저장
            request.session.update({"user": username})
            return True
        return False

    async def logout(self, request: Request) -> bool:
        request.session.clear()
        return True

    async def authenticate(self, request: Request) -> bool:
        user = request.session.get("user")
        return user is not None

# main.py
from starlette.middleware.sessions import SessionMiddleware

app.add_middleware(SessionMiddleware, secret_key="your-secret-key")

authentication_backend = AdminAuth(secret_key="your-secret-key")
admin = Admin(app, engine, authentication_backend=authentication_backend)
```

### Phase 4: 고급 기능 (옵션)

```python
# 1. 커스텀 컬럼 포맷터
from markupsafe import Markup

class CampaignAdmin(ModelView, model=Campaign):
    column_formatters = {
        Campaign.promotion_level: lambda m, a: Markup(
            f'<span class="badge badge-{"danger" if m.promotion_level >= 5 else "info"}">'
            f'{m.promotion_level}</span>'
        ),
        Campaign.img_url: lambda m, a: Markup(
            f'<img src="{m.img_url}" style="max-width:100px" />' if m.img_url else ""
        ),
        Campaign.company_link: lambda m, a: Markup(
            f'<a href="{m.company_link}" target="_blank">{m.company}</a>'
            if m.company_link else m.company
        ),
    }

# 2. 배치 액션
class CampaignAdmin(ModelView, model=Campaign):
    column_list_actions = ["view", "edit"]

    async def on_model_change(self, data, model, is_created, request):
        # 수정 시 로그 기록
        if not is_created:
            logger.info(f"Campaign {model.id} updated by {request.session.get('user')}")
        await super().on_model_change(data, model, is_created, request)

# 3. Export 기능
from sqladmin.actions import action

class CampaignAdmin(ModelView, model=Campaign):
    @action(
        name="export_csv",
        label="CSV로 내보내기",
        confirmation_message="선택한 항목을 CSV로 내보내시겠습니까?",
        add_in_detail=False,
        add_in_list=True,
    )
    async def export_to_csv(self, request: Request):
        # CSV 생성 로직
        pass
```

---

## 💰 비용 비교

| 솔루션 | 개발 기간 | 구현 난이도 | 유지보수 | 총 비용 |
|-------|----------|-----------|----------|---------|
| **SQLAdmin** | 2-3일 | 🟢 쉬움 | 🟢 낮음 | 🟢 낮음 |
| **Starlette Admin** | 3-4일 | 🟢 쉬움 | 🟢 낮음 | 🟢 낮음 |
| **FastAPI Admin** | 5-7일 | 🔴 어려움 | 🟡 중간 | 🟡 중간 |
| **Django Admin** | 3-5일 | 🟢 쉬움 | 🟢 낮음 | 🟢 낮음 |

---

## 🎯 최종 추천

### Option 1: SQLAdmin (FastAPI 네이티브) ⭐⭐⭐

**추천 이유:**
```
✅ 기존 SQLAlchemy 모델 그대로 사용
✅ 빠른 구현 (2-3일)
✅ FastAPI 생태계 통합
✅ 비동기 지원
✅ 충분한 기능
✅ 낮은 학습 곡선
```

**구현 시간:**
- Day 1: 기본 설정 + 자동 CRUD (4시간)
- Day 2: 커스터마이징 + 필터/검색 (6시간)
- Day 3: 인증 + 권한 + 테스트 (4시간)

**총: 2-3일**

### Option 2: Django Admin (하이브리드) ⭐⭐⭐

**언제 선택:**
```
✅ Django Admin의 풍부한 기능이 필요할 때
✅ 복잡한 관리 기능 (인라인, 대시보드 등)
✅ 팀이 Django에 익숙할 때
```

---

## 🔚 결론

**"FastAPI 진영에서 쓰는 admin은?"**

### 1순위: SQLAdmin
- 기존 코드 그대로 사용
- 2-3일 구현
- FastAPI 네이티브

### 2순위: Starlette Admin
- 조금 더 현대적인 UI
- 3-4일 구현

### 3순위: Django Admin (하이브리드)
- 가장 풍부한 기능
- 3-5일 구현

**당신의 경우:** SQLAdmin으로 시작 → 부족하면 Django Admin 고려

---

**작성일**: 2025년
**작성자**: Claude Code Analysis
**검토 상태**: FastAPI Admin 솔루션 비교 완료

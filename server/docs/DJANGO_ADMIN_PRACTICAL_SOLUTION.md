# Django Admin 실용적 해결책 - 읽기/쓰기 균형

## 🎯 현실적인 문제

**"읽기 전용으로 하면 어떻게 수정하냐?"**

맞습니다. 실제 운영에서는:
- ✅ 조회/모니터링: 90%
- ⚠️ 간단한 수정: 8% (promotion_level 조정, 긴급 수정 등)
- 🔴 복잡한 작업: 2%

완전 읽기 전용은 **비현실적**입니다.

---

## 💡 실용적 해결책 3가지

### Solution 1: 하이브리드 (읽기 + 제한적 쓰기) ⭐⭐⭐ 강력 추천

**개념:**
- 대부분 필드: 읽기 전용
- 특정 필드만: 수정 가능
- 중요 필드: 완전 보호

```python
@admin.register(Campaign)
class CampaignAdmin(admin.ModelAdmin):
    list_display = ['id', 'company', 'platform', 'promotion_level', 'status']
    list_filter = ['platform', 'category', 'promotion_level']
    search_fields = ['company', 'offer']

    def get_readonly_fields(self, request, obj=None):
        if obj:  # 수정 모드
            # 핵심 비즈니스 필드는 읽기 전용
            readonly = [
                'id', 'company', 'platform', 'offer',
                'apply_deadline', 'review_deadline',
                'lat', 'lng', 'created_at', 'updated_at'
            ]

            # 관리자만 수정 가능한 필드 제외
            # promotion_level, img_url, search_text 등은 수정 가능

            return readonly
        return []

    def has_add_permission(self, request):
        return False  # 추가는 금지

    def has_delete_permission(self, request, obj=None):
        return False  # 삭제는 금지

    def save_model(self, request, obj, form, change):
        if change:
            # 수정 로그 남기기
            changed_fields = form.changed_data
            logger.info(
                f"Admin update by {request.user.username}: "
                f"Campaign {obj.id} fields {changed_fields}"
            )
        super().save_model(request, obj, form, change)
```

**수정 가능 필드 예시:**
```python
# 수정 허용 필드 (관리자가 자주 조정)
writable_fields = [
    'promotion_level',  # 프로모션 레벨 조정
    'img_url',          # 이미지 URL 수정
    'search_text',      # 검색 텍스트 수정
    'category_id',      # 카테고리 재분류
]

# 읽기 전용 필드 (데이터 무결성 중요)
readonly_fields = [
    'company',          # 회사명 (크롤링 데이터)
    'offer',            # 오퍼 내용 (크롤링 데이터)
    'apply_deadline',   # 마감일 (크롤링 데이터)
    'lat', 'lng',       # 좌표 (지리 데이터)
    'created_at',       # 생성일 (시스템 필드)
]
```

**장점:**
```
✅ 현실적: 필요한 수정만 가능
✅ 안전함: 핵심 데이터 보호
✅ 추적 가능: 수정 로그 기록
✅ 빠름: 3-5일 구현
```

**단점:**
```
⚠️ 데이터 일관성: 부분적 위험 (제한적)
⚠️ 검증 우회: Django에서 직접 수정 시 FastAPI 검증 우회
```

---

### Solution 2: FastAPI Admin 패널 추가 ⭐⭐

**개념:**
- Django Admin 대신 FastAPI 기반 Admin 패널
- 기존 비즈니스 로직 재사용
- 일관된 검증 및 권한 관리

**구현: FastAPI Admin 라이브러리**

```bash
pip install fastapi-admin
```

```python
# admin_setup.py
from fastapi_admin.app import app as admin_app
from fastapi_admin.resources import Field, Model

# Campaign Admin 설정
class CampaignResource(Model):
    label = "캠페인"
    model = Campaign

    # 필드 정의
    fields = [
        Field(name="id", label="ID", display=True),
        Field(name="company", label="회사", display=True),
        Field(name="platform", label="플랫폼", display=True),
        Field(name="promotion_level", label="프로모션", input_type="number"),
        Field(name="created_at", label="생성일", display=True),
    ]

    # 읽기 전용 필드
    readonly_fields = ["id", "created_at", "updated_at"]

    # 검색 가능 필드
    search_fields = ["company", "offer"]

    # 필터
    filters = ["platform", "category_id"]

# FastAPI에 마운트
app.mount('/admin', admin_app)
```

**또는 Starlette Admin 사용:**

```bash
pip install starlette-admin
```

```python
from starlette_admin.contrib.sqla import Admin, ModelView

admin = Admin(engine, title="ReviewMaps Admin")

class CampaignAdmin(ModelView):
    # 읽기 전용 필드 지정
    exclude_fields_from_edit = ["id", "created_at", "updated_at"]

    # 목록 표시
    list_columns = ["id", "company", "platform", "created_at"]

    # 검색
    search_columns = ["company", "offer"]

    # 정렬
    sort_column = "created_at"

admin.add_view(CampaignAdmin(Campaign, label="캠페인"))

app.mount('/admin', admin.app)
```

**장점:**
```
✅ 데이터 일관성: FastAPI 비즈니스 로직 재사용
✅ 검증 통과: 기존 검증 로직 그대로 사용
✅ 통합: 단일 프레임워크
✅ 권한 관리: 기존 인증 시스템 재사용
```

**단점:**
```
❌ 기능 제한: Django Admin보다 기능 적음
❌ 커스터마이징: 더 많은 코딩 필요
❌ 성숙도: Django Admin보다 생태계 작음
❌ 개발 시간: 5-7일 소요
```

---

### Solution 3: Django Admin + FastAPI API 호출 ⭐

**개념:**
- Django Admin UI 사용
- 수정 작업은 FastAPI API 호출
- 완벽한 데이터 일관성

```python
# django_admin/services.py
import httpx
from typing import Dict, Any

class FastAPIService:
    BASE_URL = "http://localhost:8000/v1"
    API_KEY = "your-api-key"

    def __init__(self):
        self.client = httpx.Client(
            headers={"X-API-KEY": self.API_KEY},
            timeout=30.0
        )

    def update_campaign(self, campaign_id: int, data: Dict[str, Any]):
        """FastAPI를 통해 캠페인 업데이트"""
        response = self.client.patch(
            f"{self.BASE_URL}/campaigns/{campaign_id}",
            json=data
        )
        response.raise_for_status()
        return response.json()

# django_admin/admin.py
from django.contrib import admin
from django.contrib import messages
from .services import FastAPIService

@admin.register(Campaign)
class CampaignAdmin(admin.ModelAdmin):
    # 읽기는 Django ORM
    list_display = ['id', 'company', 'platform', 'promotion_level']
    list_filter = ['platform', 'category']
    search_fields = ['company', 'offer']

    # 수정 가능 필드만 표시
    fields = ['promotion_level', 'img_url', 'category']

    def save_model(self, request, obj, form, change):
        if change:  # 수정 모드
            try:
                # FastAPI를 통해 업데이트
                service = FastAPIService()
                updated_data = {
                    field: form.cleaned_data[field]
                    for field in form.changed_data
                }

                service.update_campaign(obj.id, updated_data)

                # Django 모델도 동기화
                super().save_model(request, obj, form, change)

                messages.success(
                    request,
                    f"캠페인 {obj.id} 수정 완료"
                )
            except Exception as e:
                messages.error(
                    request,
                    f"수정 실패: {str(e)}"
                )
        else:
            messages.error(request, "새 캠페인 추가는 불가능합니다.")

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
```

**FastAPI에 PATCH 엔드포인트 추가:**

```python
# api/routers/campaigns.py

@router.patch("/campaigns/{campaign_id}")
async def update_campaign(
    campaign_id: int,
    updates: CampaignUpdate,  # Pydantic 모델
    db: AsyncSession = Depends(get_db_session)
):
    """관리자용 캠페인 수정 API"""

    # 기존 캠페인 조회
    campaign = await crud.get_campaign(db, campaign_id)
    if not campaign:
        raise HTTPException(404, "Campaign not found")

    # 허용된 필드만 업데이트
    update_data = updates.dict(exclude_unset=True)
    allowed_fields = ['promotion_level', 'img_url', 'category_id']

    for field, value in update_data.items():
        if field in allowed_fields:
            setattr(campaign, field, value)

    campaign.updated_at = datetime.now(KST)
    await db.commit()
    await db.refresh(campaign)

    return campaign
```

**장점:**
```
✅ 완벽한 데이터 일관성
✅ 검증 로직 통과
✅ Django Admin UI 활용
✅ 권한 관리 일관성
```

**단점:**
```
❌ 복잡한 구현
❌ HTTP 오버헤드
❌ 에러 처리 복잡
❌ 개발 시간: 7-10일
```

---

## 📊 해결책 비교

| 항목 | Solution 1<br>(하이브리드) | Solution 2<br>(FastAPI Admin) | Solution 3<br>(API 호출) |
|------|--------------------------|------------------------------|------------------------|
| **구현 난이도** | 🟢 쉬움 | 🟡 중간 | 🔴 어려움 |
| **개발 기간** | 3-5일 | 5-7일 | 7-10일 |
| **데이터 일관성** | 🟡 제한적 | ✅ 완벽 | ✅ 완벽 |
| **기능 풍부도** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| **관리 편의성** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| **리스크** | 🟡 낮음 | 🟢 매우 낮음 | 🟢 매우 낮음 |

---

## 🎯 최종 권장: Solution 1 (하이브리드)

### 실용적 접근법

```python
# 1단계: 기본은 읽기 전용으로 시작
@admin.register(Campaign)
class CampaignAdmin(admin.ModelAdmin):
    # 조회 기능 최대한 활용
    list_display = ['id', 'company', 'platform', 'promotion_badge', 'status']
    list_filter = ['platform', 'category', 'promotion_level']
    search_fields = ['company', 'offer', 'address']

    # 수정 가능한 필드만 지정
    def get_fields(self, request, obj=None):
        if obj:  # 수정 모드
            return ['promotion_level', 'img_url', 'category']
        return []

    def get_readonly_fields(self, request, obj=None):
        if obj:
            # 나머지는 모두 읽기 전용
            all_fields = [f.name for f in self.model._meta.fields]
            writable = ['promotion_level', 'img_url', 'category']
            return [f for f in all_fields if f not in writable]
        return []
```

### 단계적 확장 전략

**Phase 1: 읽기 전용 (3일)**
- 조회, 필터링, 검색만
- 데이터 모니터링 및 분석

**Phase 2: 제한적 쓰기 추가 (2일)**
- 안전한 필드만 수정 허용
- promotion_level, img_url 등

**Phase 3: 고급 기능 (옵션, 추가 3-5일)**
- 필요 시 FastAPI API 호출 추가
- 복잡한 작업은 API 통해 처리

---

## 💡 실무 팁

### 1. 수정 가능 필드 선정 기준

```python
# 수정 허용 기준
writable_criteria = {
    "낮은 리스크": [
        "promotion_level",  # 표시 순서 (UI만 영향)
        "img_url",          # 이미지 (비즈니스 로직 무관)
        "search_text",      # 검색 텍스트 (보조 필드)
    ],

    "중간 리스크": [
        "category_id",      # 카테고리 (재분류 가능)
    ],

    "높은 리스크": [
        "apply_deadline",   # 마감일 (중요 비즈니스 데이터)
        "offer",            # 오퍼 (핵심 데이터)
        "lat", "lng",       # 좌표 (정확도 중요)
    ]
}

# 원칙: 낮은 리스크만 수정 허용
```

### 2. 안전장치 추가

```python
@admin.register(Campaign)
class CampaignAdmin(admin.ModelAdmin):
    def save_model(self, request, obj, form, change):
        if change:
            # 1. 수정 전 값 저장
            old_obj = Campaign.objects.get(pk=obj.pk)

            # 2. 수정 로그 기록
            for field in form.changed_data:
                old_value = getattr(old_obj, field)
                new_value = getattr(obj, field)

                AuditLog.objects.create(
                    user=request.user,
                    action='UPDATE',
                    model='Campaign',
                    object_id=obj.id,
                    field=field,
                    old_value=str(old_value),
                    new_value=str(new_value),
                )

            # 3. 특정 필드 검증
            if 'promotion_level' in form.changed_data:
                if not (0 <= obj.promotion_level <= 10):
                    raise ValueError("promotion_level must be 0-10")

        super().save_model(request, obj, form, change)
```

### 3. 긴급 수정 워크플로우

```python
# 읽기 전용이지만, 슈퍼유저는 수정 가능
def has_change_permission(self, request, obj=None):
    # 일반 관리자: 읽기만
    if not request.user.is_superuser:
        return False

    # 슈퍼유저: 특정 필드만 수정
    return True

def get_readonly_fields(self, request, obj=None):
    if obj and request.user.is_superuser:
        # 슈퍼유저는 더 많은 필드 수정 가능
        return ['id', 'created_at', 'updated_at']

    # 일반 관리자는 모든 필드 읽기 전용
    return [f.name for f in self.model._meta.fields]
```

---

## 🔚 최종 결론

### 추천: Solution 1 (하이브리드)

**실용적 균형:**
```
읽기: 모든 필드 (100%)
쓰기: 안전한 필드만 (20-30%)
   - promotion_level
   - img_url
   - category_id
   - search_text
```

**구현 순서:**
```
Day 1: Django 프로젝트 + 모델 설정
Day 2: Admin 기본 설정 (읽기 전용)
Day 3: 제한적 쓰기 추가
Day 4: 테스트 및 안전장치
Day 5: 배포 및 모니터링

총: 5일
```

**핵심 원칙:**
1. ✅ 기본은 읽기 전용 (안전)
2. ✅ 안전한 필드만 수정 허용 (실용)
3. ✅ 수정 로그 기록 (추적)
4. ✅ 단계적 확장 (점진적)

이렇게 하면 **Django Admin의 편리함**과 **데이터 일관성**을 모두 얻을 수 있습니다! 🎯

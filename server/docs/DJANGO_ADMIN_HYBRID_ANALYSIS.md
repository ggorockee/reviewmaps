# Django Admin 활용 하이브리드 아키텍처 분석

## 📋 Executive Summary

### 분석 목적
전체 API 마이그레이션 없이 **Django Admin의 장점만** 활용하는 하이브리드 아키텍처 분석

### 핵심 결론
**Option 2 (Django Admin Only - 읽기 전용) 추천**

---

## 🏗️ 아키텍처 시나리오 비교

### Scenario 1: Django Admin + ORM (완전 통합)

```
┌─────────────────────────────────────┐
│     Django (내부 관리 도구)          │
│  - Admin UI (CRUD)                  │
│  - Django ORM (동기)                │
│  - 복잡한 데이터 조작                │
└──────────────┬──────────────────────┘
               │
          ┌────▼────┐
          │ 공유 DB │
          │ (동일)  │
          └────▲────┘
               │
┌──────────────┴──────────────────────┐
│     FastAPI (외부 API)              │
│  - 비동기 API                        │
│  - SQLAlchemy (async)               │
│  - 최적화된 쿼리                     │
└─────────────────────────────────────┘
```

**특징:**
- Django와 FastAPI가 동일 DB를 직접 접근
- 각자의 ORM 사용 (Django ORM + SQLAlchemy)
- 데이터 일관성 문제 가능성

### Scenario 2: Django Admin Only (읽기 전용)

```
┌─────────────────────────────────────┐
│     Django (내부 관리 도구)          │
│  - Admin UI (읽기 전용)             │
│  - Django ORM (읽기만)              │
│  - 데이터 조회 및 모니터링           │
└──────────────┬──────────────────────┘
               │ (읽기)
          ┌────▼────┐
          │ 공유 DB │
          │ (동일)  │
          └────▲────┘
               │ (읽기/쓰기)
┌──────────────┴──────────────────────┐
│     FastAPI (외부 API)              │
│  - 비동기 API                        │
│  - SQLAlchemy (async)               │
│  - 모든 쓰기 작업 처리               │
└─────────────────────────────────────┘
```

**특징:**
- Django는 읽기 전용으로만 사용
- 모든 쓰기 작업은 FastAPI를 통해서만
- 데이터 일관성 보장

### Scenario 3: Django Admin + API 호출

```
┌─────────────────────────────────────┐
│     Django (내부 관리 도구)          │
│  - Admin UI                         │
│  - FastAPI HTTP 클라이언트          │
│  - 쓰기는 API 호출                  │
└──────────────┬──────────────────────┘
               │ HTTP API 호출
               │
┌──────────────▼──────────────────────┐
│     FastAPI (외부 API)              │
│  - 비동기 API                        │
│  - SQLAlchemy (async)               │
│  - 모든 비즈니스 로직                │
└──────────────┬──────────────────────┘
               │
          ┌────▼────┐
          │   DB    │
          └─────────┘
```

**특징:**
- Django는 DB 직접 접근 없음
- 모든 작업을 FastAPI API를 통해
- 완전한 데이터 일관성

---

## 📊 시나리오별 상세 분석

### Option 1: Django Admin + ORM (완전 통합)

#### 장점
```
✅ 빠른 CRUD 구현
   - Django Admin 자동 생성
   - 복잡한 필터링, 검색 내장
   - 인라인 편집, 관계 관리

✅ 개발 생산성
   - 별도 API 호출 불필요
   - Django ORM의 편의성
   - 빠른 프로토타이핑

✅ 유연한 데이터 조작
   - 복잡한 업데이트 쿼리
   - 배치 작업 처리
   - 관리자 전용 기능
```

#### 단점
```
❌ 데이터 일관성 문제 (Critical)
   - 두 개의 ORM이 동일 DB 접근
   - 트랜잭션 격리 문제
   - 캐시 무효화 복잡성

❌ 모델 중복 관리
   - SQLAlchemy 모델
   - Django 모델
   - 스키마 변경 시 양쪽 모두 수정

❌ 마이그레이션 충돌
   - SQLAlchemy 마이그레이션
   - Django 마이그레이션
   - 순서 및 의존성 관리 복잡

❌ 비즈니스 로직 분산
   - FastAPI의 검증 로직 우회 가능
   - 데이터 무결성 보장 어려움
   - 버그 추적 복잡
```

#### 구현 복잡도
```json
{
  "모델 정의": "높음 (중복 관리)",
  "마이그레이션": "매우 높음 (충돌 가능성)",
  "데이터 일관성": "높음 (복잡한 동기화)",
  "유지보수": "높음 (두 시스템 관리)",
  "예상 개발 기간": "2-3주"
}
```

#### 비용 분석
```
개발 비용:
- Django 모델 정의: 3-5일
- Admin 커스터마이징: 2-3일
- 데이터 일관성 로직: 5-7일
- 테스트 및 검증: 3-5일
총: 13-20일

운영 비용:
- 마이그레이션 관리: 높음
- 버그 수정 복잡도: 높음
- 모니터링 포인트: 2배
```

---

### Option 2: Django Admin Only (읽기 전용) ⭐ 추천

#### 장점
```
✅ 데이터 일관성 보장 (Critical)
   - 쓰기는 FastAPI만 담당
   - 단일 소스 오브 트루스
   - 트랜잭션 격리 문제 없음

✅ 간단한 구현
   - 읽기 전용 모델 정의
   - 마이그레이션 충돌 없음
   - 비즈니스 로직 분산 없음

✅ 낮은 유지보수 비용
   - 단일 마이그레이션 관리
   - 명확한 책임 분리
   - 버그 추적 용이

✅ 충분한 관리 기능
   - 데이터 조회 및 모니터링
   - 복잡한 필터링
   - CSV/JSON 내보내기
   - 대시보드 및 리포트
```

#### 단점
```
⚠️ 제한된 쓰기 작업
   - Admin에서 직접 수정 불가
   - FastAPI API를 통한 우회 필요
   - 긴급 수정 시 불편

⚠️ 추가 개발 필요 (쓰기 작업)
   - Django Admin에서 FastAPI API 호출
   - 또는 별도 관리 페이지 구현
```

#### 구현 방법

**1. 읽기 전용 Django 모델**
```python
# django_admin/models.py
from django.db import models

class Campaign(models.Model):
    id = models.BigAutoField(primary_key=True)
    category = models.ForeignKey('Category', on_delete=models.CASCADE)
    platform = models.CharField(max_length=20)
    company = models.CharField(max_length=255)
    # ... 기타 필드

    class Meta:
        managed = False  # Django 마이그레이션에서 제외
        db_table = 'campaign'  # SQLAlchemy와 동일 테이블

    def __str__(self):
        return f"{self.company} - {self.platform}"
```

**2. 읽기 전용 Admin 설정**
```python
# django_admin/admin.py
from django.contrib import admin
from .models import Campaign

@admin.register(Campaign)
class CampaignAdmin(admin.ModelAdmin):
    # 읽기 전용 설정
    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def has_change_permission(self, request, obj=None):
        return False  # 완전 읽기 전용

    # 조회 기능 최적화
    list_display = ['id', 'company', 'platform', 'category', 'created_at']
    list_filter = ['platform', 'category', 'created_at']
    search_fields = ['company', 'offer']
    date_hierarchy = 'created_at'

    # 성능 최적화
    list_select_related = ['category']
    list_per_page = 50
```

**3. 데이터베이스 설정 (읽기 전용 복제본)**
```python
# settings.py
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'crawrling',
        'USER': 'crawrling_readonly',  # 읽기 전용 사용자
        'PASSWORD': '...',
        'HOST': 'localhost',
        'PORT': '5431',
        'OPTIONS': {
            'connect_timeout': 10,
            'options': '-c default_transaction_read_only=on'  # 읽기 전용 강제
        }
    }
}
```

#### 구현 복잡도
```json
{
  "모델 정의": "낮음 (읽기 전용)",
  "마이그레이션": "없음 (managed=False)",
  "데이터 일관성": "완벽 (쓰기 없음)",
  "유지보수": "낮음 (단순)",
  "예상 개발 기간": "3-5일"
}
```

#### 비용 분석
```
개발 비용:
- Django 모델 정의 (읽기 전용): 1-2일
- Admin 커스터마이징: 1-2일
- 테스트 및 검증: 1일
총: 3-5일

운영 비용:
- 마이그레이션 관리: 없음
- 버그 수정 복잡도: 매우 낮음
- 모니터링 포인트: 기존과 동일
```

---

### Option 3: Django Admin + API 호출

#### 장점
```
✅ 완벽한 데이터 일관성
   - 모든 작업이 FastAPI 통과
   - 비즈니스 로직 중앙화
   - 검증 로직 일관성

✅ 쓰기 작업 가능
   - Admin에서 CRUD 모두 가능
   - FastAPI API 호출로 처리
   - 권한 관리 일관성
```

#### 단점
```
❌ 높은 구현 복잡도
   - Django Admin 커스터마이징 복잡
   - HTTP 클라이언트 통합
   - 에러 처리 복잡

❌ 성능 오버헤드
   - 네트워크 레이턴시
   - HTTP 직렬화/역직렬화
   - 동기 HTTP 호출 블로킹

❌ 동기-비동기 변환
   - Django Admin은 동기
   - FastAPI는 비동기
   - httpx async 클라이언트 필요
```

#### 구현 예시
```python
# django_admin/services.py
import httpx

class FastAPIClient:
    BASE_URL = "http://localhost:8000/v1"
    API_KEY = "your-api-key"

    def __init__(self):
        self.client = httpx.Client(
            headers={"X-API-KEY": self.API_KEY},
            timeout=30.0
        )

    def create_campaign(self, data):
        response = self.client.post(
            f"{self.BASE_URL}/campaigns",
            json=data
        )
        response.raise_for_status()
        return response.json()

# django_admin/admin.py
from django.contrib import admin
from .services import FastAPIClient

@admin.register(Campaign)
class CampaignAdmin(admin.ModelAdmin):
    def save_model(self, request, obj, form, change):
        client = FastAPIClient()
        data = {
            'company': obj.company,
            'platform': obj.platform,
            # ... 기타 필드
        }

        if change:
            client.update_campaign(obj.id, data)
        else:
            client.create_campaign(data)

        # Django 모델은 동기화만
        super().save_model(request, obj, form, change)
```

#### 구현 복잡도
```json
{
  "모델 정의": "중간",
  "API 통합": "높음",
  "에러 처리": "매우 높음",
  "유지보수": "높음",
  "예상 개발 기간": "2-3주"
}
```

---

## 🎯 종합 비교 및 권장사항

### 시나리오 비교표

| 평가 항목 | Option 1<br>(완전 통합) | Option 2<br>(읽기 전용) ⭐ | Option 3<br>(API 호출) |
|----------|----------------------|-------------------------|---------------------|
| **데이터 일관성** | ⚠️ 낮음 | ✅ 완벽 | ✅ 완벽 |
| **구현 복잡도** | 🔴 높음 | 🟢 낮음 | 🔴 매우 높음 |
| **개발 기간** | 2-3주 | 3-5일 | 2-3주 |
| **유지보수 비용** | 🔴 높음 | 🟢 낮음 | 🟡 중간 |
| **쓰기 작업** | ✅ 가능 | ❌ 불가능 | ✅ 가능 |
| **성능** | 🟢 빠름 | 🟢 빠름 | 🟡 느림 |
| **마이그레이션 관리** | 🔴 복잡 | 🟢 없음 | 🟡 단순 |
| **리스크** | 🔴 높음 | 🟢 낮음 | 🟡 중간 |

### 🏆 최종 권장: Option 2 (읽기 전용)

**이유:**
```
1. 데이터 일관성 보장
   - 쓰기는 FastAPI만 담당
   - 단일 소스 오브 트루스
   - 검증 로직 일관성

2. 빠른 구현 (3-5일)
   - 읽기 전용 모델 정의
   - 간단한 Admin 설정
   - 마이그레이션 불필요

3. 낮은 유지보수 비용
   - 복잡도 최소화
   - 명확한 책임 분리
   - 버그 추적 용이

4. 충분한 기능
   - 데이터 조회 및 모니터링
   - 복잡한 필터링
   - 대시보드 및 리포트
   - CSV/JSON 내보내기
```

### 🎯 실용적 해결책: 읽기 전용 + 긴급 수정

**하이브리드 접근:**
```python
# 대부분: 읽기 전용 Admin
# 긴급 상황: 특정 필드만 수정 허용

@admin.register(Campaign)
class CampaignAdmin(admin.ModelAdmin):
    # 기본적으로 읽기 전용
    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    # 긴급 상황: 특정 필드만 수정 허용
    def get_readonly_fields(self, request, obj=None):
        if obj:  # 수정 시
            # 대부분 필드는 읽기 전용
            readonly = list(self.list_display)
            # 긴급 수정 가능한 필드만 제외
            readonly.remove('promotion_level')  # 예: 프로모션 레벨만 수정 가능
            return readonly
        return []

    def save_model(self, request, obj, form, change):
        # 수정 로그 기록
        logger.warning(f"Admin manual update: {request.user} modified campaign {obj.id}")
        super().save_model(request, obj, form, change)
```

---

## 📋 구현 가이드 (Option 2 추천)

### Phase 1: Django 프로젝트 설정 (1일)

```bash
# 1. Django 프로젝트 생성
mkdir django_admin && cd django_admin
python -m venv venv
source venv/bin/activate

pip install Django psycopg2-binary

django-admin startproject admin_panel .
python manage.py startapp campaigns
```

```python
# settings.py
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'crawrling',
        'USER': 'crawrling',
        'PASSWORD': 'crawrling',
        'HOST': 'localhost',
        'PORT': '5431',
    }
}

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'campaigns',  # 추가
]
```

### Phase 2: 모델 정의 (1-2일)

```python
# campaigns/models.py
from django.db import models

class Category(models.Model):
    id = models.BigAutoField(primary_key=True)
    name = models.CharField(max_length=100)
    display_order = models.IntegerField(default=99)
    created_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = 'categories'
        verbose_name_plural = 'Categories'

    def __str__(self):
        return self.name

class Campaign(models.Model):
    id = models.BigAutoField(primary_key=True)
    category = models.ForeignKey(
        Category,
        on_delete=models.CASCADE,
        null=True,
        blank=True
    )
    platform = models.CharField(max_length=20)
    company = models.CharField(max_length=255)
    offer = models.TextField()
    apply_deadline = models.DateTimeField(null=True, blank=True)
    review_deadline = models.DateTimeField(null=True, blank=True)
    address = models.TextField(null=True, blank=True)
    lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    promotion_level = models.IntegerField(default=0)
    created_at = models.DateTimeField()
    updated_at = models.DateTimeField()

    class Meta:
        managed = False
        db_table = 'campaign'
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.company} - {self.platform}"

    @property
    def is_expired(self):
        from django.utils import timezone
        return self.apply_deadline and self.apply_deadline < timezone.now()
```

### Phase 3: Admin 설정 (1-2일)

```python
# campaigns/admin.py
from django.contrib import admin
from django.utils.html import format_html
from .models import Campaign, Category

@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ['id', 'name', 'display_order', 'campaign_count']
    list_filter = ['display_order']
    search_fields = ['name']
    ordering = ['display_order', 'name']

    # 읽기 전용
    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def campaign_count(self, obj):
        return obj.campaign_set.count()
    campaign_count.short_description = '캠페인 수'

@admin.register(Campaign)
class CampaignAdmin(admin.ModelAdmin):
    list_display = [
        'id', 'company_link', 'platform', 'category',
        'promotion_badge', 'deadline_status', 'created_at'
    ]
    list_filter = [
        'platform', 'category', 'promotion_level',
        ('created_at', admin.DateFieldListFilter),
        ('apply_deadline', admin.DateFieldListFilter)
    ]
    search_fields = ['company', 'offer', 'address']
    date_hierarchy = 'created_at'

    # 성능 최적화
    list_select_related = ['category']
    list_per_page = 50
    show_full_result_count = False  # 대용량 데이터 최적화

    # 읽기 전용
    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    # 커스텀 표시
    def company_link(self, obj):
        if obj.company_link:
            return format_html(
                '<a href="{}" target="_blank">{}</a>',
                obj.company_link,
                obj.company
            )
        return obj.company
    company_link.short_description = '회사'

    def promotion_badge(self, obj):
        if obj.promotion_level >= 5:
            color = 'red'
        elif obj.promotion_level >= 3:
            color = 'orange'
        else:
            color = 'gray'

        return format_html(
            '<span style="background-color: {}; color: white; padding: 3px 8px; border-radius: 3px;">{}</span>',
            color,
            obj.promotion_level
        )
    promotion_badge.short_description = '프로모션'

    def deadline_status(self, obj):
        if not obj.apply_deadline:
            return format_html('<span style="color: gray;">-</span>')

        if obj.is_expired:
            return format_html(
                '<span style="color: red;">만료</span>'
            )
        else:
            return format_html(
                '<span style="color: green;">진행중</span>'
            )
    deadline_status.short_description = '상태'
```

### Phase 4: 배포 (1일)

```bash
# 1. 정적 파일 수집
python manage.py collectstatic --noinput

# 2. Gunicorn으로 실행
pip install gunicorn
gunicorn admin_panel.wsgi:application --bind 0.0.0.0:8001 --workers 2

# 3. Nginx 리버스 프록시 설정 (옵션)
# /admin → Django Admin (port 8001)
# /v1 → FastAPI (port 8000)
```

---

## 💡 추가 고려사항

### 1. 읽기 전용 DB 사용자 생성 (보안 강화)

```sql
-- PostgreSQL에서 읽기 전용 사용자 생성
CREATE USER crawrling_readonly WITH PASSWORD 'readonly_password';
GRANT CONNECT ON DATABASE crawrling TO crawrling_readonly;
GRANT USAGE ON SCHEMA public TO crawrling_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO crawrling_readonly;

-- 미래의 테이블에도 자동 적용
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO crawrling_readonly;
```

### 2. Django Admin 고급 기능 활용

```python
# 대시보드 추가
from django.db.models import Count, Avg
from django.contrib.admin import AdminSite

class CustomAdminSite(AdminSite):
    site_header = 'ReviewMaps 관리자'
    site_title = 'ReviewMaps'
    index_title = '캠페인 관리 대시보드'

    def index(self, request, extra_context=None):
        extra_context = extra_context or {}

        # 통계 데이터
        extra_context['total_campaigns'] = Campaign.objects.count()
        extra_context['active_campaigns'] = Campaign.objects.filter(
            apply_deadline__gte=timezone.now()
        ).count()
        extra_context['by_platform'] = Campaign.objects.values('platform')\
            .annotate(count=Count('id')).order_by('-count')

        return super().index(request, extra_context)

admin_site = CustomAdminSite(name='customadmin')
```

### 3. 모니터링 및 알림

```python
# campaigns/management/commands/check_expired_campaigns.py
from django.core.management.base import BaseCommand
from campaigns.models import Campaign
from django.utils import timezone

class Command(BaseCommand):
    help = '만료 예정 캠페인 확인'

    def handle(self, *args, **options):
        tomorrow = timezone.now() + timedelta(days=1)
        expiring = Campaign.objects.filter(
            apply_deadline__gte=timezone.now(),
            apply_deadline__lte=tomorrow
        )

        self.stdout.write(
            f'{expiring.count()}개 캠페인이 내일 만료됩니다.'
        )
```

---

## 🔚 결론

### 최종 권장사항: Django Admin (읽기 전용)

**핵심 이유:**
1. ✅ **빠른 구현**: 3-5일
2. ✅ **낮은 리스크**: 데이터 일관성 보장
3. ✅ **충분한 기능**: 조회, 모니터링, 리포팅
4. ✅ **낮은 비용**: 유지보수 최소화

**추가 필요 시:**
- 긴급 수정: 특정 필드만 쓰기 허용
- 배치 작업: Django management 커맨드
- 복잡한 작업: FastAPI API 호출

**구현 순서:**
1. Phase 1: Django 프로젝트 설정 (1일)
2. Phase 2: 읽기 전용 모델 정의 (1-2일)
3. Phase 3: Admin 커스터마이징 (1-2일)
4. Phase 4: 테스트 및 배포 (1일)

**총 소요 기간**: 3-5일

---

**작성일**: 2025년
**작성자**: Claude Code Analysis
**검토 상태**: Django Admin 하이브리드 분석 완료

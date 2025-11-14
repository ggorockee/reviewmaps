"""
URL configuration for config project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from ninja import NinjaAPI
from campaigns.api import router as campaigns_router
from campaigns.category_api import router as categories_router

# Kubernetes 헬스체크 엔드포인트
@csrf_exempt
@require_http_methods(["GET", "HEAD"])
def health_check(request):
    """
    Kubernetes liveness/readiness probe 엔드포인트
    CSRF exempt 처리로 토큰 없이 호출 가능
    """
    return JsonResponse({
        "status": "healthy",
        "service": "reviewmaps-server",
        "version": "1.0.0"
    })

# Django Ninja API 인스턴스 생성
api = NinjaAPI(
    title="ReviewMaps API",
    version="1.0.0",
    description="캠페인 추천 시스템 API"
)

# 라우터 등록
api.add_router("/campaigns", campaigns_router)
api.add_router("/categories", categories_router)

urlpatterns = [
    path('admin/', admin.site.urls),
    path('v1/healthz', health_check, name='health'),  # Django 일반 뷰
    path('v1/', api.urls),  # /v1/campaigns, /v1/categories로 접근
]

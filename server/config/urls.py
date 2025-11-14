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
from ninja import NinjaAPI
from campaigns.api import router as campaigns_router
from campaigns.category_api import router as categories_router
from campaigns.health_api import router as health_router

# Django Ninja API 인스턴스 생성
api = NinjaAPI(
    title="ReviewMaps API",
    version="1.0.0",
    description="캠페인 추천 시스템 API"
)

# 라우터 등록
api.add_router("/campaigns", campaigns_router)
api.add_router("/categories", categories_router)
api.add_router("", health_router)  # /v1/healthz로 접근

urlpatterns = [
    path('admin/', admin.site.urls),
    path('v1/', api.urls),  # /v1/campaigns, /v1/categories, /v1/healthz로 접근
]

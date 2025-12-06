from django.contrib import admin
from django.urls import path
from django.http import JsonResponse


def health_check(request):
    """Health check endpoint for k8s probes"""
    return JsonResponse({"status": "healthy"})


def liveness_check(request):
    """Liveness probe endpoint for k8s"""
    return JsonResponse({"status": "alive"})


def readiness_check(request):
    """Readiness probe endpoint for k8s"""
    from django.db import connection

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        return JsonResponse({"status": "ready", "database": "connected"})
    except Exception as e:
        return JsonResponse({"status": "not ready", "error": str(e)}, status=503)


urlpatterns = [
    # Health check endpoints (before admin)
    path("health/", health_check, name="health"),
    path("liveness/", liveness_check, name="liveness"),
    path("readiness/", readiness_check, name="readiness"),
    # Admin at root path
    path("", admin.site.urls),
]

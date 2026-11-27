"""Custom middleware for ReviewMaps Admin."""

from django.http import JsonResponse


class HealthCheckMiddleware:
    """
    Middleware to handle health check endpoints before ALLOWED_HOSTS validation.

    K8s probes send requests using Pod IP which may not be in ALLOWED_HOSTS.
    This middleware intercepts health check requests early and responds directly,
    bypassing all Django middleware including SecurityMiddleware.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        # Handle health checks before any other middleware (including ALLOWED_HOSTS check)
        if request.path == "/health/":
            return JsonResponse({"status": "healthy"})

        if request.path == "/liveness/":
            return JsonResponse({"status": "alive"})

        if request.path == "/readiness/":
            return self._readiness_check()

        return self.get_response(request)

    def _readiness_check(self):
        """Check database connectivity for readiness probe."""
        from django.db import connection

        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
            return JsonResponse({"status": "ready", "database": "connected"})
        except Exception as e:
            return JsonResponse({"status": "not ready", "error": str(e)}, status=503)

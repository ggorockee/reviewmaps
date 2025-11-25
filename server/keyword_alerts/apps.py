from django.apps import AppConfig


class KeywordAlertsConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'keyword_alerts'

    def ready(self):
        """앱 준비 시 시그널 등록"""
        import keyword_alerts.signals  # noqa: F401

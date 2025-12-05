from django.apps import AppConfig

class AppConfigConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'app_config'
    verbose_name = '앱 설정'

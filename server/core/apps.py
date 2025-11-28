import os
import sys

from django.apps import AppConfig


class CoreConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'core'

    def ready(self):
        """Django 앱 초기화 시 스케줄러 시작"""
        # 메인 프로세스에서만 스케줄러 실행 (reload 시 중복 방지)
        # runserver의 경우 RUN_MAIN 환경변수로 구분
        # gunicorn의 경우 --preload 옵션 사용 시 마스터에서 한 번만 실행
        is_runserver = 'runserver' in sys.argv
        is_main_process = os.environ.get('RUN_MAIN') == 'true'

        # runserver: reloader 자식 프로세스에서만 실행
        # gunicorn: 워커 프로세스에서 실행
        if is_runserver and not is_main_process:
            return

        # 테스트나 마이그레이션 시에는 스케줄러 시작하지 않음
        if any(cmd in sys.argv for cmd in ['test', 'migrate', 'makemigrations', 'collectstatic', 'shell']):
            return

        # 스케줄러 시작
        from core.scheduler import start_scheduler
        start_scheduler()

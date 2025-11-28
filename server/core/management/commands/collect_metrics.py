"""
Prometheus Gauge 메트릭 수집 Management Command

Campaign 통계, 테이블 크기, 서비스 상태 등 Gauge 타입 메트릭을 수집합니다.
주기적 실행이 필요하며, 크론잡 또는 Celery Beat으로 스케줄링하세요.

사용법:
    python manage.py collect_metrics
    python manage.py collect_metrics --once  # 한 번만 실행
    python manage.py collect_metrics --interval 60  # 60초 간격 반복
"""

import time
import logging
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone
from django.db import connection

from campaigns.models import Campaign, Category
from users.models import User
from keyword_alerts.models import FCMDevice, Keyword, KeywordAlert

from core.metrics import (
    APP_NAME,
    campaign_active_total,
    table_rows_total,
    table_size_bytes,
    active_users_total,
    fcm_devices_active_total,
    update_service_status,
)

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = 'Prometheus Gauge 메트릭 수집 (Campaign 통계, 테이블 크기 등)'

    def add_arguments(self, parser):
        parser.add_argument(
            '--once',
            action='store_true',
            help='한 번만 실행하고 종료',
        )
        parser.add_argument(
            '--interval',
            type=int,
            default=300,
            help='반복 실행 간격 (초, 기본값: 300)',
        )

    def handle(self, *args, **options):
        once = options['once']
        interval = options['interval']

        self.stdout.write(self.style.SUCCESS('메트릭 수집 시작...'))

        while True:
            try:
                self._collect_all_metrics()
                self.stdout.write(
                    self.style.SUCCESS(f'메트릭 수집 완료: {timezone.now()}')
                )
            except Exception as e:
                logger.error(f'메트릭 수집 실패: {e}', exc_info=True)
                self.stdout.write(
                    self.style.ERROR(f'메트릭 수집 실패: {e}')
                )

            if once:
                break

            self.stdout.write(f'{interval}초 후 다음 수집...')
            time.sleep(interval)

    def _collect_all_metrics(self):
        """모든 Gauge 메트릭 수집"""
        self._collect_campaign_metrics()
        self._collect_table_metrics()
        self._collect_user_metrics()
        self._collect_fcm_metrics()
        self._check_service_health()

    def _collect_campaign_metrics(self):
        """Campaign 통계 메트릭 수집"""
        now = timezone.now()

        # 활성 캠페인 (마감일이 없거나 미래인 캠페인)
        active_campaigns = Campaign.objects.filter(
            apply_deadline__isnull=True
        ) | Campaign.objects.filter(
            apply_deadline__gte=now
        )

        # 지역별 활성 캠페인 수
        regions = active_campaigns.values_list('region', flat=True).distinct()

        for region in regions:
            if region:  # None이 아닌 경우만
                count = active_campaigns.filter(region=region).count()
                campaign_active_total.labels(region=region, app=APP_NAME).set(count)

        # 지역 없는 캠페인
        null_region_count = active_campaigns.filter(region__isnull=True).count()
        if null_region_count > 0:
            campaign_active_total.labels(region='unknown', app=APP_NAME).set(null_region_count)

        # 전체 활성 캠페인 수
        total_active = active_campaigns.count()
        campaign_active_total.labels(region='all', app=APP_NAME).set(total_active)

        logger.info(f'Campaign 메트릭 수집: 전체 활성 {total_active}개')

    def _collect_table_metrics(self):
        """테이블 통계 메트릭 수집"""
        tables = {
            'campaign': Campaign,
            'categories': Category,
            'users': User,
            'fcm_devices': FCMDevice,
            'keywords': Keyword,
            'keyword_alerts': KeywordAlert,
        }

        for table_name, model in tables.items():
            try:
                count = model.objects.count()
                table_rows_total.labels(table_name=table_name, app=APP_NAME).set(count)
            except Exception as e:
                logger.warning(f'테이블 {table_name} 행 수 조회 실패: {e}')

        # PostgreSQL 테이블 크기 조회 (PostgreSQL에서만 동작)
        self._collect_table_sizes()

    def _collect_table_sizes(self):
        """PostgreSQL 테이블 크기 수집"""
        if connection.vendor != 'postgresql':
            return

        table_names = [
            'campaign',
            'categories',
            'users_user',
            'keyword_alerts_fcm_devices',
            'keyword_alerts_keywords',
            'keyword_alerts_alerts',
        ]

        try:
            with connection.cursor() as cursor:
                for table_name in table_names:
                    try:
                        cursor.execute(
                            "SELECT pg_total_relation_size(%s)",
                            [table_name]
                        )
                        result = cursor.fetchone()
                        if result:
                            size_bytes = result[0]
                            # 메트릭 라벨용 이름 정규화
                            metric_name = table_name.replace('_', '_').split('_')[-1]
                            if table_name == 'users_user':
                                metric_name = 'users'
                            elif table_name.startswith('keyword_alerts_'):
                                metric_name = table_name.replace('keyword_alerts_', '')
                            table_size_bytes.labels(table_name=metric_name, app=APP_NAME).set(size_bytes)
                    except Exception as e:
                        logger.debug(f'테이블 {table_name} 크기 조회 실패: {e}')
        except Exception as e:
            logger.warning(f'테이블 크기 수집 실패: {e}')

    def _collect_user_metrics(self):
        """사용자 통계 메트릭 수집"""
        # 최근 24시간 활성 사용자
        yesterday = timezone.now() - timedelta(hours=24)
        active_count = User.objects.filter(last_login__gte=yesterday).count()
        active_users_total.labels(app=APP_NAME).set(active_count)

        logger.info(f'User 메트릭 수집: 활성 사용자 {active_count}명')

    def _collect_fcm_metrics(self):
        """FCM 디바이스 통계 메트릭 수집"""
        # 활성 Android 디바이스
        android_count = FCMDevice.objects.filter(
            device_type='android',
            is_active=True
        ).count()
        fcm_devices_active_total.labels(device_type='android', app=APP_NAME).set(android_count)

        # 활성 iOS 디바이스
        ios_count = FCMDevice.objects.filter(
            device_type='ios',
            is_active=True
        ).count()
        fcm_devices_active_total.labels(device_type='ios', app=APP_NAME).set(ios_count)

        logger.info(f'FCM 메트릭 수집: Android {android_count}, iOS {ios_count}')

    def _check_service_health(self):
        """서비스 상태 체크"""
        # Django 서비스는 이 명령이 실행되면 UP
        update_service_status('django', True)

        # 데이터베이스 연결 체크
        try:
            with connection.cursor() as cursor:
                cursor.execute('SELECT 1')
            update_service_status('database', True)
        except Exception as e:
            logger.error(f'데이터베이스 연결 실패: {e}')
            update_service_status('database', False)

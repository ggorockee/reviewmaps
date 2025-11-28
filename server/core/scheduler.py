"""
Prometheus Gauge 메트릭 수집 스케줄러

APScheduler를 사용하여 Django 서버 프로세스 내에서 주기적으로 메트릭을 수집합니다.
CronJob과 달리 동일 프로세스에서 실행되므로 Prometheus multiprocess 모드에서도
메트릭이 정상적으로 노출됩니다.

기본 설정:
- 수집 주기: 5분 (300초)
- 첫 실행: 서버 시작 30초 후 (DB 연결 안정화 대기)
"""

import logging
import os
from datetime import timedelta
from functools import wraps

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger

logger = logging.getLogger(__name__)

# 스케줄러 싱글톤
_scheduler = None

# 환경 변수로 설정 가능
METRICS_COLLECTION_INTERVAL = int(os.environ.get('METRICS_COLLECTION_INTERVAL', 300))
METRICS_COLLECTION_ENABLED = os.environ.get('METRICS_COLLECTION_ENABLED', 'true').lower() == 'true'


def with_django_db_connection(func):
    """Django DB 연결을 보장하는 데코레이터"""
    @wraps(func)
    def wrapper(*args, **kwargs):
        from django.db import connection
        # 오래된 연결 정리
        connection.close_if_unusable_or_obsolete()
        try:
            return func(*args, **kwargs)
        finally:
            # 작업 후 연결 닫기 (connection pooling을 위해)
            connection.close()
    return wrapper


@with_django_db_connection
def collect_all_metrics():
    """모든 Gauge 메트릭 수집 (스케줄러에서 호출)"""
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

    try:
        logger.info('스케줄러: 메트릭 수집 시작')

        # 1. Campaign 메트릭
        now = timezone.now()
        active_campaigns = Campaign.objects.filter(
            apply_deadline__isnull=True
        ) | Campaign.objects.filter(
            apply_deadline__gte=now
        )

        regions = active_campaigns.values_list('region', flat=True).distinct()
        for region in regions:
            if region:
                count = active_campaigns.filter(region=region).count()
                campaign_active_total.labels(region=region, app=APP_NAME).set(count)

        null_region_count = active_campaigns.filter(region__isnull=True).count()
        if null_region_count > 0:
            campaign_active_total.labels(region='unknown', app=APP_NAME).set(null_region_count)

        total_active = active_campaigns.count()
        campaign_active_total.labels(region='all', app=APP_NAME).set(total_active)
        logger.info(f'Campaign 메트릭: 전체 활성 {total_active}개')

        # 2. 테이블 행 수 메트릭
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

        # 3. PostgreSQL 테이블 크기
        if connection.vendor == 'postgresql':
            pg_table_names = [
                ('campaign', 'campaign'),
                ('categories', 'categories'),
                ('users_user', 'users'),
                ('keyword_alerts_fcmdevice', 'fcm_devices'),
                ('keyword_alerts_keyword', 'keywords'),
                ('keyword_alerts_keywordalert', 'keyword_alerts'),
            ]

            with connection.cursor() as cursor:
                for pg_name, metric_name in pg_table_names:
                    try:
                        cursor.execute(
                            "SELECT pg_total_relation_size(%s)",
                            [pg_name]
                        )
                        result = cursor.fetchone()
                        if result and result[0]:
                            table_size_bytes.labels(table_name=metric_name, app=APP_NAME).set(result[0])
                    except Exception as e:
                        logger.debug(f'테이블 {pg_name} 크기 조회 실패: {e}')

        # 4. 활성 사용자 메트릭
        yesterday = timezone.now() - timedelta(hours=24)
        active_count = User.objects.filter(last_login__gte=yesterday).count()
        active_users_total.labels(app=APP_NAME).set(active_count)
        logger.info(f'User 메트릭: 활성 사용자 {active_count}명')

        # 5. FCM 디바이스 메트릭
        android_count = FCMDevice.objects.filter(
            device_type='android',
            is_active=True
        ).count()
        fcm_devices_active_total.labels(device_type='android', app=APP_NAME).set(android_count)

        ios_count = FCMDevice.objects.filter(
            device_type='ios',
            is_active=True
        ).count()
        fcm_devices_active_total.labels(device_type='ios', app=APP_NAME).set(ios_count)
        logger.info(f'FCM 메트릭: Android {android_count}, iOS {ios_count}')

        # 6. 서비스 상태
        update_service_status('django', True)

        try:
            with connection.cursor() as cursor:
                cursor.execute('SELECT 1')
            update_service_status('database', True)
        except Exception as e:
            logger.error(f'데이터베이스 연결 실패: {e}')
            update_service_status('database', False)

        logger.info(f'스케줄러: 메트릭 수집 완료 - {timezone.now()}')

    except Exception as e:
        logger.error(f'스케줄러: 메트릭 수집 실패 - {e}', exc_info=True)


def start_scheduler():
    """메트릭 수집 스케줄러 시작"""
    global _scheduler

    if not METRICS_COLLECTION_ENABLED:
        logger.info('메트릭 수집이 비활성화되어 있습니다 (METRICS_COLLECTION_ENABLED=false)')
        return

    if _scheduler is not None:
        logger.warning('스케줄러가 이미 실행 중입니다')
        return

    _scheduler = BackgroundScheduler(
        timezone='Asia/Seoul',
        job_defaults={
            'coalesce': True,  # 누락된 실행 합치기
            'max_instances': 1,  # 동시 실행 방지
            'misfire_grace_time': 60,  # 1분 이내 지연 허용
        }
    )

    # 메트릭 수집 작업 등록
    _scheduler.add_job(
        collect_all_metrics,
        trigger=IntervalTrigger(seconds=METRICS_COLLECTION_INTERVAL),
        id='collect_metrics',
        name='Prometheus Gauge 메트릭 수집',
        replace_existing=True,
    )

    _scheduler.start()
    logger.info(f'메트릭 수집 스케줄러 시작 (주기: {METRICS_COLLECTION_INTERVAL}초)')

    # 서버 시작 후 첫 수집 실행 (30초 후)
    from apscheduler.triggers.date import DateTrigger
    from datetime import datetime, timedelta
    first_run = datetime.now() + timedelta(seconds=30)
    _scheduler.add_job(
        collect_all_metrics,
        trigger=DateTrigger(run_date=first_run),
        id='collect_metrics_initial',
        name='초기 메트릭 수집',
    )
    logger.info('초기 메트릭 수집이 30초 후 실행됩니다')


def stop_scheduler():
    """스케줄러 중지"""
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
        logger.info('메트릭 수집 스케줄러 중지')

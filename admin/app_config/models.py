"""
App Config 모델 - GORM이 관리하는 테이블 (managed=False)
Django Admin CRUD 전용
"""
from django.db import models


class AdConfig(models.Model):
    """광고 설정 - GORM 테이블 참조"""

    PLATFORM_CHOICES = [
        ('android', 'Android'),
        ('ios', 'iOS'),
    ]

    platform = models.CharField(max_length=20, choices=PLATFORM_CHOICES, verbose_name="플랫폼")
    ad_type = models.CharField(max_length=50, verbose_name="광고 유형")
    unit_id = models.CharField(max_length=255, verbose_name="광고 유닛 ID")
    is_active = models.BooleanField(default=True, verbose_name="활성화 여부")
    show_frequency = models.IntegerField(default=1, verbose_name="표시 빈도")
    show_after_count = models.IntegerField(default=0, verbose_name="표시 시작 카운트")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = 'ad_configs'
        managed = False
        verbose_name = "광고 설정"
        verbose_name_plural = "광고 설정"

    def __str__(self):
        return f"{self.platform} - {self.ad_type}"


class AppVersion(models.Model):
    """앱 버전 관리 - GORM 테이블 참조"""

    PLATFORM_CHOICES = [
        ('android', 'Android'),
        ('ios', 'iOS'),
    ]

    platform = models.CharField(max_length=20, choices=PLATFORM_CHOICES, verbose_name="플랫폼")
    min_version = models.CharField(max_length=20, verbose_name="최소 지원 버전")
    latest_version = models.CharField(max_length=20, verbose_name="최신 버전")
    force_update = models.BooleanField(default=False, verbose_name="강제 업데이트")
    update_message = models.TextField(null=True, blank=True, verbose_name="업데이트 메시지")
    store_url = models.CharField(max_length=500, null=True, blank=True, verbose_name="스토어 URL")
    maintenance_mode = models.BooleanField(default=False, verbose_name="점검 모드")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = 'app_versions'
        managed = False
        verbose_name = "앱 버전"
        verbose_name_plural = "앱 버전"

    def __str__(self):
        return f"{self.platform} - {self.latest_version}"


class AppSetting(models.Model):
    """앱 설정 (Key-Value) - GORM 테이블 참조"""

    key = models.CharField(max_length=100, unique=True, verbose_name="설정 키")
    value = models.TextField(verbose_name="설정 값")
    value_type = models.CharField(max_length=20, default='string', verbose_name="값 타입")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = 'app_settings'
        managed = False
        verbose_name = "앱 설정"
        verbose_name_plural = "앱 설정"
        ordering = ['key']

    def __str__(self):
        return self.key


class RateLimitConfig(models.Model):
    """Rate Limit 설정 - GORM 테이블 참조"""

    endpoint = models.CharField(max_length=255, unique=True, verbose_name="엔드포인트")
    max_requests = models.IntegerField(default=100, verbose_name="최대 요청 수")
    window_sec = models.IntegerField(default=60, verbose_name="시간 윈도우 (초)")
    is_active = models.BooleanField(default=True, verbose_name="활성화 여부")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = 'rate_limit_configs'
        managed = False
        verbose_name = "Rate Limit 설정"
        verbose_name_plural = "Rate Limit 설정"

    def __str__(self):
        return f"{self.endpoint} - {self.max_requests}/{self.window_sec}s"

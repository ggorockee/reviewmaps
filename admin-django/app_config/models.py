"""
App Config 모델 - 실제 DB 스키마 기반 (managed=False)
Django Admin CRUD 전용
"""

from django.db import models


class AdConfig(models.Model):
    """광고 설정 - 실제 DB 스키마 기반"""

    PLATFORM_CHOICES = [
        ("android", "Android"),
        ("ios", "iOS"),
    ]

    platform = models.CharField(max_length=20, choices=PLATFORM_CHOICES, verbose_name="플랫폼")
    ad_network = models.CharField(max_length=50, verbose_name="광고 네트워크")
    ad_unit_ids = models.JSONField(default=dict, verbose_name="광고 유닛 ID")
    is_enabled = models.BooleanField(default=True, verbose_name="활성화 여부")
    priority = models.IntegerField(default=0, verbose_name="우선순위")
    created_at = models.DateTimeField(verbose_name="생성일시")
    updated_at = models.DateTimeField(verbose_name="수정일시")

    class Meta:
        db_table = "ad_configs"
        managed = False
        verbose_name = "광고 설정"
        verbose_name_plural = "광고 설정"

    def __str__(self):
        return f"{self.platform} - {self.ad_network}"


class AppVersion(models.Model):
    """앱 버전 관리 - 실제 DB 스키마 기반"""

    PLATFORM_CHOICES = [
        ("android", "Android"),
        ("ios", "iOS"),
    ]

    platform = models.CharField(max_length=20, choices=PLATFORM_CHOICES, verbose_name="플랫폼")
    version = models.CharField(max_length=20, verbose_name="현재 버전")
    build_number = models.IntegerField(default=0, verbose_name="빌드 번호")
    minimum_version = models.CharField(max_length=20, verbose_name="최소 지원 버전")
    force_update = models.BooleanField(default=False, verbose_name="강제 업데이트")
    update_message = models.TextField(null=True, blank=True, verbose_name="업데이트 메시지")
    store_url = models.CharField(max_length=500, default="", verbose_name="스토어 URL")
    is_active = models.BooleanField(default=True, verbose_name="활성화 여부")
    created_at = models.DateTimeField(verbose_name="생성일시")
    updated_at = models.DateTimeField(verbose_name="수정일시")

    class Meta:
        db_table = "app_versions"
        managed = False
        verbose_name = "앱 버전"
        verbose_name_plural = "앱 버전"

    def __str__(self):
        return f"{self.platform} - {self.version}"


class AppSetting(models.Model):
    """앱 설정 (Key-Value) - 실제 DB 스키마 기반"""

    key = models.CharField(max_length=100, unique=True, verbose_name="설정 키")
    value = models.JSONField(default=dict, verbose_name="설정 값")
    description = models.TextField(null=True, blank=True, verbose_name="설명")
    is_active = models.BooleanField(default=True, verbose_name="활성화 여부")
    created_at = models.DateTimeField(verbose_name="생성일시")
    updated_at = models.DateTimeField(verbose_name="수정일시")

    class Meta:
        db_table = "app_settings"
        managed = False
        verbose_name = "앱 설정"
        verbose_name_plural = "앱 설정"
        ordering = ["key"]

    def __str__(self):
        return self.key


class RateLimitConfig(models.Model):
    """Rate Limit 설정 - 실제 DB 스키마 기반"""

    endpoint = models.CharField(max_length=200, unique=True, verbose_name="엔드포인트")
    max_requests = models.IntegerField(default=100, verbose_name="최대 요청 수")
    window_seconds = models.IntegerField(default=60, verbose_name="시간 윈도우 (초)")
    apply_to_authenticated = models.BooleanField(default=True, verbose_name="인증 사용자 적용")
    apply_to_anonymous = models.BooleanField(default=True, verbose_name="비인증 사용자 적용")
    block_duration_seconds = models.IntegerField(default=0, verbose_name="차단 시간 (초)")
    is_enabled = models.BooleanField(default=True, verbose_name="활성화 여부")
    priority = models.IntegerField(default=0, verbose_name="우선순위")
    description = models.TextField(null=True, blank=True, verbose_name="설명")
    created_at = models.DateTimeField(verbose_name="생성일시")
    updated_at = models.DateTimeField(verbose_name="수정일시")

    class Meta:
        db_table = "rate_limit_configs"
        managed = False
        verbose_name = "Rate Limit 설정"
        verbose_name_plural = "Rate Limit 설정"

    def __str__(self):
        return f"{self.endpoint} - {self.max_requests}/{self.window_seconds}s"

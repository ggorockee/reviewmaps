"""
Keyword Alerts 모델 - GORM이 관리하는 테이블 (managed=False)
Django Admin CRUD 전용
"""

from django.db import models
from django.conf import settings


class FCMDevice(models.Model):
    """FCM 푸시 토큰 - GORM 테이블 참조"""

    DEVICE_TYPE_CHOICES = [
        ("android", "Android"),
        ("ios", "iOS"),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name="fcm_devices",
        verbose_name="사용자",
    )
    anonymous_session_id = models.CharField(max_length=255, null=True, blank=True, verbose_name="익명 세션 ID")
    fcm_token = models.CharField(max_length=500, unique=True, db_column="fcm_token", verbose_name="FCM 토큰")
    device_type = models.CharField(
        max_length=20,
        choices=DEVICE_TYPE_CHOICES,
        default="android",
        db_column="device_type",
        verbose_name="디바이스 타입",
    )
    is_active = models.BooleanField(default=True, verbose_name="활성 상태")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = "keyword_alerts_fcm_devices"
        managed = False
        verbose_name = "FCM 디바이스"
        verbose_name_plural = "FCM 디바이스"

    def __str__(self):
        owner = self.user.email if self.user else "익명"
        return f"{self.device_type} - {owner}"


class Keyword(models.Model):
    """관심 키워드 - GORM 테이블 참조"""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name="keywords",
        verbose_name="사용자",
    )
    anonymous_session_id = models.CharField(max_length=255, null=True, blank=True, verbose_name="익명 세션 ID")
    keyword = models.CharField(max_length=100, verbose_name="키워드")
    is_active = models.BooleanField(default=True, verbose_name="활성 상태")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = "keyword_alerts_keywords"
        managed = False
        verbose_name = "관심 키워드"
        verbose_name_plural = "관심 키워드"

    def __str__(self):
        owner = self.user.email if self.user else "익명"
        return f"{self.keyword} - {owner}"


class KeywordAlert(models.Model):
    """키워드 알람 기록 - GORM 테이블 참조"""

    keyword = models.ForeignKey(Keyword, on_delete=models.CASCADE, related_name="alerts", verbose_name="키워드")
    campaign = models.ForeignKey(
        "campaigns.Campaign",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="keyword_alerts",
        verbose_name="캠페인",
    )
    matched_field = models.CharField(max_length=50, default="title", verbose_name="매칭 필드")
    is_read = models.BooleanField(default=False, verbose_name="읽음 여부")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = "keyword_alerts_alerts"
        managed = False
        verbose_name = "키워드 알람"
        verbose_name_plural = "키워드 알람"
        ordering = ["-created_at"]

    def __str__(self):
        try:
            campaign_title = self.campaign.title[:30] if self.campaign_id and self.campaign.title else "(삭제된 캠페인)"
        except Exception:
            campaign_title = "(삭제된 캠페인)"
        return f"{self.keyword.keyword} → {campaign_title}"

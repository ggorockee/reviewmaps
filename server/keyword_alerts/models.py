from django.db import models
from django.conf import settings
from core.models import CoreModel


class FCMDevice(CoreModel):
    """
    FCM 푸시 토큰 저장
    - 사용자 또는 익명 세션에 연결
    - 디바이스별로 고유 토큰 저장
    """
    DEVICE_TYPE_CHOICES = [
        ('android', 'Android'),
        ('ios', 'iOS'),
    ]

    fcm_token = models.CharField(
        max_length=500,
        unique=True,
        verbose_name="FCM 토큰",
        help_text="Firebase Cloud Messaging 디바이스 토큰"
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='fcm_devices',
        null=True,
        blank=True,
        verbose_name="사용자",
        help_text="토큰을 등록한 사용자"
    )
    anonymous_session_id = models.CharField(
        max_length=255,
        null=True,
        blank=True,
        verbose_name="익명 세션 ID",
        help_text="익명 사용자의 세션 ID"
    )
    device_type = models.CharField(
        max_length=20,
        choices=DEVICE_TYPE_CHOICES,
        default='android',
        verbose_name="디바이스 타입"
    )
    is_active = models.BooleanField(
        default=True,
        verbose_name="활성 상태",
        help_text="푸시 수신 활성화 여부"
    )

    class Meta:
        db_table = 'keyword_alerts_fcm_devices'
        verbose_name = "FCM 디바이스"
        verbose_name_plural = "FCM 디바이스"
        indexes = [
            models.Index(fields=['user', 'is_active']),
            models.Index(fields=['anonymous_session_id', 'is_active']),
            models.Index(fields=['fcm_token']),
        ]
        constraints = [
            models.CheckConstraint(
                check=models.Q(user__isnull=False) | models.Q(anonymous_session_id__isnull=False),
                name='fcm_device_has_owner'
            )
        ]

    def __str__(self):
        if self.user:
            owner = self.user.email
        elif self.anonymous_session_id:
            owner = f"익명({self.anonymous_session_id[:8]})"
        else:
            owner = "알 수 없음"
        return f"{self.device_type} - {owner}"


class Keyword(CoreModel):
    """
    사용자 관심 키워드
    - 사용자 또는 익명 세션에 연결
    - 익명 → 회원 전환 시 user_id로 마이그레이션
    """
    keyword = models.CharField(
        max_length=100,
        verbose_name="키워드",
        help_text="알람을 받을 키워드"
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='keywords',
        null=True,
        blank=True,
        verbose_name="사용자",
        help_text="키워드를 등록한 사용자"
    )
    anonymous_session_id = models.CharField(
        max_length=255,
        null=True,
        blank=True,
        verbose_name="익명 세션 ID",
        help_text="익명 사용자의 세션 ID"
    )
    is_active = models.BooleanField(
        default=True,
        verbose_name="활성 상태",
        help_text="알람 활성화 여부"
    )

    class Meta:
        db_table = 'keyword_alerts_keywords'
        verbose_name = "관심 키워드"
        verbose_name_plural = "관심 키워드"
        indexes = [
            models.Index(fields=['user', 'is_active']),
            models.Index(fields=['anonymous_session_id', 'is_active']),
            models.Index(fields=['keyword']),
        ]
        constraints = [
            # user 또는 anonymous_session_id 둘 중 하나는 반드시 있어야 함
            models.CheckConstraint(
                check=models.Q(user__isnull=False) | models.Q(anonymous_session_id__isnull=False),
                name='keyword_has_owner'
            )
        ]

    def __str__(self):
        if self.user:
            owner = self.user.email
        elif self.anonymous_session_id:
            owner = f"익명({self.anonymous_session_id[:8]})"
        else:
            owner = "알 수 없음"
        return f"{self.keyword} - {owner}"


class KeywordAlert(CoreModel):
    """
    키워드 매칭 알람 로그
    - 캠페인에서 키워드가 발견되면 생성
    """
    keyword = models.ForeignKey(
        Keyword,
        on_delete=models.CASCADE,
        related_name='alerts',
        verbose_name="키워드"
    )
    campaign = models.ForeignKey(
        'campaigns.Campaign',  # lazy reference
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='keyword_alerts',
        verbose_name="캠페인",
        help_text="캠페인이 삭제되어도 알림 히스토리는 보존됨"
    )
    matched_field = models.CharField(
        max_length=50,
        verbose_name="매칭 필드",
        help_text="키워드가 매칭된 필드 (title, description 등)"
    )
    is_read = models.BooleanField(
        default=False,
        verbose_name="읽음 여부",
        help_text="사용자가 알람을 확인했는지 여부"
    )

    class Meta:
        db_table = 'keyword_alerts_alerts'
        verbose_name = "키워드 알람"
        verbose_name_plural = "키워드 알람"
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['keyword', 'is_read']),
            models.Index(fields=['campaign']),
            models.Index(fields=['-created_at']),
        ]

    def __str__(self):
        campaign_title = self.campaign.title[:30] if self.campaign else "(삭제된 캠페인)"
        return f"{self.keyword.keyword} → {campaign_title}"

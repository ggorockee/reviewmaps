"""
app_config 모델
모바일 앱 설정을 중앙화 관리하는 모델
"""
from django.db import models
from django.core.validators import MinValueValidator


class AdConfig(models.Model):
    """
    광고 설정 모델
    플랫폼별 광고 네트워크 설정을 관리
    """
    PLATFORM_CHOICES = [
        ('android', 'Android'),
        ('ios', 'iOS'),
    ]

    platform = models.CharField(
        max_length=20,
        choices=PLATFORM_CHOICES,
        verbose_name="플랫폼"
    )
    ad_network = models.CharField(
        max_length=50,
        verbose_name="광고 네트워크",
        help_text="예: admob, applovin, unity, etc."
    )
    is_enabled = models.BooleanField(
        default=True,
        verbose_name="활성화 여부"
    )
    ad_unit_ids = models.JSONField(
        default=dict,
        verbose_name="광고 유닛 ID",
        help_text="banner_id, interstitial_id, native_id, rewarded_id 등"
    )
    priority = models.IntegerField(
        default=0,
        verbose_name="우선순위",
        help_text="숫자가 높을수록 우선순위 높음"
    )
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = 'ad_configs'
        verbose_name = "광고 설정"
        verbose_name_plural = "광고 설정"
        ordering = ['-priority', '-created_at']
        indexes = [
            models.Index(fields=['platform', 'is_enabled'], name='idx_adcfg_platform_enabled'),
            models.Index(fields=['-priority'], name='idx_adcfg_priority'),
        ]

    def __str__(self):
        return f"{self.platform} - {self.ad_network} (priority: {self.priority})"


class AppVersion(models.Model):
    """
    앱 버전 관리 모델
    플랫폼별 최신 버전 정보 및 강제 업데이트 설정
    """
    PLATFORM_CHOICES = [
        ('android', 'Android'),
        ('ios', 'iOS'),
    ]

    platform = models.CharField(
        max_length=20,
        choices=PLATFORM_CHOICES,
        verbose_name="플랫폼"
    )
    version = models.CharField(
        max_length=20,
        verbose_name="버전",
        help_text="예: 1.3.5"
    )
    build_number = models.IntegerField(
        verbose_name="빌드 번호",
        help_text="예: 50"
    )
    minimum_version = models.CharField(
        max_length=20,
        verbose_name="최소 지원 버전",
        help_text="이 버전보다 낮으면 강제 업데이트 필요"
    )
    force_update = models.BooleanField(
        default=False,
        verbose_name="강제 업데이트 여부"
    )
    update_message = models.TextField(
        null=True,
        blank=True,
        verbose_name="업데이트 메시지"
    )
    store_url = models.URLField(
        max_length=500,
        verbose_name="스토어 URL",
        help_text="Play Store 또는 App Store URL"
    )
    is_active = models.BooleanField(
        default=True,
        verbose_name="활성화 여부",
        help_text="가장 최신 활성 버전이 사용됨"
    )
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = 'app_versions'
        verbose_name = "앱 버전"
        verbose_name_plural = "앱 버전"
        ordering = ['-is_active', '-created_at']
        indexes = [
            models.Index(fields=['platform', 'is_active'], name='idx_appver_platform_active'),
            models.Index(fields=['-created_at'], name='idx_appver_created'),
        ]

    def __str__(self):
        return f"{self.platform} - {self.version} (build {self.build_number})"


class AppSetting(models.Model):
    """
    일반 앱 설정 모델
    Key-Value 형식으로 유연한 설정 관리
    """
    key = models.CharField(
        max_length=100,
        unique=True,
        verbose_name="설정 키"
    )
    value = models.JSONField(
        verbose_name="설정 값",
        help_text="JSON 형식으로 저장"
    )
    description = models.TextField(
        null=True,
        blank=True,
        verbose_name="설명"
    )
    is_active = models.BooleanField(
        default=True,
        verbose_name="활성화 여부"
    )
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = 'app_settings'
        verbose_name = "앱 설정"
        verbose_name_plural = "앱 설정"
        ordering = ['key']
        indexes = [
            models.Index(fields=['key'], name='idx_appsetting_key'),
            models.Index(fields=['is_active'], name='idx_appsetting_active'),
        ]

    def __str__(self):
        return self.key


class RateLimitConfig(models.Model):
    """
    API Rate Limiting 설정 모델
    엔드포인트별 요청 제한을 Django Admin에서 관리
    """
    endpoint = models.CharField(
        max_length=200,
        unique=True,
        verbose_name="엔드포인트",
        help_text="예: /api/v1/campaigns/*, /api/v1/auth/*, 또는 * (전체)"
    )
    max_requests = models.IntegerField(
        validators=[MinValueValidator(1)],
        verbose_name="최대 요청 수",
        help_text="시간 윈도우 내 최대 허용 요청 수"
    )
    window_seconds = models.IntegerField(
        validators=[MinValueValidator(1)],
        verbose_name="시간 윈도우 (초)",
        help_text="Rate limit을 체크할 시간 범위 (예: 60초)"
    )
    apply_to_authenticated = models.BooleanField(
        default=True,
        verbose_name="인증된 사용자에게 적용",
        help_text="로그인한 사용자에게도 Rate Limit 적용"
    )
    apply_to_anonymous = models.BooleanField(
        default=True,
        verbose_name="익명 사용자에게 적용",
        help_text="비로그인 사용자에게 Rate Limit 적용"
    )
    block_duration_seconds = models.IntegerField(
        default=300,
        validators=[MinValueValidator(0)],
        verbose_name="차단 시간 (초)",
        help_text="Rate Limit 초과 시 차단할 시간 (0=차단 없음)"
    )
    is_enabled = models.BooleanField(
        default=True,
        verbose_name="활성화 여부"
    )
    priority = models.IntegerField(
        default=0,
        verbose_name="우선순위",
        help_text="숫자가 높을수록 먼저 적용됨 (특정 엔드포인트를 * 보다 먼저 체크)"
    )
    description = models.TextField(
        null=True,
        blank=True,
        verbose_name="설명"
    )
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = 'rate_limit_configs'
        verbose_name = "Rate Limit 설정"
        verbose_name_plural = "Rate Limit 설정"
        ordering = ['-priority', 'endpoint']
        indexes = [
            models.Index(fields=['endpoint', 'is_enabled'], name='idx_ratelimit_endpoint'),
            models.Index(fields=['-priority'], name='idx_ratelimit_priority'),
        ]

    def __str__(self):
        return f"{self.endpoint} - {self.max_requests}/{self.window_seconds}s"

    def matches_path(self, path: str) -> bool:
        """
        요청 경로가 이 설정과 매칭되는지 확인
        """
        if self.endpoint == '*':
            return True
        
        # 와일드카드 처리
        if self.endpoint.endswith('*'):
            prefix = self.endpoint[:-1]
            return path.startswith(prefix)
        
        # 정확히 일치
        return path == self.endpoint

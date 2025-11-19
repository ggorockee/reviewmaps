from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin, BaseUserManager
from django.db import models
from django.utils import timezone


class UserManager(BaseUserManager):
    """Custom User Manager - email 기반 인증"""

    def create_user(self, email, password=None, **extra_fields):
        """일반 사용자 생성"""
        if not email:
            raise ValueError('이메일은 필수입니다.')

        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        """슈퍼유저 생성"""
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)

        if extra_fields.get('is_staff') is not True:
            raise ValueError('슈퍼유저는 is_staff=True 여야 합니다.')
        if extra_fields.get('is_superuser') is not True:
            raise ValueError('슈퍼유저는 is_superuser=True 여야 합니다.')

        return self.create_user(email, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    """
    Custom User 모델 - email 기반 인증
    username 필드 제거, email을 primary identifier로 사용
    """

    LOGIN_METHOD_CHOICES = [
        ('email', '이메일'),
        ('google', 'Google'),
        ('apple', 'Apple'),
        ('kakao', 'Kakao'),
        ('naver', 'Naver'),
    ]

    email = models.EmailField(
        unique=True,
        verbose_name="이메일",
        help_text="사용자 로그인용 이메일 주소"
    )
    login_method = models.CharField(
        max_length=20,
        choices=LOGIN_METHOD_CHOICES,
        default='email',
        verbose_name="로그인 방식",
        help_text="사용자가 가입한 방식 (email, google, apple, kakao, naver)"
    )
    is_active = models.BooleanField(default=True, verbose_name="활성 상태")
    is_staff = models.BooleanField(default=False, verbose_name="스태프 권한")
    date_joined = models.DateTimeField(default=timezone.now, verbose_name="가입일시")

    objects = UserManager()

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []

    class Meta:
        db_table = 'users'
        verbose_name = "사용자"
        verbose_name_plural = "사용자"
        ordering = ['-date_joined']

    def __str__(self):
        return self.email


class SocialAccount(models.Model):
    """
    SNS 로그인 계정 정보 (Kakao, Google, Apple)
    사용자와 SNS 제공자 간의 연결 정보 관리
    """

    PROVIDER_CHOICES = [
        ('kakao', 'Kakao'),
        ('google', 'Google'),
        ('apple', 'Apple'),
    ]

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='social_accounts',
        verbose_name="사용자"
    )
    provider = models.CharField(
        max_length=20,
        choices=PROVIDER_CHOICES,
        verbose_name="SNS 제공자"
    )
    provider_user_id = models.CharField(
        max_length=255,
        verbose_name="SNS 제공자의 사용자 ID",
        help_text="Kakao ID, Google ID, Apple ID 등"
    )
    email = models.EmailField(
        verbose_name="SNS 이메일",
        help_text="SNS 제공자로부터 받은 이메일"
    )
    name = models.CharField(
        max_length=100,
        blank=True,
        verbose_name="이름",
        help_text="SNS 제공자로부터 받은 이름"
    )
    profile_image = models.URLField(
        blank=True,
        verbose_name="프로필 이미지 URL"
    )
    access_token = models.TextField(
        blank=True,
        verbose_name="액세스 토큰",
        help_text="암호화 필요 (향후 구현)"
    )
    refresh_token = models.TextField(
        blank=True,
        verbose_name="리프레시 토큰",
        help_text="암호화 필요 (향후 구현)"
    )
    token_expires_at = models.DateTimeField(
        null=True,
        blank=True,
        verbose_name="토큰 만료 시간"
    )
    created_at = models.DateTimeField(
        auto_now_add=True,
        verbose_name="생성일시"
    )
    updated_at = models.DateTimeField(
        auto_now=True,
        verbose_name="수정일시"
    )

    class Meta:
        db_table = 'social_accounts'
        verbose_name = "SNS 계정"
        verbose_name_plural = "SNS 계정"
        unique_together = ('provider', 'provider_user_id')
        indexes = [
            models.Index(fields=['provider', 'provider_user_id'], name='idx_provider_user'),
            models.Index(fields=['user', 'provider'], name='idx_user_provider'),
        ]
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.provider} - {self.email}"

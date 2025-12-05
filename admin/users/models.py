"""
Users 모델 - GORM이 관리하는 테이블 (managed=False)
Django Admin CRUD 전용
"""
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin, BaseUserManager
from django.db import models
from django.utils import timezone


class UserManager(BaseUserManager):
    """Custom User Manager - email + login_method 기반 인증"""

    def create_user(self, email, password=None, login_method='email', **extra_fields):
        if not email:
            raise ValueError('이메일은 필수입니다.')

        email = self.normalize_email(email)
        login_method = extra_fields.pop('login_method', login_method)
        extra_fields.pop('username', None)
        username = f"{email}_{login_method}"
        user = self.model(email=email, username=username, login_method=login_method, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)
        extra_fields.setdefault('login_method', 'email')

        if extra_fields.get('is_staff') is not True:
            raise ValueError('슈퍼유저는 is_staff=True 여야 합니다.')
        if extra_fields.get('is_superuser') is not True:
            raise ValueError('슈퍼유저는 is_superuser=True 여야 합니다.')

        return self.create_user(email, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    """Custom User 모델 - GORM 테이블 참조"""

    LOGIN_METHOD_CHOICES = [
        ('email', '이메일'),
        ('google', 'Google'),
        ('apple', 'Apple'),
        ('kakao', 'Kakao'),
        ('naver', 'Naver'),
        ('anonymous', '익명'),
    ]

    username = models.CharField(max_length=255, unique=True, editable=False, default='', verbose_name="사용자명")
    email = models.EmailField(verbose_name="이메일")
    login_method = models.CharField(max_length=20, choices=LOGIN_METHOD_CHOICES, default='email', verbose_name="로그인 방식")
    name = models.CharField(max_length=100, blank=True, default='', verbose_name="이름")
    profile_image = models.URLField(max_length=500, blank=True, default='', verbose_name="프로필 이미지 URL")
    is_active = models.BooleanField(default=True, verbose_name="활성 상태")
    is_staff = models.BooleanField(default=False, verbose_name="스태프 권한")
    date_joined = models.DateTimeField(default=timezone.now, verbose_name="가입일시")
    last_login = models.DateTimeField(null=True, blank=True, verbose_name="마지막 로그인")

    objects = UserManager()

    USERNAME_FIELD = 'username'
    REQUIRED_FIELDS = ['email']

    class Meta:
        db_table = 'users'
        managed = False  # GORM이 테이블 관리
        verbose_name = "사용자"
        verbose_name_plural = "사용자"
        ordering = ['-date_joined']

    def save(self, *args, **kwargs):
        if not self.username:
            self.username = f"{self.email}_{self.login_method}"
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.email} ({self.login_method})"


class SocialAccount(models.Model):
    """SNS 계정 연동 정보 - GORM 테이블 참조"""

    PROVIDER_CHOICES = [
        ('kakao', 'Kakao'),
        ('google', 'Google'),
        ('apple', 'Apple'),
    ]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='social_accounts', verbose_name="사용자")
    provider = models.CharField(max_length=20, choices=PROVIDER_CHOICES, verbose_name="SNS 제공자")
    provider_user_id = models.CharField(max_length=255, verbose_name="SNS 사용자 ID")
    email = models.EmailField(verbose_name="SNS 이메일")
    name = models.CharField(max_length=100, blank=True, verbose_name="이름")
    profile_image = models.URLField(blank=True, verbose_name="프로필 이미지 URL")
    access_token = models.TextField(blank=True, verbose_name="액세스 토큰")
    refresh_token = models.TextField(blank=True, verbose_name="리프레시 토큰")
    token_expires_at = models.DateTimeField(null=True, blank=True, verbose_name="토큰 만료 시간")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = 'social_accounts'
        managed = False
        verbose_name = "SNS 계정"
        verbose_name_plural = "SNS 계정"
        unique_together = ('provider', 'provider_user_id')
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.provider} - {self.email}"


class EmailVerification(models.Model):
    """이메일 인증 코드 - GORM 테이블 참조"""

    email = models.EmailField(verbose_name="이메일")
    code = models.CharField(max_length=10, verbose_name="인증코드")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    expires_at = models.DateTimeField(verbose_name="만료일시")
    attempts = models.IntegerField(default=0, verbose_name="시도 횟수")
    is_verified = models.BooleanField(default=False, verbose_name="인증 완료 여부")
    verification_token = models.CharField(max_length=255, blank=True, verbose_name="인증 토큰")
    send_count = models.IntegerField(default=1, verbose_name="발송 횟수")
    last_sent_at = models.DateTimeField(auto_now_add=True, verbose_name="마지막 발송 시간")

    class Meta:
        db_table = 'email_verifications'
        managed = False
        verbose_name = "이메일 인증"
        verbose_name_plural = "이메일 인증"
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.email} - {'인증완료' if self.is_verified else '미인증'}"

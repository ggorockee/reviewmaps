from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.utils.translation import gettext_lazy as _
from .models import User, SocialAccount


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    """Custom User Admin - email + login_method 기반 인증"""

    # 목록 페이지에서 보여질 필드
    list_display = ('username', 'email', 'name', 'login_method', 'is_active', 'is_staff', 'is_superuser', 'date_joined')
    list_filter = ('login_method', 'is_active', 'is_staff', 'is_superuser', 'date_joined')
    search_fields = ('email', 'username', 'name')
    ordering = ('-date_joined',)

    # 사용자 상세/수정 페이지
    fieldsets = (
        (None, {'fields': ('username', 'email', 'login_method', 'password')}),
        (_('프로필'), {
            'fields': ('name', 'profile_image'),
        }),
        (_('권한'), {
            'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions'),
        }),
        (_('중요한 날짜'), {'fields': ('last_login', 'date_joined')}),
    )

    # 사용자 추가 페이지
    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('email', 'login_method', 'password1', 'password2'),
        }),
    )

    readonly_fields = ('username', 'date_joined', 'last_login')


@admin.register(SocialAccount)
class SocialAccountAdmin(admin.ModelAdmin):
    """SNS 계정 Admin"""

    list_display = ('user', 'provider', 'email', 'name', 'created_at')
    list_filter = ('provider', 'created_at')
    search_fields = ('email', 'name', 'provider_user_id', 'user__email')
    readonly_fields = ('created_at', 'updated_at')
    ordering = ('-created_at',)

    fieldsets = (
        ('사용자 정보', {
            'fields': ('user', 'provider', 'provider_user_id')
        }),
        ('SNS 프로필', {
            'fields': ('email', 'name', 'profile_image')
        }),
        ('토큰 정보', {
            'fields': ('access_token', 'refresh_token', 'token_expires_at'),
            'classes': ('collapse',)
        }),
        ('타임스탬프', {
            'fields': ('created_at', 'updated_at')
        }),
    )

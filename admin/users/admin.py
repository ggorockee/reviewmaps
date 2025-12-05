from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from unfold.admin import ModelAdmin
from unfold.forms import AdminPasswordChangeForm, UserChangeForm, UserCreationForm
from .models import User, SocialAccount, EmailVerification


@admin.register(User)
class UserAdmin(BaseUserAdmin, ModelAdmin):
    form = UserChangeForm
    add_form = UserCreationForm
    change_password_form = AdminPasswordChangeForm

    list_display = ('email', 'login_method', 'name', 'is_active', 'is_staff', 'date_joined')
    list_filter = ('login_method', 'is_active', 'is_staff', 'date_joined')
    search_fields = ('email', 'name', 'username')
    ordering = ('-date_joined',)

    fieldsets = (
        (None, {'fields': ('email', 'password')}),
        ('개인정보', {'fields': ('name', 'profile_image', 'login_method')}),
        ('권한', {'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions')}),
        ('날짜', {'fields': ('date_joined', 'last_login')}),
    )
    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('email', 'password1', 'password2', 'login_method'),
        }),
    )
    readonly_fields = ('date_joined', 'last_login', 'username')


@admin.register(SocialAccount)
class SocialAccountAdmin(ModelAdmin):
    list_display = ('user', 'provider', 'email', 'created_at')
    list_filter = ('provider', 'created_at')
    search_fields = ('user__email', 'email', 'provider_user_id')
    ordering = ('-created_at',)
    readonly_fields = ('created_at', 'updated_at')


@admin.register(EmailVerification)
class EmailVerificationAdmin(ModelAdmin):
    list_display = ('email', 'code', 'is_verified', 'attempts', 'expires_at', 'created_at')
    list_filter = ('is_verified', 'created_at')
    search_fields = ('email',)
    ordering = ('-created_at',)
    readonly_fields = ('created_at', 'last_sent_at')

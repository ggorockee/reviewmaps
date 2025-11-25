from django.contrib import admin
from .models import Keyword, KeywordAlert, FCMDevice


@admin.register(Keyword)
class KeywordAdmin(admin.ModelAdmin):
    """키워드 Admin"""
    list_display = ['id', 'keyword', 'user', 'anonymous_session_id', 'is_active', 'created_at']
    list_filter = ['is_active', 'created_at']
    search_fields = ['keyword', 'user__email', 'anonymous_session_id']
    readonly_fields = ['created_at', 'updated_at']
    ordering = ['-created_at']


@admin.register(KeywordAlert)
class KeywordAlertAdmin(admin.ModelAdmin):
    """키워드 알람 Admin"""
    list_display = ['id', 'keyword', 'campaign', 'matched_field', 'is_read', 'created_at']
    list_filter = ['is_read', 'matched_field', 'created_at']
    search_fields = ['keyword__keyword', 'campaign__title']
    readonly_fields = ['created_at', 'updated_at']
    ordering = ['-created_at']


@admin.register(FCMDevice)
class FCMDeviceAdmin(admin.ModelAdmin):
    """FCM 디바이스 Admin"""
    list_display = ['id', 'get_owner', 'device_type', 'is_active', 'fcm_token_short', 'created_at', 'updated_at']
    list_filter = ['device_type', 'is_active', 'created_at']
    search_fields = ['fcm_token', 'user__email', 'anonymous_session_id']
    readonly_fields = ['created_at', 'updated_at']
    ordering = ['-created_at']
    list_per_page = 50

    @admin.display(description='소유자')
    def get_owner(self, obj):
        if obj.user:
            return obj.user.email
        elif obj.anonymous_session_id:
            return f"익명({obj.anonymous_session_id[:8]}...)"
        return "알 수 없음"

    @admin.display(description='FCM 토큰')
    def fcm_token_short(self, obj):
        """FCM 토큰 축약 표시"""
        if obj.fcm_token:
            return f"{obj.fcm_token[:20]}...{obj.fcm_token[-10:]}"
        return "-"

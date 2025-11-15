from django.contrib import admin
from .models import Keyword, KeywordAlert


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

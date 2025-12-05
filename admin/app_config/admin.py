from django.contrib import admin
from unfold.admin import ModelAdmin
from .models import AdConfig, AppVersion, AppSetting, RateLimitConfig


@admin.register(AdConfig)
class AdConfigAdmin(ModelAdmin):
    list_display = ('platform', 'ad_type', 'unit_id', 'is_active', 'show_frequency', 'created_at')
    list_filter = ('platform', 'ad_type', 'is_active')
    search_fields = ('unit_id',)
    ordering = ('platform', 'ad_type')
    readonly_fields = ('created_at', 'updated_at')


@admin.register(AppVersion)
class AppVersionAdmin(ModelAdmin):
    list_display = ('platform', 'latest_version', 'min_version', 'force_update', 'maintenance_mode', 'updated_at')
    list_filter = ('platform', 'force_update', 'maintenance_mode')
    ordering = ('platform', '-updated_at')
    readonly_fields = ('created_at', 'updated_at')


@admin.register(AppSetting)
class AppSettingAdmin(ModelAdmin):
    list_display = ('key', 'value', 'value_type', 'updated_at')
    search_fields = ('key',)
    ordering = ('key',)
    readonly_fields = ('created_at', 'updated_at')


@admin.register(RateLimitConfig)
class RateLimitConfigAdmin(ModelAdmin):
    list_display = ('endpoint', 'max_requests', 'window_sec', 'is_active', 'updated_at')
    list_filter = ('is_active',)
    search_fields = ('endpoint',)
    ordering = ('endpoint',)
    readonly_fields = ('created_at', 'updated_at')

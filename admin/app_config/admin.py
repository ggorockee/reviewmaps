from django.contrib import admin
from unfold.admin import ModelAdmin
from .models import AdConfig, AppVersion, AppSetting, RateLimitConfig


@admin.register(AdConfig)
class AdConfigAdmin(ModelAdmin):
    list_display = ("platform", "ad_network", "is_enabled", "priority", "created_at")
    list_filter = ("platform", "ad_network", "is_enabled")
    search_fields = ("ad_network",)
    ordering = ("platform", "priority")
    readonly_fields = ("created_at", "updated_at")


@admin.register(AppVersion)
class AppVersionAdmin(ModelAdmin):
    list_display = ("platform", "version", "minimum_version", "build_number", "is_active", "force_update", "updated_at")
    list_filter = ("platform", "is_active", "force_update")
    ordering = ("platform", "-updated_at")
    readonly_fields = ("created_at", "updated_at")


@admin.register(AppSetting)
class AppSettingAdmin(ModelAdmin):
    list_display = ("key", "value", "is_active", "updated_at")
    list_filter = ("is_active",)
    search_fields = ("key", "description")
    ordering = ("key",)
    readonly_fields = ("created_at", "updated_at")


@admin.register(RateLimitConfig)
class RateLimitConfigAdmin(ModelAdmin):
    list_display = ("endpoint", "max_requests", "window_seconds", "is_enabled", "priority", "updated_at")
    list_filter = ("is_enabled", "apply_to_authenticated", "apply_to_anonymous")
    search_fields = ("endpoint", "description")
    ordering = ("priority", "endpoint")
    readonly_fields = ("created_at", "updated_at")

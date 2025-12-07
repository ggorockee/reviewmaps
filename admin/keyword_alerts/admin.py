from django.contrib import admin
from unfold.admin import ModelAdmin
from .models import FCMDevice, Keyword, KeywordAlert


@admin.register(FCMDevice)
class FCMDeviceAdmin(ModelAdmin):
    list_display = ("user", "platform", "is_active", "created_at")
    list_filter = ("platform", "is_active")
    search_fields = ("user__email", "token")
    ordering = ("-created_at",)
    readonly_fields = ("created_at", "updated_at")


@admin.register(Keyword)
class KeywordAdmin(ModelAdmin):
    list_display = ("keyword", "user", "is_active", "created_at")
    list_filter = ("is_active",)
    search_fields = ("keyword", "user__email")
    ordering = ("-created_at",)
    readonly_fields = ("created_at", "updated_at")


@admin.register(KeywordAlert)
class KeywordAlertAdmin(ModelAdmin):
    list_display = ("keyword", "campaign", "matched_field", "is_read", "created_at")
    list_filter = ("is_read", "matched_field", "created_at")
    search_fields = ("keyword__keyword", "campaign__company", "campaign__title")
    ordering = ("-created_at",)
    date_hierarchy = "created_at"
    readonly_fields = ("created_at", "updated_at")

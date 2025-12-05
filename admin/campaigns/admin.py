from django.contrib import admin
from unfold.admin import ModelAdmin
from .models import Category, Campaign, RawCategory, CategoryMapping


@admin.register(Category)
class CategoryAdmin(ModelAdmin):
    list_display = ("name", "slug", "sort_order", "is_active", "created_at")
    list_filter = ("is_active",)
    search_fields = ("name", "slug")
    ordering = ("sort_order", "id")
    list_editable = ("sort_order", "is_active")


@admin.register(Campaign)
class CampaignAdmin(ModelAdmin):
    list_display = ("company", "platform", "category", "promotion_level", "apply_deadline", "region", "created_at")
    list_filter = ("platform", "category", "campaign_type", "region", "promotion_level")
    search_fields = ("company", "title", "offer", "address")
    ordering = ("-created_at",)
    date_hierarchy = "created_at"
    readonly_fields = ("created_at", "updated_at")

    fieldsets = (
        ("기본 정보", {"fields": ("platform", "company", "company_link", "offer", "title", "category")}),
        ("날짜", {"fields": ("apply_from", "apply_deadline", "review_deadline")}),
        ("위치", {"fields": ("address", "lat", "lng", "region")}),
        ("미디어", {"fields": ("img_url", "content_link")}),
        ("분류", {"fields": ("campaign_type", "campaign_channel", "source", "search_text")}),
        ("프로모션", {"fields": ("promotion_level",)}),
        ("타임스탬프", {"fields": ("created_at", "updated_at"), "classes": ("collapse",)}),
    )


@admin.register(RawCategory)
class RawCategoryAdmin(ModelAdmin):
    list_display = ("name", "source", "created_at")
    list_filter = ("source",)
    search_fields = ("name",)
    ordering = ("-created_at",)


@admin.register(CategoryMapping)
class CategoryMappingAdmin(ModelAdmin):
    list_display = ("raw_category", "category", "created_at")
    list_filter = ("category",)
    search_fields = ("raw_category__name", "category__name")
    autocomplete_fields = ("raw_category", "category")

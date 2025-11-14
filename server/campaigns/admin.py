from django.contrib import admin
from .models import Category, Campaign, RawCategory, CategoryMapping


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    """카테고리 관리자"""

    list_display = ('name', 'display_order', 'created_at')
    list_filter = ('created_at',)
    search_fields = ('name',)
    ordering = ('display_order', 'id')


@admin.register(Campaign)
class CampaignAdmin(admin.ModelAdmin):
    """캠페인 관리자"""

    list_display = ('company', 'platform', 'category', 'promotion_level', 'apply_deadline', 'created_at')
    list_filter = ('platform', 'category', 'promotion_level', 'created_at')
    search_fields = ('company', 'offer', 'title', 'search_text')
    ordering = ('-created_at',)
    readonly_fields = ('created_at', 'updated_at')

    fieldsets = (
        ('기본 정보', {
            'fields': ('category', 'platform', 'company', 'company_link', 'offer')
        }),
        ('날짜 정보', {
            'fields': ('apply_from', 'apply_deadline', 'review_deadline')
        }),
        ('위치 정보', {
            'fields': ('address', 'lat', 'lng')
        }),
        ('이미지 및 링크', {
            'fields': ('img_url', 'content_link')
        }),
        ('검색 및 분류', {
            'fields': ('search_text', 'source', 'title', 'campaign_type', 'region', 'campaign_channel')
        }),
        ('프로모션', {
            'fields': ('promotion_level',)
        }),
        ('타임스탬프', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )


@admin.register(RawCategory)
class RawCategoryAdmin(admin.ModelAdmin):
    """원본 카테고리 관리자"""

    list_display = ('raw_text', 'created_at')
    search_fields = ('raw_text',)
    ordering = ('-created_at',)


@admin.register(CategoryMapping)
class CategoryMappingAdmin(admin.ModelAdmin):
    """카테고리 매핑 관리자"""

    list_display = ('raw_category', 'standard_category')
    list_filter = ('standard_category',)
    search_fields = ('raw_category__raw_text', 'standard_category__name')

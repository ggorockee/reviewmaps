"""
app_config Django Admin 설정
"""
from django.contrib import admin
from app_config.models import AdConfig, AppVersion, AppSetting


@admin.register(AdConfig)
class AdConfigAdmin(admin.ModelAdmin):
    """광고 설정 Admin"""
    list_display = ['platform', 'ad_network', 'is_enabled', 'priority', 'created_at']
    list_filter = ['platform', 'is_enabled', 'ad_network']
    search_fields = ['ad_network']
    ordering = ['-priority', '-created_at']
    readonly_fields = ['created_at', 'updated_at']

    fieldsets = (
        ('기본 정보', {
            'fields': ('platform', 'ad_network', 'is_enabled', 'priority')
        }),
        ('광고 유닛 ID', {
            'fields': ('ad_unit_ids',),
            'description': 'JSON 형식으로 입력하세요. 예: {"banner_id": "ca-app-pub-xxx", "interstitial_id": "ca-app-pub-yyy"}'
        }),
        ('타임스탬프', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )


@admin.register(AppVersion)
class AppVersionAdmin(admin.ModelAdmin):
    """앱 버전 Admin"""
    list_display = ['platform', 'version', 'build_number', 'minimum_version', 'force_update', 'is_active', 'created_at']
    list_filter = ['platform', 'is_active', 'force_update']
    search_fields = ['version', 'update_message']
    ordering = ['-is_active', '-created_at']
    readonly_fields = ['created_at', 'updated_at']

    fieldsets = (
        ('기본 정보', {
            'fields': ('platform', 'version', 'build_number', 'is_active')
        }),
        ('버전 관리', {
            'fields': ('minimum_version', 'force_update', 'update_message')
        }),
        ('스토어 정보', {
            'fields': ('store_url',)
        }),
        ('타임스탬프', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )

    def save_model(self, request, obj, form, change):
        """
        버전 저장 시 동일 플랫폼의 다른 활성 버전 비활성화 옵션
        (선택적 기능 - 필요시 주석 해제)
        """
        # if obj.is_active:
        #     AppVersion.objects.filter(
        #         platform=obj.platform,
        #         is_active=True
        #     ).exclude(id=obj.id).update(is_active=False)
        super().save_model(request, obj, form, change)


@admin.register(AppSetting)
class AppSettingAdmin(admin.ModelAdmin):
    """앱 설정 Admin"""
    list_display = ['key', 'description', 'is_active', 'created_at']
    list_filter = ['is_active']
    search_fields = ['key', 'description']
    ordering = ['key']
    readonly_fields = ['created_at', 'updated_at']

    fieldsets = (
        ('기본 정보', {
            'fields': ('key', 'description', 'is_active')
        }),
        ('설정 값', {
            'fields': ('value',),
            'description': 'JSON 형식으로 입력하세요. 예: {"enabled": true, "message": "점검 중"}'
        }),
        ('타임스탬프', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )

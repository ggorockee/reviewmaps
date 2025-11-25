"""
app_config API
비동기 Django Ninja API 엔드포인트
"""
from ninja import Router
from typing import List
from django.http import Http404

from app_config.models import AdConfig, AppVersion, AppSetting
from app_config.schemas import (
    AdConfigSchema,
    VersionCheckResponseSchema,
    AppSettingSchema,
    KeywordLimitResponse,
    KeywordLimitUpdateRequest,
)

router = Router(tags=["앱 설정 (App Config)"])


# ===== 광고 설정 API =====

@router.get("/ads", response=List[AdConfigSchema])
async def get_ads(request, platform: str):
    """
    플랫폼별 활성화된 광고 설정 조회

    Args:
        platform: android 또는 ios

    Returns:
        활성화된 광고 설정 리스트 (우선순위 순)
    """
    configs = []
    async for config in AdConfig.objects.filter(
        platform=platform,
        is_enabled=True
    ).order_by('-priority'):
        configs.append(config)

    return configs


# ===== 앱 버전 API =====

@router.get("/version", response=VersionCheckResponseSchema)
async def check_version(request, platform: str):
    """
    앱 버전 설정 조회

    플랫폼별 버전 설정 정보를 반환.
    force_update 값은 DB 모델에서 가져오며, 최종 UI 처리는 클라이언트에서 담당.

    Args:
        platform: android 또는 ios

    Returns:
        {
            "latest_version": "1.4.0",
            "min_version": "1.3.0",
            "force_update": true/false,  // DB 모델 값 반환
            "store_url": "https://...",
            "message_title": "업데이트 안내",
            "message_body": "더 안정적인 서비스 이용을 위해..."
        }

    Client Logic (Flutter):
        1. force_update == true → 강제 업데이트 (스킵 불가)
        2. current < min_version → 강제 업데이트
        3. min_version ≤ current < latest_version → 권장 업데이트
        4. current ≥ latest_version → 업데이트 안내 없음

    Raises:
        404: 활성화된 버전 정보가 없을 때
    """
    # 가장 최신의 활성화된 버전 조회
    try:
        latest_config = await AppVersion.objects.filter(
            platform=platform,
            is_active=True
        ).afirst()

        if not latest_config:
            raise Http404(f"{platform} 플랫폼의 활성화된 버전 정보가 없습니다.")
    except AppVersion.DoesNotExist:
        raise Http404(f"{platform} 플랫폼의 활성화된 버전 정보가 없습니다.")

    # 서버 모델 값 반환, 최종 판단은 클라이언트에서
    return VersionCheckResponseSchema(
        latest_version=latest_config.version,
        min_version=latest_config.minimum_version,
        force_update=latest_config.force_update,  # 모델의 force_update 값 사용
        store_url=latest_config.store_url,
        message_title="업데이트 안내",
        message_body=latest_config.update_message or (
            "더 안정적이고 편리한 서비스 이용을 위해\n"
            "최신 버전으로 업데이트해 주세요."
        )
    )


# ===== 앱 설정 API =====

@router.get("/settings", response=List[AppSettingSchema])
async def get_settings(request):
    """
    모든 활성화된 앱 설정 조회

    Returns:
        활성화된 앱 설정 리스트 (key 알파벳 순)
    """
    settings = []
    async for setting in AppSetting.objects.filter(is_active=True).order_by('key'):
        settings.append(setting)

    return settings


# ===== 키워드 제한 설정 API (특정 경로를 동적 경로보다 먼저 정의) =====

@router.get("/settings/keyword-limit", response=KeywordLimitResponse, summary="키워드 등록 개수 제한 조회")
async def get_keyword_limit(request):
    """
    키워드 등록 개수 제한 조회 API

    Returns:
        max_active_keywords: 활성 키워드 최대 개수
        max_inactive_keywords: 비활성 키워드 최대 개수
        total_keywords: 전체 키워드 최대 개수

    Note:
        - 설정이 없으면 기본값 반환 (활성 20개, 비활성 0개)
        - total_keywords = max_active + max_inactive
    """
    try:
        setting = await AppSetting.objects.aget(key='keyword_limit', is_active=True)
        value = setting.value
        max_active = value.get('max_active_keywords', 20)
        max_inactive = value.get('max_inactive_keywords', 0)
    except AppSetting.DoesNotExist:
        # 기본값
        max_active = 20
        max_inactive = 0

    return {
        "max_active_keywords": max_active,
        "max_inactive_keywords": max_inactive,
        "total_keywords": max_active + max_inactive,
    }


@router.put("/settings/keyword-limit", response=KeywordLimitResponse, summary="키워드 등록 개수 제한 설정")
async def update_keyword_limit(request, payload: KeywordLimitUpdateRequest):
    """
    키워드 등록 개수 제한 설정 API

    Args:
        max_active_keywords: 활성 키워드 최대 개수 (최소 1개)
        max_inactive_keywords: 비활성 키워드 최대 개수 (최소 0개)

    Returns:
        업데이트된 키워드 제한 설정

    Note:
        - 설정이 없으면 새로 생성
        - 기존 설정이 있으면 업데이트
    """
    # 유효성 검증
    if payload.max_active_keywords < 1:
        raise Http404("활성 키워드 최대 개수는 최소 1개 이상이어야 합니다.")
    if payload.max_inactive_keywords < 0:
        raise Http404("비활성 키워드 최대 개수는 0개 이상이어야 합니다.")

    # 설정 업데이트 또는 생성
    await AppSetting.objects.aupdate_or_create(
        key='keyword_limit',
        defaults={
            'value': {
                'max_active_keywords': payload.max_active_keywords,
                'max_inactive_keywords': payload.max_inactive_keywords,
            },
            'description': '키워드 등록 개수 제한 설정',
            'is_active': True,
        }
    )

    return {
        "max_active_keywords": payload.max_active_keywords,
        "max_inactive_keywords": payload.max_inactive_keywords,
        "total_keywords": payload.max_active_keywords + payload.max_inactive_keywords,
    }


@router.get("/settings/{key}", response=AppSettingSchema)
async def get_setting_by_key(request, key: str):
    """
    특정 키의 앱 설정 조회

    Args:
        key: 설정 키

    Returns:
        해당 키의 설정 정보

    Raises:
        404: 설정이 없거나 비활성화된 경우
    """
    try:
        setting = await AppSetting.objects.aget(key=key, is_active=True)
        return setting
    except AppSetting.DoesNotExist:
        raise Http404(f"설정 키 '{key}'를 찾을 수 없습니다.")

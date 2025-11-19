"""
app_config Pydantic 스키마
API 요청/응답 검증을 위한 스키마
"""
from ninja import Schema
from typing import Optional, Dict, Any
from datetime import datetime


# ===== 광고 설정 스키마 =====

class AdConfigSchema(Schema):
    """광고 설정 응답 스키마"""
    id: int
    platform: str
    ad_network: str
    is_enabled: bool
    ad_unit_ids: Dict[str, Any]
    priority: int
    created_at: datetime
    updated_at: datetime


# ===== 앱 버전 스키마 =====

class AppVersionSchema(Schema):
    """앱 버전 응답 스키마"""
    id: int
    platform: str
    version: str
    build_number: int
    minimum_version: str
    force_update: bool
    update_message: Optional[str] = None
    store_url: str
    is_active: bool
    created_at: datetime
    updated_at: datetime


class VersionCheckResponseSchema(Schema):
    """버전 체크 응답 스키마"""
    needs_update: bool
    force_update: bool
    latest_version: str
    message: Optional[str] = None
    store_url: str


# ===== 앱 설정 스키마 =====

class AppSettingSchema(Schema):
    """앱 설정 응답 스키마"""
    id: int
    key: str
    value: Dict[str, Any]
    description: Optional[str] = None
    is_active: bool
    created_at: datetime
    updated_at: datetime


# ===== 키워드 제한 설정 스키마 =====

class KeywordLimitResponse(Schema):
    """키워드 제한 설정 응답 스키마"""
    max_active_keywords: int
    max_inactive_keywords: int
    total_keywords: int


class KeywordLimitUpdateRequest(Schema):
    """키워드 제한 설정 업데이트 요청 스키마"""
    max_active_keywords: int
    max_inactive_keywords: int

"""
Keyword Alerts 관련 Pydantic 스키마
"""
from ninja import Schema
from typing import Optional
from datetime import datetime


class KeywordCreateRequest(Schema):
    """키워드 등록 요청"""
    keyword: str


class KeywordResponse(Schema):
    """키워드 응답"""
    id: int
    keyword: str
    is_active: bool
    created_at: datetime


class KeywordListResponse(Schema):
    """키워드 목록 응답"""
    keywords: list[KeywordResponse]


class KeywordAlertResponse(Schema):
    """키워드 알람 응답"""
    id: int
    keyword: str
    campaign_id: int
    campaign_title: str
    campaign_company: Optional[str] = None  # 업체명
    campaign_offer: Optional[str] = None
    campaign_address: Optional[str] = None
    campaign_lat: Optional[float] = None
    campaign_lng: Optional[float] = None
    campaign_img_url: Optional[str] = None
    campaign_platform: Optional[str] = None  # 플랫폼
    campaign_apply_deadline: Optional[datetime] = None  # 신청 마감일
    campaign_content_link: Optional[str] = None  # 콘텐츠 링크
    campaign_channel: Optional[str] = None  # 캠페인 채널
    matched_field: str
    is_read: bool
    created_at: datetime
    distance: Optional[float] = None  # 거리 (km)


class KeywordAlertListResponse(Schema):
    """키워드 알람 목록 응답"""
    alerts: list[KeywordAlertResponse]
    unread_count: int


class MarkAlertReadRequest(Schema):
    """알람 읽음 처리 요청"""
    alert_ids: list[int]


class FCMDeviceRegisterRequest(Schema):
    """FCM 디바이스 토큰 등록 요청"""
    fcm_token: str
    device_type: str = "android"  # "android" or "ios"


class FCMDeviceResponse(Schema):
    """FCM 디바이스 응답"""
    id: int
    fcm_token: str
    device_type: str
    is_active: bool
    created_at: datetime

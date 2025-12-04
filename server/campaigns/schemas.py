from ninja import Schema
from typing import Optional
from datetime import datetime
from decimal import Decimal
from django.utils import timezone


class CategorySchema(Schema):
    """카테고리 스키마"""
    id: int
    name: str
    display_order: int
    created_at: datetime


class CampaignOut(Schema):
    """캠페인 출력 스키마"""
    id: int
    category: Optional[CategorySchema] = None
    platform: str
    company: str
    company_link: Optional[str] = None
    offer: str
    apply_deadline: Optional[datetime] = None
    review_deadline: Optional[datetime] = None
    apply_from: Optional[datetime] = None
    address: Optional[str] = None
    lat: Optional[Decimal] = None
    lng: Optional[Decimal] = None
    img_url: Optional[str] = None
    content_link: Optional[str] = None
    search_text: Optional[str] = None
    source: Optional[str] = None
    title: Optional[str] = None
    campaign_type: Optional[str] = None
    region: Optional[str] = None
    campaign_channel: Optional[str] = None
    promotion_level: int
    created_at: datetime
    updated_at: datetime
    distance: Optional[float] = None  # 계산된 거리 (km)
    is_expired: Optional[bool] = None  # 마감 여부 (오늘 날짜 기준)

    class Config:
        from_attributes = True

    @staticmethod
    def resolve_is_expired(obj) -> Optional[bool]:
        """
        캠페인 마감 여부 계산 (오늘 날짜 기준, 당일까지는 유효)

        - apply_deadline이 NULL이면 None (무기한)
        - apply_deadline < 오늘 00:00:00 (KST) 이면 True (마감됨)
        - apply_deadline >= 오늘 00:00:00 (KST) 이면 False (유효)

        주의: timezone.now()는 UTC 기준이므로, 로컬 타임존(Asia/Seoul)으로 변환 후
              오늘 시작 시간을 계산해야 정확한 마감 여부 판단이 가능
        """
        if obj.apply_deadline is None:
            return None  # 무기한

        # 로컬 타임존(Asia/Seoul) 기준 현재 시간
        now_local = timezone.localtime(timezone.now())
        # 오늘 날짜의 시작 (00:00:00 KST)
        today_start_local = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
        return obj.apply_deadline < today_start_local


class CampaignListResponse(Schema):
    """캠페인 목록 응답 스키마"""
    total: int
    limit: int
    offset: int
    items: list[CampaignOut]

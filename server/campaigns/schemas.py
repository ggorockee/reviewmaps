from ninja import Schema
from typing import Optional
from datetime import datetime
from decimal import Decimal


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

    class Config:
        from_attributes = True


class CampaignListResponse(Schema):
    """캠페인 목록 응답 스키마"""
    total: int
    limit: int
    offset: int
    items: list[CampaignOut]

from __future__ import annotations
from pydantic import BaseModel, Field, ConfigDict
from typing import Optional
from datetime import datetime

class CampaignOut(BaseModel):
    id: int
    platform: str
    company: str
    company_link: Optional[str] = None
    offer: str
    apply_deadline: Optional[datetime] = None
    review_deadline: Optional[datetime] = None
    address: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    img_url: Optional[str] = None
    search_text: Optional[str] = None
    is_new: bool = False
    distance: Optional[float] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class CampaignOutV2(CampaignOut):
    source: Optional[str] = None
    title: Optional[str] = None
    content_link: Optional[str] = None
    campaign_type: Optional[str] = None
    region: Optional[str] = None
    campaign_channel: Optional[str] = None
    apply_from: Optional[datetime] = None
    promotion_level: Optional[int] = None
    category_id: Optional[int] = None
    # category_id는 필터링 조건으로만 사용되므로, 응답 모델에는 일단 제외하겠습니다.
    # 만약 응답에도 포함하고 싶다면 여기에 'category_id: Optional[int] = None'을 추가하세요.


class CampaignList(BaseModel):
    total: int = Field(..., description="총 행 수")
    limit: int
    offset: int
    items: list[CampaignOut]

class CampaignListV2(BaseModel):
    total: int = Field(..., description="총 행 수")
    limit: int
    offset: int
    items: list[CampaignOutV2]
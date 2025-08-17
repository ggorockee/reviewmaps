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
    distance: Optional[float] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class CampaignList(BaseModel):
    total: int = Field(..., description="총 행 수")
    limit: int
    offset: int
    items: list[CampaignOut]

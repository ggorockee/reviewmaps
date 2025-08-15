from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from api.deps import get_db_session
from db import crud
from schemas.campaign import CampaignList, CampaignOut

from datetime import datetime
from zoneinfo import ZoneInfo

KST = ZoneInfo("Asia/Seoul")

def _parse_kst(dt_str: str | None) -> datetime | None:
    if not dt_str:
        return None
    # 1) 문자열을 datetime으로
    dt = datetime.fromisoformat(dt_str)
    # 2) tz가 없으면 KST로 로컬라이즈, 있으면 그대로 사용
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=KST)
    return dt

router = APIRouter(tags=["campaigns"])



@router.get("/campaigns", response_model=CampaignList, summary="캠페인 목록 조회 (async)")
async def list_campaigns(
    db: AsyncSession            = Depends(get_db_session),
    q: Optional[str]            = Query(None, description="회사/오퍼/플랫폼 부분검색"),
    platform: Optional[str]     = Query(None),
    company: Optional[str]      = Query(None, description="회사명 부분검색"),
    apply_from: Optional[str]   = Query(None, description="apply_deadline >= (ISO8601)"),
    apply_to: Optional[str]     = Query(None, description="apply_deadline <= (ISO8601)"),
    review_from: Optional[str]  = Query(None, description="review_deadline >= (ISO8601)"),
    review_to: Optional[str]    = Query(None, description="review_deadline <= (ISO8601)"),
    sort: str                   = Query("-created_at", description="정렬 키. -는 내림차순"),
    limit: int                  = Query(20, ge=1, le=200),
    offset: int                 = Query(0, ge=0),
):
    total, rows = await crud.list_campaigns(
        db,
        q=q,
        platform=platform,
        company=company,
        apply_from=_parse_kst(apply_from),
        apply_to=_parse_kst(apply_to),
        review_from=_parse_kst(review_from),
        review_to=_parse_kst(review_to),
        sort=sort,
        limit=limit,
        offset=offset,
    )
    return {"total": total, "limit": limit, "offset": offset, "items": rows}

@router.get("/campaigns/{campaign_id}", response_model=CampaignOut, summary="캠페인 상세 (async)")
async def get_campaign(
    campaign_id: int,
    db: AsyncSession = Depends(get_db_session)
):
    row = await crud.get_campaign(db, campaign_id)
    if not row:
        raise HTTPException(status_code=404, detail="Not found")
    return row
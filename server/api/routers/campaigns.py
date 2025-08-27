from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from api.deps import get_db_session
from db import crud
from schemas.campaign import CampaignList, CampaignOut

from core.utils import _parse_kst, KST
from datetime import datetime


router = APIRouter(tags=["campaigns"])



@router.get("/campaigns", response_model=CampaignList, summary="캠페인 목록 조회 (async)")
async def list_campaigns(
    db: AsyncSession            = Depends(get_db_session),
    category_id: Optional[int]  = Query(None, description="카테고리 ID로 필터링"),
    q: Optional[str]            = Query(None, description="회사/오퍼/플랫폼 부분검색"),
    platform: Optional[str]     = Query(None),
    company: Optional[str]      = Query(None, description="회사명 부분검색"),
    apply_from: Optional[str]   = Query(None, description="apply_deadline >= (ISO8601)"),
    apply_to: Optional[str]     = Query(None, description="apply_deadline <= (ISO8601)"),
    review_from: Optional[str]  = Query(None, description="review_deadline >= (ISO8601)"),
    review_to: Optional[str]    = Query(None, description="review_deadline <= (ISO8601)"),
    
    #  Bounding Box를 위한 4개의 좌표 파라미터
    sw_lat: Optional[float]     = Query(None, description="남서쪽(좌측 하단) 위도"),
    sw_lng: Optional[float]     = Query(None, description="남서쪽(좌측 하단) 경도"),
    ne_lat: Optional[float]     = Query(None, description="북동쪽(우측 상단) 위도"),
    ne_lng: Optional[float]     = Query(None, description="북동쪽(우측 상단) 경도"),
    
    lat: Optional[float]        = Query(None, description="사용자 현재 위도 (sort='distance'일 때 필수)"),
    lng: Optional[float]        = Query(None, description="사용자 현재 경도 (sort='distance'일 때 필수)"),
    sort: str                   = Query(
                                    "-created_at", 
                                    description="정렬 키. -는 내림차순. 사용 가능 키: created_at, apply_deadline, distance"
                                    ),
    
    limit: int                  = Query(20, ge=1, le=100),
    offset: int                 = Query(0, ge=0),
):
    if sort == "distance":
        if lat is None or lng is None:
            raise HTTPException(
                status_code=400,
                detail="sort='distance' requires 'lat' and 'lng' parameters."
            )
            
    now_kst = datetime.now(KST)
    user_apply_from = _parse_kst(apply_from)

    effective_apply_from = user_apply_from
    if effective_apply_from is None or effective_apply_from < now_kst:
        effective_apply_from = now_kst

            
    total, rows = await crud.list_campaigns(
        db,
        category_id=category_id,
        q=q,
        platform=platform,
        company=company,
        apply_from=effective_apply_from,
        apply_to=_parse_kst(apply_to),
        review_from=_parse_kst(review_from),
        review_to=_parse_kst(review_to),
        sw_lat=sw_lat,
        sw_lng=sw_lng,
        ne_lat=ne_lat,
        ne_lng=ne_lng,

        
        lat=lat,
        lng=lng,
        
        
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
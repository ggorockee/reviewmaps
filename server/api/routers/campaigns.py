from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from api.deps import get_db_session
from db import crud
from schemas.campaign import CampaignList, CampaignOut
from schemas.campaign import CampaignListV2, CampaignOutV2

from core.utils import _parse_kst, KST
from datetime import datetime


router = APIRouter(tags=["campaigns"])




@router.get("/campaigns", response_model=CampaignListV2, summary="캠페인 목록 조회 (V2)")
async def list_campaigns(
    db: AsyncSession            = Depends(get_db_session),

    # --- 신규/기존 필터 ---
    region: Optional[str]       = Query(None, description="지역으로 필터링 (예: 서울, 경기)"),
    offer: Optional[str]        = Query(None, description="오퍼(텍스트) 부분검색, 예: 10만원"),
    campaign_type: Optional[str]= Query(None, description="캠페인 유형 (예: 방문형, 배송형)"),
    campaign_channel: Optional[str] = Query(None, description="캠페인 채널 (예: blog, instagram)"),

    category_id: Optional[int]  = Query(None, description="카테고리 ID"),
    q: Optional[str]            = Query(None, description="회사/오퍼/플랫폼/제목 부분검색"),
    platform: Optional[str]     = Query(None),
    company: Optional[str]      = Query(None, description="회사명 부분검색"),

    # 구형 파라미터(있으면 추가로 적용), 기본 필터는 오늘 날짜로 별도 적용됨
    apply_from: Optional[str]   = Query(None, description="apply_deadline >= (ISO8601, 선택)"),
    apply_to: Optional[str]     = Query(None, description="apply_deadline <= (ISO8601)"),
    review_from: Optional[str]  = Query(None, description="review_deadline >= (ISO8601)"),
    review_to: Optional[str]    = Query(None, description="review_deadline <= (ISO8601)"),

    #  Bounding Box
    sw_lat: Optional[float]     = Query(None, description="남서 위도"),
    sw_lng: Optional[float]     = Query(None, description="남서 경도"),
    ne_lat: Optional[float]     = Query(None, description="북동 위도"),
    ne_lng: Optional[float]     = Query(None, description="북동 경도"),

    # 거리 정렬용
    lat: Optional[float]        = Query(None, description="사용자 위도 (sort='distance'일 때 필수)"),
    lng: Optional[float]        = Query(None, description="사용자 경도 (sort='distance'일 때 필수)"),

    sort: str = Query(
        "-created_at",
        description="정렬 키: created_at, apply_deadline, review_deadline, distance (앞에 -는 내림차순)"
    ),

    # 🔹 신규: 플랫폼 다양화 옵션(쏠림 방지)
    diversify: Optional[str] = Query(
        "platform",
        description="다양성 보장 모드: 'platform'이면 플랫폼별 상한 적용"
    ),
    platform_cap: int = Query(5, ge=1, le=20, description="플랫폼당 최대 노출 개수"),

    limit: int = Query(20, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    # 거리 정렬이면 좌표 필수
    if sort == "distance":
        if lat is None or lng is None:
            raise HTTPException(
                status_code=400,
                detail="sort='distance' requires 'lat' and 'lng' parameters."
            )

    # ✅ 항상 적용할 '오늘(KST) 날짜 기준' 필터 값
    today_kst_date = datetime.now(KST).date()

    total, rows = await crud.list_campaigns(
        db,
        # --- v2 파라미터 ---
        region=region,
        offer=offer,
        campaign_type=campaign_type,
        campaign_channel=campaign_channel,

        # --- 기본 필터 ---
        category_id=category_id,
        q=q,
        platform=platform,
        company=company,

        # ✅ '오늘 이후' 기본 필터를 date로 전달 (핵심)
        apply_from_date=today_kst_date,

        # 선택: 구형 파라미터 추가 적용
        apply_from=_parse_kst(apply_from),
        apply_to=_parse_kst(apply_to),
        review_from=_parse_kst(review_from),
        review_to=_parse_kst(review_to),

        # 지도/거리
        sw_lat=sw_lat, sw_lng=sw_lng, ne_lat=ne_lat, ne_lng=ne_lng,
        lat=lat, lng=lng,

        # 정렬/페이징
        sort=sort, limit=limit, offset=offset,

        # 🔹 플랫폼 다양화 옵션 전달
        diversify=diversify,
        platform_cap=platform_cap,
    )
    return {"total": total, "limit": limit, "offset": offset, "items": rows}


@router.get("/campaigns/{campaign_id}", response_model=CampaignOutV2, summary="캠페인 상세 (V2)")
async def get_campaign(
    campaign_id: int,
    db: AsyncSession = Depends(get_db_session)
):
    row = await crud.get_campaign(db, campaign_id)
    if not row:
        raise HTTPException(status_code=404, detail="Not found")
    return row
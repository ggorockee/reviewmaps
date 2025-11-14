from ninja import Router, Query
from ninja.errors import HttpError
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.db import models
from typing import Optional
from decimal import Decimal
import math

from .models import Campaign, Category
from .schemas import CampaignListResponse, CampaignOut

router = Router()  # tags 제거 - URL prefix가 자동으로 태그가 됨


def calculate_distance(lat1: Decimal, lng1: Decimal, lat2: Decimal, lng2: Decimal) -> float:
    """
    Haversine 공식을 사용한 두 지점 간 거리 계산 (km 단위)
    """
    R = 6371  # 지구 반지름 (km)

    lat1_rad = math.radians(float(lat1))
    lat2_rad = math.radians(float(lat2))
    dlat = math.radians(float(lat2 - lat1))
    dlng = math.radians(float(lng2 - lng1))

    a = math.sin(dlat / 2) ** 2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlng / 2) ** 2
    c = 2 * math.asin(math.sqrt(a))

    return R * c


@router.get("/campaigns", response=CampaignListResponse, summary="캠페인 목록 조회")
async def list_campaigns(
    request,
    # 필터 파라미터
    region: Optional[str] = Query(None, description="지역으로 필터링"),
    offer: Optional[str] = Query(None, description="오퍼 텍스트 검색"),
    campaign_type: Optional[str] = Query(None, description="캠페인 유형 필터"),
    campaign_channel: Optional[str] = Query(None, description="캠페인 채널 필터"),
    category_id: Optional[int] = Query(None, description="카테고리 ID 필터"),
    q: Optional[str] = Query(None, description="통합 검색 (회사/오퍼/플랫폼)"),
    platform: Optional[str] = Query(None, description="플랫폼 필터"),
    company: Optional[str] = Query(None, description="회사명 검색"),

    # 바운딩 박스
    sw_lat: Optional[float] = Query(None, description="남서쪽 위도"),
    sw_lng: Optional[float] = Query(None, description="남서쪽 경도"),
    ne_lat: Optional[float] = Query(None, description="북동쪽 위도"),
    ne_lng: Optional[float] = Query(None, description="북동쪽 경도"),

    # 거리 계산용
    lat: Optional[float] = Query(None, description="사용자 위도"),
    lng: Optional[float] = Query(None, description="사용자 경도"),

    # 정렬 및 페이지네이션
    sort: str = Query("-created_at", description="정렬 키 (-는 내림차순)"),
    limit: int = Query(20, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    """캠페인 목록 조회 API (비동기)"""

    # 거리 정렬 시 lat, lng 필수 체크
    if sort == "distance":
        if lat is None or lng is None:
            raise HttpError(400, "sort='distance' requires 'lat' and 'lng' parameters")

    # 기본 쿼리: 만료되지 않은 캠페인만
    queryset = Campaign.objects.select_related('category').filter(
        models.Q(apply_deadline__isnull=True) | models.Q(apply_deadline__gte=timezone.now())
    )

    # 필터 적용
    if region:
        queryset = queryset.filter(region__icontains=region)
    if offer:
        queryset = queryset.filter(offer__icontains=offer)
    if campaign_type:
        queryset = queryset.filter(campaign_type__icontains=campaign_type)
    if campaign_channel:
        queryset = queryset.filter(campaign_channel__icontains=campaign_channel)
    if category_id:
        queryset = queryset.filter(category_id=category_id)
    if platform:
        queryset = queryset.filter(platform__icontains=platform)
    if company:
        queryset = queryset.filter(company__icontains=company)
    if q:
        queryset = queryset.filter(
            models.Q(company__icontains=q) |
            models.Q(offer__icontains=q) |
            models.Q(platform__icontains=q)
        )

    # 바운딩 박스 필터
    if all([sw_lat, sw_lng, ne_lat, ne_lng]):
        queryset = queryset.filter(
            lat__gte=sw_lat, lat__lte=ne_lat,
            lng__gte=sw_lng, lng__lte=ne_lng
        )

    # 정렬
    if sort == "distance" and lat and lng:
        # 거리 계산은 Python에서 수행 (비동기 쿼리)
        campaigns = [campaign async for campaign in queryset]
        for campaign in campaigns:
            if campaign.lat and campaign.lng:
                campaign.distance = calculate_distance(
                    Decimal(str(lat)), Decimal(str(lng)),
                    campaign.lat, campaign.lng
                )
            else:
                campaign.distance = float('inf')

        # 거리로 정렬
        campaigns.sort(key=lambda c: c.distance)
        total = len(campaigns)
        items = campaigns[offset:offset + limit]
    else:
        # 프로모션 레벨 우선 정렬
        order_by = []
        order_by.append('-promotion_level')  # 항상 프로모션 레벨 우선

        if sort.startswith('-'):
            order_by.append(sort)
        else:
            order_by.append(sort)

        queryset = queryset.order_by(*order_by)
        total = await queryset.acount()
        items = [item async for item in queryset[offset:offset + limit]]

        # 거리 계산 (정렬은 아니지만 표시용)
        if lat and lng:
            for campaign in items:
                if campaign.lat and campaign.lng:
                    campaign.distance = calculate_distance(
                        Decimal(str(lat)), Decimal(str(lng)),
                        campaign.lat, campaign.lng
                    )

    return {
        "total": total,
        "limit": limit,
        "offset": offset,
        "items": items
    }


@router.get("/campaigns/{campaign_id}", response=CampaignOut, summary="캠페인 상세 조회")
async def get_campaign(request, campaign_id: int):
    """캠페인 상세 조회 API (비동기)"""
    campaign = await Campaign.objects.select_related('category').aget(id=campaign_id)
    if not campaign:
        raise HttpError(404, "Campaign not found")
    return campaign

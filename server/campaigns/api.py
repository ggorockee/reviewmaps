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

router = Router(tags=["캠페인 (Campaigns)"])


def get_active_campaign_filter():
    """
    마감되지 않은 캠페인 필터 조건 반환 (Asia/Seoul 기준)

    - apply_deadline이 NULL이면 무기한이므로 표시
    - apply_deadline >= 오늘 날짜 00:00:00 (KST) 이면 표시 (당일까지 보임)
    - apply_deadline < 오늘 날짜 00:00:00 (KST) 이면 숨김

    예시: 마감일이 12/20이고 오늘이 12/20이면 → 보임
          마감일이 12/20이고 오늘이 12/21이면 → 안 보임

    주의: timezone.now()는 UTC 기준이므로, 로컬 타임존(Asia/Seoul)으로 변환 후
          오늘 시작 시간을 계산해야 정확한 필터링이 가능
    """
    # 로컬 타임존(Asia/Seoul) 기준 현재 시간
    now_local = timezone.localtime(timezone.now())
    # 오늘 날짜의 시작 (00:00:00 KST)
    today_start_local = now_local.replace(hour=0, minute=0, second=0, microsecond=0)

    return models.Q(apply_deadline__isnull=True) | models.Q(apply_deadline__gte=today_start_local)


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


@router.get("/", response=CampaignListResponse, summary="캠페인 목록 조회")
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

    # 기본 쿼리: 만료되지 않은 캠페인만 (오늘 날짜 기준, 당일까지 보임)
    queryset = Campaign.objects.select_related('category').filter(get_active_campaign_filter())

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
        # 거리 기반 정렬 (DB 레벨에서 처리)
        # 1순위: promotion_level (내림차순)
        # 2순위: distance (오름차순, NULL은 뒤로)
        # 3순위: pseudo_random (동일 레벨+거리 내 균형 분포)
        # 4순위: created_at (내림차순)

        from django.db.models import F, Case, When, IntegerField, FloatField
        from django.db.models.functions import Coalesce, Power, Sqrt, ACos, Sin, Cos, Radians, Cast
        from decimal import Decimal as D

        # Haversine 공식으로 거리 계산 (km 단위)
        # distance = 2 * R * asin(sqrt(sin²(Δlat/2) + cos(lat1) * cos(lat2) * sin²(Δlng/2)))
        # R = 6371 (지구 반지름 km)

        user_lat = D(str(lat))
        user_lng = D(str(lng))

        # 위도/경도를 라디안으로 변환
        lat1_rad = Radians(user_lat)
        lng1_rad = Radians(user_lng)
        lat2_rad = Radians(F('lat'))
        lng2_rad = Radians(F('lng'))

        # Δlat, Δlng 계산
        dlat = lat2_rad - lat1_rad
        dlng = lng2_rad - lng1_rad

        # Haversine 공식
        # a = sin²(Δlat/2) + cos(lat1) * cos(lat2) * sin²(Δlng/2)
        # c = 2 * atan2(√a, √(1-a))  ≈ 2 * asin(√a) for small distances
        # distance = R * c

        a = (
            Power(Sin(dlat / 2), 2) +
            Cos(lat1_rad) * Cos(lat2_rad) * Power(Sin(dlng / 2), 2)
        )

        # SQLite는 asin을 지원하지 않을 수 있으므로, atan2 사용
        # c = 2 * asin(sqrt(a))를 근사
        # 거리가 짧을 때는 sqrt(a) ≈ sin(c/2)이므로 직접 sqrt(a) 사용
        distance_expr = 2 * 6371 * Sqrt(a)

        # promotion_level NULL 처리 (0으로 간주)
        promotion_level_coalesced = Coalesce(F('promotion_level'), 0)

        # pseudo_random: ID 기반 해시 (균형 분포)
        # Django ORM에서는 직접 hash() 함수를 쓸 수 없으므로 id % 1000 사용
        pseudo_random = F('id') % 1000

        # 거리 NULL 처리: lat 또는 lng가 NULL이면 매우 큰 값으로 설정
        distance_with_null = Case(
            When(lat__isnull=True, then=999999.0),
            When(lng__isnull=True, then=999999.0),
            default=distance_expr,
            output_field=FloatField()
        )

        # Annotate distance
        queryset = queryset.annotate(
            distance=distance_with_null,
            promotion_level_val=promotion_level_coalesced
        )

        # 정렬 적용
        queryset = queryset.order_by(
            '-promotion_level_val',  # 1순위: promotion_level 내림차순
            'distance',              # 2순위: 거리 오름차순 (NULL은 999999로 처리되어 뒤로)
            pseudo_random,           # 3순위: 동일 레벨+거리 내 균형 분포
            '-created_at'            # 4순위: 생성일 내림차순
        )

        total = await queryset.acount()
        items = [item async for item in queryset[offset:offset + limit]]

    else:
        # 프로모션 레벨 우선 정렬
        order_by = []

        # promotion_level NULL 처리
        from django.db.models import F
        from django.db.models.functions import Coalesce
        promotion_level_coalesced = Coalesce(F('promotion_level'), 0)
        pseudo_random = F('id') % 1000

        queryset = queryset.annotate(promotion_level_val=promotion_level_coalesced)

        order_by.append('-promotion_level_val')  # 1순위: 프로모션 레벨 우선
        order_by.append(pseudo_random)           # 2순위: 동일 레벨 내 균형 분포

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


@router.get("/{campaign_id}", response=CampaignOut, summary="캠페인 상세 조회")
async def get_campaign(request, campaign_id: int):
    """
    캠페인 상세 조회 API (비동기)

    - 마감 여부와 상관없이 조회 가능 (링크 공유, 북마크 등 대응)
    - 응답의 is_expired 필드로 마감 여부 확인 가능
    """
    try:
        campaign = await Campaign.objects.select_related('category').aget(id=campaign_id)
        return campaign
    except Campaign.DoesNotExist:
        raise HttpError(404, "캠페인을 찾을 수 없습니다.")

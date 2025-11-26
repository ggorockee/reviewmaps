"""
Keyword Alerts API - Django Ninja 비동기 API
"""
import math
from datetime import timedelta
from typing import Optional
from ninja import Router, Query
from ninja.errors import HttpError
from django.contrib.auth import get_user_model
from django.db.models import Q, Count
from django.utils import timezone
from asgiref.sync import sync_to_async

from .models import Keyword, KeywordAlert, FCMDevice
from .schemas import (
    KeywordCreateRequest,
    KeywordResponse,
    KeywordListResponse,
    KeywordAlertResponse,
    KeywordAlertListResponse,
    MarkAlertReadRequest,
    FCMDeviceRegisterRequest,
    FCMDeviceResponse,
)
from users.utils import get_user_from_token, decode_anonymous_session
from app_config.models import AppSetting


def calculate_distance(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """
    두 좌표 간의 거리 계산 (Haversine formula)
    Returns: 거리 (km)
    """
    R = 6371  # 지구 반지름 (km)

    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lng = math.radians(lng2 - lng1)

    a = math.sin(delta_lat / 2) ** 2 + \
        math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lng / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c

User = get_user_model()
router = Router(tags=["키워드 알람 (Keyword Alerts)"])


def get_auth_info(request):
    """
    요청에서 인증 정보 추출
    Returns: (user, anonymous_session_id)
    """
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        raise HttpError(401, "로그인이 필요합니다.")

    token = auth_header.split(' ')[1]

    # JWT 토큰으로 사용자 인증 시도
    user = get_user_from_token(token)
    if user:
        return user, None

    # 익명 세션 토큰 확인
    session_id = decode_anonymous_session(token)
    if session_id:
        return None, session_id

    raise HttpError(401, "유효하지 않은 토큰입니다.")


@router.post("/keywords", response=KeywordResponse, summary="관심 키워드 등록")
async def create_keyword(request, payload: KeywordCreateRequest):
    """
    관심 키워드 등록 API
    - 사용자 또는 익명 세션에 키워드 등록
    - Authorization: Bearer {token} 필요
    - 활성 키워드 개수 제한 검증
    """
    user, session_id = await sync_to_async(get_auth_info)(request)

    # 키워드 등록 개수 제한 조회
    try:
        setting = await AppSetting.objects.aget(key='keyword_limit', is_active=True)
        max_active = setting.value.get('max_active_keywords', 20)
    except AppSetting.DoesNotExist:
        # 기본값: 활성 키워드 20개
        max_active = 20

    # 현재 활성 키워드 개수 확인
    if user:
        active_count = await Keyword.objects.filter(
            user=user,
            is_active=True
        ).acount()
    else:
        active_count = await Keyword.objects.filter(
            anonymous_session_id=session_id,
            is_active=True
        ).acount()

    # 제한 검증
    if active_count >= max_active:
        raise HttpError(400, f"활성 키워드는 최대 {max_active}개까지 등록할 수 있습니다.")

    # 중복 키워드 확인
    if user:
        exists = await sync_to_async(
            Keyword.objects.filter(
                user=user,
                keyword=payload.keyword,
                is_active=True
            ).exists
        )()
    else:
        exists = await sync_to_async(
            Keyword.objects.filter(
                anonymous_session_id=session_id,
                keyword=payload.keyword,
                is_active=True
            ).exists
        )()

    if exists:
        raise HttpError(400, "이미 등록된 키워드입니다.")

    # 키워드 생성
    keyword = await sync_to_async(Keyword.objects.create)(
        keyword=payload.keyword,
        user=user,
        anonymous_session_id=session_id,
    )

    return {
        "id": keyword.id,
        "keyword": keyword.keyword,
        "is_active": keyword.is_active,
        "created_at": keyword.created_at,
    }


@router.get("/keywords", response=KeywordListResponse, summary="내 키워드 목록")
async def list_keywords(request):
    """
    내 키워드 목록 조회 API
    - 등록한 모든 키워드 목록 반환
    """
    user, session_id = await sync_to_async(get_auth_info)(request)

    # 키워드 조회
    if user:
        keywords = await sync_to_async(list)(
            Keyword.objects.filter(user=user, is_active=True).order_by('-created_at')
        )
    else:
        keywords = await sync_to_async(list)(
            Keyword.objects.filter(anonymous_session_id=session_id, is_active=True).order_by('-created_at')
        )

    return {
        "keywords": [
            {
                "id": k.id,
                "keyword": k.keyword,
                "is_active": k.is_active,
                "created_at": k.created_at,
            }
            for k in keywords
        ]
    }


@router.delete("/keywords/{keyword_id}", summary="키워드 삭제")
async def delete_keyword(request, keyword_id: int):
    """
    키워드 삭제 API
    - 키워드를 DB에서 완전히 삭제 (hard delete)
    - 활성화/비활성화 상태 모두 삭제 가능
    """
    user, session_id = await sync_to_async(get_auth_info)(request)

    # 키워드 조회 (is_active 조건 없이 - 비활성화 상태도 삭제 가능)
    try:
        if user:
            keyword = await sync_to_async(Keyword.objects.get)(
                id=keyword_id,
                user=user,
            )
        else:
            keyword = await sync_to_async(Keyword.objects.get)(
                id=keyword_id,
                anonymous_session_id=session_id,
            )
    except Keyword.DoesNotExist:
        raise HttpError(404, "키워드를 찾을 수 없습니다.")

    # Hard delete (실제 삭제)
    await sync_to_async(keyword.delete)()

    return {"message": "삭제되었습니다."}


@router.patch("/keywords/{keyword_id}/toggle", response=KeywordResponse, summary="키워드 활성화/비활성화 토글")
async def toggle_keyword(request, keyword_id: int):
    """
    키워드 활성화/비활성화 토글 API
    - is_active를 반대로 전환
    - 비활성화 상태인 키워드도 다시 활성화 가능
    """
    user, session_id = await sync_to_async(get_auth_info)(request)

    # 키워드 조회 (is_active 조건 없이 조회)
    try:
        if user:
            keyword = await sync_to_async(Keyword.objects.get)(
                id=keyword_id,
                user=user,
            )
        else:
            keyword = await sync_to_async(Keyword.objects.get)(
                id=keyword_id,
                anonymous_session_id=session_id,
            )
    except Keyword.DoesNotExist:
        raise HttpError(404, "키워드를 찾을 수 없습니다.")

    # 활성화 상태 토글
    keyword.is_active = not keyword.is_active
    await sync_to_async(keyword.save)()

    status_text = "활성화" if keyword.is_active else "비활성화"

    return {
        "id": keyword.id,
        "keyword": keyword.keyword,
        "is_active": keyword.is_active,
        "created_at": keyword.created_at,
    }


@router.get("/alerts", response=KeywordAlertListResponse, summary="내 알람 목록")
async def list_alerts(
    request,
    is_read: bool = None,
    lat: Optional[float] = Query(None, description="사용자 위도 (거리 계산용)"),
    lng: Optional[float] = Query(None, description="사용자 경도 (거리 계산용)"),
    sort: str = Query("created_at", description="정렬 기준: created_at(최신순), distance(거리순)")
):
    """
    내 키워드 알람 목록 조회 API
    - 매칭된 캠페인 알람 목록 반환
    - is_read: 읽음/안읽음 필터 (None이면 전체)
    - lat, lng: 사용자 위치 (거리 계산 및 정렬용)
    - sort: 정렬 기준 (created_at: 최신순, distance: 가까운순)
    """
    user, session_id = await sync_to_async(get_auth_info)(request)

    # 내 키워드 조회
    if user:
        my_keywords = await sync_to_async(list)(
            Keyword.objects.filter(user=user, is_active=True).values_list('id', flat=True)
        )
    else:
        my_keywords = await sync_to_async(list)(
            Keyword.objects.filter(anonymous_session_id=session_id, is_active=True).values_list('id', flat=True)
        )

    # 보관 기간 조회 (AppSetting에서 동적으로 설정 가능)
    try:
        setting = await AppSetting.objects.aget(key='alert_retention', is_active=True)
        retention_days = setting.value.get('retention_days', 30)
    except AppSetting.DoesNotExist:
        # 기본값: 30일
        retention_days = 30

    # 보관 기간 기준 날짜 계산
    retention_threshold = timezone.now() - timedelta(days=retention_days)

    # 알람 조회 (보관 기간 내 데이터만)
    query = KeywordAlert.objects.filter(
        keyword_id__in=my_keywords,
        created_at__gte=retention_threshold
    )
    if is_read is not None:
        query = query.filter(is_read=is_read)

    alerts = await sync_to_async(list)(
        query.select_related('keyword', 'campaign').order_by('-created_at')
    )

    # 안읽은 알람 개수
    unread_count = await sync_to_async(
        KeywordAlert.objects.filter(
            keyword_id__in=my_keywords,
            is_read=False
        ).count
    )()

    # 알람 데이터 변환 (캠페인 위치 정보 포함)
    alert_list = []
    for alert in alerts:
        campaign = alert.campaign
        campaign_lat = float(campaign.lat) if campaign.lat else None
        campaign_lng = float(campaign.lng) if campaign.lng else None

        # 거리 계산
        distance = None
        if lat is not None and lng is not None and campaign_lat and campaign_lng:
            distance = round(calculate_distance(lat, lng, campaign_lat, campaign_lng), 2)

        alert_list.append({
            "id": alert.id,
            "keyword": alert.keyword.keyword,
            "campaign_id": campaign.id,
            "campaign_title": campaign.title,
            "campaign_company": campaign.company,
            "campaign_offer": campaign.offer,
            "campaign_address": campaign.address,
            "campaign_lat": campaign_lat,
            "campaign_lng": campaign_lng,
            "campaign_img_url": campaign.img_url,
            "campaign_platform": campaign.platform,
            "campaign_apply_deadline": campaign.apply_deadline,
            "campaign_content_link": campaign.content_link,
            "campaign_channel": campaign.campaign_channel,
            "matched_field": alert.matched_field,
            "is_read": alert.is_read,
            "created_at": alert.created_at,
            "distance": distance,
        })

    # 거리순 정렬 (distance가 있는 경우만)
    if sort == "distance" and lat is not None and lng is not None:
        # distance가 None인 경우 맨 뒤로
        alert_list.sort(key=lambda x: (x["distance"] is None, x["distance"] or float('inf')))

    return {
        "alerts": alert_list,
        "unread_count": unread_count,
    }


@router.post("/alerts/read", summary="알람 읽음 처리")
async def mark_alerts_read(request, payload: MarkAlertReadRequest):
    """
    알람 읽음 처리 API
    - 여러 알람을 한번에 읽음 처리
    """
    user, session_id = await sync_to_async(get_auth_info)(request)

    # 내 키워드 조회
    if user:
        my_keywords = await sync_to_async(list)(
            Keyword.objects.filter(user=user, is_active=True).values_list('id', flat=True)
        )
    else:
        my_keywords = await sync_to_async(list)(
            Keyword.objects.filter(anonymous_session_id=session_id, is_active=True).values_list('id', flat=True)
        )

    # 알람 읽음 처리
    updated_count = await sync_to_async(
        KeywordAlert.objects.filter(
            id__in=payload.alert_ids,
            keyword_id__in=my_keywords
        ).update
    )(is_read=True)

    return {
        "message": f"{updated_count}개의 알람을 읽음 처리했습니다.",
        "updated_count": updated_count,
    }


@router.post("/fcm/register", response=FCMDeviceResponse, summary="FCM 디바이스 토큰 등록")
async def register_fcm_device(request, payload: FCMDeviceRegisterRequest):
    """
    FCM 디바이스 토큰 등록/갱신 API
    - 푸시 알림을 받기 위한 디바이스 토큰 등록
    - 이미 등록된 토큰이면 갱신
    - Authorization: Bearer {token} 필요
    """
    user, session_id = await sync_to_async(get_auth_info)(request)

    # 유효한 device_type 검증
    if payload.device_type not in ['android', 'ios']:
        raise HttpError(400, "device_type은 'android' 또는 'ios'만 허용됩니다.")

    # 기존 토큰 조회 또는 생성
    def get_or_create_device():
        # 기존 토큰 확인 (동일 토큰)
        try:
            device = FCMDevice.objects.get(fcm_token=payload.fcm_token)
            # 소유자 업데이트 (익명 → 회원 전환 등)
            device.user = user
            device.anonymous_session_id = session_id
            device.device_type = payload.device_type
            device.is_active = True
            device.save()
            return device
        except FCMDevice.DoesNotExist:
            pass

        # 새 디바이스 생성
        device = FCMDevice.objects.create(
            fcm_token=payload.fcm_token,
            user=user,
            anonymous_session_id=session_id,
            device_type=payload.device_type,
            is_active=True
        )
        return device

    device = await sync_to_async(get_or_create_device)()

    return {
        "id": device.id,
        "fcm_token": device.fcm_token,
        "device_type": device.device_type,
        "is_active": device.is_active,
        "created_at": device.created_at,
    }


@router.delete("/fcm/unregister", summary="FCM 디바이스 토큰 해제")
async def unregister_fcm_device(request, fcm_token: str = Query(..., description="해제할 FCM 토큰")):
    """
    FCM 디바이스 토큰 해제 API
    - 푸시 알림 수신 중지
    - 디바이스 비활성화 처리
    """
    user, session_id = await sync_to_async(get_auth_info)(request)

    def deactivate_device():
        try:
            device = FCMDevice.objects.get(fcm_token=fcm_token)
            device.is_active = False
            device.save()
            return True
        except FCMDevice.DoesNotExist:
            return False

    success = await sync_to_async(deactivate_device)()

    if not success:
        raise HttpError(404, "등록된 디바이스를 찾을 수 없습니다.")

    return {"message": "푸시 알림이 해제되었습니다."}

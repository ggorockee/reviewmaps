"""
Keyword Alerts API - Django Ninja 비동기 API
"""
from ninja import Router
from ninja.errors import HttpError
from django.contrib.auth import get_user_model
from django.db.models import Q, Count
from asgiref.sync import sync_to_async

from .models import Keyword, KeywordAlert
from .schemas import (
    KeywordCreateRequest,
    KeywordResponse,
    KeywordListResponse,
    KeywordAlertResponse,
    KeywordAlertListResponse,
    MarkAlertReadRequest,
)
from users.utils import get_user_from_token, decode_anonymous_session

User = get_user_model()
router = Router(tags=["키워드 알람 (Keyword Alerts)"])


def get_auth_info(request):
    """
    요청에서 인증 정보 추출
    Returns: (user, anonymous_session_id)
    """
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        raise HttpError(401, "인증 토큰이 필요합니다.")

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
    """
    user, session_id = await sync_to_async(get_auth_info)(request)

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
    - is_active를 False로 변경 (soft delete)
    """
    user, session_id = await sync_to_async(get_auth_info)(request)

    # 키워드 조회
    try:
        if user:
            keyword = await sync_to_async(Keyword.objects.get)(
                id=keyword_id,
                user=user,
                is_active=True
            )
        else:
            keyword = await sync_to_async(Keyword.objects.get)(
                id=keyword_id,
                anonymous_session_id=session_id,
                is_active=True
            )
    except Keyword.DoesNotExist:
        raise HttpError(404, "키워드를 찾을 수 없습니다.")

    # Soft delete
    keyword.is_active = False
    await sync_to_async(keyword.save)()

    return {"message": "키워드가 삭제되었습니다."}


@router.get("/alerts", response=KeywordAlertListResponse, summary="내 알람 목록")
async def list_alerts(request, is_read: bool = None):
    """
    내 키워드 알람 목록 조회 API
    - 매칭된 캠페인 알람 목록 반환
    - is_read: 읽음/안읽음 필터 (None이면 전체)
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

    # 알람 조회
    query = KeywordAlert.objects.filter(keyword_id__in=my_keywords)
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

    return {
        "alerts": [
            {
                "id": alert.id,
                "keyword": alert.keyword.keyword,
                "campaign_id": alert.campaign.id,
                "campaign_title": alert.campaign.title,
                "matched_field": alert.matched_field,
                "is_read": alert.is_read,
                "created_at": alert.created_at,
            }
            for alert in alerts
        ],
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

"""
Users API - Django Ninja 비동기 API
"""
from ninja import Router
from ninja.errors import HttpError
from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import check_password
from datetime import datetime, timedelta
from django.conf import settings
from asgiref.sync import sync_to_async
from typing import Union

from .schemas import (
    UserSignupRequest,
    UserLoginRequest,
    TokenResponse,
    TokenRefreshRequest,
    AnonymousSessionRequest,
    AnonymousSessionResponse,
    UserResponse,
    UserDetailResponse,
    AnonymousUserResponse,
    ConvertAnonymousRequest,
)
from .utils import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_user_from_token,
    create_anonymous_session_id,
    decode_anonymous_session,
)

User = get_user_model()
router = Router(tags=["인증 (Authentication)"])


@router.post("/signup", response=TokenResponse, summary="회원가입")
async def signup(request, payload: UserSignupRequest):
    """
    회원가입 API
    - email + password로 회원가입
    - 성공 시 access_token과 refresh_token 반환
    """
    # 이메일 중복 확인
    if await sync_to_async(User.objects.filter(email=payload.email).exists)():
        raise HttpError(400, "이미 가입된 이메일입니다.")

    # 사용자 생성
    user = await sync_to_async(User.objects.create_user)(
        email=payload.email,
        password=payload.password,
    )

    # JWT 토큰 생성
    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token(user.id)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }


@router.post("/login", response=TokenResponse, summary="로그인")
async def login(request, payload: UserLoginRequest):
    """
    로그인 API
    - email + password로 로그인
    - 성공 시 access_token과 refresh_token 반환
    """
    # 사용자 조회
    try:
        user = await sync_to_async(User.objects.get)(email=payload.email)
    except User.DoesNotExist:
        raise HttpError(401, "로그인 정보가 올바르지 않습니다.")

    # 비밀번호 확인
    if not await sync_to_async(check_password)(payload.password, user.password):
        raise HttpError(401, "로그인 정보가 올바르지 않습니다.")

    # 활성 사용자 확인
    if not user.is_active:
        raise HttpError(403, "이용이 정지된 계정입니다.")

    # JWT 토큰 생성
    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token(user.id)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }


@router.post("/refresh", response=TokenResponse, summary="토큰 갱신")
async def refresh_token(request, payload: TokenRefreshRequest):
    """
    토큰 갱신 API
    - refresh_token으로 새로운 access_token 발급
    """
    # Refresh token 검증
    token_payload = decode_token(payload.refresh_token)
    if not token_payload or token_payload.get('type') != 'refresh':
        raise HttpError(401, "유효하지 않은 토큰입니다.")

    # 사용자 조회
    user_id = token_payload.get('user_id')
    try:
        user = await sync_to_async(User.objects.get)(id=user_id, is_active=True)
    except User.DoesNotExist:
        raise HttpError(401, "회원 정보를 찾을 수 없습니다.")

    # 새로운 토큰 생성
    access_token = create_access_token(user.id)
    refresh_token_new = create_refresh_token(user.id)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token_new,
        "token_type": "bearer",
    }


@router.post("/anonymous", response=AnonymousSessionResponse, summary="회원가입 없이 시작하기")
async def create_anonymous_session(request, payload: AnonymousSessionRequest = None):
    """
    익명 사용자 세션 생성 API
    - 회원가입 없이 앱 사용 시작
    - 기본값: 168시간(7일) 유효기간의 세션 토큰 발급
    - expire_hours 파라미터로 만료 시간 설정 가능
    """
    # 만료 시간 설정 (파라미터가 없으면 기본값 사용)
    expire_hours = settings.ANONYMOUS_SESSION_EXPIRE_HOURS
    if payload and payload.expire_hours:
        expire_hours = payload.expire_hours

    session_token = create_anonymous_session_id(expire_hours)
    expires_at = datetime.utcnow() + timedelta(hours=expire_hours)

    return {
        "session_token": session_token,
        "expires_at": expires_at,
        "expire_hours": expire_hours,
    }


@router.post("/convert-anonymous", response=TokenResponse, summary="익명 사용자 → 회원 전환")
async def convert_anonymous_to_user(request, payload: ConvertAnonymousRequest):
    """
    익명 사용자를 정식 회원으로 전환
    - 익명 세션 토큰 검증
    - 이메일 + 비밀번호로 회원가입
    - 기존 익명 사용자 데이터 유지 (키워드 알람 등)
    """
    # 익명 세션 검증
    session_id = decode_anonymous_session(payload.session_token)
    if not session_id:
        raise HttpError(401, "유효하지 않은 세션입니다.")

    # 이메일 중복 확인
    if await sync_to_async(User.objects.filter(email=payload.email).exists)():
        raise HttpError(400, "이미 가입된 이메일입니다.")

    # 사용자 생성
    user = await sync_to_async(User.objects.create_user)(
        email=payload.email,
        password=payload.password,
    )

    # 익명 사용자 데이터를 정식 사용자로 마이그레이션
    # 키워드 알람 데이터를 session_id에서 user_id로 변경
    from keyword_alerts.models import Keyword
    migrated_count = await sync_to_async(
        Keyword.objects.filter(
            anonymous_session_id=session_id,
            user__isnull=True
        ).update
    )(user=user, anonymous_session_id=None)

    # JWT 토큰 생성
    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token(user.id)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }


@router.get("/me", response=Union[UserDetailResponse, AnonymousUserResponse], summary="내 정보 조회")
async def get_my_info(request):
    """
    내 정보 조회 API
    - Authorization 헤더의 Bearer token 필요
    - 일반 사용자: 사용자 정보 반환 (email, login_method 등)
    - 익명 사용자: 세션 정보 및 남은 시간 반환
    """
    # Authorization 헤더에서 토큰 추출
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        raise HttpError(401, "로그인이 필요합니다.")

    token = auth_header.split(' ')[1]

    # JWT 토큰으로 일반 사용자 인증 시도
    user = await sync_to_async(get_user_from_token)(token)
    if user:
        return {
            "id": user.id,
            "email": user.email,
            "name": user.name or None,
            "profile_image": user.profile_image or None,
            "is_active": user.is_active,
            "date_joined": user.date_joined,
            "login_method": user.login_method,
        }

    # 익명 세션 토큰 확인
    token_payload = decode_token(token)
    if token_payload and token_payload.get('type') == 'anonymous':
        session_id = token_payload.get('session_id')
        expires_at = datetime.utcfromtimestamp(token_payload.get('exp'))

        # 남은 시간 계산 (시간 단위)
        remaining_seconds = (expires_at - datetime.utcnow()).total_seconds()
        remaining_hours = remaining_seconds / 3600 if remaining_seconds > 0 else 0

        return {
            "session_id": session_id,
            "expires_at": expires_at,
            "remaining_hours": round(remaining_hours, 2),
        }

    raise HttpError(401, "유효하지 않은 토큰입니다.")

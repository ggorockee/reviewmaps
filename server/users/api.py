"""
Users API - Django Ninja 비동기 API
"""
import random
import secrets
from ninja import Router
from ninja.errors import HttpError
from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import check_password
from django.core.mail import send_mail
from datetime import datetime, timedelta
from django.conf import settings
from asgiref.sync import sync_to_async
from typing import Union
from django.utils import timezone

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
    EmailSendCodeRequest,
    EmailSendCodeResponse,
    EmailVerifyCodeRequest,
    EmailVerifyCodeResponse,
    PasswordResetRequest,
    PasswordResetResponse,
    PasswordResetVerifyRequest,
    PasswordResetVerifyResponse,
    PasswordResetConfirmRequest,
    PasswordChangeRequest,
    MessageResponse,
)
from .utils import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_user_from_token,
    create_anonymous_session_id,
    decode_anonymous_session,
)
from .models import EmailVerification

User = get_user_model()
router = Router(tags=["인증 (Authentication)"])


# ===== 이메일 인증 API =====

@router.post("/email/send-code", response=EmailSendCodeResponse, summary="이메일 인증코드 발송")
async def send_email_code(request, payload: EmailSendCodeRequest):
    """
    이메일 인증코드 발송 API
    - 6자리 숫자 인증코드 생성 후 이메일 발송
    - 유효시간: 60분
    - 재발송: 첫 번째는 바로 가능, 이후 60초 대기
    """
    email = payload.email.lower().strip()

    # 이메일 형식 검증
    if '@' not in email or '.' not in email:
        raise HttpError(400, "올바른 이메일 형식이 아닙니다.")

    # 이미 가입된 이메일인지 확인 (email + login_method='email' 조합)
    if await sync_to_async(User.objects.filter(email=email, login_method='email').exists)():
        raise HttpError(400, "이미 가입된 이메일입니다.")

    # 기존 인증 레코드 조회
    existing = await sync_to_async(
        EmailVerification.objects.filter(email=email, is_verified=False).order_by('-created_at').first
    )()

    # 재발송 쿨다운 체크 (첫 번째 재발송은 바로 가능, 두 번째 이후 60초 대기)
    if existing and existing.send_count > 1:
        cooldown_seconds = settings.EMAIL_VERIFICATION_RESEND_COOLDOWN_SECONDS
        time_since_last_sent = (timezone.now() - existing.last_sent_at).total_seconds()
        if time_since_last_sent < cooldown_seconds:
            remaining = int(cooldown_seconds - time_since_last_sent)
            raise HttpError(429, f"{remaining}초 후에 다시 시도해 주세요.")

    # 6자리 인증코드 생성
    code = f"{random.randint(0, 999999):06d}"
    expires_at = timezone.now() + timedelta(minutes=settings.EMAIL_VERIFICATION_EXPIRE_MINUTES)

    # 기존 레코드 업데이트 또는 새로 생성
    if existing:
        existing.code = code
        existing.expires_at = expires_at
        existing.attempts = 0
        existing.send_count += 1
        existing.last_sent_at = timezone.now()
        existing.verification_token = ''
        await sync_to_async(existing.save)()
    else:
        await sync_to_async(EmailVerification.objects.create)(
            email=email,
            code=code,
            expires_at=expires_at,
        )

    # 이메일 발송
    subject = "[ReviewMaps] 이메일 인증코드"
    message = f"""안녕하세요,

ReviewMaps 회원가입을 위한 인증코드입니다.

인증코드: {code}

이 코드는 {settings.EMAIL_VERIFICATION_EXPIRE_MINUTES}분간 유효합니다.
본인이 요청하지 않은 경우 이 메일을 무시해 주세요.

감사합니다.
ReviewMaps 팀
"""

    try:
        await sync_to_async(send_mail)(
            subject=subject,
            message=message,
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[email],
            fail_silently=False,
        )
    except Exception as e:
        raise HttpError(500, "이메일 발송에 실패했습니다. 잠시 후 다시 시도해 주세요.")

    return {
        "message": "인증코드가 발송되었습니다.",
        "expires_in": settings.EMAIL_VERIFICATION_EXPIRE_MINUTES * 60,
    }


@router.post("/email/verify-code", response=EmailVerifyCodeResponse, summary="이메일 인증코드 확인")
async def verify_email_code(request, payload: EmailVerifyCodeRequest):
    """
    이메일 인증코드 확인 API
    - 인증코드 검증 후 verification_token 반환
    - 5회 실패 시 재발송 필요
    """
    email = payload.email.lower().strip()
    code = payload.code.strip()

    # 인증 레코드 조회
    verification = await sync_to_async(
        EmailVerification.objects.filter(email=email, is_verified=False).order_by('-created_at').first
    )()

    if not verification:
        raise HttpError(400, "인증 요청을 찾을 수 없습니다. 인증코드를 다시 요청해 주세요.")

    # 만료 확인
    if timezone.now() > verification.expires_at:
        raise HttpError(400, "인증코드가 만료되었습니다. 다시 요청해 주세요.")

    # 시도 횟수 확인
    if verification.attempts >= settings.EMAIL_VERIFICATION_MAX_ATTEMPTS:
        raise HttpError(429, "인증 시도 횟수를 초과했습니다. 인증코드를 다시 요청해 주세요.")

    # 코드 검증
    if verification.code != code:
        verification.attempts += 1
        await sync_to_async(verification.save)()
        remaining = settings.EMAIL_VERIFICATION_MAX_ATTEMPTS - verification.attempts
        raise HttpError(400, f"인증코드가 일치하지 않습니다. ({remaining}회 남음)")

    # 인증 성공 - verification_token 생성
    verification_token = secrets.token_urlsafe(32)
    verification.is_verified = True
    verification.verification_token = verification_token
    await sync_to_async(verification.save)()

    return {
        "verified": True,
        "verification_token": verification_token,
    }


@router.post("/signup", response=TokenResponse, summary="회원가입")
async def signup(request, payload: UserSignupRequest):
    """
    회원가입 API
    - 이메일 인증 완료 후 회원가입
    - verification_token 필수
    - 비밀번호 8자 이상
    - 성공 시 access_token과 refresh_token 반환
    """
    email = payload.email.lower().strip()

    # 비밀번호 길이 검증 (8자 이상)
    if len(payload.password) < 8:
        raise HttpError(400, "비밀번호는 8자 이상이어야 합니다.")

    # verification_token 검증
    verification = await sync_to_async(
        EmailVerification.objects.filter(
            email=email,
            verification_token=payload.verification_token,
            is_verified=True
        ).first
    )()

    if not verification:
        raise HttpError(400, "이메일 인증이 필요합니다.")

    # 이메일 중복 확인 (email + login_method='email' 조합)
    if await sync_to_async(User.objects.filter(email=email, login_method='email').exists)():
        raise HttpError(400, "이미 가입된 이메일입니다.")

    # 사용자 생성
    user = await sync_to_async(User.objects.create_user)(
        email=email,
        password=payload.password,
        name=payload.name or '',
    )

    # 인증 레코드 삭제 (사용 완료)
    await sync_to_async(verification.delete)()

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


# ===== 비밀번호 재설정 API =====

@router.post("/password/reset-request", response=PasswordResetResponse, summary="비밀번호 재설정 요청")
async def password_reset_request(request, payload: PasswordResetRequest):
    """
    비밀번호 재설정 요청 API
    - 이메일로 6자리 인증코드 발송
    - 가입된 이메일(login_method='email')만 가능
    - 유효시간: 60분
    """
    email = payload.email.lower().strip()

    # 이메일 형식 검증
    if '@' not in email or '.' not in email:
        raise HttpError(400, "올바른 이메일 형식이 아닙니다.")

    # 가입된 이메일인지 확인 (email 로그인만)
    user_exists = await sync_to_async(
        User.objects.filter(email=email, login_method='email').exists
    )()
    
    if not user_exists:
        raise HttpError(404, "가입되지 않은 이메일입니다.")

    # 기존 인증 레코드 조회 (비밀번호 재설정용)
    existing = await sync_to_async(
        EmailVerification.objects.filter(email=email, is_verified=False).order_by('-created_at').first
    )()

    # 재발송 쿨다운 체크
    if existing and existing.send_count > 1:
        cooldown_seconds = settings.EMAIL_VERIFICATION_RESEND_COOLDOWN_SECONDS
        time_since_last_sent = (timezone.now() - existing.last_sent_at).total_seconds()
        if time_since_last_sent < cooldown_seconds:
            remaining = int(cooldown_seconds - time_since_last_sent)
            raise HttpError(429, f"{remaining}초 후에 다시 시도해 주세요.")

    # 6자리 인증코드 생성
    code = f"{random.randint(0, 999999):06d}"
    expires_at = timezone.now() + timedelta(minutes=settings.EMAIL_VERIFICATION_EXPIRE_MINUTES)

    # 기존 레코드 업데이트 또는 새로 생성
    if existing:
        existing.code = code
        existing.expires_at = expires_at
        existing.attempts = 0
        existing.send_count += 1
        existing.last_sent_at = timezone.now()
        existing.verification_token = ''
        existing.is_verified = False
        await sync_to_async(existing.save)()
    else:
        await sync_to_async(EmailVerification.objects.create)(
            email=email,
            code=code,
            expires_at=expires_at,
        )

    # 이메일 발송
    subject = "[ReviewMaps] 비밀번호 재설정 인증코드"
    message = f"""안녕하세요,

ReviewMaps 비밀번호 재설정을 위한 인증코드입니다.

인증코드: {code}

이 코드는 {settings.EMAIL_VERIFICATION_EXPIRE_MINUTES}분간 유효합니다.
본인이 요청하지 않은 경우 이 메일을 무시해 주세요.

감사합니다.
ReviewMaps 팀
"""

    try:
        await sync_to_async(send_mail)(
            subject=subject,
            message=message,
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[email],
            fail_silently=False,
        )
    except Exception as e:
        raise HttpError(500, "이메일 발송에 실패했습니다. 잠시 후 다시 시도해 주세요.")

    return {
        "message": "인증코드가 발송되었습니다.",
        "expires_in": settings.EMAIL_VERIFICATION_EXPIRE_MINUTES * 60,
    }


@router.post("/password/reset-verify", response=PasswordResetVerifyResponse, summary="비밀번호 재설정 인증코드 확인")
async def password_reset_verify(request, payload: PasswordResetVerifyRequest):
    """
    비밀번호 재설정 인증코드 확인 API
    - 인증코드 검증 후 reset_token 반환
    - 5회 실패 시 재요청 필요
    """
    email = payload.email.lower().strip()
    code = payload.code.strip()

    # 인증 레코드 조회
    verification = await sync_to_async(
        EmailVerification.objects.filter(email=email, is_verified=False).order_by('-created_at').first
    )()

    if not verification:
        raise HttpError(404, "인증 요청을 먼저 진행해 주세요.")

    # 만료 확인
    if timezone.now() > verification.expires_at:
        raise HttpError(400, "인증코드가 만료되었습니다. 다시 요청해 주세요.")

    # 시도 횟수 확인
    if verification.attempts >= settings.EMAIL_VERIFICATION_MAX_ATTEMPTS:
        raise HttpError(429, "인증 시도 횟수를 초과했습니다. 다시 요청해 주세요.")

    # 인증코드 확인
    if verification.code != code:
        verification.attempts += 1
        await sync_to_async(verification.save)()
        remaining = settings.EMAIL_VERIFICATION_MAX_ATTEMPTS - verification.attempts
        raise HttpError(400, f"인증코드가 일치하지 않습니다. (남은 시도: {remaining}회)")

    # 인증 성공 - reset_token 발급
    reset_token = secrets.token_urlsafe(32)
    verification.is_verified = True
    verification.verification_token = reset_token
    await sync_to_async(verification.save)()

    return {
        "verified": True,
        "reset_token": reset_token,
    }


@router.post("/password/reset-confirm", response=MessageResponse, summary="비밀번호 재설정 확정")
async def password_reset_confirm(request, payload: PasswordResetConfirmRequest):
    """
    비밀번호 재설정 확정 API
    - reset_token으로 검증 후 새 비밀번호 설정
    - 비밀번호는 8자 이상
    """
    email = payload.email.lower().strip()
    reset_token = payload.reset_token
    new_password = payload.new_password

    # 비밀번호 길이 검증
    if len(new_password) < 8:
        raise HttpError(400, "비밀번호는 8자 이상이어야 합니다.")

    # 인증 레코드 확인
    verification = await sync_to_async(
        EmailVerification.objects.filter(
            email=email,
            is_verified=True,
            verification_token=reset_token
        ).first
    )()

    if not verification:
        raise HttpError(400, "유효하지 않은 인증 토큰입니다.")

    # 만료 확인 (인증 후 60분 이내)
    if timezone.now() > verification.expires_at:
        raise HttpError(400, "인증 토큰이 만료되었습니다. 다시 요청해 주세요.")

    # 사용자 조회
    user = await sync_to_async(
        User.objects.filter(email=email, login_method='email').first
    )()

    if not user:
        raise HttpError(404, "사용자를 찾을 수 없습니다.")

    # 비밀번호 변경
    await sync_to_async(user.set_password)(new_password)
    await sync_to_async(user.save)()

    # 인증 레코드 삭제 (재사용 방지)
    await sync_to_async(verification.delete)()

    return {
        "message": "비밀번호가 성공적으로 변경되었습니다.",
        "success": True,
    }


@router.post("/password/change", response=MessageResponse, summary="비밀번호 변경 (로그인 사용자)")
async def password_change(request, payload: PasswordChangeRequest):
    """
    비밀번호 변경 API (로그인한 사용자)
    - Authorization 헤더 필수
    - 현재 비밀번호 확인 후 새 비밀번호로 변경
    """
    # 인증 확인
    auth_header = request.headers.get('Authorization', '')
    if not auth_header.startswith('Bearer '):
        raise HttpError(401, "인증이 필요합니다.")

    token = auth_header.replace('Bearer ', '')
    user = await get_user_from_token(token)

    if not user:
        raise HttpError(401, "유효하지 않은 토큰입니다.")

    # email 로그인 사용자만 가능
    if user.login_method != 'email':
        raise HttpError(400, "이메일 로그인 사용자만 비밀번호를 변경할 수 있습니다.")

    # 현재 비밀번호 확인
    current_password = payload.current_password
    if not await sync_to_async(check_password)(current_password, user.password):
        raise HttpError(400, "현재 비밀번호가 일치하지 않습니다.")

    # 새 비밀번호 길이 검증
    new_password = payload.new_password
    if len(new_password) < 8:
        raise HttpError(400, "새 비밀번호는 8자 이상이어야 합니다.")

    # 새 비밀번호가 현재 비밀번호와 같은지 확인
    if current_password == new_password:
        raise HttpError(400, "새 비밀번호는 현재 비밀번호와 달라야 합니다.")

    # 비밀번호 변경
    await sync_to_async(user.set_password)(new_password)
    await sync_to_async(user.save)()

    return {
        "message": "비밀번호가 성공적으로 변경되었습니다.",
        "success": True,
    }

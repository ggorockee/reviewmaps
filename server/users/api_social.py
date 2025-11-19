"""
SNS 로그인 API - Kakao, Google, Apple
"""
from ninja import Router
from ninja.errors import HttpError
from django.contrib.auth import get_user_model
from django.db import transaction
from asgiref.sync import sync_to_async

from .schemas import (
    KakaoLoginRequest,
    GoogleLoginRequest,
    AppleLoginRequest,
    SNSLoginResponse,
    UserResponse,
)
from .services import (
    verify_kakao_token,
    verify_google_token,
    verify_apple_token,
)
from .auth import create_access_token, create_refresh_token
from .models import SocialAccount

User = get_user_model()
router = Router(tags=["SNS 로그인"])


@router.post("/kakao", response=SNSLoginResponse, summary="Kakao 로그인")
async def kakao_login(request, payload: KakaoLoginRequest):
    """
    Kakao 로그인 API

    Flutter 앱에서 Kakao SDK로 받은 액세스 토큰을 검증하고,
    사용자 정보를 가져와서 로그인 처리합니다.

    - 처음 로그인: User 생성 + SocialAccount 생성
    - 기존 사용자: SocialAccount 업데이트
    - JWT 토큰 발급 및 반환
    """
    # Kakao 토큰 검증
    kakao_user_info = await verify_kakao_token(payload.access_token)
    if not kakao_user_info:
        raise HttpError(401, "Kakao 토큰 검증에 실패했습니다.")

    kakao_user_id = str(kakao_user_info['id'])
    email = kakao_user_info.get('email', '')

    if not email:
        raise HttpError(400, "Kakao 계정에 이메일이 없습니다. 이메일 제공 동의가 필요합니다.")

    # 트랜잭션으로 사용자 생성/조회 및 소셜 계정 연결
    @transaction.atomic
    def create_or_update_user():
        # 1. SocialAccount로 기존 사용자 확인
        try:
            social_account = SocialAccount.objects.select_related('user').get(
                provider='kakao',
                provider_user_id=kakao_user_id
            )
            user = social_account.user

            # 소셜 계정 정보 업데이트
            social_account.email = email
            social_account.name = kakao_user_info.get('name', '')
            social_account.profile_image = kakao_user_info.get('profile_image', '')
            social_account.access_token = payload.access_token
            social_account.save()

        except SocialAccount.DoesNotExist:
            # 2. 이메일로 기존 사용자 확인
            user, created = User.objects.get_or_create(
                email=email,
                defaults={
                    'login_method': 'kakao',
                }
            )

            # 3. SocialAccount 생성
            social_account = SocialAccount.objects.create(
                user=user,
                provider='kakao',
                provider_user_id=kakao_user_id,
                email=email,
                name=kakao_user_info.get('name', ''),
                profile_image=kakao_user_info.get('profile_image', ''),
                access_token=payload.access_token,
            )

        return user

    user = await sync_to_async(create_or_update_user)()

    # JWT 토큰 생성
    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token(user.id)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "email": user.email,
            "is_active": user.is_active,
            "date_joined": user.date_joined,
            "login_method": user.login_method,
        }
    }


@router.post("/google", response=SNSLoginResponse, summary="Google 로그인")
async def google_login(request, payload: GoogleLoginRequest):
    """
    Google 로그인 API

    Flutter 앱에서 Google SDK로 받은 액세스 토큰을 검증하고,
    사용자 정보를 가져와서 로그인 처리합니다.
    """
    # Google 토큰 검증
    google_user_info = await verify_google_token(payload.access_token)
    if not google_user_info:
        raise HttpError(401, "Google 토큰 검증에 실패했습니다.")

    google_user_id = str(google_user_info['id'])
    email = google_user_info.get('email', '')

    if not email:
        raise HttpError(400, "Google 계정에 이메일이 없습니다.")

    # 트랜잭션으로 사용자 생성/조회 및 소셜 계정 연결
    @transaction.atomic
    def create_or_update_user():
        try:
            social_account = SocialAccount.objects.select_related('user').get(
                provider='google',
                provider_user_id=google_user_id
            )
            user = social_account.user

            # 소셜 계정 정보 업데이트
            social_account.email = email
            social_account.name = google_user_info.get('name', '')
            social_account.profile_image = google_user_info.get('profile_image', '')
            social_account.access_token = payload.access_token
            social_account.save()

        except SocialAccount.DoesNotExist:
            user, created = User.objects.get_or_create(
                email=email,
                defaults={
                    'login_method': 'google',
                }
            )

            social_account = SocialAccount.objects.create(
                user=user,
                provider='google',
                provider_user_id=google_user_id,
                email=email,
                name=google_user_info.get('name', ''),
                profile_image=google_user_info.get('profile_image', ''),
                access_token=payload.access_token,
            )

        return user

    user = await sync_to_async(create_or_update_user)()

    # JWT 토큰 생성
    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token(user.id)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "email": user.email,
            "is_active": user.is_active,
            "date_joined": user.date_joined,
            "login_method": user.login_method,
        }
    }


@router.post("/apple", response=SNSLoginResponse, summary="Apple 로그인")
async def apple_login(request, payload: AppleLoginRequest):
    """
    Apple 로그인 API

    Flutter 앱에서 Apple Sign In으로 받은 identity token을 검증하고,
    사용자 정보를 가져와서 로그인 처리합니다.
    """
    # Apple 토큰 검증
    apple_user_info = await verify_apple_token(
        payload.identity_token,
        payload.authorization_code
    )
    if not apple_user_info:
        raise HttpError(401, "Apple 토큰 검증에 실패했습니다.")

    apple_user_id = str(apple_user_info['id'])
    email = apple_user_info.get('email', '')

    if not email:
        raise HttpError(400, "Apple 계정에 이메일이 없습니다.")

    # 트랜잭션으로 사용자 생성/조회 및 소셜 계정 연결
    @transaction.atomic
    def create_or_update_user():
        try:
            social_account = SocialAccount.objects.select_related('user').get(
                provider='apple',
                provider_user_id=apple_user_id
            )
            user = social_account.user

            # 소셜 계정 정보 업데이트
            social_account.email = email
            # Apple은 이름과 프로필 이미지를 제공하지 않음
            social_account.save()

        except SocialAccount.DoesNotExist:
            user, created = User.objects.get_or_create(
                email=email,
                defaults={
                    'login_method': 'apple',
                }
            )

            social_account = SocialAccount.objects.create(
                user=user,
                provider='apple',
                provider_user_id=apple_user_id,
                email=email,
                name='',  # Apple은 이름을 제공하지 않음
                profile_image='',  # Apple은 프로필 이미지를 제공하지 않음
            )

        return user

    user = await sync_to_async(create_or_update_user)()

    # JWT 토큰 생성
    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token(user.id)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "email": user.email,
            "is_active": user.is_active,
            "date_joined": user.date_joined,
            "login_method": user.login_method,
        }
    }

"""
/me API - 로그인한 사용자 본인 정보 조회/수정
"""
from ninja import Router, Schema
from ninja.errors import HttpError
from django.contrib.auth import get_user_model
from typing import Optional
import logging

from .schemas import UserDetailResponse, SocialAccountInfo, MessageResponse
from .auth import JWTAuth
from .models import SocialAccount

logger = logging.getLogger(__name__)


class DeleteAccountRequest(Schema):
    """회원 탈퇴 요청"""
    reason: Optional[str] = None  # 탈퇴 사유 (선택)

User = get_user_model()
router = Router(tags=["사용자 정보 (본인)"])


@router.get("/me", response=UserDetailResponse, auth=JWTAuth(), summary="내 정보 조회")
async def get_my_info(request):
    """
    로그인한 사용자 본인의 정보 조회

    - JWT 인증 필수
    - 본인의 정보만 조회 가능
    - 연결된 SNS 계정 정보 포함

    Returns:
        UserDetailResponse: 사용자 정보 + 소셜 계정 목록
    """
    user = request.auth  # JWTAuth에서 검증된 사용자

    # 연결된 소셜 계정 조회
    social_accounts_qs = SocialAccount.objects.filter(
        user=user
    ).values('provider', 'email', 'profile_image', 'name', 'created_at')

    # async iteration으로 리스트 변환
    social_accounts = [account async for account in social_accounts_qs]

    social_accounts_list = [
        SocialAccountInfo(
            provider=account['provider'],
            email=account['email'],
            profile_image=account['profile_image'] or None,
            connected_at=account['created_at']
        )
        for account in social_accounts
    ]

    # User 모델에서 직접 name, profile_image 조회
    logger.info(f"[api_me] user_id={user.id}, email={user.email}, name={user.name}, profile_image={user.profile_image}")

    return {
        "id": user.id,
        "email": user.email,
        "name": user.name or None,
        "profile_image": user.profile_image or None,
        "is_active": user.is_active,
        "date_joined": user.date_joined,
        "login_method": user.login_method,
        "social_accounts": social_accounts_list,
    }


class UpdateProfileRequest(Schema):
    """프로필 수정 요청"""
    # 현재는 email과 login_method는 수정 불가
    # 향후 필요 시 추가 필드 정의
    pass


@router.patch("/me", response=UserDetailResponse, auth=JWTAuth(), summary="내 정보 수정")
async def update_my_info(request, payload: UpdateProfileRequest):
    """
    로그인한 사용자 본인의 정보 수정

    - JWT 인증 필수
    - 본인의 정보만 수정 가능
    - 현재는 수정 가능한 필드가 없음 (향후 확장 가능)

    Note:
        - email은 인증과 관련되어 있어 수정 불가
        - login_method는 시스템에서 관리하므로 수정 불가
        - 향후 nickname, profile_image 등 추가 필드 구현 가능

    Returns:
        UserDetailResponse: 업데이트된 사용자 정보
    """
    user = request.auth  # JWTAuth에서 검증된 사용자

    # 연결된 소셜 계정 조회
    social_accounts_qs = SocialAccount.objects.filter(
        user=user
    ).values('provider', 'email', 'profile_image', 'name', 'created_at')

    social_accounts = [account async for account in social_accounts_qs]

    social_accounts_list = [
        SocialAccountInfo(
            provider=account['provider'],
            email=account['email'],
            profile_image=account['profile_image'] or None,
            connected_at=account['created_at']
        )
        for account in social_accounts
    ]

    return {
        "id": user.id,
        "email": user.email,
        "name": user.name or None,
        "profile_image": user.profile_image or None,
        "is_active": user.is_active,
        "date_joined": user.date_joined,
        "login_method": user.login_method,
        "social_accounts": social_accounts_list,
    }


@router.delete("/me", response=MessageResponse, auth=JWTAuth(), summary="회원 탈퇴")
async def delete_my_account(request, payload: DeleteAccountRequest = None):
    """
    회원 탈퇴 (Soft delete)

    - JWT 인증 필수
    - is_active = False로 설정하여 비활성화
    - 연결된 SNS 계정도 함께 삭제
    - 사용자 데이터는 보존 (법적 요구사항 대응)

    Args:
        payload: 탈퇴 사유 (선택)

    Returns:
        MessageResponse: 탈퇴 완료 메시지
    """
    from django.db import transaction

    user = request.auth  # JWTAuth에서 검증된 사용자

    # 탈퇴 사유 로깅 (선택)
    reason = payload.reason if payload else None
    logger.info(f"[회원 탈퇴] user_id={user.id}, email={user.email}, reason={reason}")

    try:
        # 트랜잭션으로 원자성 보장
        with transaction.atomic():
            # 1. 연결된 SNS 계정 삭제
            deleted_count = await SocialAccount.objects.filter(user=user).adelete()
            logger.info(f"[회원 탈퇴] 삭제된 SNS 계정 수: {deleted_count[0]}")

            # 2. 사용자 비활성화 (Soft delete)
            user.is_active = False
            await user.asave(update_fields=['is_active'])

            logger.info(f"[회원 탈퇴] 완료 - user_id={user.id}")

        return MessageResponse(
            message="회원 탈퇴가 완료되었습니다. 그동안 이용해 주셔서 감사합니다.",
            success=True
        )

    except Exception as e:
        logger.error(f"[회원 탈퇴] 실패 - user_id={user.id}, error={str(e)}")
        raise HttpError(500, "회원 탈퇴 처리 중 오류가 발생했습니다.")


# 향후 확장 가능한 API들

# @router.post("/me/change-password", auth=JWTAuth(), summary="비밀번호 변경")
# async def change_password(request, payload: ChangePasswordRequest):
#     """
#     비밀번호 변경
#     - 현재 비밀번호 확인 필수
#     - 새 비밀번호 유효성 검증
#     """
#     pass

# @router.get("/me/social-accounts", auth=JWTAuth(), summary="연결된 SNS 계정 목록")
# async def list_social_accounts(request):
#     """
#     연결된 모든 SNS 계정 목록 조회
#     """
#     pass

# @router.delete("/me/social-accounts/{provider}", auth=JWTAuth(), summary="SNS 계정 연결 해제")
# async def disconnect_social_account(request, provider: str):
#     """
#     특정 SNS 계정 연결 해제
#     - 마지막 로그인 방법인 경우 해제 불가
#     """
#     pass

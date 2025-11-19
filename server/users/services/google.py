"""
Google OAuth 검증 서비스

Google OAuth2 API를 사용하여 액세스 토큰을 검증하고 사용자 정보를 가져옵니다.
공식 문서: https://developers.google.com/identity/protocols/oauth2
"""
import httpx
import logging
from typing import Optional, Dict, Any
from django.conf import settings

logger = logging.getLogger(__name__)


async def verify_google_token(access_token: str) -> Optional[Dict[str, Any]]:
    """
    Google 액세스 토큰 검증 및 사용자 정보 조회

    Args:
        access_token: Google 액세스 토큰 (Flutter SDK로부터 받은 토큰)

    Returns:
        dict: 사용자 정보 딕셔너리
            {
                'id': str,  # Google 사용자 ID (sub)
                'email': str,  # 이메일
                'name': str,  # 이름
                'profile_image': str,  # 프로필 이미지 URL
            }
        None: 검증 실패 시
    """
    try:
        async with httpx.AsyncClient() as client:
            # Google UserInfo API
            # https://www.googleapis.com/oauth2/v2/userinfo
            response = await client.get(
                'https://www.googleapis.com/oauth2/v2/userinfo',
                headers={
                    'Authorization': f'Bearer {access_token}',
                }
            )

            if response.status_code != 200:
                # 토큰이 유효하지 않거나 만료됨
                return None

            data = response.json()

            # 사용자 정보 추출
            user_info = {
                'id': data.get('id'),  # Google 사용자 ID (필수)
                'email': data.get('email', ''),  # 이메일
                'name': data.get('name', ''),  # 이름
                'profile_image': data.get('picture', ''),  # 프로필 이미지
            }

            # 필수 필드 확인
            if not user_info['id']:
                return None

            # 이메일 검증 여부 확인
            if not data.get('verified_email', False):
                # 이메일이 검증되지 않은 경우
                return None

            return user_info

    except Exception as e:
        # 네트워크 에러, JSON 파싱 에러 등
        logger.error(f"Google token verification error: {e}")
        return None


async def get_google_user_info(access_token: str) -> Optional[Dict[str, Any]]:
    """
    Google 사용자 정보 조회 (verify_google_token의 alias)

    Args:
        access_token: Google 액세스 토큰

    Returns:
        dict: 사용자 정보 또는 None
    """
    return await verify_google_token(access_token)

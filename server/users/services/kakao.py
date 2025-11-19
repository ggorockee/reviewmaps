"""
Kakao OAuth 검증 서비스

Kakao REST API를 사용하여 액세스 토큰을 검증하고 사용자 정보를 가져옵니다.
공식 문서: https://developers.kakao.com/docs/latest/ko/kakaologin/rest-api
"""
import httpx
import logging
from typing import Optional, Dict, Any
from django.conf import settings

logger = logging.getLogger(__name__)


async def verify_kakao_token(access_token: str) -> Optional[Dict[str, Any]]:
    """
    Kakao 액세스 토큰 검증 및 사용자 정보 조회

    Args:
        access_token: Kakao 액세스 토큰 (Flutter SDK로부터 받은 토큰)

    Returns:
        dict: 사용자 정보 딕셔너리
            {
                'id': int,  # Kakao 사용자 ID
                'email': str,  # 이메일
                'name': str,  # 이름 (닉네임)
                'profile_image': str,  # 프로필 이미지 URL
            }
        None: 검증 실패 시
    """
    try:
        async with httpx.AsyncClient() as client:
            # Kakao API - 사용자 정보 가져오기
            # https://developers.kakao.com/docs/latest/ko/kakaologin/rest-api#req-user-info
            response = await client.get(
                'https://kapi.kakao.com/v2/user/me',
                headers={
                    'Authorization': f'Bearer {access_token}',
                    'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
                }
            )

            if response.status_code != 200:
                # 토큰이 유효하지 않거나 만료됨
                return None

            data = response.json()

            # 사용자 정보 추출
            user_info = {
                'id': data.get('id'),  # Kakao 사용자 ID (필수)
                'email': data.get('kakao_account', {}).get('email', ''),  # 이메일 (선택)
                'name': data.get('properties', {}).get('nickname', ''),  # 닉네임
                'profile_image': data.get('properties', {}).get('profile_image', ''),  # 프로필 이미지
            }

            # 필수 필드 확인
            if not user_info['id']:
                return None

            return user_info

    except Exception as e:
        # 네트워크 에러, JSON 파싱 에러 등
        logger.error(f"Kakao token verification error: {e}")
        return None


async def get_kakao_user_info(access_token: str) -> Optional[Dict[str, Any]]:
    """
    Kakao 사용자 정보 조회 (verify_kakao_token의 alias)

    Args:
        access_token: Kakao 액세스 토큰

    Returns:
        dict: 사용자 정보 또는 None
    """
    return await verify_kakao_token(access_token)

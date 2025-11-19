"""
Apple OAuth 검증 서비스

Apple Sign In REST API를 사용하여 identity token을 검증하고 사용자 정보를 가져옵니다.
공식 문서: https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api
"""
import httpx
import jwt
import logging
from typing import Optional, Dict, Any
from django.conf import settings
import json

logger = logging.getLogger(__name__)

# Apple 공개 키 캐시 (1시간 유효)
_apple_public_keys_cache: Optional[Dict[str, Any]] = None
_apple_public_keys_cache_time: Optional[float] = None


async def get_apple_public_keys() -> Optional[Dict[str, Any]]:
    """
    Apple 공개 키 가져오기 (캐싱)

    Returns:
        dict: Apple 공개 키 딕셔너리 {kid: public_key}
        None: 실패 시
    """
    global _apple_public_keys_cache, _apple_public_keys_cache_time

    import time
    current_time = time.time()

    # 캐시 유효성 확인 (1시간)
    if _apple_public_keys_cache and _apple_public_keys_cache_time:
        if current_time - _apple_public_keys_cache_time < 3600:
            return _apple_public_keys_cache

    try:
        async with httpx.AsyncClient() as client:
            response = await client.get('https://appleid.apple.com/auth/keys')

            if response.status_code != 200:
                logger.error(f"Failed to fetch Apple public keys: {response.status_code}")
                return None

            data = response.json()
            keys = {}

            # JWK를 공개 키로 변환
            from jwt.algorithms import RSAAlgorithm
            for key_data in data.get('keys', []):
                kid = key_data.get('kid')
                if kid:
                    # RSA 공개 키 생성 (cryptography 패키지 필요)
                    public_key = RSAAlgorithm.from_jwk(json.dumps(key_data))
                    keys[kid] = public_key

            # 캐시 업데이트
            _apple_public_keys_cache = keys
            _apple_public_keys_cache_time = current_time

            logger.info(f"Apple public keys fetched and cached: {len(keys)} keys")
            return keys

    except Exception as e:
        logger.error(f"Error fetching Apple public keys: {e}")
        return None


async def verify_apple_token(identity_token: str, authorization_code: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """
    Apple Identity Token 검증 및 사용자 정보 조회 (프로덕션 ready)

    Apple Sign In의 경우 identity_token (JWT)을 Apple 공개 키로 검증합니다.

    Args:
        identity_token: Apple Identity Token (JWT 형식)
        authorization_code: Apple Authorization Code (선택, 향후 refresh token 구현 시 사용)

    Returns:
        dict: 사용자 정보 딕셔너리
            {
                'id': str,  # Apple 사용자 ID (sub)
                'email': str,  # 이메일
                'name': str,  # 이름 (빈 문자열, Apple은 처음 로그인 시에만 제공)
                'profile_image': str,  # 프로필 이미지 (빈 문자열, Apple은 제공하지 않음)
            }
        None: 검증 실패 시

    Note:
        - Apple 공개 키로 JWT 서명을 검증합니다 (보안 강화)
        - Apple은 프로필 이미지를 제공하지 않습니다.
        - Apple은 이름을 처음 로그인 시에만 제공하며, JWT에는 포함되지 않습니다.
    """
    try:
        # 1. JWT 헤더에서 kid (Key ID) 추출
        unverified_header = jwt.get_unverified_header(identity_token)
        kid = unverified_header.get('kid')

        if not kid:
            logger.warning("Apple JWT missing kid in header")
            return None

        # 2. Apple 공개 키 가져오기
        public_keys = await get_apple_public_keys()
        if not public_keys or kid not in public_keys:
            logger.error(f"Apple public key not found for kid: {kid}")
            return None

        public_key = public_keys[kid]

        # 3. JWT 서명 검증 및 디코딩
        apple_client_id = getattr(settings, 'APPLE_CLIENT_ID', None)

        decoded = jwt.decode(
            identity_token,
            public_key,
            algorithms=['RS256'],
            audience=apple_client_id,
            options={
                'verify_signature': True,  # 서명 검증 활성화
                'verify_exp': True,  # 만료 시간 검증
                'verify_aud': True if apple_client_id else False,  # audience 검증
            }
        )

        # 4. 사용자 정보 추출
        user_info = {
            'id': decoded.get('sub'),  # Apple 사용자 ID (필수)
            'email': decoded.get('email', ''),  # 이메일
            'name': '',  # Apple은 JWT에 이름을 포함하지 않음
            'profile_image': '',  # Apple은 프로필 이미지를 제공하지 않음
        }

        # 5. 필수 필드 확인
        if not user_info['id']:
            logger.warning("Apple JWT missing sub (user ID)")
            return None

        logger.info(f"Apple token verified successfully for user: {user_info['id']}")
        return user_info

    except jwt.ExpiredSignatureError:
        logger.warning("Apple token expired")
        return None
    except jwt.InvalidAudienceError:
        logger.warning("Apple token invalid audience")
        return None
    except jwt.InvalidTokenError as e:
        logger.warning(f"Apple token invalid: {e}")
        return None
    except Exception as e:
        logger.error(f"Apple token verification error: {e}")
        return None


async def get_apple_user_info(identity_token: str, authorization_code: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """
    Apple 사용자 정보 조회 (verify_apple_token의 alias)

    Args:
        identity_token: Apple Identity Token (JWT)
        authorization_code: Apple Authorization Code (선택)

    Returns:
        dict: 사용자 정보 또는 None
    """
    return await verify_apple_token(identity_token, authorization_code)


# verify_apple_token이 이미 프로덕션 ready 구현이므로 제거
# (위의 verify_apple_token 함수가 Apple 공개 키로 서명 검증을 수행합니다)

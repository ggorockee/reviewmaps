"""
Apple OAuth 검증 서비스

Apple Sign In REST API를 사용하여 identity token을 검증하고 사용자 정보를 가져옵니다.
공식 문서: https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api
"""
import httpx
import jwt
from typing import Optional, Dict, Any
from django.conf import settings


async def verify_apple_token(identity_token: str, authorization_code: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """
    Apple Identity Token 검증 및 사용자 정보 조회

    Apple Sign In의 경우 identity_token (JWT)을 직접 검증합니다.
    클라이언트에서 받은 JWT를 디코딩하여 사용자 정보를 추출합니다.

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
        - Apple은 프로필 이미지를 제공하지 않습니다.
        - Apple은 이름을 처음 로그인 시에만 제공하며, JWT에는 포함되지 않습니다.
        - 실제 프로덕션 환경에서는 Apple 공개 키로 JWT 서명을 검증해야 합니다.
    """
    try:
        # JWT 디코딩 (서명 검증 없이 - 개발 단계)
        # 프로덕션에서는 Apple 공개 키로 서명 검증 필요
        # https://appleid.apple.com/auth/keys
        decoded = jwt.decode(
            identity_token,
            options={'verify_signature': False},  # 개발 단계: 서명 검증 비활성화
            audience=getattr(settings, 'APPLE_CLIENT_ID', None),
        )

        # 사용자 정보 추출
        user_info = {
            'id': decoded.get('sub'),  # Apple 사용자 ID (필수)
            'email': decoded.get('email', ''),  # 이메일
            'name': '',  # Apple은 JWT에 이름을 포함하지 않음
            'profile_image': '',  # Apple은 프로필 이미지를 제공하지 않음
        }

        # 필수 필드 확인
        if not user_info['id']:
            return None

        # 이메일 검증 여부 확인
        if not decoded.get('email_verified', False):
            # Apple은 email_verified 대신 is_private_email 사용
            # 사설 이메일 릴레이 주소도 유효한 이메일로 간주
            pass

        return user_info

    except jwt.ExpiredSignatureError:
        # 토큰 만료
        print("Apple token expired")
        return None
    except jwt.InvalidTokenError as e:
        # 유효하지 않은 토큰
        print(f"Apple token invalid: {e}")
        return None
    except Exception as e:
        # 기타 에러
        print(f"Apple token verification error: {e}")
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


# 프로덕션 구현 시 필요한 함수 (향후 구현)
async def verify_apple_token_with_public_key(identity_token: str) -> Optional[Dict[str, Any]]:
    """
    Apple 공개 키로 Identity Token 서명 검증 (프로덕션용)

    Steps:
    1. Apple의 공개 키 가져오기 (https://appleid.apple.com/auth/keys)
    2. JWT 헤더에서 kid (Key ID) 추출
    3. kid에 해당하는 공개 키로 서명 검증
    4. 검증 성공 시 사용자 정보 반환

    현재는 미구현 상태 (개발 단계에서는 서명 검증 생략)
    """
    # TODO: 프로덕션 환경에서 구현 필요
    pass

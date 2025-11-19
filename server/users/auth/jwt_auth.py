"""
JWT 인증 미들웨어
Django Ninja와 함께 사용하기 위한 JWT 기반 인증 시스템
"""
import jwt
from datetime import datetime, timedelta
from typing import Optional
from django.conf import settings
from django.contrib.auth import get_user_model
from ninja.security import HttpBearer

User = get_user_model()


class JWTAuth(HttpBearer):
    """
    Django Ninja용 JWT 인증 클래스

    사용법:
        from users.auth import JWTAuth

        @api.get("/protected", auth=JWTAuth())
        async def protected_route(request):
            user = request.auth  # 인증된 사용자
            return {"email": user.email}
    """

    async def authenticate(self, request, token: str) -> Optional[User]:
        """
        JWT 토큰을 검증하고 사용자 객체를 반환

        Args:
            request: Django request 객체
            token: JWT 액세스 토큰

        Returns:
            User: 인증된 사용자 객체
            None: 인증 실패 시
        """
        try:
            # JWT 토큰 검증
            payload = jwt.decode(
                token,
                settings.JWT_SECRET_KEY,
                algorithms=[settings.JWT_ALGORITHM]
            )

            # 토큰 타입 확인 (access token만 허용)
            if payload.get('type') != 'access':
                return None

            # 만료 시간 확인 (jwt.decode가 자동으로 체크하지만 명시적으로 확인)
            exp = payload.get('exp')
            if exp and datetime.fromtimestamp(exp) < datetime.now():
                return None

            user_id = payload.get('user_id')
            if not user_id:
                return None

            # 사용자 조회 (비동기)
            user = await User.objects.aget(id=user_id, is_active=True)
            return user

        except jwt.ExpiredSignatureError:
            # 토큰 만료
            return None
        except jwt.InvalidTokenError:
            # 유효하지 않은 토큰
            return None
        except User.DoesNotExist:
            # 사용자 없음
            return None
        except Exception:
            # 기타 에러
            return None


def create_access_token(user_id: int) -> str:
    """
    액세스 토큰 생성

    Args:
        user_id: 사용자 ID

    Returns:
        str: JWT 액세스 토큰
    """
    now = datetime.now()
    expire = now + timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES)

    payload = {
        'user_id': user_id,
        'type': 'access',
        'exp': expire,
        'iat': now,
    }

    token = jwt.encode(
        payload,
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM
    )

    return token


def create_refresh_token(user_id: int) -> str:
    """
    리프레시 토큰 생성

    Args:
        user_id: 사용자 ID

    Returns:
        str: JWT 리프레시 토큰
    """
    now = datetime.now()
    expire = now + timedelta(days=settings.JWT_REFRESH_TOKEN_EXPIRE_DAYS)

    payload = {
        'user_id': user_id,
        'type': 'refresh',
        'exp': expire,
        'iat': now,
    }

    token = jwt.encode(
        payload,
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM
    )

    return token


def verify_refresh_token(token: str) -> Optional[int]:
    """
    리프레시 토큰 검증 및 사용자 ID 반환

    Args:
        token: JWT 리프레시 토큰

    Returns:
        int: 사용자 ID
        None: 검증 실패 시
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM]
        )

        # 토큰 타입 확인 (refresh token만 허용)
        if payload.get('type') != 'refresh':
            return None

        user_id = payload.get('user_id')
        return user_id

    except (jwt.ExpiredSignatureError, jwt.InvalidTokenError):
        return None

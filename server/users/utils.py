"""
JWT 토큰 관련 유틸리티 함수
"""
import jwt
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from django.conf import settings
from django.contrib.auth import get_user_model

User = get_user_model()


def create_access_token(user_id: int, user_email: str) -> str:
    """
    Access Token 생성

    Args:
        user_id: 사용자 ID
        user_email: 사용자 이메일

    Returns:
        JWT access token
    """
    expire = datetime.utcnow() + timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        'user_id': user_id,
        'email': user_email,
        'exp': expire,
        'iat': datetime.utcnow(),
        'type': 'access'
    }

    token = jwt.encode(
        payload,
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM
    )
    return token


def create_refresh_token(user_id: int, user_email: str) -> str:
    """
    Refresh Token 생성

    Args:
        user_id: 사용자 ID
        user_email: 사용자 이메일

    Returns:
        JWT refresh token
    """
    expire = datetime.utcnow() + timedelta(days=settings.JWT_REFRESH_TOKEN_EXPIRE_DAYS)
    payload = {
        'user_id': user_id,
        'email': user_email,
        'exp': expire,
        'iat': datetime.utcnow(),
        'type': 'refresh'
    }

    token = jwt.encode(
        payload,
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM
    )
    return token


def decode_token(token: str) -> Optional[Dict[str, Any]]:
    """
    JWT 토큰 디코딩

    Args:
        token: JWT 토큰

    Returns:
        디코딩된 payload 또는 None
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM]
        )
        return payload
    except jwt.ExpiredSignatureError:
        # 토큰 만료
        return None
    except jwt.InvalidTokenError:
        # 유효하지 않은 토큰
        return None


def get_user_from_token(token: str) -> Optional[User]:
    """
    JWT 토큰에서 사용자 객체 가져오기

    Args:
        token: JWT 토큰

    Returns:
        User 객체 또는 None
    """
    payload = decode_token(token)
    if not payload:
        return None

    user_id = payload.get('user_id')
    if not user_id:
        return None

    try:
        user = User.objects.get(id=user_id, is_active=True)
        return user
    except User.DoesNotExist:
        return None


def create_anonymous_session_id(expire_hours: int = None) -> str:
    """
    익명 사용자 세션 ID 생성

    Args:
        expire_hours: 만료 시간 (시간 단위). None이면 기본값 사용

    Returns:
        세션 ID (JWT 형식)
    """
    import uuid
    session_id = str(uuid.uuid4())

    # 만료 시간 설정 (파라미터가 없으면 설정값 사용)
    if expire_hours is None:
        expire_hours = settings.ANONYMOUS_SESSION_EXPIRE_HOURS

    expire = datetime.utcnow() + timedelta(hours=expire_hours)

    payload = {
        'session_id': session_id,
        'exp': expire,
        'iat': datetime.utcnow(),
        'type': 'anonymous'
    }

    token = jwt.encode(
        payload,
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM
    )
    return token


def decode_anonymous_session(token: str) -> Optional[str]:
    """
    익명 세션 토큰 디코딩

    Args:
        token: 익명 세션 토큰

    Returns:
        세션 ID 또는 None
    """
    payload = decode_token(token)
    if not payload or payload.get('type') != 'anonymous':
        return None

    return payload.get('session_id')

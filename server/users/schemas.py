"""
User 관련 Pydantic 스키마
"""
from ninja import Schema
from typing import Optional
from datetime import datetime


class UserSignupRequest(Schema):
    """회원가입 요청"""
    email: str
    password: str


class UserLoginRequest(Schema):
    """로그인 요청"""
    email: str
    password: str


class TokenResponse(Schema):
    """토큰 응답"""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class TokenRefreshRequest(Schema):
    """토큰 갱신 요청"""
    refresh_token: str


class AnonymousSessionResponse(Schema):
    """익명 세션 응답"""
    session_token: str
    expires_at: datetime


class UserResponse(Schema):
    """사용자 정보 응답"""
    id: int
    email: str
    is_active: bool
    date_joined: datetime


class ConvertAnonymousRequest(Schema):
    """익명 사용자 → 회원 전환 요청"""
    session_token: str
    email: str
    password: str

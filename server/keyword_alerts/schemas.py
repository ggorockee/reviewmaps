"""
Keyword Alerts 관련 Pydantic 스키마
"""
from ninja import Schema
from typing import Optional
from datetime import datetime


class KeywordCreateRequest(Schema):
    """키워드 등록 요청"""
    keyword: str


class KeywordResponse(Schema):
    """키워드 응답"""
    id: int
    keyword: str
    is_active: bool
    created_at: datetime


class KeywordListResponse(Schema):
    """키워드 목록 응답"""
    keywords: list[KeywordResponse]


class KeywordAlertResponse(Schema):
    """키워드 알람 응답"""
    id: int
    keyword: str
    campaign_id: int
    campaign_title: str
    matched_field: str
    is_read: bool
    created_at: datetime


class KeywordAlertListResponse(Schema):
    """키워드 알람 목록 응답"""
    alerts: list[KeywordAlertResponse]
    unread_count: int


class MarkAlertReadRequest(Schema):
    """알람 읽음 처리 요청"""
    alert_ids: list[int]

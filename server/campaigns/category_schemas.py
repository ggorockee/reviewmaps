from ninja import Schema
from typing import List
from datetime import datetime


class CategoryOut(Schema):
    """카테고리 출력 스키마"""
    id: int
    name: str
    display_order: int
    created_at: datetime

    class Config:
        from_attributes = True


class CategoryCreate(Schema):
    """카테고리 생성/수정 스키마"""
    name: str
    display_order: int


class RawCategoryOut(Schema):
    """원본 카테고리 출력 스키마"""
    id: int
    raw_text: str
    created_at: datetime

    class Config:
        from_attributes = True


class CategoryMappingOut(Schema):
    """카테고리 매핑 출력 스키마"""
    id: int
    raw_category: RawCategoryOut
    standard_category: CategoryOut

    class Config:
        from_attributes = True


class CategoryMappingCreate(Schema):
    """카테고리 매핑 생성 스키마"""
    raw_category_id: int
    standard_category_id: int


class CategoryOrderUpdate(Schema):
    """카테고리 순서 업데이트 스키마"""
    ordered_ids: List[int]

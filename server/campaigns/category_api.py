from ninja import Router
from ninja.errors import HttpError
from django.shortcuts import get_object_or_404
from django.db import IntegrityError, transaction
from django.http import HttpResponse
from typing import List

from .models import Category, RawCategory, CategoryMapping
from .category_schemas import (
    CategoryOut,
    CategoryCreate,
    RawCategoryOut,
    CategoryMappingOut,
    CategoryMappingCreate,
    CategoryOrderUpdate
)

router = Router(tags=["categories"])


@router.get("/", response=List[CategoryOut], summary="카테고리 목록 조회")
def list_categories(request):
    """표준 카테고리 전체 목록 조회"""
    categories = Category.objects.all().order_by('display_order', 'id')
    return list(categories)


@router.post("/", response={201: CategoryOut}, summary="카테고리 생성")
def create_category(request, payload: CategoryCreate):
    """새로운 표준 카테고리 생성"""
    # 중복 체크
    if Category.objects.filter(name=payload.name).exists():
        raise HttpError(409, "Category with this name already exists")

    category = Category.objects.create(
        name=payload.name,
        display_order=payload.display_order
    )
    return 201, category


# 특정 경로는 파라미터 경로보다 먼저 정의
@router.get("/unmapped-categories", response=List[RawCategoryOut], summary="매핑되지 않은 원본 카테고리 조회")
def list_unmapped_categories(request):
    """매핑되지 않은 원본 카테고리 목록 조회"""
    # CategoryMapping에 없는 RawCategory 조회
    mapped_raw_ids = CategoryMapping.objects.values_list('raw_category_id', flat=True)
    unmapped = RawCategory.objects.exclude(id__in=mapped_raw_ids).order_by('-created_at')
    return list(unmapped)


@router.post("/category-mappings", response=CategoryMappingOut, summary="카테고리 매핑 생성")
def create_category_mapping(request, payload: CategoryMappingCreate):
    """새로운 카테고리 매핑 생성"""
    # raw_category와 standard_category 존재 확인
    raw_category = get_object_or_404(RawCategory, id=payload.raw_category_id)
    standard_category = get_object_or_404(Category, id=payload.standard_category_id)

    # 이미 매핑되어 있는지 확인 (OneToOneField)
    if CategoryMapping.objects.filter(raw_category=raw_category).exists():
        raise HttpError(409, "Mapping failed. This raw category is already mapped.")

    try:
        mapping = CategoryMapping.objects.create(
            raw_category=raw_category,
            standard_category=standard_category
        )
        return mapping
    except IntegrityError:
        raise HttpError(409, "Mapping failed. It might already exist.")


@router.put("/order", response={204: None}, summary="카테고리 순서 일괄 업데이트")
def update_category_order(request, payload: CategoryOrderUpdate):
    """
    카테고리 ID 목록을 순서대로 받아 display_order를 업데이트합니다.
    """
    # 모든 카테고리 ID 가져오기
    all_category_ids = set(Category.objects.values_list('id', flat=True))

    # 요청으로 들어온 ID 목록과 DB의 ID 목록이 일치하는지 확인
    if set(payload.ordered_ids) != all_category_ids:
        raise HttpError(
            400,
            "Provided ID list does not match the existing categories. "
            "Ensure all category IDs are included exactly once."
        )

    # 트랜잭션으로 일괄 업데이트
    with transaction.atomic():
        for index, category_id in enumerate(payload.ordered_ids, start=1):
            Category.objects.filter(id=category_id).update(display_order=index)

    return 204, None


# 파라미터 경로는 마지막에 정의
@router.get("/{category_id}", response=CategoryOut, summary="카테고리 상세 조회")
def get_category(request, category_id: int):
    """특정 표준 카테고리 조회"""
    category = get_object_or_404(Category, id=category_id)
    return category


@router.put("/{category_id}", response=CategoryOut, summary="카테고리 수정")
def update_category(request, category_id: int, payload: CategoryCreate):
    """특정 표준 카테고리 수정"""
    category = get_object_or_404(Category, id=category_id)

    # 다른 카테고리와 이름 중복 체크
    existing = Category.objects.filter(name=payload.name).exclude(id=category_id).first()
    if existing:
        raise HttpError(409, "Category with this name already exists")

    category.name = payload.name
    category.display_order = payload.display_order
    category.save()

    return category


@router.delete("/{category_id}", response={204: None}, summary="카테고리 삭제")
def delete_category(request, category_id: int):
    """특정 표준 카테고리 삭제"""
    category = get_object_or_404(Category, id=category_id)

    try:
        category.delete()
    except IntegrityError:
        raise HttpError(400, "Cannot delete category. It is being used by campaigns or mappings.")

    return 204, None

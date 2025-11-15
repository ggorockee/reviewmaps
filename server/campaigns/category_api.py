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

router = Router(tags=["카테고리 (Categories)"])


@router.get("/", response=List[CategoryOut], summary="카테고리 목록 조회")
async def list_categories(request):
    """표준 카테고리 전체 목록 조회 (비동기)"""
    categories = [cat async for cat in Category.objects.all().order_by('display_order', 'id')]
    return categories


@router.post("/", response={201: CategoryOut}, summary="카테고리 생성")
async def create_category(request, payload: CategoryCreate):
    """새로운 표준 카테고리 생성 (비동기)"""
    # 중복 체크
    exists = await Category.objects.filter(name=payload.name).aexists()
    if exists:
        raise HttpError(409, "Category with this name already exists")

    category = await Category.objects.acreate(
        name=payload.name,
        display_order=payload.display_order
    )
    return 201, category


# 특정 경로는 파라미터 경로보다 먼저 정의
@router.get("/unmapped-categories", response=List[RawCategoryOut], summary="매핑되지 않은 원본 카테고리 조회")
async def list_unmapped_categories(request):
    """매핑되지 않은 원본 카테고리 목록 조회 (비동기)"""
    # CategoryMapping에 없는 RawCategory 조회
    mapped_raw_ids = [id async for id in CategoryMapping.objects.values_list('raw_category_id', flat=True)]
    unmapped = [cat async for cat in RawCategory.objects.exclude(id__in=mapped_raw_ids).order_by('-created_at')]
    return unmapped


@router.post("/category-mappings", response=CategoryMappingOut, summary="카테고리 매핑 생성")
async def create_category_mapping(request, payload: CategoryMappingCreate):
    """새로운 카테고리 매핑 생성 (비동기)"""
    # raw_category와 standard_category 존재 확인
    try:
        raw_category = await RawCategory.objects.aget(id=payload.raw_category_id)
    except RawCategory.DoesNotExist:
        raise HttpError(404, "Raw category not found")

    try:
        standard_category = await Category.objects.aget(id=payload.standard_category_id)
    except Category.DoesNotExist:
        raise HttpError(404, "Standard category not found")

    # 이미 매핑되어 있는지 확인 (OneToOneField)
    exists = await CategoryMapping.objects.filter(raw_category=raw_category).aexists()
    if exists:
        raise HttpError(409, "Mapping failed. This raw category is already mapped.")

    try:
        mapping = await CategoryMapping.objects.acreate(
            raw_category=raw_category,
            standard_category=standard_category
        )
        return mapping
    except IntegrityError:
        raise HttpError(409, "Mapping failed. It might already exist.")


@router.put("/order", response={204: None}, summary="카테고리 순서 일괄 업데이트")
async def update_category_order(request, payload: CategoryOrderUpdate):
    """
    카테고리 ID 목록을 순서대로 받아 display_order를 업데이트합니다 (비동기).
    """
    # 모든 카테고리 ID 가져오기
    all_category_ids = set([id async for id in Category.objects.values_list('id', flat=True)])

    # 요청으로 들어온 ID 목록과 DB의 ID 목록이 일치하는지 확인
    if set(payload.ordered_ids) != all_category_ids:
        raise HttpError(
            400,
            "Provided ID list does not match the existing categories. "
            "Ensure all category IDs are included exactly once."
        )

    # 트랜잭션으로 일괄 업데이트 (비동기)
    from asgiref.sync import sync_to_async

    @sync_to_async
    def update_orders():
        with transaction.atomic():
            for index, category_id in enumerate(payload.ordered_ids, start=1):
                Category.objects.filter(id=category_id).update(display_order=index)

    await update_orders()
    return 204, None


# 파라미터 경로는 마지막에 정의
@router.get("/{category_id}", response=CategoryOut, summary="카테고리 상세 조회")
async def get_category(request, category_id: int):
    """특정 표준 카테고리 조회 (비동기)"""
    try:
        category = await Category.objects.aget(id=category_id)
        return category
    except Category.DoesNotExist:
        raise HttpError(404, "Category not found")


@router.put("/{category_id}", response=CategoryOut, summary="카테고리 수정")
async def update_category(request, category_id: int, payload: CategoryCreate):
    """특정 표준 카테고리 수정 (비동기)"""
    try:
        category = await Category.objects.aget(id=category_id)
    except Category.DoesNotExist:
        raise HttpError(404, "Category not found")

    # 다른 카테고리와 이름 중복 체크
    existing = await Category.objects.filter(name=payload.name).exclude(id=category_id).afirst()
    if existing:
        raise HttpError(409, "Category with this name already exists")

    category.name = payload.name
    category.display_order = payload.display_order
    await category.asave()

    return category


@router.delete("/{category_id}", response={204: None}, summary="카테고리 삭제")
async def delete_category(request, category_id: int):
    """특정 표준 카테고리 삭제 (비동기)"""
    try:
        category = await Category.objects.aget(id=category_id)
    except Category.DoesNotExist:
        raise HttpError(404, "Category not found")

    try:
        await category.adelete()
    except IntegrityError:
        raise HttpError(400, "Cannot delete category. It is being used by campaigns or mappings.")

    return 204, None

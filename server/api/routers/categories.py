from fastapi import APIRouter, Depends, Query, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from typing import Optional

from api.deps import get_db_session
from db import crud
from schemas.campaign import CampaignList, CampaignOut
from schemas import category as CategorySchema

from typing import List

from core.utils import _parse_kst



router = APIRouter(prefix="/categories", tags=["categories"])

@router.get("/", response_model=List[CategorySchema.Category])
async def read_categories(db: AsyncSession = Depends(get_db_session)):
    """표준 카테고리 전체 목록 조회"""
    categories = await crud.get_categories(db)
    return categories

@router.post("/", status_code=status.HTTP_201_CREATED, response_model=CategorySchema.Category)
async def create_category(
    category: CategorySchema.CategoryCreate, db: AsyncSession = Depends(get_db_session)
):
    """새로운 표준 카테고리 생성"""
    existing_category = await crud.get_category_by_name(db, name=category.name)
    if existing_category:
        raise HTTPException(status_code=409, detail="Category with this name already exists")
    return await crud.create_category(db=db, category=category)




@router.get("/unmapped-categories", response_model=List[CategorySchema.RawCategory])
async def read_unmapped_categories(db: AsyncSession = Depends(get_db_session)):
    """매핑되지 않은 원본 카테고리 목록 조회"""
    raw_categories = await crud.get_unmapped_raw_categories(db)
    return raw_categories

@router.post("/category-mappings", response_model=CategorySchema.CategoryMapping)
async def create_mapping(mapping: CategorySchema.CategoryMappingCreate, db: AsyncSession = Depends(get_db_session)):
    """새로운 카테고리 매핑 생성"""
    try:
        return await crud.create_category_mapping(db=db, mapping=mapping)
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Mapping failed. It might already exist.")



















@router.get("/{category_id}", response_model=CategorySchema.Category)
async def read_category(category_id: int, db: AsyncSession = Depends(get_db_session)):
    """특정 표준 카테고리 조회"""
    db_category = await crud.get_category(db, category_id=category_id)
    if db_category is None:
        raise HTTPException(status_code=404, detail="Category not found")
    return db_category


@router.put("/{category_id}", response_model=CategorySchema.Category)
async def update_category(
    category_id: int, category: CategorySchema.CategoryCreate, db: AsyncSession = Depends(get_db_session)
):
    """특정 표준 카테고리 수정"""
    db_category = await crud.get_category(db, category_id=category_id)
    if not db_category:
        raise HTTPException(status_code=404, detail="Category not found")
    
    # 수정하려는 이름이 이미 다른 카테고리에 존재하는지 확인
    existing_category = await crud.get_category_by_name(db, name=category.name)
    if existing_category and existing_category.id != category_id:
        raise HTTPException(status_code=409, detail="Category with this name already exists")
        
    return await crud.update_category(db=db, category_id=category_id, category_update=category)

@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_category(category_id: int, db: AsyncSession = Depends(get_db_session)):
    """특정 표준 카테고리 삭제"""
    db_category = await crud.get_category(db, category_id=category_id)
    if not db_category:
        raise HTTPException(status_code=404, detail="Category not found")
    try:
        await crud.delete_category(db=db, category_id=category_id)
    except IntegrityError:
        # 외래 키 제약 조건 위반 시
        raise HTTPException(status_code=400, detail="Cannot delete category. It is being used by campaigns or mappings.")
    return



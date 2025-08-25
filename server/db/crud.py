from __future__ import annotations
from typing import Optional, Sequence, Tuple
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, update, delete, Date
from datetime import timedelta
from .models import Campaign, Category, RawCategory, CategoryMapping
from schemas.category import CategoryMappingCreate,CategoryCreate



async def get_campaign(db: AsyncSession, campaign_id: int) -> Campaign | None:
    return await db.get(Campaign, campaign_id)


def get_distance_query(lat: float, lng: float):
    """Haversine 공식을 사용하여 SQLAlchemy 쿼리 표현식을 반환합니다."""
    # 지구 반지름 (km)
    R = 6371

    # 라디안 변환
    lat_rad = func.radians(lat)
    lng_rad = func.radians(lng)
    db_lat_rad = func.radians(Campaign.lat)
    db_lng_rad = func.radians(Campaign.lng)

    # 하버사인 공식
    dlat = db_lat_rad - lat_rad
    dlng = db_lng_rad - lng_rad
    a = func.power(func.sin(dlat / 2), 2) + func.cos(lat_rad) * func.cos(db_lat_rad) * func.power(func.sin(dlng / 2), 2)
    c = 2 * func.asin(func.sqrt(a))
    
    # 거리 (km)
    distance = R * c
    return distance.label("distance")



async def list_campaigns(
    db: AsyncSession,
    *,
    category_id: Optional[int] = None, # ✨ 필터 파라미터 추가
    q: Optional[str] = None,
    platform: Optional[str] = None,
    company: Optional[str] = None,
    apply_from: Optional[str] = None, # API 단에서 datetime으로 파싱된 것을 받는다고 가정
    apply_to: Optional[str] = None,
    review_from: Optional[str] = None,
    review_to: Optional[str] = None,
    sw_lat: Optional[float] = None,
    sw_lng: Optional[float] = None,
    ne_lat: Optional[float] = None,
    ne_lng: Optional[float] = None,
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    sort: str = "-created_at",
    limit: int = 20,
    offset: int = 0,
) -> Tuple[int, Sequence[Campaign]]:
    
    # ✨ is_new 로직을 위한 SQL 표현식. PostgreSQL 문법 활용
    # (created_at의 날짜 부분 - 1일)이 (오늘 날짜 - 3일)보다 크거나 같으면 true
    is_new_expression = (
        (func.cast(Campaign.created_at, Date) >= (func.current_date() - timedelta(days=2)))
    ).label("is_new")

    # 공통 필터 적용 함수 (기존 코드와 동일)
    def apply_common_filters(stmt_):
        if q:
            like = f"%{q}%"
            stmt_ = stmt_.where(
                (Campaign.company.ilike(like)) |
                (Campaign.offer.ilike(like)) |
                (Campaign.platform.ilike(like))
            )
        if platform:
            stmt_ = stmt_.where(Campaign.platform == platform)
        if company:
            stmt_ = stmt_.where(Campaign.company.ilike(f"%{company}%"))
        if category_id:
            stmt_ = stmt_.where(Campaign.category_id == category_id)
        if apply_from:
            stmt_ = stmt_.where(Campaign.apply_deadline >= apply_from)
        if apply_to:
            stmt_ = stmt_.where(Campaign.apply_deadline <= apply_to)
        if review_from:
            stmt_ = stmt_.where(Campaign.review_deadline >= review_from)
        if review_to:
            stmt_ = stmt_.where(Campaign.review_deadline <= review_to)
        if all([sw_lat, sw_lng, ne_lat, ne_lng]):
            stmt_ = stmt_.where(
                Campaign.lat.between(sw_lat, ne_lat),
                Campaign.lng.between(sw_lng, ne_lng)
            )
        return stmt_

    # === 거리순 정렬 로직 ===
    if sort == "distance" and lat is not None and lng is not None:
        distance_col = get_distance_query(lat, lng)
        
        # ✨ SELECT 구문에 is_new_expression, Category 추가 및 JOIN
        stmt = select(Campaign, Category, is_new_expression, distance_col)
        stmt = stmt.outerjoin(Category, Campaign.category_id == Category.id)
        stmt = stmt.where(Campaign.lat.isnot(None), Campaign.lng.isnot(None))
        stmt = apply_common_filters(stmt)
        
        # 2. total count 계산 (필터가 모두 적용된 쿼리 기반)
        count_stmt = select(func.count()).select_from(stmt.subquery())
        total = (await db.execute(count_stmt)).scalar_one()

        # 3. 정렬 및 페이지네이션 적용
        stmt = stmt.order_by(distance_col.asc()).limit(limit).offset(offset)
        
        # 4. 쿼리 실행 및 결과 처리
        result = await db.execute(stmt)
        rows = []
        for campaign, category, is_new, distance in result.all():
            campaign.is_new = is_new
            campaign.distance = distance
            campaign.category = category
            rows.append(campaign)
        
        return total, rows

    # === 일반 정렬 로직 ===
    else:
        # ✨ SELECT 구문에 is_new_expression, Category 추가 및 JOIN
        stmt = select(Campaign, Category, is_new_expression)
        stmt = stmt.outerjoin(Category, Campaign.category_id == Category.id)
        stmt = apply_common_filters(stmt)

        # 2. total count 계산 (필터가 모두 적용된 쿼리 기반)
        count_stmt = select(func.count()).select_from(stmt.subquery())
        total = (await db.execute(count_stmt)).scalar_one()

        # 3. 정렬 로직 적용
        sort_map = {
            "created_at": Campaign.created_at,
            "updated_at": Campaign.updated_at,
            "apply_deadline": Campaign.apply_deadline,
            "review_deadline": Campaign.review_deadline,
        }
        desc = sort.startswith("-")
        key = sort[1:] if desc else sort
        sort_col = sort_map.get(key, Campaign.created_at)
        
        stmt = stmt.order_by(sort_col.desc() if desc else sort_col.asc())
        
        stmt = stmt.limit(limit).offset(offset)
        result = await db.execute(stmt)
        rows = []
        # ✨ 결과 처리 로직 수정
        for campaign, category, is_new in result.all():
            campaign.is_new = is_new
            campaign.category = category
            rows.append(campaign)
        
        return total, rows


async def get_categories(db: AsyncSession) -> Sequence[Category]:
    """모든 표준 카테고리 목록을 조회합니다."""
    stmt = select(Category).order_by(Category.name)
    result = await db.execute(stmt)
    return result.scalars().all()

async def get_category(db: AsyncSession, category_id: int) -> Category | None:
    """ID로 단일 표준 카테고리를 조회합니다."""
    return await db.get(Category, category_id)

async def get_category_by_name(db: AsyncSession, name: str) -> Category | None:
    """이름으로 단일 표준 카테고리를 조회합니다."""
    stmt = select(Category).where(Category.name == name)
    result = await db.execute(stmt)
    return result.scalars().first()

async def create_category(db: AsyncSession, category: CategoryCreate) -> Category:
    """새로운 표준 카테고리를 생성합니다."""
    db_category = Category(name=category.name)
    db.add(db_category)
    await db.commit()
    await db.refresh(db_category)
    return db_category


async def update_category(db: AsyncSession, category_id: int, category_update: CategoryCreate) -> Category | None:
    """표준 카테고리 정보를 수정합니다."""
    # SQLAlchemy 2.0 style update
    stmt = (
        update(Category)
        .where(Category.id == category_id)
        .values(name=category_update.name)
        .returning(Category)
    )
    result = await db.execute(stmt)
    await db.commit()
    return result.scalars().first()

async def delete_category(db: AsyncSession, category_id: int) -> int:
    """표준 카테고리를 삭제합니다."""
    stmt = delete(Category).where(Category.id == category_id)
    result = await db.execute(stmt)
    await db.commit()
    return result.rowcount # 삭제된 행의 수를 반환 (0 또는 1)

async def get_unmapped_raw_categories(db: AsyncSession):
    """아직 매핑되지 않은 원본 카테고리 목록을 조회합니다."""
    # raw_categories 테이블과 category_mappings 테이블을 LEFT JOIN
    # 매핑 정보가 없는(m.id IS NULL) 것들만 필터링
    stmt = (
        select(RawCategory)
        .outerjoin(CategoryMapping, RawCategory.id == CategoryMapping.raw_category_id)
        .filter(CategoryMapping.id.is_(None))
        .order_by(RawCategory.created_at.desc())
    )
    result = await db.execute(stmt)
    return result.scalars().all()
    
async def create_category_mapping(db: AsyncSession, mapping: CategoryMappingCreate):
    """새로운 카테고리 매핑을 생성합니다."""
    db_mapping = CategoryMapping(
        raw_category_id=mapping.raw_category_id,
        standard_category_id=mapping.standard_category_id,
    )
    db.add(db_mapping)
    await db.commit()
    await db.refresh(db_mapping)
    return db_mapping
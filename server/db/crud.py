from __future__ import annotations
from typing import Optional, Sequence, Tuple
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from db.models import Campaign



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
        
        # 1. 데이터 조회 쿼리 생성
        stmt = select(Campaign, distance_col)
        # 1-1. 거리 계산을 위해 좌표가 있는 캠페인만 필터링
        stmt = stmt.where(Campaign.lat.isnot(None), Campaign.lng.isnot(None))
        # 1-2. 공통 필터 적용
        stmt = apply_common_filters(stmt)
        
        # 2. total count 계산 (필터가 모두 적용된 쿼리 기반)
        count_stmt = select(func.count()).select_from(stmt.subquery())
        total = (await db.execute(count_stmt)).scalar_one()

        # 3. 정렬 및 페이지네이션 적용
        stmt = stmt.order_by(distance_col.asc()).limit(limit).offset(offset)
        
        # 4. 쿼리 실행 및 결과 처리
        result = await db.execute(stmt)
        rows = []
        for campaign, distance in result.all():
            campaign.distance = distance  # 모델 객체에 동적으로 거리 정보 추가
            rows.append(campaign)
        
        return total, rows

    # === 일반 정렬 로직 ===
    else:
        # 1. 데이터 조회 쿼리 생성
        stmt = select(Campaign)
        # 1-1. 공통 필터 적용
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
        
        # 4. 페이지네이션 적용 및 쿼리 실행
        stmt = stmt.limit(limit).offset(offset)
        rows = (await db.execute(stmt)).scalars().all()
        
        return total, rows

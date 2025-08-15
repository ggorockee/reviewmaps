from __future__ import annotations
from typing import Optional, Sequence, Tuple
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from db.models import Campaign

async def list_campaigns(
    db: AsyncSession,
    *,
    q: Optional[str] = None,
    platform: Optional[str] = None,
    company: Optional[str] = None,
    apply_from: Optional[str] = None,
    apply_to: Optional[str] = None,
    review_from: Optional[str] = None,
    review_to: Optional[str] = None,
    sort: str = "-created_at",
    limit: int = 20,
    offset: int = 0,
) -> Tuple[int, Sequence[Campaign]]:
    # 공통 필터 적용 함수
    def apply_filters(stmt_):
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
        return stmt_

    # 카운트
    count_stmt = apply_filters(select(func.count()).select_from(Campaign))
    total = (await db.execute(count_stmt)).scalar_one()

    # 정렬
    sort_map = {
        "created_at": Campaign.created_at,
        "updated_at": Campaign.updated_at,
        "apply_deadline": Campaign.apply_deadline,
        "review_deadline": Campaign.review_deadline,
        "company": Campaign.company,
        "platform": Campaign.platform,
    }
    desc = sort.startswith("-")
    key = sort[1:] if desc else sort
    col = sort_map.get(key, Campaign.created_at)

    # 데이터
    stmt = apply_filters(select(Campaign)).order_by(col.desc() if desc else col.asc()).limit(limit).offset(offset)
    rows = (await db.execute(stmt)).scalars().all()
    return total, rows

async def get_campaign(db: AsyncSession, campaign_id: int) -> Campaign | None:
    return await db.get(Campaign, campaign_id)

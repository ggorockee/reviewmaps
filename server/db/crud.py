from __future__ import annotations
from typing import Optional, Sequence, Tuple, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, update, delete, Date, case, or_, and_
from datetime import timedelta, date
from .models import Campaign, Category, RawCategory, CategoryMapping
from schemas.category import CategoryMappingCreate,CategoryCreate


import re



# --- offer 정규화 유틸 ---
_NUM_UNIT_PAT = re.compile(
    r'(?P<num>\d+)\s*(?P<unit>개월|월|주|일|시간|분|회|회차|인|명|대|병|장|팩|개)'
)

def _normalize_money_variants(value: int) -> list[str]:
    """정수 금액 -> 다양한 문자열 표현(숫자/쉼표/만원 단위) 목록"""
    variants = [f"{value}", f"{value:,}"]
    if value % 10000 == 0:
        man = value // 10000
        variants += [f"{man}만", f"{man}만원"]
    return variants


def _extract_money_value(s: str) -> int | None:
    """'40,000'/'40000'/'4만'/'4만원' 등에서 금액(원) 뽑기."""
    s = s.strip()
    # 한글 '만/만원' 케이스
    m = re.match(r'^(\d+)\s*만(원)?$', s)
    if m:
        return int(m.group(1)) * 10000
    # 숫자만/쉼표 숫자
    digits = re.sub(r'\D', '', s)
    return int(digits) if digits else None


def build_offer_predicates(offer_input: str, column):
    """
    offer 입력을 의미 단위로 나눠서,
    각 단위를 (여러 표현 OR)로 만들고, 전체는 AND로 결합하기 위한 predicate 리스트를 반환.
    사용 예: for pred in build_offer_predicates(...): stmt = stmt.where(pred)
    """
    if not offer_input or not offer_input.strip():
        return []

    terms = [t for t in re.split(r'\s+', offer_input.strip()) if t]
    predicates = []

    for term in terms:
        or_variants = []

        # 1) 금액 후보
        money = _extract_money_value(term)
        if money:
            for v in _normalize_money_variants(money):
                or_variants.append(column.ilike(f"%{v}%"))
            # 예: "4만"만 적어도 '40,000'과 매칭되도록 원본 term 자체도 포함
            or_variants.append(column.ilike(f"%{term}%"))

        # 2) 수량/기간 (2개월, 10회, 2인, 3주, 30분, 2시간 등)
        m = _NUM_UNIT_PAT.fullmatch(term)
        if m:
            n = m.group('num')
            u = m.group('unit')
            # 동의어/표현 다양화
            unit_alias = {
                '개월': ['개월', '달', '월'],
                '월':   ['월', '개월', '달'],
                '주':   ['주'],
                '일':   ['일'],
                '시간': ['시간', '시간권'],
                '분':   ['분'],
                '회':   ['회', '회차'],
                '회차': ['회차', '회'],
                '인':   ['인', '명'],
                '명':   ['명', '인'],
                '대':   ['대'],
                '병':   ['병'],
                '장':   ['장'],
                '팩':   ['팩'],
                '개':   ['개'],
            }.get(u, [u])

            for ua in unit_alias:
                # 공백 유무 모두
                or_variants.append(column.ilike(f"%{n}{ua}%"))
                or_variants.append(column.ilike(f"%{n} {ua}%"))
            # 원본 그대로
            or_variants.append(column.ilike(f"%{term}%"))

        # 3) 일반 키워드 (헬스장, PT, 커플, 이용권 등)
        #    숫자/단위/금액으로 잡히지 않았다면 키워드로 처리
        if not or_variants:
            # PT 같이 대소문자 섞이는 건 ILIKE로 충분
            or_variants.append(column.ilike(f"%{term}%"))

            # 가벼운 동의어 추가 (필요 시 확장)
            synonym_map = {
                '헬스장': ['헬스장', '헬스', '피트니스', '짐', 'GYM', 'fitness'],
                'PT':    ['PT', '피티', '퍼스널트레이닝', '퍼스널', 'personal training'],
                '커플':  ['커플', '2인', '두명'],
                '이용권': ['이용권', '이용 쿠폰', '이용권한', '이용권증정'],
            }
            if term in synonym_map:
                for syn in synonym_map[term]:
                    or_variants.append(column.ilike(f"%{syn}%"))

        # 그룹(표현들)을 OR로 묶고, 그룹 간은 AND
        predicates.append(or_(*or_variants))

    return predicates


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
    # ✅ 항상 적용할 '오늘 이후' 날짜 필터 (KST에서 계산된 date를 라우터가 전달)
    apply_from_date: Optional[date] = None,

    # --- 새로운 필터 파라미터 ---
    region: Optional[str] = None,
    offer: Optional[str] = None,  # 오퍼(텍스트) 부분검색
    campaign_type: Optional[str] = None,
    campaign_channel: Optional[str] = None,

    # 다양화(플랫폼 쏠림 방지)
    diversify: Optional[str] = None,  # 'platform' 사용 시 플랫폼별 cap 적용
    platform_cap: int = 5,

    # --- 기존 필터 ---
    category_id: Optional[int] = None,
    q: Optional[str] = None,
    platform: Optional[str] = None,
    company: Optional[str] = None,
    apply_from: Optional[str] = None,  # (선택) 구형 파라미터: 시간단위 비교
    apply_to: Optional[str] = None,
    review_from: Optional[str] = None,
    review_to: Optional[str] = None,

    # 지도/거리
    sw_lat: Optional[float] = None,
    sw_lng: Optional[float] = None,
    ne_lat: Optional[float] = None,
    ne_lng: Optional[float] = None,
    lat: Optional[float] = None,
    lng: Optional[float] = None,

    # 정렬/페이징
    sort: str = "-created_at",
    limit: int = 20,
    offset: int = 0,
) -> Tuple[int, Sequence[Campaign]]:

    # ✨ is_new: 최근 2일 이내 생성
    is_new_expression = (
        (func.cast(Campaign.created_at, Date) >= (func.current_date() - timedelta(days=2)))
    ).label("is_new")

    # 공통 필터
    def apply_common_filters(stmt_):
        if q:
            like = f"%{q}%"
            stmt_ = stmt_.where(
                or_(
                    Campaign.company.ilike(like),
                    Campaign.offer.ilike(like),
                    Campaign.platform.ilike(like),
                    Campaign.title.ilike(like),
                )
            )
        if platform:
            stmt_ = stmt_.where(Campaign.platform == platform)
        if company:
            stmt_ = stmt_.where(Campaign.company.ilike(f"%{company}%"))

        # 지역/주소/제목 토큰 검색
        if region:
            tokens = [t.strip() for t in region.split() if t.strip()]
            for token in tokens:
                like = f"%{token}%"
                stmt_ = stmt_.where(
                    (Campaign.region.ilike(like)) | (Campaign.address.ilike(like)) | (Campaign.title.ilike(like))
                )

        # 오퍼(금액/단위/키워드 파서)
        if offer:
            for pred in build_offer_predicates(offer, Campaign.offer):
                stmt_ = stmt_.where(pred)

        if campaign_type:
            stmt_ = stmt_.where(Campaign.campaign_type == campaign_type)

        if campaign_channel:
            tokens = [t.strip() for t in campaign_channel.split(",") if t.strip()]
            if tokens:
                stmt_ = stmt_.where(or_(*[Campaign.campaign_channel.ilike(f"%{t}%") for t in tokens]))

        if category_id:
            stmt_ = stmt_.where(Campaign.category_id == category_id)

        # ✅ 항상 적용되는 '오늘 이후' 필터 (date 기준)
        if apply_from_date:
            stmt_ = stmt_.where(func.cast(Campaign.apply_deadline, Date) >= apply_from_date)

        # (선택) 구형 파라미터가 온 경우: 시간 단위로 추가 적용 가능
        if apply_from:
            stmt_ = stmt_.where(Campaign.apply_deadline >= apply_from)
        if apply_to:
            stmt_ = stmt_.where(Campaign.apply_deadline <= apply_to)

        if review_from:
            stmt_ = stmt_.where(Campaign.review_deadline >= review_from)
        if review_to:
            stmt_ = stmt_.where(Campaign.review_deadline <= review_to)

        # BBox
        if None not in (sw_lat, sw_lng, ne_lat, ne_lng):
            lat_min, lat_max = sorted([sw_lat, ne_lat])
            lng_min, lng_max = sorted([sw_lng, ne_lng])
            stmt_ = stmt_.where(
                Campaign.lat.between(lat_min, lat_max),
                Campaign.lng.between(lng_min, lng_max)
            )
        return stmt_

    # === 거리순 정렬 ===
    if sort == "distance" and lat is not None and lng is not None:
        distance_col = get_distance_query(lat, lng)

        stmt = (
            select(Campaign, Category, is_new_expression, distance_col)
            .outerjoin(Category, Campaign.category_id == Category.id)
        )
        stmt = apply_common_filters(stmt)

        count_stmt = select(func.count()).select_from(stmt.subquery())
        total = (await db.execute(count_stmt)).scalar_one()

        try:
            order_by_clause = (
                distance_col.asc().nulls_last(),
                Campaign.created_at.desc(),
            )
        except Exception:
            order_by_clause = (
                case((distance_col.is_(None), 1), else_=0),
                distance_col.asc(),
                Campaign.created_at.desc(),
            )

        stmt = stmt.order_by(*order_by_clause).limit(limit).offset(offset)
        result = await db.execute(stmt)
        rows = []
        for campaign, category, is_new, distance in result.all():
            campaign.is_new = is_new
            campaign.distance = distance
            campaign.category = category
            rows.append(campaign)
        return total, rows

    # === 일반 정렬 (+ 선택적 다양화) ===
    # 기본 셀렉트
    base_stmt = (
        select(Campaign, Category, is_new_expression)
        .outerjoin(Category, Campaign.category_id == Category.id)
    )
    base_stmt = apply_common_filters(base_stmt)

    # 🔹 플랫폼 다양화 모드: 플랫폼별 최신순 상한 cap
    if diversify == "platform":
        # 플랫폼별 row_number
        rn_base = (
            select(
                Campaign.id.label("id"),
                Campaign.created_at.label("created_at"),
                Campaign.platform.label("platform"),
                is_new_expression.label("is_new"),
                func.row_number().over(
                    partition_by=Campaign.platform,
                    order_by=Campaign.created_at.desc()
                ).label("rn")
            )
            .select_from(Campaign)
            .outerjoin(Category, Campaign.category_id == Category.id)
        )
        rn_base = apply_common_filters(rn_base)
        subq = rn_base.subquery()

        # 플랫폼당 cap 이하만
        filtered = select(subq).where(subq.c.rn <= platform_cap)

        # total
        total = (await db.execute(select(func.count()).select_from(filtered.subquery()))).scalar_one()

        # 최신순으로 아이디만 뽑아 페이징
        id_rows = await db.execute(
            filtered.order_by(subq.c.created_at.desc()).limit(limit).offset(offset)
        )
        ids = [row.id for row in id_rows.all()]
        if not ids:
            return 0, []

        # 실제 객체 재조회
        rows_stmt = (
            select(Campaign, Category, is_new_expression)
            .outerjoin(Category, Campaign.category_id == Category.id)
            .where(Campaign.id.in_(ids))
        )
        result = await db.execute(rows_stmt)
        rows = []
        order_map = {i: k for k, i in enumerate(ids)}
        for campaign, category, is_new in result.all():
            campaign.is_new = is_new
            campaign.category = category
            rows.append(campaign)
        rows.sort(key=lambda c: order_map.get(c.id, 10**9))
        return total, rows

    # 🔸 다양화 OFF: 기존 정렬대로
    sort_map = {
        "created_at": Campaign.created_at,
        "updated_at": Campaign.updated_at,
        "apply_deadline": Campaign.apply_deadline,
        "review_deadline": Campaign.review_deadline,
    }
    desc = sort.startswith("-")
    key = sort[1:] if desc else sort
    sort_col = sort_map.get(key, Campaign.created_at)

    stmt = base_stmt.order_by(sort_col.desc() if desc else sort_col.asc()).limit(limit).offset(offset)
    result = await db.execute(stmt)

    count_stmt = select(func.count()).select_from(base_stmt.subquery())
    total = (await db.execute(count_stmt)).scalar_one()

    rows = []
    for campaign, category, is_new in result.all():
        campaign.is_new = is_new
        campaign.category = category
        rows.append(campaign)
    return total, rows


async def get_categories(db: AsyncSession) -> Sequence[Category]:
    """모든 표준 카테고리 목록을 조회합니다."""
    stmt = select(Category).order_by(Category.display_order, Category.name)
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

async def update_category_order(db: AsyncSession, ordered_ids: List[int]) -> int:
    """
    제공된 ID 목록 순서대로 카테고리의 display_order를 일괄 업데이트합니다.
    SQL의 CASE 문을 사용하여 한 번의 쿼리로 효율적으로 처리합니다.
    """
    if not ordered_ids:
        return 0

    # ID 목록을 기반으로 CASE 문을 생성
    # 예: CASE WHEN id=3 THEN 1 WHEN id=1 THEN 2 ... END
    case_statement = case(
        {category_id: index + 1 for index, category_id in enumerate(ordered_ids)},
        value=Category.id,
    )

    # 일괄 업데이트 쿼리 실행
    stmt = (
        update(Category)
        .where(Category.id.in_(ordered_ids))
        .values(display_order=case_statement)
    )
    result = await db.execute(stmt)
    await db.commit()

    return result.rowcount # 업데이트된 행의 수를 반환
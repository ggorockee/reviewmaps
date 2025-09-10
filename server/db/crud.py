from __future__ import annotations
from typing import Optional, Sequence, Tuple, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, update, delete, Date, case, or_, and_, text
from datetime import timedelta
from .models import Campaign, Category, RawCategory, CategoryMapping
from schemas.category import CategoryMappingCreate,CategoryCreate


import re



# --- offer ?�규???�틸 ---
_NUM_UNIT_PAT = re.compile(
    r'(?P<num>\d+)\s*(?P<unit>개월|??�????�간|�????�차|??�??�|�?????�?'
)

def _normalize_money_variants(value: int) -> list[str]:
    """?�수 금액 -> ?�양??문자???�현(?�자/?�표/만원 ?�위) 목록"""
    variants = [f"{value}", f"{value:,}"]
    if value % 10000 == 0:
        man = value // 10000
        variants += [f"{man}�?, f"{man}만원"]
    return variants


def _extract_money_value(s: str) -> int | None:
    """'40,000'/'40000'/'4�?/'4만원' ?�에??금액(?? 뽑기."""
    s = s.strip()
    # ?��? '�?만원' 케?�스
    m = re.match(r'^(\d+)\s*�????$', s)
    if m:
        return int(m.group(1)) * 10000
    # ?�자�??�표 ?�자
    digits = re.sub(r'\D', '', s)
    return int(digits) if digits else None


def build_offer_predicates(offer_input: str, column):
    """
    offer ?�력???��? ?�위�??�눠??
    �??�위�?(?�러 ?�현 OR)�?만들�? ?�체??AND�?결합?�기 ?�한 predicate 리스?��? 반환.
    ?�용 ?? for pred in build_offer_predicates(...): stmt = stmt.where(pred)
    """
    if not offer_input or not offer_input.strip():
        return []

    terms = [t for t in re.split(r'\s+', offer_input.strip()) if t]
    predicates = []

    for term in terms:
        or_variants = []

        # 1) 금액 ?�보
        money = _extract_money_value(term)
        if money:
            for v in _normalize_money_variants(money):
                or_variants.append(column.ilike(f"%{v}%"))
            # ?? "4�?�??�어??'40,000'�?매칭?�도�??�본 term ?�체???�함
            or_variants.append(column.ilike(f"%{term}%"))

        # 2) ?�량/기간 (2개월, 10?? 2?? 3�? 30�? 2?�간 ??
        m = _NUM_UNIT_PAT.fullmatch(term)
        if m:
            n = m.group('num')
            u = m.group('unit')
            # ?�의???�현 ?�양??
            unit_alias = {
                '개월': ['개월', '??, '??],
                '??:   ['??, '개월', '??],
                '�?:   ['�?],
                '??:   ['??],
                '?�간': ['?�간', '?�간�?],
                '�?:   ['�?],
                '??:   ['??, '?�차'],
                '?�차': ['?�차', '??],
                '??:   ['??, '�?],
                '�?:   ['�?, '??],
                '?�':   ['?�'],
                '�?:   ['�?],
                '??:   ['??],
                '??:   ['??],
                '�?:   ['�?],
            }.get(u, [u])

            for ua in unit_alias:
                # 공백 ?�무 모두
                or_variants.append(column.ilike(f"%{n}{ua}%"))
                or_variants.append(column.ilike(f"%{n} {ua}%"))
            # ?�본 그�?�?
            or_variants.append(column.ilike(f"%{term}%"))

        # 3) ?�반 ?�워??(?�스?? PT, 커플, ?�용�???
        #    ?�자/?�위/금액?�로 ?�히지 ?�았?�면 ?�워?�로 처리
        if not or_variants:
            # PT 같이 ?�?�문???�이??�?ILIKE�?충분
            or_variants.append(column.ilike(f"%{term}%"))

            # 가벼운 ?�의??추�? (?�요 ???�장)
            synonym_map = {
                '?�스??: ['?�스??, '?�스', '?�트?�스', '�?, 'GYM', 'fitness'],
                'PT':    ['PT', '?�티', '?�스?�트?�이??, '?�스??, 'personal training'],
                '커플':  ['커플', '2??, '?�명'],
                '?�용�?: ['?�용�?, '?�용 쿠폰', '?�용권한', '?�용권증??],
            }
            if term in synonym_map:
                for syn in synonym_map[term]:
                    or_variants.append(column.ilike(f"%{syn}%"))

        # 그룹(?�현????OR�?묶고, 그룹 간�? AND
        predicates.append(or_(*or_variants))

    return predicates


async def get_campaign(db: AsyncSession, campaign_id: int) -> Campaign | None:
    return await db.get(Campaign, campaign_id)


def get_distance_query(lat: float, lng: float):
    """Haversine 공식???�용?�여 SQLAlchemy 쿼리 ?�현?�을 반환?�니??"""
    # 지�?반�?�?(km)
    R = 6371

    # ?�디??변??
    lat_rad = func.radians(lat)
    lng_rad = func.radians(lng)
    db_lat_rad = func.radians(Campaign.lat)
    db_lng_rad = func.radians(Campaign.lng)

    # ?�버?�인 공식
    dlat = db_lat_rad - lat_rad
    dlng = db_lng_rad - lng_rad
    a = func.power(func.sin(dlat / 2), 2) + func.cos(lat_rad) * func.cos(db_lat_rad) * func.power(func.sin(dlng / 2), 2)
    c = 2 * func.asin(func.sqrt(a))
    
    # 거리 (km)
    distance = R * c
    return distance.label("distance")



async def list_campaigns_optimized(
    db: AsyncSession,
    *,
    # --- ?�로???�터 ?�라미터 추�? ---
    region: Optional[str] = None,
    offer: Optional[str] = None,  # ??추�?: ?�퍼(?�스?? 부분�???
    campaign_type: Optional[str] = None,
    campaign_channel: Optional[str] = None,
    # ------------------------------------
    category_id: Optional[int] = None, # ???�터 ?�라미터 추�?
    q: Optional[str] = None,
    platform: Optional[str] = None,
    company: Optional[str] = None,
    apply_from: Optional[str] = None, # API ?�에??datetime?�로 ?�싱??것을 받는?�고 가??
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
    """
    ???�능 최적?�된 캠페??목록 조회
    - idx_campaign_promo_deadline_lat_lng ?�덱??최�? ?�용
    - idx_campaign_lat_lng GiST ?�덱???�용 (지??뷰포?�용)
    - Raw SQL�?최적?�된 쿼리 ?�행
    """
    
    # 기본 조건: apply_deadline >= current_date 강제 ?�용
    base_conditions = ["c.apply_deadline >= CURRENT_DATE"]
    params = {}
    
    # 지??뷰포??조건 ?�인 (GiST ?�덱???�용 가??
    is_map_viewport = None not in (sw_lat, sw_lng, ne_lat, ne_lng)
    
    if is_map_viewport:
        # GiST ?�덱???�용???�한 point <@ box 조건
        lat_min, lat_max = sorted([sw_lat, ne_lat])
        lng_min, lng_max = sorted([sw_lng, ne_lng])
        
        # ?��? 범위 검????GiST ?�덱???�용
        viewport_area = (lat_max - lat_min) * (lng_max - lng_min)
        if viewport_area > 0.01:  # ?��? 범위 (??1km² ?�상)
            base_conditions.append("point(c.lng, c.lat) <@ box(point(:sw_lng, :sw_lat), point(:ne_lng, :ne_lat))")
            params.update({
                'sw_lat': lat_min, 'sw_lng': lng_min,
                'ne_lat': lat_max, 'ne_lng': lng_max
            })
        else:
            # 좁�? 범위??B-Tree ?�덱???�용
            base_conditions.extend([
                "c.lat BETWEEN :lat_min AND :lat_max",
                "c.lng BETWEEN :lng_min AND :lng_max"
            ])
            params.update({
                'lat_min': lat_min, 'lat_max': lat_max,
                'lng_min': lng_min, 'lng_max': lng_max
            })
    
    # 추�? ?�터 조건??
    if category_id:
        base_conditions.append("c.category_id = :category_id")
        params['category_id'] = category_id
    
    if platform:
        base_conditions.append("c.platform = :platform")
        params['platform'] = platform
    
    if company:
        base_conditions.append("c.company ILIKE :company")
        params['company'] = f"%{company}%"
    
    if campaign_type:
        base_conditions.append("c.campaign_type = :campaign_type")
        params['campaign_type'] = campaign_type
    
    if campaign_channel:
        tokens = [t.strip() for t in campaign_channel.split(",") if t.strip()]
        if tokens:
            channel_conditions = []
            for i, token in enumerate(tokens):
                param_name = f"campaign_channel_{i}"
                channel_conditions.append(f"c.campaign_channel ILIKE :{param_name}")
                params[param_name] = f"%{token}%"
            base_conditions.append(f"({' OR '.join(channel_conditions)})")
    
    if region:
        tokens = [t.strip() for t in region.split() if t.strip()]
        region_conditions = []
        for i, token in enumerate(tokens):
            param_name = f"region_{i}"
            region_conditions.append(f"(c.region ILIKE :{param_name} OR c.address ILIKE :{param_name} OR c.title ILIKE :{param_name})")
            params[param_name] = f"%{token}%"
        base_conditions.append(f"({' OR '.join(region_conditions)})")
    
    if q:
        base_conditions.append("(c.company ILIKE :q OR c.offer ILIKE :q OR c.platform ILIKE :q OR c.title ILIKE :q)")
        params['q'] = f"%{q}%"
    
    # ?�렬 조건 결정
    if sort == "distance" and lat is not None and lng is not None:
        # 거리???�렬: promotion_level ?�선 + 거리??+ ?�사?�덤
        order_clause = """
            COALESCE(c.promotion_level, 0) DESC,
            ST_Distance(
                ST_Point(c.lng, c.lat)::geography,
                ST_Point(:user_lng, :user_lat)::geography
            ) ASC NULLS LAST,
            ABS(HASH(c.id)) % 1000,
            c.created_at DESC
        """
        params.update({'user_lat': lat, 'user_lng': lng})
    else:
        # ?�반 ?�렬: promotion_level ?�선 + ?�사?�덤 + 기존 ?�렬
        sort_map = {
            "created_at": "c.created_at",
            "updated_at": "c.updated_at", 
            "apply_deadline": "c.apply_deadline",
            "review_deadline": "c.review_deadline",
        }
        desc = sort.startswith("-")
        key = sort[1:] if desc else sort
        sort_col = sort_map.get(key, "c.created_at")
        sort_direction = "DESC" if desc else "ASC"
        
        order_clause = f"""
            COALESCE(c.promotion_level, 0) DESC,
            ABS(HASH(c.id)) % 1000,
            {sort_col} {sort_direction}
        """
    
    # 최적?�된 쿼리 ?�행
    where_clause = " AND ".join(base_conditions)
    
    # 메인 쿼리 - idx_campaign_promo_deadline_lat_lng ?�덱??최�? ?�용
    main_query = text(f"""
        WITH filtered_campaigns AS (
            SELECT 
                c.*,
                cat.name as category_name,
                cat.display_order as category_display_order,
                (c.created_at::date >= CURRENT_DATE - INTERVAL '2 days') as is_new,
                CASE 
                    WHEN :user_lat IS NOT NULL AND :user_lng IS NOT NULL THEN
                        ST_Distance(
                            ST_Point(c.lng, c.lat)::geography,
                            ST_Point(:user_lng, :user_lat)::geography
                        )
                    ELSE NULL
                END as distance
            FROM campaign c
            LEFT JOIN categories cat ON c.category_id = cat.id
            WHERE {where_clause}
        )
        SELECT 
            id, category_id, platform, company, company_link, offer,
            apply_deadline, review_deadline, address, lat, lng, img_url,
            search_text, created_at, updated_at, source, title, content_link,
            campaign_type, region, campaign_channel, apply_from, promotion_level,
            category_name, category_display_order, is_new, distance
        FROM filtered_campaigns
        ORDER BY {order_clause}
        LIMIT :limit OFFSET :offset
    """)
    
    # Count 쿼리 - ?�일???�터 조건 ?�용
    count_query = text(f"""
        SELECT COUNT(*)
        FROM campaign c
        WHERE {where_clause}
    """)
    
    # ?�라미터 ?�정
    params.update({
        'limit': limit,
        'offset': offset,
        'user_lat': lat if lat is not None else None,
        'user_lng': lng if lng is not None else None
    })
    
    # 쿼리 ?�행
    count_result = await db.execute(count_query, params)
    total = count_result.scalar()
    
    main_result = await db.execute(main_query, params)
    rows = []
    
    for row in main_result:
        # Campaign 객체 ?�성 �??�성 ?�정
        campaign = Campaign()
        for key, value in row._mapping.items():
            if hasattr(campaign, key):
                setattr(campaign, key, value)
        
        # 추�? ?�성 ?�정
        campaign.is_new = row.is_new
        campaign.distance = row.distance
        
        # Category 객체 ?�정
        if row.category_name:
            campaign.category = Category(
                id=row.category_id,
                name=row.category_name,
                display_order=row.category_display_order
            )
        
        rows.append(campaign)
    
    return total, rows


async def list_campaigns(
    db: AsyncSession,
    *,
    # --- ?�로???�터 ?�라미터 추�? ---
    region: Optional[str] = None,
    offer: Optional[str] = None,  # ??추�?: ?�퍼(?�스?? 부분�???
    campaign_type: Optional[str] = None,
    campaign_channel: Optional[str] = None,
    # ------------------------------------
    category_id: Optional[int] = None, # ???�터 ?�라미터 추�?
    q: Optional[str] = None,
    platform: Optional[str] = None,
    company: Optional[str] = None,
    apply_from: Optional[str] = None, # API ?�에??datetime?�로 ?�싱??것을 받는?�고 가??
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
    """
    ??PostGIS ?�이 ?�동?�는 최적?�된 캠페??목록 조회
    - idx_campaign_promo_deadline_lat_lng ?�덱??최�? ?�용
    - Haversine 공식 기반 거리 계산
    - Raw SQL�?최적?�된 쿼리 ?�행
    """
    
    # 기본 조건: apply_deadline >= current_date 강제 ?�용
    base_conditions = ["c.apply_deadline >= CURRENT_DATE"]
    params = {}
    
    # 지??뷰포??조건 ?�인
    is_map_viewport = None not in (sw_lat, sw_lng, ne_lat, ne_lng)
    
    if is_map_viewport:
        lat_min, lat_max = sorted([sw_lat, ne_lat])
        lng_min, lng_max = sorted([sw_lng, ne_lng])
        
        base_conditions.extend([
            "c.lat BETWEEN :lat_min AND :lat_max",
            "c.lng BETWEEN :lng_min AND :lng_max"
        ])
        params.update({
            'lat_min': lat_min, 'lat_max': lat_max,
            'lng_min': lng_min, 'lng_max': lng_max
        })
    
    # 추�? ?�터 조건??
    if category_id:
        base_conditions.append("c.category_id = :category_id")
        params['category_id'] = category_id
    
    if platform:
        base_conditions.append("c.platform = :platform")
        params['platform'] = platform
    
    if company:
        base_conditions.append("c.company ILIKE :company")
        params['company'] = f"%{company}%"
    
    if campaign_type:
        base_conditions.append("c.campaign_type = :campaign_type")
        params['campaign_type'] = campaign_type
    
    if campaign_channel:
        tokens = [t.strip() for t in campaign_channel.split(",") if t.strip()]
        if tokens:
            channel_conditions = []
            for i, token in enumerate(tokens):
                param_name = f"campaign_channel_{i}"
                channel_conditions.append(f"c.campaign_channel ILIKE :{param_name}")
                params[param_name] = f"%{token}%"
            base_conditions.append(f"({' OR '.join(channel_conditions)})")
    
    if region:
        tokens = [t.strip() for t in region.split() if t.strip()]
        region_conditions = []
        for i, token in enumerate(tokens):
            param_name = f"region_{i}"
            region_conditions.append(f"(c.region ILIKE :{param_name} OR c.address ILIKE :{param_name} OR c.title ILIKE :{param_name})")
            params[param_name] = f"%{token}%"
        base_conditions.append(f"({' OR '.join(region_conditions)})")
    
    if q:
        base_conditions.append("(c.company ILIKE :q OR c.offer ILIKE :q OR c.platform ILIKE :q OR c.title ILIKE :q)")
        params['q'] = f"%{q}%"
    
    # ?�렬 조건 결정
    if sort == "distance" and lat is not None and lng is not None:
        # 거리???�렬: promotion_level ?�선 + 거리??+ ?�사?�덤
        order_clause = """
            COALESCE(promotion_level, 0) DESC,
            distance ASC NULLS LAST,
            id % 1000,
            created_at DESC
        """
        params.update({'user_lat': lat, 'user_lng': lng})
    else:
        # ?�반 ?�렬: promotion_level ?�선 + ?�사?�덤 + 기존 ?�렬
        sort_map = {
            "created_at": "created_at",
            "updated_at": "updated_at", 
            "apply_deadline": "apply_deadline",
            "review_deadline": "review_deadline",
        }
        desc = sort.startswith("-")
        key = sort[1:] if desc else sort
        sort_col = sort_map.get(key, "created_at")
        sort_direction = "DESC" if desc else "ASC"
        
        order_clause = f"""
            COALESCE(promotion_level, 0) DESC,
            id % 1000,
            {sort_col} {sort_direction}
        """
    
    # 최적?�된 쿼리 ?�행
    where_clause = " AND ".join(base_conditions)
    
    # 메인 쿼리 - idx_campaign_promo_deadline_lat_lng ?�덱??최�? ?�용
    main_query = text(f"""
        WITH filtered_campaigns AS (
            SELECT 
                c.*,
                cat.name as category_name,
                cat.display_order as category_display_order,
                (c.created_at::date >= CURRENT_DATE - INTERVAL '2 days') as is_new,
                CASE 
                    WHEN :user_lat IS NOT NULL AND :user_lng IS NOT NULL THEN
                        -- Haversine 공식???�용??거리 계산 (PostGIS ?�이)
                        6371 * acos(
                            cos(radians(:user_lat)) * cos(radians(c.lat)) * 
                            cos(radians(c.lng) - radians(:user_lng)) + 
                            sin(radians(:user_lat)) * sin(radians(c.lat))
                        )
                    ELSE NULL
                END as distance
            FROM campaign c
            LEFT JOIN categories cat ON c.category_id = cat.id
            WHERE {where_clause}
        )
        SELECT 
            id, category_id, platform, company, company_link, offer,
            apply_deadline, review_deadline, address, lat, lng, img_url,
            search_text, created_at, updated_at, source, title, content_link,
            campaign_type, region, campaign_channel, apply_from, promotion_level,
            category_name, category_display_order, is_new, distance
        FROM filtered_campaigns
        ORDER BY {order_clause}
        LIMIT :limit OFFSET :offset
    """)
    
    # Count 쿼리 - ?�일???�터 조건 ?�용
    count_query = text(f"""
        SELECT COUNT(*)
        FROM campaign c
        WHERE {where_clause}
    """)
    
    # ?�라미터 ?�정
    params.update({
        'limit': limit,
        'offset': offset,
        'user_lat': lat if lat is not None else None,
        'user_lng': lng if lng is not None else None
    })
    
    # 쿼리 ?�행
    count_result = await db.execute(count_query, params)
    total = count_result.scalar()
    
    main_result = await db.execute(main_query, params)
    rows = []
    
    for row in main_result:
        # Campaign 객체 ?�성 �??�성 ?�정
        campaign = Campaign()
        for key, value in row._mapping.items():
            if hasattr(campaign, key):
                setattr(campaign, key, value)
        
        # 추�? ?�성 ?�정
        campaign.is_new = row.is_new
        campaign.distance = row.distance
        
        # Category 객체 ?�정
        if row.category_name:
            campaign.category = Category(
                id=row.category_id,
                name=row.category_name,
                display_order=row.category_display_order
            )
        
        rows.append(campaign)
    
    return total, rows


async def list_campaigns_legacy(
    db: AsyncSession,
    *,
    # --- ?�로???�터 ?�라미터 추�? ---
    region: Optional[str] = None,
    offer: Optional[str] = None,  # ??추�?: ?�퍼(?�스?? 부분�???
    campaign_type: Optional[str] = None,
    campaign_channel: Optional[str] = None,
    # ------------------------------------
    category_id: Optional[int] = None, # ???�터 ?�라미터 추�?
    q: Optional[str] = None,
    platform: Optional[str] = None,
    company: Optional[str] = None,
    apply_from: Optional[str] = None, # API ?�에??datetime?�로 ?�싱??것을 받는?�고 가??
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
    
    # ??is_new 로직???�한 SQL ?�현?? PostgreSQL 문법 ?�용
    # (created_at???�짜 부�?- 1????(?�늘 ?�짜 - 3??보다 ?�거??같으�?true
    is_new_expression = (
        (func.cast(Campaign.created_at, Date) >= (func.current_date() - timedelta(days=2)))
    ).label("is_new")

    # 공통 ?�터 ?�용 ?�수 (기존 코드?� ?�일)
    def apply_common_filters(stmt_):
        # ??추천 체험??API ?�구?�항: apply_deadline < ?�늘?�짜 캠페???�외
        # apply_deadline??NULL?�거???�늘 ?�후??캠페?�만 ?�함
        stmt_ = stmt_.where(
            or_(
                Campaign.apply_deadline.is_(None),  # 마감?�이 ?�는 경우
                Campaign.apply_deadline >= func.current_timestamp()  # ?�늘 ?�후 마감??경우
            )
        )
        
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
        # --- ?�로???�터 로직 추�? ---
        if region:
            tokens = [t.strip() for t in region.split() if t.strip()]
            for token in tokens:
                like = f"%{token}%"
                stmt_ = stmt_.where(
                    (Campaign.region.ilike(like)) | (Campaign.address.ilike(like)) | (Campaign.title.ilike(like))
                )
        if offer:
            # ?�스???�퍼(?? '10만원', '?�용�?) 부분�???
            for pred in build_offer_predicates(offer, Campaign.offer):
                stmt_ = stmt_.where(pred)
        if campaign_type:
            stmt_ = stmt_.where(Campaign.campaign_type == campaign_type)
        if campaign_channel:
            # ?�표�?구분???�러 채널 �??�나?�도 ?�함?�면 검??(?? 'blog,instagram')
            tokens = [t.strip() for t in campaign_channel.split(",") if t.strip()]
            if tokens:
                stmt_ = stmt_.where(or_(*[Campaign.campaign_channel.ilike(f"%{t}%") for t in tokens]))
        # --------------------------------
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
        if None not in (sw_lat, sw_lng, ne_lat, ne_lng):
            lat_min, lat_max = sorted([sw_lat, ne_lat])
            lng_min, lng_max = sorted([sw_lng, ne_lng])
            stmt_ = stmt_.where(
                Campaign.lat.between(lat_min, lat_max),
                Campaign.lng.between(lng_min, lng_max)
            )
        return stmt_

    # === 거리???�렬 로직 ===
    if sort == "distance" and lat is not None and lng is not None:
        distance_col = get_distance_query(lat, lng)

        # 좌표 ?�무 관계없??모두 ?�함 (좌표 ?�는 ??��??결과???�긴??
        stmt = (
            select(Campaign, Category, is_new_expression, distance_col)
            .outerjoin(Category, Campaign.category_id == Category.id)
        )

        # 공통 ?�터 ?�용 (region/offer ??
        stmt = apply_common_filters(stmt)

        # ???�능 최적?? 거리???�렬?�서??count 쿼리 최적??
        # total 계산 (?�터가 ?�용???�브쿼리 기�?)
        count_stmt = select(func.count()).select_from(stmt.subquery())
        total = (await db.execute(count_stmt)).scalar_one()

        # ??거리???�렬?�서??promotion_level ?�선 ?�렬 ?�용
        # 1?�위: promotion_level ?�림차순 (?��? ?�벨??먼�?)
        # 2?�위: 거리 ?�름차순 (가까운 곳이 먼�?)
        # 3?�위: ?�일 promotion_level + 거리 ?�에???�사?�덤??(균형 분포 보장)
        
        promotion_level_coalesced = func.coalesce(Campaign.promotion_level, 0)
        pseudo_random = func.abs(func.hash(Campaign.id)) % 1000  # ID 기반 ?�사?�덤
        
        # Postgres + SQLAlchemy 2.x�?nulls_last() 지??
        try:
            order_by_clause = (
                promotion_level_coalesced.desc(),  # 1?�위: promotion_level ?�림차순
                distance_col.asc().nulls_last(),   # 2?�위: 거리 ?�름차순 (NULL?� ?�로)
                pseudo_random,                     # 3?�위: ?�일 ?�벨+거리 ???�사?�덤??
                Campaign.created_at.desc(),        # 4?�위: ?�성???�림차순
            )
        except Exception:
            # DB/?�라?�버?�서 nulls_last 미�??�이�?case�??��?
            order_by_clause = (
                promotion_level_coalesced.desc(),  # 1?�위: promotion_level ?�림차순
                case((distance_col.is_(None), 1), else_=0),  # NULL 먼�? ?�래�?1) ???�로 �?
                distance_col.asc(),                # 2?�위: 거리 ?�름차순
                pseudo_random,                     # 3?�위: ?�일 ?�벨+거리 ???�사?�덤??
                Campaign.created_at.desc(),        # 4?�위: ?�성???�림차순
            )

        stmt = stmt.order_by(*order_by_clause).limit(limit).offset(offset)

        result = await db.execute(stmt)
        rows = []
        for campaign, category, is_new, distance in result.all():
            campaign.is_new = is_new
            campaign.distance = distance  # 좌표 ?�으�?None
            campaign.category = category
            rows.append(campaign)

        return total, rows

    # === ?�반 ?�렬 로직 ===
    else:
        # ??SELECT 구문??is_new_expression, Category 추�? �?JOIN
        stmt = select(Campaign, Category, is_new_expression)
        stmt = stmt.outerjoin(Category, Campaign.category_id == Category.id)
        stmt = apply_common_filters(stmt)

        # 2. total count 계산 (?�터가 모두 ?�용??쿼리 기반)
        # ???�능 최적?? ?�?�량 ?�이?�셋?�서 count 쿼리 최적??
        # 복잡???�터가 ?�는 경우 ?�브쿼리 ?�??직접 count ?�용
        count_stmt = select(func.count()).select_from(stmt.subquery())
        total = (await db.execute(count_stmt)).scalar_one()

        # 3. ?�렬 로직 ?�용 - ??추천 체험??API ?�구?�항 반영
        sort_map = {
            "created_at": Campaign.created_at,
            "updated_at": Campaign.updated_at,
            "apply_deadline": Campaign.apply_deadline,
            "review_deadline": Campaign.review_deadline,
        }
        desc = sort.startswith("-")
        key = sort[1:] if desc else sort
        sort_col = sort_map.get(key, Campaign.created_at)
        
        # ??promotion_level 기반 ?�선 ?�렬 + ?�일 ?�벨 ??균형 분포
        # 1?�위: promotion_level ?�림차순 (?��? ?�벨??먼�?)
        # 2?�위: ?�일 promotion_level ?�에???�덤?�된 ?�렬 (균형 분포 보장)
        # 3?�위: 기존 ?�렬 ??(created_at ??
        
        # ???�능 최적?? ?�덤?��? ?�한 ?�율?�인 방법
        # PostgreSQL??random() ?�수???�능??부?�이 ?????�으므�?
        # ID 기반 ?�시�??�용???�사?�덤 ?�렬�??��?
        # ?�는 ?��???결과�?보장?�면?�도 ?�능???�상?�킴
        pseudo_random = func.abs(func.hash(Campaign.id)) % 1000  # ID 기반 ?�사?�덤
        
        # promotion_level??NULL??경우 0?�로 처리?�여 가???�로 ?�렬
        promotion_level_coalesced = func.coalesce(Campaign.promotion_level, 0)
        
        order_by_clause = (
            promotion_level_coalesced.desc(),  # 1?�위: promotion_level ?�림차순
            pseudo_random,                     # 2?�위: ?�일 ?�벨 ???�사?�덤??
            sort_col.desc() if desc else sort_col.asc()  # 3?�위: 기존 ?�렬 ??
        )
        
        stmt = stmt.order_by(*order_by_clause)
        
        stmt = stmt.limit(limit).offset(offset)
        result = await db.execute(stmt)
        rows = []
        # ??결과 처리 로직 ?�정
        for campaign, category, is_new in result.all():
            campaign.is_new = is_new
            campaign.category = category
            rows.append(campaign)
        
        return total, rows


async def get_categories(db: AsyncSession) -> Sequence[Category]:
    """모든 ?��? 카테고리 목록??조회?�니??"""
    stmt = select(Category).order_by(Category.display_order, Category.name)
    result = await db.execute(stmt)
    return result.scalars().all()

async def get_category(db: AsyncSession, category_id: int) -> Category | None:
    """ID�??�일 ?��? 카테고리�?조회?�니??"""
    return await db.get(Category, category_id)

async def get_category_by_name(db: AsyncSession, name: str) -> Category | None:
    """?�름?�로 ?�일 ?��? 카테고리�?조회?�니??"""
    stmt = select(Category).where(Category.name == name)
    result = await db.execute(stmt)
    return result.scalars().first()

async def create_category(db: AsyncSession, category: CategoryCreate) -> Category:
    """?�로???��? 카테고리�??�성?�니??"""
    db_category = Category(name=category.name)
    db.add(db_category)
    await db.commit()
    await db.refresh(db_category)
    return db_category


async def update_category(db: AsyncSession, category_id: int, category_update: CategoryCreate) -> Category | None:
    """?��? 카테고리 ?�보�??�정?�니??"""
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
    """?��? 카테고리�???��?�니??"""
    stmt = delete(Category).where(Category.id == category_id)
    result = await db.execute(stmt)
    await db.commit()
    return result.rowcount # ??��???�의 ?��? 반환 (0 ?�는 1)

async def get_unmapped_raw_categories(db: AsyncSession):
    """?�직 매핑?��? ?��? ?�본 카테고리 목록??조회?�니??"""
    # raw_categories ?�이블과 category_mappings ?�이블을 LEFT JOIN
    # 매핑 ?�보가 ?�는(m.id IS NULL) 것들�??�터�?
    stmt = (
        select(RawCategory)
        .outerjoin(CategoryMapping, RawCategory.id == CategoryMapping.raw_category_id)
        .filter(CategoryMapping.id.is_(None))
        .order_by(RawCategory.created_at.desc())
    )
    result = await db.execute(stmt)
    return result.scalars().all()
    
async def create_category_mapping(db: AsyncSession, mapping: CategoryMappingCreate):
    """?�로??카테고리 매핑???�성?�니??"""
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
    ?�공??ID 목록 ?�서?��?카테고리??display_order�??�괄 ?�데?�트?�니??
    SQL??CASE 문을 ?�용?�여 ??번의 쿼리�??�율?�으�?처리?�니??
    """
    if not ordered_ids:
        return 0

    # ID 목록??기반?�로 CASE 문을 ?�성
    # ?? CASE WHEN id=3 THEN 1 WHEN id=1 THEN 2 ... END
    case_statement = case(
        {category_id: index + 1 for index, category_id in enumerate(ordered_ids)},
        value=Category.id,
    )

    # ?�괄 ?�데?�트 쿼리 ?�행
    stmt = (
        update(Category)
        .where(Category.id.in_(ordered_ids))
        .values(display_order=case_statement)
    )
    result = await db.execute(stmt)
    await db.commit()

    return result.rowcount # ?�데?�트???�의 ?��? 반환


async def explain_analyze_campaign_query(
    db: AsyncSession,
    *,
    region: Optional[str] = None,
    offer: Optional[str] = None,
    campaign_type: Optional[str] = None,
    campaign_channel: Optional[str] = None,
    category_id: Optional[int] = None,
    q: Optional[str] = None,
    platform: Optional[str] = None,
    company: Optional[str] = None,
    apply_from: Optional[str] = None,
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
) -> str:
    """
    ??EXPLAIN ANALYZE�??�한 쿼리 ?�능 분석
    - ?�덱???�용???�인
    - ?�행 계획 분석
    - ?�능 병목 지???�별
    """
    
    # 기본 조건: apply_deadline >= current_date 강제 ?�용
    base_conditions = ["c.apply_deadline >= CURRENT_DATE"]
    params = {}
    
    # 지??뷰포??조건 ?�인 (GiST ?�덱???�용 가??
    is_map_viewport = None not in (sw_lat, sw_lng, ne_lat, ne_lng)
    
    if is_map_viewport:
        # GiST ?�덱???�용???�한 point <@ box 조건
        lat_min, lat_max = sorted([sw_lat, ne_lat])
        lng_min, lng_max = sorted([sw_lng, ne_lng])
        
        # ?��? 범위 검????GiST ?�덱???�용
        viewport_area = (lat_max - lat_min) * (lng_max - lng_min)
        if viewport_area > 0.01:  # ?��? 범위 (??1km² ?�상)
            base_conditions.append("point(c.lng, c.lat) <@ box(point(:sw_lng, :sw_lat), point(:ne_lng, :ne_lat))")
            params.update({
                'sw_lat': lat_min, 'sw_lng': lng_min,
                'ne_lat': lat_max, 'ne_lng': lng_max
            })
        else:
            # 좁�? 범위??B-Tree ?�덱???�용
            base_conditions.extend([
                "c.lat BETWEEN :lat_min AND :lat_max",
                "c.lng BETWEEN :lng_min AND :lng_max"
            ])
            params.update({
                'lat_min': lat_min, 'lat_max': lat_max,
                'lng_min': lng_min, 'lng_max': lng_max
            })
    
    # 추�? ?�터 조건??
    if category_id:
        base_conditions.append("c.category_id = :category_id")
        params['category_id'] = category_id
    
    if platform:
        base_conditions.append("c.platform = :platform")
        params['platform'] = platform
    
    if company:
        base_conditions.append("c.company ILIKE :company")
        params['company'] = f"%{company}%"
    
    if campaign_type:
        base_conditions.append("c.campaign_type = :campaign_type")
        params['campaign_type'] = campaign_type
    
    if campaign_channel:
        tokens = [t.strip() for t in campaign_channel.split(",") if t.strip()]
        if tokens:
            channel_conditions = []
            for i, token in enumerate(tokens):
                param_name = f"campaign_channel_{i}"
                channel_conditions.append(f"c.campaign_channel ILIKE :{param_name}")
                params[param_name] = f"%{token}%"
            base_conditions.append(f"({' OR '.join(channel_conditions)})")
    
    if region:
        tokens = [t.strip() for t in region.split() if t.strip()]
        region_conditions = []
        for i, token in enumerate(tokens):
            param_name = f"region_{i}"
            region_conditions.append(f"(c.region ILIKE :{param_name} OR c.address ILIKE :{param_name} OR c.title ILIKE :{param_name})")
            params[param_name] = f"%{token}%"
        base_conditions.append(f"({' OR '.join(region_conditions)})")
    
    if q:
        base_conditions.append("(c.company ILIKE :q OR c.offer ILIKE :q OR c.platform ILIKE :q OR c.title ILIKE :q)")
        params['q'] = f"%{q}%"
    
    # ?�렬 조건 결정
    if sort == "distance" and lat is not None and lng is not None:
        # 거리???�렬: promotion_level ?�선 + 거리??+ ?�사?�덤
        order_clause = """
            COALESCE(c.promotion_level, 0) DESC,
            ST_Distance(
                ST_Point(c.lng, c.lat)::geography,
                ST_Point(:user_lng, :user_lat)::geography
            ) ASC NULLS LAST,
            ABS(HASH(c.id)) % 1000,
            c.created_at DESC
        """
        params.update({'user_lat': lat, 'user_lng': lng})
    else:
        # ?�반 ?�렬: promotion_level ?�선 + ?�사?�덤 + 기존 ?�렬
        sort_map = {
            "created_at": "c.created_at",
            "updated_at": "c.updated_at", 
            "apply_deadline": "c.apply_deadline",
            "review_deadline": "c.review_deadline",
        }
        desc = sort.startswith("-")
        key = sort[1:] if desc else sort
        sort_col = sort_map.get(key, "c.created_at")
        sort_direction = "DESC" if desc else "ASC"
        
        order_clause = f"""
            COALESCE(c.promotion_level, 0) DESC,
            ABS(HASH(c.id)) % 1000,
            {sort_col} {sort_direction}
        """
    
    # EXPLAIN ANALYZE 쿼리
    where_clause = " AND ".join(base_conditions)
    
    explain_query = text(f"""
        EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        WITH filtered_campaigns AS (
            SELECT 
                c.*,
                cat.name as category_name,
                cat.display_order as category_display_order,
                (c.created_at::date >= CURRENT_DATE - INTERVAL '2 days') as is_new,
                CASE 
                    WHEN :user_lat IS NOT NULL AND :user_lng IS NOT NULL THEN
                        ST_Distance(
                            ST_Point(c.lng, c.lat)::geography,
                            ST_Point(:user_lng, :user_lat)::geography
                        )
                    ELSE NULL
                END as distance
            FROM campaign c
            LEFT JOIN categories cat ON c.category_id = cat.id
            WHERE {where_clause}
        )
        SELECT 
            id, category_id, platform, company, company_link, offer,
            apply_deadline, review_deadline, address, lat, lng, img_url,
            search_text, created_at, updated_at, source, title, content_link,
            campaign_type, region, campaign_channel, apply_from, promotion_level,
            category_name, category_display_order, is_new, distance
        FROM filtered_campaigns
        ORDER BY {order_clause}
        LIMIT :limit OFFSET :offset
    """)
    
    # ?�라미터 ?�정
    params.update({
        'limit': limit,
        'offset': offset,
        'user_lat': lat if lat is not None else None,
        'user_lng': lng if lng is not None else None
    })
    
    # EXPLAIN ANALYZE ?�행
    result = await db.execute(explain_query, params)
    explain_result = result.scalar()
    
    # JSON 결과�?문자?�로 변?�하??반환
    import json
    return json.dumps(explain_result, indent=2, ensure_ascii=False)


async def get_index_usage_stats(db: AsyncSession) -> dict:
    """
    ???�덱???�용 ?�계 조회
    - idx_campaign_promo_deadline_lat_lng ?�용�?
    - idx_campaign_lat_lng ?�용�?
    - ?�체 ?�덱???�율??분석
    """
    
    stats_query = text("""
        SELECT 
            schemaname,
            tablename,
            indexname,
            idx_scan as index_scans,
            idx_tup_read as tuples_read,
            idx_tup_fetch as tuples_fetched,
            pg_size_pretty(pg_relation_size(indexrelid)) as index_size
        FROM pg_stat_user_indexes 
        WHERE tablename = 'campaign'
        AND indexname IN (
            'idx_campaign_promo_deadline_lat_lng',
            'idx_campaign_lat_lng',
            'idx_campaign_promotion_deadline',
            'idx_campaign_created_at',
            'idx_campaign_category_id',
            'idx_campaign_apply_deadline'
        )
        ORDER BY idx_scan DESC;
    """)
    
    result = await db.execute(stats_query)
    stats = []
    
    for row in result:
        stats.append({
            'schema': row.schemaname,
            'table': row.tablename,
            'index': row.indexname,
            'scans': row.index_scans,
            'tuples_read': row.tuples_read,
            'tuples_fetched': row.tuples_fetched,
            'size': row.index_size
        })
    
    return {'index_stats': stats}


async def benchmark_campaign_queries(db: AsyncSession) -> dict:
    """
    ??캠페??쿼리 ?�능 벤치마크
    - 추천 체험??쿼리 ?�능 측정
    - 지??뷰포??쿼리 ?�능 측정
    - ?�양???�나리오�??�능 비교
    """
    import time
    
    benchmarks = {}
    
    # 1. 추천 체험??쿼리 벤치마크
    start_time = time.time()
    total, rows = await list_campaigns_optimized(
        db=db,
        limit=20,
        offset=0
    )
    recommendation_time = (time.time() - start_time) * 1000
    benchmarks['recommendation_query'] = {
        'execution_time_ms': recommendation_time,
        'total_results': total,
        'returned_results': len(rows)
    }
    
    # 2. 지??뷰포??쿼리 벤치마크 (좁�? 범위)
    start_time = time.time()
    total, rows = await list_campaigns_optimized(
        db=db,
        sw_lat=37.5, sw_lng=127.0,
        ne_lat=37.6, ne_lng=127.1,
        limit=20,
        offset=0
    )
    map_narrow_time = (time.time() - start_time) * 1000
    benchmarks['map_viewport_narrow'] = {
        'execution_time_ms': map_narrow_time,
        'total_results': total,
        'returned_results': len(rows)
    }
    
    # 3. 지??뷰포??쿼리 벤치마크 (?��? 범위)
    start_time = time.time()
    total, rows = await list_campaigns_optimized(
        db=db,
        sw_lat=37.0, sw_lng=126.0,
        ne_lat=38.0, ne_lng=128.0,
        limit=20,
        offset=0
    )
    map_wide_time = (time.time() - start_time) * 1000
    benchmarks['map_viewport_wide'] = {
        'execution_time_ms': map_wide_time,
        'total_results': total,
        'returned_results': len(rows)
    }
    
    # 4. 거리???�렬 쿼리 벤치마크
    start_time = time.time()
    total, rows = await list_campaigns_optimized(
        db=db,
        lat=37.5665, lng=126.9780,  # ?�울?�청 좌표
        sort="distance",
        limit=20,
        offset=0
    )
    distance_sort_time = (time.time() - start_time) * 1000
    benchmarks['distance_sort_query'] = {
        'execution_time_ms': distance_sort_time,
        'total_results': total,
        'returned_results': len(rows)
    }
    
    return benchmarks

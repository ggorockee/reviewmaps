from __future__ import annotations
from typing import Optional, Sequence, Tuple, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, update, delete, Date, case, or_, and_, text
from datetime import timedelta
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



async def list_campaigns_optimized(
    db: AsyncSession,
    *,
    # --- 새로운 필터 파라미터 추가 ---
    region: Optional[str] = None,
    offer: Optional[str] = None,  # ✨ 추가: 오퍼(텍스트) 부분검색
    campaign_type: Optional[str] = None,
    campaign_channel: Optional[str] = None,
    # ------------------------------------
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
    """
    ✨ 성능 최적화된 캠페인 목록 조회
    - idx_campaign_promo_deadline_lat_lng 인덱스 최대 활용
    - idx_campaign_lat_lng GiST 인덱스 활용 (지도 뷰포트용)
    - Raw SQL로 최적화된 쿼리 실행
    """
    
    # 기본 조건: apply_deadline >= current_date 강제 적용
    base_conditions = ["c.apply_deadline >= CURRENT_DATE"]
    params = {}
    
    # 지도 뷰포트 조건 확인 (GiST 인덱스 활용 가능)
    is_map_viewport = None not in (sw_lat, sw_lng, ne_lat, ne_lng)
    
    if is_map_viewport:
        # GiST 인덱스 활용을 위한 point <@ box 조건
        lat_min, lat_max = sorted([sw_lat, ne_lat])
        lng_min, lng_max = sorted([sw_lng, ne_lng])
        
        # 넓은 범위 검색 시 GiST 인덱스 활용
        viewport_area = (lat_max - lat_min) * (lng_max - lng_min)
        if viewport_area > 0.01:  # 넓은 범위 (약 1km² 이상)
            base_conditions.append("point(c.lng, c.lat) <@ box(point(:sw_lng, :sw_lat), point(:ne_lng, :ne_lat))")
            params.update({
                'sw_lat': lat_min, 'sw_lng': lng_min,
                'ne_lat': lat_max, 'ne_lng': lng_max
            })
        else:
            # 좁은 범위는 B-Tree 인덱스 활용
            base_conditions.extend([
                "c.lat BETWEEN :lat_min AND :lat_max",
                "c.lng BETWEEN :lng_min AND :lng_max"
            ])
            params.update({
                'lat_min': lat_min, 'lat_max': lat_max,
                'lng_min': lng_min, 'lng_max': lng_max
            })
    
    # 추가 필터 조건들
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
    
    # 정렬 조건 결정
    if sort == "distance" and lat is not None and lng is not None:
        # 거리순 정렬: promotion_level 우선 + 거리순 + 의사랜덤
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
        # 일반 정렬: promotion_level 우선 + 의사랜덤 + 기존 정렬
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
    
    # 최적화된 쿼리 실행
    where_clause = " AND ".join(base_conditions)
    
    # 메인 쿼리 - idx_campaign_promo_deadline_lat_lng 인덱스 최대 활용
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
    
    # Count 쿼리 - 동일한 필터 조건 적용
    count_query = text(f"""
        SELECT COUNT(*)
        FROM campaign c
        WHERE {where_clause}
    """)
    
    # 파라미터 설정
    params.update({
        'limit': limit,
        'offset': offset,
        'user_lat': lat if lat is not None else None,
        'user_lng': lng if lng is not None else None
    })
    
    # 쿼리 실행
    count_result = await db.execute(count_query, params)
    total = count_result.scalar()
    
    main_result = await db.execute(main_query, params)
    rows = []
    
    for row in main_result:
        # Campaign 객체 생성 및 속성 설정
        campaign = Campaign()
        for key, value in row._mapping.items():
            if hasattr(campaign, key):
                setattr(campaign, key, value)
        
        # 추가 속성 설정
        campaign.is_new = row.is_new
        campaign.distance = row.distance
        
        # Category 객체 설정
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
    # --- 새로운 필터 파라미터 추가 ---
    region: Optional[str] = None,
    offer: Optional[str] = None,  # ✨ 추가: 오퍼(텍스트) 부분검색
    campaign_type: Optional[str] = None,
    campaign_channel: Optional[str] = None,
    # ------------------------------------
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
    """
    ✨ PostGIS 없이 작동하는 최적화된 캠페인 목록 조회
    - idx_campaign_promo_deadline_lat_lng 인덱스 최대 활용
    - Haversine 공식 기반 거리 계산
    - Raw SQL로 최적화된 쿼리 실행
    """
    
    # 기본 조건: apply_deadline >= current_date 강제 적용
    base_conditions = ["c.apply_deadline >= CURRENT_DATE"]
    params = {}
    
    # 지도 뷰포트 조건 확인
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
    
    # 추가 필터 조건들
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
    
    # 정렬 조건 결정
    if sort == "distance" and lat is not None and lng is not None:
        # 거리순 정렬: promotion_level 우선 + 거리순 + 의사랜덤
        order_clause = """
            COALESCE(promotion_level, 0) DESC,
            distance ASC NULLS LAST,
            ABS(HASH(id)) % 1000,
            created_at DESC
        """
        params.update({'user_lat': lat, 'user_lng': lng})
    else:
        # 일반 정렬: promotion_level 우선 + 의사랜덤 + 기존 정렬
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
            ABS(HASH(id)) % 1000,
            {sort_col} {sort_direction}
        """
    
    # 최적화된 쿼리 실행
    where_clause = " AND ".join(base_conditions)
    
    # 메인 쿼리 - idx_campaign_promo_deadline_lat_lng 인덱스 최대 활용
    main_query = text(f"""
        WITH filtered_campaigns AS (
            SELECT 
                c.*,
                cat.name as category_name,
                cat.display_order as category_display_order,
                (c.created_at::date >= CURRENT_DATE - INTERVAL '2 days') as is_new,
                CASE 
                    WHEN :user_lat IS NOT NULL AND :user_lng IS NOT NULL THEN
                        -- Haversine 공식을 사용한 거리 계산 (PostGIS 없이)
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
    
    # Count 쿼리 - 동일한 필터 조건 적용
    count_query = text(f"""
        SELECT COUNT(*)
        FROM campaign c
        WHERE {where_clause}
    """)
    
    # 파라미터 설정
    params.update({
        'limit': limit,
        'offset': offset,
        'user_lat': lat if lat is not None else None,
        'user_lng': lng if lng is not None else None
    })
    
    # 쿼리 실행
    count_result = await db.execute(count_query, params)
    total = count_result.scalar()
    
    main_result = await db.execute(main_query, params)
    rows = []
    
    for row in main_result:
        # Campaign 객체 생성 및 속성 설정
        campaign = Campaign()
        for key, value in row._mapping.items():
            if hasattr(campaign, key):
                setattr(campaign, key, value)
        
        # 추가 속성 설정
        campaign.is_new = row.is_new
        campaign.distance = row.distance
        
        # Category 객체 설정
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
    # --- 새로운 필터 파라미터 추가 ---
    region: Optional[str] = None,
    offer: Optional[str] = None,  # ✨ 추가: 오퍼(텍스트) 부분검색
    campaign_type: Optional[str] = None,
    campaign_channel: Optional[str] = None,
    # ------------------------------------
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
        # ✨ 추천 체험단 API 요구사항: apply_deadline < 오늘날짜 캠페인 제외
        # apply_deadline이 NULL이거나 오늘 이후인 캠페인만 포함
        stmt_ = stmt_.where(
            or_(
                Campaign.apply_deadline.is_(None),  # 마감일이 없는 경우
                Campaign.apply_deadline >= func.current_timestamp()  # 오늘 이후 마감인 경우
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
        # --- 새로운 필터 로직 추가 ---
        if region:
            tokens = [t.strip() for t in region.split() if t.strip()]
            for token in tokens:
                like = f"%{token}%"
                stmt_ = stmt_.where(
                    (Campaign.region.ilike(like)) | (Campaign.address.ilike(like)) | (Campaign.title.ilike(like))
                )
        if offer:
            # 텍스트 오퍼(예: '10만원', '이용권') 부분검색
            for pred in build_offer_predicates(offer, Campaign.offer):
                stmt_ = stmt_.where(pred)
        if campaign_type:
            stmt_ = stmt_.where(Campaign.campaign_type == campaign_type)
        if campaign_channel:
            # 쉼표로 구분된 여러 채널 중 하나라도 포함되면 검색 (예: 'blog,instagram')
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

    # === 거리순 정렬 로직 ===
    if sort == "distance" and lat is not None and lng is not None:
        distance_col = get_distance_query(lat, lng)

        # 좌표 유무 관계없이 모두 포함 (좌표 없는 항목도 결과에 남긴다)
        stmt = (
            select(Campaign, Category, is_new_expression, distance_col)
            .outerjoin(Category, Campaign.category_id == Category.id)
        )

        # 공통 필터 적용 (region/offer 등)
        stmt = apply_common_filters(stmt)

        # ✨ 성능 최적화: 거리순 정렬에서도 count 쿼리 최적화
        # total 계산 (필터가 적용된 서브쿼리 기준)
        count_stmt = select(func.count()).select_from(stmt.subquery())
        total = (await db.execute(count_stmt)).scalar_one()

        # ✨ 거리순 정렬에서도 promotion_level 우선 정렬 적용
        # 1순위: promotion_level 내림차순 (높은 레벨이 먼저)
        # 2순위: 거리 오름차순 (가까운 곳이 먼저)
        # 3순위: 동일 promotion_level + 거리 내에서 의사랜덤화 (균형 분포 보장)
        
        promotion_level_coalesced = func.coalesce(Campaign.promotion_level, 0)
        pseudo_random = func.abs(func.hash(Campaign.id)) % 1000  # ID 기반 의사랜덤
        
        # Postgres + SQLAlchemy 2.x면 nulls_last() 지원
        try:
            order_by_clause = (
                promotion_level_coalesced.desc(),  # 1순위: promotion_level 내림차순
                distance_col.asc().nulls_last(),   # 2순위: 거리 오름차순 (NULL은 뒤로)
                pseudo_random,                     # 3순위: 동일 레벨+거리 내 의사랜덤화
                Campaign.created_at.desc(),        # 4순위: 생성일 내림차순
            )
        except Exception:
            # DB/드라이버에서 nulls_last 미지원이면 case로 대체
            order_by_clause = (
                promotion_level_coalesced.desc(),  # 1순위: promotion_level 내림차순
                case((distance_col.is_(None), 1), else_=0),  # NULL 먼저 플래그(1) → 뒤로 감
                distance_col.asc(),                # 2순위: 거리 오름차순
                pseudo_random,                     # 3순위: 동일 레벨+거리 내 의사랜덤화
                Campaign.created_at.desc(),        # 4순위: 생성일 내림차순
            )

        stmt = stmt.order_by(*order_by_clause).limit(limit).offset(offset)

        result = await db.execute(stmt)
        rows = []
        for campaign, category, is_new, distance in result.all():
            campaign.is_new = is_new
            campaign.distance = distance  # 좌표 없으면 None
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
        # ✨ 성능 최적화: 대용량 데이터셋에서 count 쿼리 최적화
        # 복잡한 필터가 있는 경우 서브쿼리 대신 직접 count 사용
        count_stmt = select(func.count()).select_from(stmt.subquery())
        total = (await db.execute(count_stmt)).scalar_one()

        # 3. 정렬 로직 적용 - ✨ 추천 체험단 API 요구사항 반영
        sort_map = {
            "created_at": Campaign.created_at,
            "updated_at": Campaign.updated_at,
            "apply_deadline": Campaign.apply_deadline,
            "review_deadline": Campaign.review_deadline,
        }
        desc = sort.startswith("-")
        key = sort[1:] if desc else sort
        sort_col = sort_map.get(key, Campaign.created_at)
        
        # ✨ promotion_level 기반 우선 정렬 + 동일 레벨 내 균형 분포
        # 1순위: promotion_level 내림차순 (높은 레벨이 먼저)
        # 2순위: 동일 promotion_level 내에서 랜덤화된 정렬 (균형 분포 보장)
        # 3순위: 기존 정렬 키 (created_at 등)
        
        # ✨ 성능 최적화: 랜덤화를 위한 효율적인 방법
        # PostgreSQL의 random() 함수는 성능상 부담이 될 수 있으므로
        # ID 기반 해시를 사용한 의사랜덤 정렬로 대체
        # 이는 일관된 결과를 보장하면서도 성능을 향상시킴
        pseudo_random = func.abs(func.hash(Campaign.id)) % 1000  # ID 기반 의사랜덤
        
        # promotion_level이 NULL인 경우 0으로 처리하여 가장 뒤로 정렬
        promotion_level_coalesced = func.coalesce(Campaign.promotion_level, 0)
        
        order_by_clause = (
            promotion_level_coalesced.desc(),  # 1순위: promotion_level 내림차순
            pseudo_random,                     # 2순위: 동일 레벨 내 의사랜덤화
            sort_col.desc() if desc else sort_col.asc()  # 3순위: 기존 정렬 키
        )
        
        stmt = stmt.order_by(*order_by_clause)
        
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
    ✨ EXPLAIN ANALYZE를 통한 쿼리 성능 분석
    - 인덱스 활용도 확인
    - 실행 계획 분석
    - 성능 병목 지점 식별
    """
    
    # 기본 조건: apply_deadline >= current_date 강제 적용
    base_conditions = ["c.apply_deadline >= CURRENT_DATE"]
    params = {}
    
    # 지도 뷰포트 조건 확인 (GiST 인덱스 활용 가능)
    is_map_viewport = None not in (sw_lat, sw_lng, ne_lat, ne_lng)
    
    if is_map_viewport:
        # GiST 인덱스 활용을 위한 point <@ box 조건
        lat_min, lat_max = sorted([sw_lat, ne_lat])
        lng_min, lng_max = sorted([sw_lng, ne_lng])
        
        # 넓은 범위 검색 시 GiST 인덱스 활용
        viewport_area = (lat_max - lat_min) * (lng_max - lng_min)
        if viewport_area > 0.01:  # 넓은 범위 (약 1km² 이상)
            base_conditions.append("point(c.lng, c.lat) <@ box(point(:sw_lng, :sw_lat), point(:ne_lng, :ne_lat))")
            params.update({
                'sw_lat': lat_min, 'sw_lng': lng_min,
                'ne_lat': lat_max, 'ne_lng': lng_max
            })
        else:
            # 좁은 범위는 B-Tree 인덱스 활용
            base_conditions.extend([
                "c.lat BETWEEN :lat_min AND :lat_max",
                "c.lng BETWEEN :lng_min AND :lng_max"
            ])
            params.update({
                'lat_min': lat_min, 'lat_max': lat_max,
                'lng_min': lng_min, 'lng_max': lng_max
            })
    
    # 추가 필터 조건들
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
    
    # 정렬 조건 결정
    if sort == "distance" and lat is not None and lng is not None:
        # 거리순 정렬: promotion_level 우선 + 거리순 + 의사랜덤
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
        # 일반 정렬: promotion_level 우선 + 의사랜덤 + 기존 정렬
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
    
    # 파라미터 설정
    params.update({
        'limit': limit,
        'offset': offset,
        'user_lat': lat if lat is not None else None,
        'user_lng': lng if lng is not None else None
    })
    
    # EXPLAIN ANALYZE 실행
    result = await db.execute(explain_query, params)
    explain_result = result.scalar()
    
    # JSON 결과를 문자열로 변환하여 반환
    import json
    return json.dumps(explain_result, indent=2, ensure_ascii=False)


async def get_index_usage_stats(db: AsyncSession) -> dict:
    """
    ✨ 인덱스 사용 통계 조회
    - idx_campaign_promo_deadline_lat_lng 사용률
    - idx_campaign_lat_lng 사용률
    - 전체 인덱스 효율성 분석
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
    ✨ 캠페인 쿼리 성능 벤치마크
    - 추천 체험단 쿼리 성능 측정
    - 지도 뷰포트 쿼리 성능 측정
    - 다양한 시나리오별 성능 비교
    """
    import time
    
    benchmarks = {}
    
    # 1. 추천 체험단 쿼리 벤치마크
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
    
    # 2. 지도 뷰포트 쿼리 벤치마크 (좁은 범위)
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
    
    # 3. 지도 뷰포트 쿼리 벤치마크 (넓은 범위)
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
    
    # 4. 거리순 정렬 쿼리 벤치마크
    start_time = time.time()
    total, rows = await list_campaigns_optimized(
        db=db,
        lat=37.5665, lng=126.9780,  # 서울시청 좌표
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
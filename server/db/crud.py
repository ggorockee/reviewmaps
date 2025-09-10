from __future__ import annotations
from typing import Optional, Sequence, Tuple, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, update, delete, Date, case, or_, and_, text
from datetime import timedelta
from .models import Campaign, Category, RawCategory, CategoryMapping
from schemas.category import CategoryMappingCreate,CategoryCreate


import re



# --- offer ?•ê·œ??? í‹¸ ---
_NUM_UNIT_PAT = re.compile(
    r'(?P<num>\d+)\s*(?P<unit>ê°œì›”|??ì£????œê°„|ë¶????Œì°¨|??ëª??€|ë³?????ê°?'
)

def _normalize_money_variants(value: int) -> list[str]:
    """?•ìˆ˜ ê¸ˆì•¡ -> ?¤ì–‘??ë¬¸ì???œí˜„(?«ì/?¼í‘œ/ë§Œì› ?¨ìœ„) ëª©ë¡"""
    variants = [f"{value}", f"{value:,}"]
    if value % 10000 == 0:
        man = value // 10000
        variants += [f"{man}ë§?, f"{man}ë§Œì›"]
    return variants


def _extract_money_value(s: str) -> int | None:
    """'40,000'/'40000'/'4ë§?/'4ë§Œì›' ?±ì—??ê¸ˆì•¡(?? ë½‘ê¸°."""
    s = s.strip()
    # ?œê? 'ë§?ë§Œì›' ì¼€?´ìŠ¤
    m = re.match(r'^(\d+)\s*ë§????$', s)
    if m:
        return int(m.group(1)) * 10000
    # ?«ìë§??¼í‘œ ?«ì
    digits = re.sub(r'\D', '', s)
    return int(digits) if digits else None


def build_offer_predicates(offer_input: str, column):
    """
    offer ?…ë ¥???˜ë? ?¨ìœ„ë¡??˜ëˆ ??
    ê°??¨ìœ„ë¥?(?¬ëŸ¬ ?œí˜„ OR)ë¡?ë§Œë“¤ê³? ?„ì²´??ANDë¡?ê²°í•©?˜ê¸° ?„í•œ predicate ë¦¬ìŠ¤?¸ë? ë°˜í™˜.
    ?¬ìš© ?? for pred in build_offer_predicates(...): stmt = stmt.where(pred)
    """
    if not offer_input or not offer_input.strip():
        return []

    terms = [t for t in re.split(r'\s+', offer_input.strip()) if t]
    predicates = []

    for term in terms:
        or_variants = []

        # 1) ê¸ˆì•¡ ?„ë³´
        money = _extract_money_value(term)
        if money:
            for v in _normalize_money_variants(money):
                or_variants.append(column.ilike(f"%{v}%"))
            # ?? "4ë§?ë§??ì–´??'40,000'ê³?ë§¤ì¹­?˜ë„ë¡??ë³¸ term ?ì²´???¬í•¨
            or_variants.append(column.ilike(f"%{term}%"))

        # 2) ?˜ëŸ‰/ê¸°ê°„ (2ê°œì›”, 10?? 2?? 3ì£? 30ë¶? 2?œê°„ ??
        m = _NUM_UNIT_PAT.fullmatch(term)
        if m:
            n = m.group('num')
            u = m.group('unit')
            # ?™ì˜???œí˜„ ?¤ì–‘??
            unit_alias = {
                'ê°œì›”': ['ê°œì›”', '??, '??],
                '??:   ['??, 'ê°œì›”', '??],
                'ì£?:   ['ì£?],
                '??:   ['??],
                '?œê°„': ['?œê°„', '?œê°„ê¶?],
                'ë¶?:   ['ë¶?],
                '??:   ['??, '?Œì°¨'],
                '?Œì°¨': ['?Œì°¨', '??],
                '??:   ['??, 'ëª?],
                'ëª?:   ['ëª?, '??],
                '?€':   ['?€'],
                'ë³?:   ['ë³?],
                '??:   ['??],
                '??:   ['??],
                'ê°?:   ['ê°?],
            }.get(u, [u])

            for ua in unit_alias:
                # ê³µë°± ? ë¬´ ëª¨ë‘
                or_variants.append(column.ilike(f"%{n}{ua}%"))
                or_variants.append(column.ilike(f"%{n} {ua}%"))
            # ?ë³¸ ê·¸ë?ë¡?
            or_variants.append(column.ilike(f"%{term}%"))

        # 3) ?¼ë°˜ ?¤ì›Œ??(?¬ìŠ¤?? PT, ì»¤í”Œ, ?´ìš©ê¶???
        #    ?«ì/?¨ìœ„/ê¸ˆì•¡?¼ë¡œ ?¡íˆì§€ ?Šì•˜?¤ë©´ ?¤ì›Œ?œë¡œ ì²˜ë¦¬
        if not or_variants:
            # PT ê°™ì´ ?€?Œë¬¸???ì´??ê±?ILIKEë¡?ì¶©ë¶„
            or_variants.append(column.ilike(f"%{term}%"))

            # ê°€ë²¼ìš´ ?™ì˜??ì¶”ê? (?„ìš” ???•ì¥)
            synonym_map = {
                '?¬ìŠ¤??: ['?¬ìŠ¤??, '?¬ìŠ¤', '?¼íŠ¸?ˆìŠ¤', 'ì§?, 'GYM', 'fitness'],
                'PT':    ['PT', '?¼í‹°', '?¼ìŠ¤?íŠ¸?ˆì´??, '?¼ìŠ¤??, 'personal training'],
                'ì»¤í”Œ':  ['ì»¤í”Œ', '2??, '?ëª…'],
                '?´ìš©ê¶?: ['?´ìš©ê¶?, '?´ìš© ì¿ í°', '?´ìš©ê¶Œí•œ', '?´ìš©ê¶Œì¦??],
            }
            if term in synonym_map:
                for syn in synonym_map[term]:
                    or_variants.append(column.ilike(f"%{syn}%"))

        # ê·¸ë£¹(?œí˜„????ORë¡?ë¬¶ê³ , ê·¸ë£¹ ê°„ì? AND
        predicates.append(or_(*or_variants))

    return predicates


async def get_campaign(db: AsyncSession, campaign_id: int) -> Campaign | None:
    return await db.get(Campaign, campaign_id)


def get_distance_query(lat: float, lng: float):
    """Haversine ê³µì‹???¬ìš©?˜ì—¬ SQLAlchemy ì¿¼ë¦¬ ?œí˜„?ì„ ë°˜í™˜?©ë‹ˆ??"""
    # ì§€êµ?ë°˜ì?ë¦?(km)
    R = 6371

    # ?¼ë””??ë³€??
    lat_rad = func.radians(lat)
    lng_rad = func.radians(lng)
    db_lat_rad = func.radians(Campaign.lat)
    db_lng_rad = func.radians(Campaign.lng)

    # ?˜ë²„?¬ì¸ ê³µì‹
    dlat = db_lat_rad - lat_rad
    dlng = db_lng_rad - lng_rad
    a = func.power(func.sin(dlat / 2), 2) + func.cos(lat_rad) * func.cos(db_lat_rad) * func.power(func.sin(dlng / 2), 2)
    c = 2 * func.asin(func.sqrt(a))
    
    # ê±°ë¦¬ (km)
    distance = R * c
    return distance.label("distance")



async def list_campaigns_optimized(
    db: AsyncSession,
    *,
    # --- ?ˆë¡œ???„í„° ?Œë¼ë¯¸í„° ì¶”ê? ---
    region: Optional[str] = None,
    offer: Optional[str] = None,  # ??ì¶”ê?: ?¤í¼(?ìŠ¤?? ë¶€ë¶„ê???
    campaign_type: Optional[str] = None,
    campaign_channel: Optional[str] = None,
    # ------------------------------------
    category_id: Optional[int] = None, # ???„í„° ?Œë¼ë¯¸í„° ì¶”ê?
    q: Optional[str] = None,
    platform: Optional[str] = None,
    company: Optional[str] = None,
    apply_from: Optional[str] = None, # API ?¨ì—??datetime?¼ë¡œ ?Œì‹±??ê²ƒì„ ë°›ëŠ”?¤ê³  ê°€??
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
    ???±ëŠ¥ ìµœì ?”ëœ ìº í˜??ëª©ë¡ ì¡°íšŒ
    - idx_campaign_promo_deadline_lat_lng ?¸ë±??ìµœë? ?œìš©
    - idx_campaign_lat_lng GiST ?¸ë±???œìš© (ì§€??ë·°í¬?¸ìš©)
    - Raw SQLë¡?ìµœì ?”ëœ ì¿¼ë¦¬ ?¤í–‰
    """
    
    # ê¸°ë³¸ ì¡°ê±´: apply_deadline >= current_date ê°•ì œ ?ìš©
    base_conditions = ["c.apply_deadline >= CURRENT_DATE"]
    params = {}
    
    # ì§€??ë·°í¬??ì¡°ê±´ ?•ì¸ (GiST ?¸ë±???œìš© ê°€??
    is_map_viewport = None not in (sw_lat, sw_lng, ne_lat, ne_lng)
    
    if is_map_viewport:
        # GiST ?¸ë±???œìš©???„í•œ point <@ box ì¡°ê±´
        lat_min, lat_max = sorted([sw_lat, ne_lat])
        lng_min, lng_max = sorted([sw_lng, ne_lng])
        
        # ?“ì? ë²”ìœ„ ê²€????GiST ?¸ë±???œìš©
        viewport_area = (lat_max - lat_min) * (lng_max - lng_min)
        if viewport_area > 0.01:  # ?“ì? ë²”ìœ„ (??1kmÂ² ?´ìƒ)
            base_conditions.append("point(c.lng, c.lat) <@ box(point(:sw_lng, :sw_lat), point(:ne_lng, :ne_lat))")
            params.update({
                'sw_lat': lat_min, 'sw_lng': lng_min,
                'ne_lat': lat_max, 'ne_lng': lng_max
            })
        else:
            # ì¢ì? ë²”ìœ„??B-Tree ?¸ë±???œìš©
            base_conditions.extend([
                "c.lat BETWEEN :lat_min AND :lat_max",
                "c.lng BETWEEN :lng_min AND :lng_max"
            ])
            params.update({
                'lat_min': lat_min, 'lat_max': lat_max,
                'lng_min': lng_min, 'lng_max': lng_max
            })
    
    # ì¶”ê? ?„í„° ì¡°ê±´??
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
    
    # ?•ë ¬ ì¡°ê±´ ê²°ì •
    if sort == "distance" and lat is not None and lng is not None:
        # ê±°ë¦¬???•ë ¬: promotion_level ?°ì„  + ê±°ë¦¬??+ ?˜ì‚¬?œë¤
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
        # ?¼ë°˜ ?•ë ¬: promotion_level ?°ì„  + ?˜ì‚¬?œë¤ + ê¸°ì¡´ ?•ë ¬
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
    
    # ìµœì ?”ëœ ì¿¼ë¦¬ ?¤í–‰
    where_clause = " AND ".join(base_conditions)
    
    # ë©”ì¸ ì¿¼ë¦¬ - idx_campaign_promo_deadline_lat_lng ?¸ë±??ìµœë? ?œìš©
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
    
    # Count ì¿¼ë¦¬ - ?™ì¼???„í„° ì¡°ê±´ ?ìš©
    count_query = text(f"""
        SELECT COUNT(*)
        FROM campaign c
        WHERE {where_clause}
    """)
    
    # ?Œë¼ë¯¸í„° ?¤ì •
    params.update({
        'limit': limit,
        'offset': offset,
        'user_lat': lat if lat is not None else None,
        'user_lng': lng if lng is not None else None
    })
    
    # ì¿¼ë¦¬ ?¤í–‰
    count_result = await db.execute(count_query, params)
    total = count_result.scalar()
    
    main_result = await db.execute(main_query, params)
    rows = []
    
    for row in main_result:
        # Campaign ê°ì²´ ?ì„± ë°??ì„± ?¤ì •
        campaign = Campaign()
        for key, value in row._mapping.items():
            if hasattr(campaign, key):
                setattr(campaign, key, value)
        
        # ì¶”ê? ?ì„± ?¤ì •
        campaign.is_new = row.is_new
        campaign.distance = row.distance
        
        # Category ê°ì²´ ?¤ì •
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
    # --- ?ˆë¡œ???„í„° ?Œë¼ë¯¸í„° ì¶”ê? ---
    region: Optional[str] = None,
    offer: Optional[str] = None,  # ??ì¶”ê?: ?¤í¼(?ìŠ¤?? ë¶€ë¶„ê???
    campaign_type: Optional[str] = None,
    campaign_channel: Optional[str] = None,
    # ------------------------------------
    category_id: Optional[int] = None, # ???„í„° ?Œë¼ë¯¸í„° ì¶”ê?
    q: Optional[str] = None,
    platform: Optional[str] = None,
    company: Optional[str] = None,
    apply_from: Optional[str] = None, # API ?¨ì—??datetime?¼ë¡œ ?Œì‹±??ê²ƒì„ ë°›ëŠ”?¤ê³  ê°€??
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
    ??PostGIS ?†ì´ ?‘ë™?˜ëŠ” ìµœì ?”ëœ ìº í˜??ëª©ë¡ ì¡°íšŒ
    - idx_campaign_promo_deadline_lat_lng ?¸ë±??ìµœë? ?œìš©
    - Haversine ê³µì‹ ê¸°ë°˜ ê±°ë¦¬ ê³„ì‚°
    - Raw SQLë¡?ìµœì ?”ëœ ì¿¼ë¦¬ ?¤í–‰
    """
    
    # ê¸°ë³¸ ì¡°ê±´: apply_deadline >= current_date ê°•ì œ ?ìš©
    base_conditions = ["c.apply_deadline >= CURRENT_DATE"]
    params = {}
    
    # ì§€??ë·°í¬??ì¡°ê±´ ?•ì¸
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
    
    # ì¶”ê? ?„í„° ì¡°ê±´??
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
    
    # ?•ë ¬ ì¡°ê±´ ê²°ì •
    if sort == "distance" and lat is not None and lng is not None:
        # ê±°ë¦¬???•ë ¬: promotion_level ?°ì„  + ê±°ë¦¬??+ ?˜ì‚¬?œë¤
        order_clause = """
            COALESCE(promotion_level, 0) DESC,
            distance ASC NULLS LAST,
            id % 1000,
            created_at DESC
        """
        params.update({'user_lat': lat, 'user_lng': lng})
    else:
        # ?¼ë°˜ ?•ë ¬: promotion_level ?°ì„  + ?˜ì‚¬?œë¤ + ê¸°ì¡´ ?•ë ¬
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
    
    # ìµœì ?”ëœ ì¿¼ë¦¬ ?¤í–‰
    where_clause = " AND ".join(base_conditions)
    
    # ë©”ì¸ ì¿¼ë¦¬ - idx_campaign_promo_deadline_lat_lng ?¸ë±??ìµœë? ?œìš©
    main_query = text(f"""
        WITH filtered_campaigns AS (
            SELECT 
                c.*,
                cat.name as category_name,
                cat.display_order as category_display_order,
                (c.created_at::date >= CURRENT_DATE - INTERVAL '2 days') as is_new,
                CASE 
                    WHEN :user_lat IS NOT NULL AND :user_lng IS NOT NULL THEN
                        -- Haversine ê³µì‹???¬ìš©??ê±°ë¦¬ ê³„ì‚° (PostGIS ?†ì´)
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
    
    # Count ì¿¼ë¦¬ - ?™ì¼???„í„° ì¡°ê±´ ?ìš©
    count_query = text(f"""
        SELECT COUNT(*)
        FROM campaign c
        WHERE {where_clause}
    """)
    
    # ?Œë¼ë¯¸í„° ?¤ì •
    params.update({
        'limit': limit,
        'offset': offset,
        'user_lat': lat if lat is not None else None,
        'user_lng': lng if lng is not None else None
    })
    
    # ì¿¼ë¦¬ ?¤í–‰
    count_result = await db.execute(count_query, params)
    total = count_result.scalar()
    
    main_result = await db.execute(main_query, params)
    rows = []
    
    for row in main_result:
        # Campaign ê°ì²´ ?ì„± ë°??ì„± ?¤ì •
        campaign = Campaign()
        for key, value in row._mapping.items():
            if hasattr(campaign, key):
                setattr(campaign, key, value)
        
        # ì¶”ê? ?ì„± ?¤ì •
        campaign.is_new = row.is_new
        campaign.distance = row.distance
        
        # Category ê°ì²´ ?¤ì •
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
    # --- ?ˆë¡œ???„í„° ?Œë¼ë¯¸í„° ì¶”ê? ---
    region: Optional[str] = None,
    offer: Optional[str] = None,  # ??ì¶”ê?: ?¤í¼(?ìŠ¤?? ë¶€ë¶„ê???
    campaign_type: Optional[str] = None,
    campaign_channel: Optional[str] = None,
    # ------------------------------------
    category_id: Optional[int] = None, # ???„í„° ?Œë¼ë¯¸í„° ì¶”ê?
    q: Optional[str] = None,
    platform: Optional[str] = None,
    company: Optional[str] = None,
    apply_from: Optional[str] = None, # API ?¨ì—??datetime?¼ë¡œ ?Œì‹±??ê²ƒì„ ë°›ëŠ”?¤ê³  ê°€??
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
    
    # ??is_new ë¡œì§???„í•œ SQL ?œí˜„?? PostgreSQL ë¬¸ë²• ?œìš©
    # (created_at??? ì§œ ë¶€ë¶?- 1????(?¤ëŠ˜ ? ì§œ - 3??ë³´ë‹¤ ?¬ê±°??ê°™ìœ¼ë©?true
    is_new_expression = (
        (func.cast(Campaign.created_at, Date) >= (func.current_date() - timedelta(days=2)))
    ).label("is_new")

    # ê³µí†µ ?„í„° ?ìš© ?¨ìˆ˜ (ê¸°ì¡´ ì½”ë“œ?€ ?™ì¼)
    def apply_common_filters(stmt_):
        # ??ì¶”ì²œ ì²´í—˜??API ?”êµ¬?¬í•­: apply_deadline < ?¤ëŠ˜? ì§œ ìº í˜???œì™¸
        # apply_deadline??NULL?´ê±°???¤ëŠ˜ ?´í›„??ìº í˜?¸ë§Œ ?¬í•¨
        stmt_ = stmt_.where(
            or_(
                Campaign.apply_deadline.is_(None),  # ë§ˆê°?¼ì´ ?†ëŠ” ê²½ìš°
                Campaign.apply_deadline >= func.current_timestamp()  # ?¤ëŠ˜ ?´í›„ ë§ˆê°??ê²½ìš°
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
        # --- ?ˆë¡œ???„í„° ë¡œì§ ì¶”ê? ---
        if region:
            tokens = [t.strip() for t in region.split() if t.strip()]
            for token in tokens:
                like = f"%{token}%"
                stmt_ = stmt_.where(
                    (Campaign.region.ilike(like)) | (Campaign.address.ilike(like)) | (Campaign.title.ilike(like))
                )
        if offer:
            # ?ìŠ¤???¤í¼(?? '10ë§Œì›', '?´ìš©ê¶?) ë¶€ë¶„ê???
            for pred in build_offer_predicates(offer, Campaign.offer):
                stmt_ = stmt_.where(pred)
        if campaign_type:
            stmt_ = stmt_.where(Campaign.campaign_type == campaign_type)
        if campaign_channel:
            # ?¼í‘œë¡?êµ¬ë¶„???¬ëŸ¬ ì±„ë„ ì¤??˜ë‚˜?¼ë„ ?¬í•¨?˜ë©´ ê²€??(?? 'blog,instagram')
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

    # === ê±°ë¦¬???•ë ¬ ë¡œì§ ===
    if sort == "distance" and lat is not None and lng is not None:
        distance_col = get_distance_query(lat, lng)

        # ì¢Œí‘œ ? ë¬´ ê´€ê³„ì—†??ëª¨ë‘ ?¬í•¨ (ì¢Œí‘œ ?†ëŠ” ??ª©??ê²°ê³¼???¨ê¸´??
        stmt = (
            select(Campaign, Category, is_new_expression, distance_col)
            .outerjoin(Category, Campaign.category_id == Category.id)
        )

        # ê³µí†µ ?„í„° ?ìš© (region/offer ??
        stmt = apply_common_filters(stmt)

        # ???±ëŠ¥ ìµœì ?? ê±°ë¦¬???•ë ¬?ì„œ??count ì¿¼ë¦¬ ìµœì ??
        # total ê³„ì‚° (?„í„°ê°€ ?ìš©???œë¸Œì¿¼ë¦¬ ê¸°ì?)
        count_stmt = select(func.count()).select_from(stmt.subquery())
        total = (await db.execute(count_stmt)).scalar_one()

        # ??ê±°ë¦¬???•ë ¬?ì„œ??promotion_level ?°ì„  ?•ë ¬ ?ìš©
        # 1?œìœ„: promotion_level ?´ë¦¼ì°¨ìˆœ (?’ì? ?ˆë²¨??ë¨¼ì?)
        # 2?œìœ„: ê±°ë¦¬ ?¤ë¦„ì°¨ìˆœ (ê°€ê¹Œìš´ ê³³ì´ ë¨¼ì?)
        # 3?œìœ„: ?™ì¼ promotion_level + ê±°ë¦¬ ?´ì—???˜ì‚¬?œë¤??(ê· í˜• ë¶„í¬ ë³´ì¥)
        
        promotion_level_coalesced = func.coalesce(Campaign.promotion_level, 0)
        pseudo_random = func.abs(func.hash(Campaign.id)) % 1000  # ID ê¸°ë°˜ ?˜ì‚¬?œë¤
        
        # Postgres + SQLAlchemy 2.xë©?nulls_last() ì§€??
        try:
            order_by_clause = (
                promotion_level_coalesced.desc(),  # 1?œìœ„: promotion_level ?´ë¦¼ì°¨ìˆœ
                distance_col.asc().nulls_last(),   # 2?œìœ„: ê±°ë¦¬ ?¤ë¦„ì°¨ìˆœ (NULL?€ ?¤ë¡œ)
                pseudo_random,                     # 3?œìœ„: ?™ì¼ ?ˆë²¨+ê±°ë¦¬ ???˜ì‚¬?œë¤??
                Campaign.created_at.desc(),        # 4?œìœ„: ?ì„±???´ë¦¼ì°¨ìˆœ
            )
        except Exception:
            # DB/?œë¼?´ë²„?ì„œ nulls_last ë¯¸ì??ì´ë©?caseë¡??€ì²?
            order_by_clause = (
                promotion_level_coalesced.desc(),  # 1?œìœ„: promotion_level ?´ë¦¼ì°¨ìˆœ
                case((distance_col.is_(None), 1), else_=0),  # NULL ë¨¼ì? ?Œë˜ê·?1) ???¤ë¡œ ê°?
                distance_col.asc(),                # 2?œìœ„: ê±°ë¦¬ ?¤ë¦„ì°¨ìˆœ
                pseudo_random,                     # 3?œìœ„: ?™ì¼ ?ˆë²¨+ê±°ë¦¬ ???˜ì‚¬?œë¤??
                Campaign.created_at.desc(),        # 4?œìœ„: ?ì„±???´ë¦¼ì°¨ìˆœ
            )

        stmt = stmt.order_by(*order_by_clause).limit(limit).offset(offset)

        result = await db.execute(stmt)
        rows = []
        for campaign, category, is_new, distance in result.all():
            campaign.is_new = is_new
            campaign.distance = distance  # ì¢Œí‘œ ?†ìœ¼ë©?None
            campaign.category = category
            rows.append(campaign)

        return total, rows

    # === ?¼ë°˜ ?•ë ¬ ë¡œì§ ===
    else:
        # ??SELECT êµ¬ë¬¸??is_new_expression, Category ì¶”ê? ë°?JOIN
        stmt = select(Campaign, Category, is_new_expression)
        stmt = stmt.outerjoin(Category, Campaign.category_id == Category.id)
        stmt = apply_common_filters(stmt)

        # 2. total count ê³„ì‚° (?„í„°ê°€ ëª¨ë‘ ?ìš©??ì¿¼ë¦¬ ê¸°ë°˜)
        # ???±ëŠ¥ ìµœì ?? ?€?©ëŸ‰ ?°ì´?°ì…‹?ì„œ count ì¿¼ë¦¬ ìµœì ??
        # ë³µì¡???„í„°ê°€ ?ˆëŠ” ê²½ìš° ?œë¸Œì¿¼ë¦¬ ?€??ì§ì ‘ count ?¬ìš©
        count_stmt = select(func.count()).select_from(stmt.subquery())
        total = (await db.execute(count_stmt)).scalar_one()

        # 3. ?•ë ¬ ë¡œì§ ?ìš© - ??ì¶”ì²œ ì²´í—˜??API ?”êµ¬?¬í•­ ë°˜ì˜
        sort_map = {
            "created_at": Campaign.created_at,
            "updated_at": Campaign.updated_at,
            "apply_deadline": Campaign.apply_deadline,
            "review_deadline": Campaign.review_deadline,
        }
        desc = sort.startswith("-")
        key = sort[1:] if desc else sort
        sort_col = sort_map.get(key, Campaign.created_at)
        
        # ??promotion_level ê¸°ë°˜ ?°ì„  ?•ë ¬ + ?™ì¼ ?ˆë²¨ ??ê· í˜• ë¶„í¬
        # 1?œìœ„: promotion_level ?´ë¦¼ì°¨ìˆœ (?’ì? ?ˆë²¨??ë¨¼ì?)
        # 2?œìœ„: ?™ì¼ promotion_level ?´ì—???œë¤?”ëœ ?•ë ¬ (ê· í˜• ë¶„í¬ ë³´ì¥)
        # 3?œìœ„: ê¸°ì¡´ ?•ë ¬ ??(created_at ??
        
        # ???±ëŠ¥ ìµœì ?? ?œë¤?”ë? ?„í•œ ?¨ìœ¨?ì¸ ë°©ë²•
        # PostgreSQL??random() ?¨ìˆ˜???±ëŠ¥??ë¶€?´ì´ ?????ˆìœ¼ë¯€ë¡?
        # ID ê¸°ë°˜ ?´ì‹œë¥??¬ìš©???˜ì‚¬?œë¤ ?•ë ¬ë¡??€ì²?
        # ?´ëŠ” ?¼ê???ê²°ê³¼ë¥?ë³´ì¥?˜ë©´?œë„ ?±ëŠ¥???¥ìƒ?œí‚´
        pseudo_random = func.abs(func.hash(Campaign.id)) % 1000  # ID ê¸°ë°˜ ?˜ì‚¬?œë¤
        
        # promotion_level??NULL??ê²½ìš° 0?¼ë¡œ ì²˜ë¦¬?˜ì—¬ ê°€???¤ë¡œ ?•ë ¬
        promotion_level_coalesced = func.coalesce(Campaign.promotion_level, 0)
        
        order_by_clause = (
            promotion_level_coalesced.desc(),  # 1?œìœ„: promotion_level ?´ë¦¼ì°¨ìˆœ
            pseudo_random,                     # 2?œìœ„: ?™ì¼ ?ˆë²¨ ???˜ì‚¬?œë¤??
            sort_col.desc() if desc else sort_col.asc()  # 3?œìœ„: ê¸°ì¡´ ?•ë ¬ ??
        )
        
        stmt = stmt.order_by(*order_by_clause)
        
        stmt = stmt.limit(limit).offset(offset)
        result = await db.execute(stmt)
        rows = []
        # ??ê²°ê³¼ ì²˜ë¦¬ ë¡œì§ ?˜ì •
        for campaign, category, is_new in result.all():
            campaign.is_new = is_new
            campaign.category = category
            rows.append(campaign)
        
        return total, rows


async def get_categories(db: AsyncSession) -> Sequence[Category]:
    """ëª¨ë“  ?œì? ì¹´í…Œê³ ë¦¬ ëª©ë¡??ì¡°íšŒ?©ë‹ˆ??"""
    stmt = select(Category).order_by(Category.display_order, Category.name)
    result = await db.execute(stmt)
    return result.scalars().all()

async def get_category(db: AsyncSession, category_id: int) -> Category | None:
    """IDë¡??¨ì¼ ?œì? ì¹´í…Œê³ ë¦¬ë¥?ì¡°íšŒ?©ë‹ˆ??"""
    return await db.get(Category, category_id)

async def get_category_by_name(db: AsyncSession, name: str) -> Category | None:
    """?´ë¦„?¼ë¡œ ?¨ì¼ ?œì? ì¹´í…Œê³ ë¦¬ë¥?ì¡°íšŒ?©ë‹ˆ??"""
    stmt = select(Category).where(Category.name == name)
    result = await db.execute(stmt)
    return result.scalars().first()

async def create_category(db: AsyncSession, category: CategoryCreate) -> Category:
    """?ˆë¡œ???œì? ì¹´í…Œê³ ë¦¬ë¥??ì„±?©ë‹ˆ??"""
    db_category = Category(name=category.name)
    db.add(db_category)
    await db.commit()
    await db.refresh(db_category)
    return db_category


async def update_category(db: AsyncSession, category_id: int, category_update: CategoryCreate) -> Category | None:
    """?œì? ì¹´í…Œê³ ë¦¬ ?•ë³´ë¥??˜ì •?©ë‹ˆ??"""
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
    """?œì? ì¹´í…Œê³ ë¦¬ë¥??? œ?©ë‹ˆ??"""
    stmt = delete(Category).where(Category.id == category_id)
    result = await db.execute(stmt)
    await db.commit()
    return result.rowcount # ?? œ???‰ì˜ ?˜ë? ë°˜í™˜ (0 ?ëŠ” 1)

async def get_unmapped_raw_categories(db: AsyncSession):
    """?„ì§ ë§¤í•‘?˜ì? ?Šì? ?ë³¸ ì¹´í…Œê³ ë¦¬ ëª©ë¡??ì¡°íšŒ?©ë‹ˆ??"""
    # raw_categories ?Œì´ë¸”ê³¼ category_mappings ?Œì´ë¸”ì„ LEFT JOIN
    # ë§¤í•‘ ?•ë³´ê°€ ?†ëŠ”(m.id IS NULL) ê²ƒë“¤ë§??„í„°ë§?
    stmt = (
        select(RawCategory)
        .outerjoin(CategoryMapping, RawCategory.id == CategoryMapping.raw_category_id)
        .filter(CategoryMapping.id.is_(None))
        .order_by(RawCategory.created_at.desc())
    )
    result = await db.execute(stmt)
    return result.scalars().all()
    
async def create_category_mapping(db: AsyncSession, mapping: CategoryMappingCreate):
    """?ˆë¡œ??ì¹´í…Œê³ ë¦¬ ë§¤í•‘???ì„±?©ë‹ˆ??"""
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
    ?œê³µ??ID ëª©ë¡ ?œì„œ?€ë¡?ì¹´í…Œê³ ë¦¬??display_orderë¥??¼ê´„ ?…ë°?´íŠ¸?©ë‹ˆ??
    SQL??CASE ë¬¸ì„ ?¬ìš©?˜ì—¬ ??ë²ˆì˜ ì¿¼ë¦¬ë¡??¨ìœ¨?ìœ¼ë¡?ì²˜ë¦¬?©ë‹ˆ??
    """
    if not ordered_ids:
        return 0

    # ID ëª©ë¡??ê¸°ë°˜?¼ë¡œ CASE ë¬¸ì„ ?ì„±
    # ?? CASE WHEN id=3 THEN 1 WHEN id=1 THEN 2 ... END
    case_statement = case(
        {category_id: index + 1 for index, category_id in enumerate(ordered_ids)},
        value=Category.id,
    )

    # ?¼ê´„ ?…ë°?´íŠ¸ ì¿¼ë¦¬ ?¤í–‰
    stmt = (
        update(Category)
        .where(Category.id.in_(ordered_ids))
        .values(display_order=case_statement)
    )
    result = await db.execute(stmt)
    await db.commit()

    return result.rowcount # ?…ë°?´íŠ¸???‰ì˜ ?˜ë? ë°˜í™˜


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
    ??EXPLAIN ANALYZEë¥??µí•œ ì¿¼ë¦¬ ?±ëŠ¥ ë¶„ì„
    - ?¸ë±???œìš©???•ì¸
    - ?¤í–‰ ê³„íš ë¶„ì„
    - ?±ëŠ¥ ë³‘ëª© ì§€???ë³„
    """
    
    # ê¸°ë³¸ ì¡°ê±´: apply_deadline >= current_date ê°•ì œ ?ìš©
    base_conditions = ["c.apply_deadline >= CURRENT_DATE"]
    params = {}
    
    # ì§€??ë·°í¬??ì¡°ê±´ ?•ì¸ (GiST ?¸ë±???œìš© ê°€??
    is_map_viewport = None not in (sw_lat, sw_lng, ne_lat, ne_lng)
    
    if is_map_viewport:
        # GiST ?¸ë±???œìš©???„í•œ point <@ box ì¡°ê±´
        lat_min, lat_max = sorted([sw_lat, ne_lat])
        lng_min, lng_max = sorted([sw_lng, ne_lng])
        
        # ?“ì? ë²”ìœ„ ê²€????GiST ?¸ë±???œìš©
        viewport_area = (lat_max - lat_min) * (lng_max - lng_min)
        if viewport_area > 0.01:  # ?“ì? ë²”ìœ„ (??1kmÂ² ?´ìƒ)
            base_conditions.append("point(c.lng, c.lat) <@ box(point(:sw_lng, :sw_lat), point(:ne_lng, :ne_lat))")
            params.update({
                'sw_lat': lat_min, 'sw_lng': lng_min,
                'ne_lat': lat_max, 'ne_lng': lng_max
            })
        else:
            # ì¢ì? ë²”ìœ„??B-Tree ?¸ë±???œìš©
            base_conditions.extend([
                "c.lat BETWEEN :lat_min AND :lat_max",
                "c.lng BETWEEN :lng_min AND :lng_max"
            ])
            params.update({
                'lat_min': lat_min, 'lat_max': lat_max,
                'lng_min': lng_min, 'lng_max': lng_max
            })
    
    # ì¶”ê? ?„í„° ì¡°ê±´??
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
    
    # ?•ë ¬ ì¡°ê±´ ê²°ì •
    if sort == "distance" and lat is not None and lng is not None:
        # ê±°ë¦¬???•ë ¬: promotion_level ?°ì„  + ê±°ë¦¬??+ ?˜ì‚¬?œë¤
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
        # ?¼ë°˜ ?•ë ¬: promotion_level ?°ì„  + ?˜ì‚¬?œë¤ + ê¸°ì¡´ ?•ë ¬
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
    
    # EXPLAIN ANALYZE ì¿¼ë¦¬
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
    
    # ?Œë¼ë¯¸í„° ?¤ì •
    params.update({
        'limit': limit,
        'offset': offset,
        'user_lat': lat if lat is not None else None,
        'user_lng': lng if lng is not None else None
    })
    
    # EXPLAIN ANALYZE ?¤í–‰
    result = await db.execute(explain_query, params)
    explain_result = result.scalar()
    
    # JSON ê²°ê³¼ë¥?ë¬¸ì?´ë¡œ ë³€?˜í•˜??ë°˜í™˜
    import json
    return json.dumps(explain_result, indent=2, ensure_ascii=False)


async def get_index_usage_stats(db: AsyncSession) -> dict:
    """
    ???¸ë±???¬ìš© ?µê³„ ì¡°íšŒ
    - idx_campaign_promo_deadline_lat_lng ?¬ìš©ë¥?
    - idx_campaign_lat_lng ?¬ìš©ë¥?
    - ?„ì²´ ?¸ë±???¨ìœ¨??ë¶„ì„
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
    ??ìº í˜??ì¿¼ë¦¬ ?±ëŠ¥ ë²¤ì¹˜ë§ˆí¬
    - ì¶”ì²œ ì²´í—˜??ì¿¼ë¦¬ ?±ëŠ¥ ì¸¡ì •
    - ì§€??ë·°í¬??ì¿¼ë¦¬ ?±ëŠ¥ ì¸¡ì •
    - ?¤ì–‘???œë‚˜ë¦¬ì˜¤ë³??±ëŠ¥ ë¹„êµ
    """
    import time
    
    benchmarks = {}
    
    # 1. ì¶”ì²œ ì²´í—˜??ì¿¼ë¦¬ ë²¤ì¹˜ë§ˆí¬
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
    
    # 2. ì§€??ë·°í¬??ì¿¼ë¦¬ ë²¤ì¹˜ë§ˆí¬ (ì¢ì? ë²”ìœ„)
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
    
    # 3. ì§€??ë·°í¬??ì¿¼ë¦¬ ë²¤ì¹˜ë§ˆí¬ (?“ì? ë²”ìœ„)
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
    
    # 4. ê±°ë¦¬???•ë ¬ ì¿¼ë¦¬ ë²¤ì¹˜ë§ˆí¬
    start_time = time.time()
    total, rows = await list_campaigns_optimized(
        db=db,
        lat=37.5665, lng=126.9780,  # ?œìš¸?œì²­ ì¢Œí‘œ
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

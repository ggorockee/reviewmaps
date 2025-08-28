from __future__ import annotations
from typing import Optional, Dict, Tuple, List
import os, time, requests
import pandas as pd
from sqlalchemy.engine import Engine
from sqlalchemy import text
from sqlalchemy import text as sa_text


from .config import Settings
from .db import get_engine, update_where_id
from .logger import get_logger

import random, time

from .scrapers.reviewnote import ReviewNoteScraper 



log = get_logger("enricher")

def fetch_campaigns_to_enrich(
    engine: Engine,
    table: str,
    company_col: str = "company",
    region_filters: Optional[List[str]] = None,  # ✨ 추가: 지역 필터(검색 키==search_text)
) -> pd.DataFrame:
    """
    보강 대상 캠페인을 가져옵니다.
    - address/lat/lng 중 하나라도 NULL 인 것만
    - ENRICH_SCOPE=region 인 경우, region_filters (예: ['세종','충남',...]) 로 제한
    """
    base_sql = f'''
    SELECT "id", "{company_col}", "search_text"
    FROM "{table}"
    WHERE (address IS NULL OR lat IS NULL OR lng IS NULL)
    '''
    params: Dict[str, object] = {}

    if region_filters:
        # search_text 정확 매칭(권장). OR-체인으로 안전한 바인딩 구성
        conds = []
        for i, r in enumerate(region_filters):
            key = f"r{i}"
            conds.append(f'search_text = :{key}')
            params[key] = r
        base_sql += " AND (" + " OR ".join(conds) + ")"

    try:
        q = sa_text(base_sql)
        df = pd.read_sql_query(q, engine, params=params)
        log.info(f'[{table}] 보강 대상 {len(df)}건 로드 (regions={region_filters if region_filters else "ALL"})')
        return df
    except Exception as e:
        log.error(f"캠페인 로드 실패: {e}")
        return pd.DataFrame()


def naver_local_search(api_keys: List[Tuple[str, str]], query: str) -> Optional[Dict]:
    """
    키를 라운드로빈하지 않고, 1번 키를 최대한 소진 → 429가 일정 횟수 누적되면 '해당 키 소진'으로 판단하여
    리스트에서 제거하고 다음 키로 넘어간다.
    """
    
    url = "https://openapi.naver.com/v1/search/local.json"
    clean_q = (query or "").replace("[","").replace("]","").replace("/"," ").strip()
    params = {"query": clean_q, "display": 1}

    if not api_keys:
        log.error("Local API 키 없음")
        return None

    # 429 일시 속도 제한을 위한 백오프 파라미터
    # - 동일 키에서 429가 STRIKE_LIMIT 번 이상 발생하면 '소진' 판단
    STRIKE_LIMIT = 3               # 이 횟수 이상 429면 키 소진 처리
    INITIAL_SLEEP = 0.4            # 첫 백오프(초)
    BACKOFF_FACTOR = 1.7           # 지수 백오프 계수
    MAX_BACKOFF = 6.0              # 같은 키에서 한 번 시도 시 최대 대기
    JITTER = (0.0, 0.3)            # 지터 범위

    # 항상 첫 번째 키부터 시도 → 소진되면 pop(0)으로 제거
    # (원본 리스트를 수정해 다음 호출(enrich_once 루프)에도 상태가 반영되도록 함)
    while api_keys:
        client_id, client_secret = api_keys[0]
        headers = {"X-Naver-Client-Id": client_id, "X-Naver-Client-Secret": client_secret}

        strikes = 0
        backoff = INITIAL_SLEEP

        while True:
            try:
                log.info(
                    f"Naver Local API 호출 (현재 키: ...{client_id[-4:]}, 잔여키수: {len(api_keys)}, "
                    f"Query(raw)='{query}', Query(clean)='{clean_q}')"
                    )
                r = requests.get(url, headers=headers, params=params, timeout=5)
                r.raise_for_status()
                items = r.json().get("items", [])
                # 성공했어도 라운드로빈 금지: 같은 키 그대로 유지
                # (다음 요청도 이 키로 시도; enrich_once 루프에서 자연스러운 pace를 위해 약간 쉼)
                return items[0] if items else None

            except requests.RequestException as e:
                status = getattr(getattr(e, "response", None), "status_code", None)

                # 429 → 같은 키로 재시도(지수 백오프 + 지터). STRIKE_LIMIT 넘으면 '소진' 처리.
                if status == 429:
                    strikes += 1
                    if strikes >= STRIKE_LIMIT:
                        log.warning(f"Key ...{client_id[-4:]} 429 {strikes}회 → 소진 판단, 키 제거 후 다음 키로 이동.")
                        api_keys.pop(0)  # 이 키 제거 → 다음 키로 넘어감
                        break  # 외부 while로 나가 다음 키 시도
                    sleep_for = min(MAX_BACKOFF, backoff) + random.uniform(*JITTER)
                    log.warning(f"429(Too Many Requests): 같은 키 재시도까지 {sleep_for:.2f}s 대기 "
                                f"(strike {strikes}/{STRIKE_LIMIT}, key ...{client_id[-4:]})")
                    time.sleep(sleep_for)
                    backoff *= BACKOFF_FACTOR
                    continue

                # 네트워크/기타 오류 → 같은 키로 짧게 재시도(두세 번만)
                # 여기서는 429와 다르게 strikes 카운트를 쓰지 않고, 2~3회 정도만 빠르게 재도전 후 키 소진 처리해도 됨.
                # 단순화를 위해 한 번 더만 시도:
                log.warning(f"Naver Local API 실패(status={status}): {e}. 같은 키로 1회 재시도.")
                time.sleep(0.5 + random.uniform(*JITTER))
                try:
                    r = requests.get(url, headers=headers, params=params, timeout=5)
                    r.raise_for_status()
                    items = r.json().get("items", [])
                    return items[0] if items else None
                except Exception as e2:
                    log.warning(f"재시도 실패: {e2}. 키 소진으로 판단하고 제거.")
                    api_keys.pop(0)
                    break  # 다음 키로 이동

    # 여기 도달 = 모든 키가 소진됨
    log.error(f"Naver Local API 모든 키 소진(또는 실패): {clean_q}")
    return None

def naver_geocode(map_id: str, map_secret: str, address: str) -> Optional[Tuple[float, float]]:
    # 반환값: (lat, lng)
    url = "https://maps.apigw.ntruss.com/map-geocode/v2/geocode"
    headers = {"x-ncp-apigw-api-key-id": map_id, "x-ncp-apigw-api-key": map_secret}
    params = {"query": address}
    max_retries = 3
    backoff_factor = 1 # 초기 대기 시간 (초)
    
    for attempt in range(max_retries):
        try:
            r = requests.get(url, headers=headers, params=params, timeout=10)
            r.raise_for_status()
            addrs = r.json().get("addresses", [])
            if not addrs:
                return None
            lat = float(addrs[0]["y"])
            lng = float(addrs[0]["x"])
            return (lat, lng)
        except requests.RequestException as e:
            # 429 (Too Many Requests) 에러일 경우에만 재시도
            if e.response and e.response.status_code == 429:
                wait_time = backoff_factor * (2 ** attempt)
                log.warning(f"Geocode API 쿼터 초과 ({address}). {wait_time}초 후 재시도... ({attempt + 1}/{max_retries})")
                time.sleep(wait_time)
            else:
                log.warning(f"Geocode 실패 ({address}): {e}")
                wait_time = backoff_factor * (2 ** attempt)
                time.sleep(wait_time)
                return None # 다른 종류의 에러는 재시도하지 않음

    log.error(f"Geocode API 모든 재시도 실패 ({address})")
    return None
    
def get_or_create_raw_category(engine: Engine, raw_text: str) -> Optional[int]:
    """
    raw_categories 테이블에서 raw_text를 찾아 ID를 반환합니다. 없으면 새로 생성합니다.
    """
    if not raw_text or not raw_text.strip():
        return None

    clean_text = raw_text.strip()
    
    with engine.begin() as conn:
        # 먼저 ID를 조회
        find_q = text("SELECT id FROM raw_categories WHERE raw_text = :text")
        result = conn.execute(find_q, {"text": clean_text}).scalar_one_or_none()
        
        if result is not None:
            return result
        
        # 없으면 새로 생성하고 ID를 반환 (ON CONFLICT를 사용하여 동시성 문제 방지)
        log.info(f"새로운 원본 카테고리 발견: '{clean_text}'")
        insert_q = text("INSERT INTO raw_categories (raw_text) VALUES (:text) ON CONFLICT (raw_text) DO NOTHING RETURNING id")
        result = conn.execute(insert_q, {"text": clean_text}).scalar_one_or_none()
        
        # ON CONFLICT DO NOTHING 때문에 INSERT가 안됐을 수 있으므로 다시 조회하여 ID를 확실히 반환
        if result is None:
            result = conn.execute(find_q, {"text": clean_text}).scalar_one_or_none()
            
        return result
    
def find_mapped_category_id(engine: Engine, raw_category_id: int) -> Optional[int]:
    """
    category_mappings 테이블에서 매핑된 standard_category_id를 찾습니다.
    """
    if raw_category_id is None:
        return None
    
    q = text("SELECT standard_category_id FROM category_mappings WHERE raw_category_id = :id")
    with engine.connect() as conn:
        result = conn.execute(q, {"id": raw_category_id}).scalar_one_or_none()
    return result

def enrich_once(settings: Settings) -> int:
    seen = set()
    eng = get_engine(settings)

    scope = os.getenv("ENRICH_SCOPE", "all").strip().lower()  # all | region
    region_filters = None

    if scope == "region":
        region_filters = list(getattr(ReviewNoteScraper, "region_map", {}).keys())
        if not region_filters:
            log.warning("ENRICH_SCOPE=region 이지만 region_map이 비어있습니다. 보강을 건너뜁니다.")
            return 0
        log.info(f"ENRICH_SCOPE=region → region_map 전체 적용: {region_filters}")
    else:
        log.info("ENRICH_SCOPE=all → 전체 캠페인 대상")
        
    df = fetch_campaigns_to_enrich(
        eng,
        settings.table_name,
        "company",
        region_filters=region_filters,
    )
    if df.empty:
        log.info("보강(enrich) 대상 없음")
        return 0

    search_api_keys = []
    if settings.naver_search_client_id and settings.naver_search_client_secret:
        search_api_keys.append((settings.naver_search_client_id, settings.naver_search_client_secret))
    if settings.naver_search_client_id_2 and settings.naver_search_client_secret_2:
        search_api_keys.append((settings.naver_search_client_id_2, settings.naver_search_client_secret_2))
    if settings.naver_search_client_id_3 and settings.naver_search_client_secret_3:
        search_api_keys.append((settings.naver_search_client_id_3, settings.naver_search_client_secret_3))
    
    if not search_api_keys:
        log.error("사용 가능한 Naver Search API 키가 없습니다. .env 파일을 확인하세요.")
        return 0
    
    updated_count = 0
    for row in df.itertuples():
        cid = row.id
        name = (row.company or "").strip()

        if not name or name in seen:
            continue
        seen.add(name)

        if not search_api_keys: # 모든 키가 소진되었으면 중단
            log.error("모든 Naver Search API 키의 할당량이 소진되어 보강 작업을 중단합니다.")
            break
            
        place = naver_local_search(search_api_keys, name)
        
        if not place:
            time.sleep(0.1) # 실패 시 잠시 대기
            continue

        address = place.get("roadAddress") or place.get("address")
        img_url = place.get("link")
        lat, lng = (None, None)
        if address:
            coords = naver_geocode(settings.naver_map_client_id, settings.naver_map_client_secret, address)
            if coords:
                lat, lng = coords
        
        data_to_update = { "address": address, "lat": lat, "lng": lng, "img_url": img_url }
        
        raw_category_text = place.get("category")
        if raw_category_text:
            raw_id = get_or_create_raw_category(eng, raw_category_text)
            if raw_id:
                standard_id = find_mapped_category_id(eng, raw_id)
                if standard_id:
                    data_to_update["category_id"] = standard_id

        changed = update_where_id(eng, table=settings.table_name, row_id=cid, data=data_to_update)
        if changed:
            updated_count += 1
        time.sleep(0.4 + random.random() * 0.3)  # 0.4 ~ 0.7초

    log.info(f"Enrich 완료: {updated_count} rows updated")
    return updated_count

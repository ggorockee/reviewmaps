from __future__ import annotations
from typing import Optional, Dict, Tuple, List
import os, time, requests
import pandas as pd
from sqlalchemy.engine import Engine
from sqlalchemy import text

from .config import Settings
from .db import get_engine, update_where_id
from .logger import get_logger

log = get_logger("enricher")

def fetch_campaigns_to_enrich(engine: Engine, table: str, company_col: str = "company") -> pd.DataFrame:
    """
    모든 캠페인을 가져옵니다. (향후 category_id가 NULL인 것만 가져오도록 최적화 가능)
    """
    q = f'SELECT "id", "{company_col}" FROM "{table}"'

    try:
        df = pd.read_sql_query(q, engine)
        log.info(f"[{table}] 보강 대상 {len(df)}건 로드")
        return df
    except Exception as e:
        log.error(f"캠페인 로드 실패: {e}")
        return pd.DataFrame()

def naver_local_search(api_keys: List[Tuple[str, str]], query: str) -> Optional[Dict]:
    url = "https://openapi.naver.com/v1/search/local.json"
    params = {"query": query, "display": 1}

    # 👇 [수정] 복사된 키 목록을 사용. 원본 리스트를 직접 수정하지 않기 위함.
    keys_to_try = list(api_keys)
    
    while keys_to_try:
        client_id, client_secret = keys_to_try[0] # 항상 목록의 첫 번째 키를 사용
        
        log.info(f"Naver Local API 호출 (남은 Key 개수: {len(keys_to_try)}, Query: {query})")
        headers = {"X-Naver-Client-Id": client_id, "X-Naver-Client-Secret": client_secret}

        try:
            r = requests.get(url, headers=headers, params=params, timeout=5)
            r.raise_for_status()
            items = r.json().get("items", [])
            return items[0] if items else None # 성공 시 즉시 결과 반환

        except requests.RequestException as e:
            # 429 (Too Many Requests) 에러일 경우, 현재 키를 목록에서 제거하고 다음 키로 넘어감
            if e.response and e.response.status_code == 429:
                log.warning(f"Key (ID: ...{client_id[-4:]}) 할당량 초과. 해당 키를 목록에서 제거합니다.")
                # 현재 사용한 키(첫 번째 키)를 제거
                keys_to_try.pop(0)
                # 원본 api_keys 리스트에서도 동일하게 제거하여 다음번 enrich_once 호출에 영향
                if (client_id, client_secret) in api_keys:
                    api_keys.remove((client_id, client_secret))
                continue # 다음 키로 재시도
            else:
                log.warning(f"Naver Local API 실패: {e}. 다음 키로 시도합니다.")
                # 429가 아닌 다른 에러(네트워크 등) 발생 시에도 현재 키를 제거하고 다음 키로 시도
                keys_to_try.pop(0)
                continue
    
    log.error(f"Naver Local API 모든 키 사용 실패 ({query})")
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
    eng = get_engine(settings)
    df = fetch_campaigns_to_enrich(eng, settings.table_name, "company") # 함수 이름 변경
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
        name = row.company

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
        time.sleep(0.3) # 성공 시 API 부하 감소를 위한 대기

    log.info(f"Enrich 완료: {updated_count} rows updated")
    return updated_count

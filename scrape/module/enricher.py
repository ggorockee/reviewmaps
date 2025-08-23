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

def naver_local_search(client_id: str, client_secret: str, query: str) -> Optional[Dict]:
    url = "https://openapi.naver.com/v1/search/local.json"
    headers = {"X-Naver-Client-Id": client_id, "X-Naver-Client-Secret": client_secret}
    params = {"query": query, "display": 1}
    try:
        r = requests.get(url, headers=headers, params=params, timeout=10)
        r.raise_for_status()
        items = r.json().get("items", [])
        return items[0] if items else None
    except requests.RequestException as e:
        log.warning(f"Naver Local 실패 ({query}): {e}")
        return None

def naver_geocode(map_id: str, map_secret: str, address: str) -> Optional[Tuple[float, float]]:
    # 반환값: (lat, lng)
    url = "https://maps.apigw.ntruss.com/map-geocode/v2/geocode"
    headers = {"x-ncp-apigw-api-key-id": map_id, "x-ncp-apigw-api-key": map_secret}
    try:
        r = requests.get(url, headers=headers, params={"query": address}, timeout=10)
        r.raise_for_status()
        addrs = r.json().get("addresses", [])
        if not addrs:
            return None
        # Naver: x=lng, y=lat
        lat = float(addrs[0]["y"])
        lng = float(addrs[0]["x"])
        return (lat, lng)
    except requests.RequestException as e:
        log.warning(f"Geocode 실패 ({address}): {e}")
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

    updated_count = 0
    for _, row in df.iterrows():
        cid = int(row["id"])
        name = str(row["company"])

        place = naver_local_search(settings.naver_search_client_id,
                                   settings.naver_search_client_secret,
                                   name)
        if not place:
            continue

        address = place.get("roadAddress") or place.get("address")

        # 썸네일/링크가 명확치 않아 link를 img_url로 임시 저장 (원본 코드 유지)
        img_url = place.get("link")

        lat, lng = (None, None)
        if address:
            coords = naver_geocode(settings.naver_map_client_id,
                                   settings.naver_map_client_secret,
                                   address)
            if coords:
                lat, lng = coords
                
        data_to_update = {
            "address": address, 
            "lat": lat, 
            "lng": lng, 
            "img_url": img_url,
            }
        
        
        # --- ✨ 카테고리 보강 로직 시작 ---
        raw_category_text = place.get("category")
        if raw_category_text:
            # 1. 원본 카테고리 Get or Create
            raw_id = get_or_create_raw_category(eng, raw_category_text)
            
            # 2. 매핑된 표준 카테고리 ID 조회
            if raw_id:
                standard_id = find_mapped_category_id(eng, raw_id)
                # 3. 매핑된 ID가 있을 경우에만 업데이트 목록에 추가
                if standard_id:
                    data_to_update["category_id"] = standard_id
        # --- 카테고리 보강 로직 끝 ---

        # --- DB 업데이트 ---
        changed = update_where_id(
            eng,
            table=settings.table_name,
            row_id=cid,
            data=data_to_update,
        )
        if changed:
            updated_count += 1
        time.sleep(0.1)

    log.info(f"Enrich 완료: {updated_count} rows updated")
    return updated_count

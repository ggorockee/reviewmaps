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

def fetch_campaigns(engine: Engine, table: str, company_col: str = "company") -> pd.DataFrame:
    q = f'SELECT "id", "{company_col}" FROM "{table}"'
    try:
        df = pd.read_sql_query(q, engine)
        log.info(f"[{table}] {len(df)}건 로드")
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

def enrich_once(settings: Settings) -> int:
    eng = get_engine(settings)
    df = fetch_campaigns(eng, settings.table_name, "company")
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

        changed = update_where_id(
            eng,
            table=settings.table_name,
            row_id=cid,
            data={"address": address, "lat": lat, "lng": lng, "img_url": img_url},
        )
        if changed:
            updated_count += 1
        time.sleep(0.1)

    log.info(f"Enrich 완료: {updated_count} rows updated")
    return updated_count

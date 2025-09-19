import os
import requests
import pandas as pd
from core.base import BaseScraper, DRIFT_METERS
from core.logger import get_logger
import time

from typing import List, Dict, Any

from sqlalchemy import create_engine

from core.enricher import (
    naver_local_search,
    naver_geocode,
    get_or_create_raw_category,
    find_mapped_category_id,
)

logger = get_logger(__name__)

MEDIA_MAP = {
    "BP_": "blog",
    "IP_": "instagram",
    "IR_": "reels",
    "BC_": "clip",
    "BP_BC_": "blog,clip",
    "IP_IR_": "instagram,reels",
    "BP_IP_": "blog,instagram",
    "IP_IP_": "instagram",
    "YP_": "youtube",
    "YS_": "shorts",
    "YP_YS_": "youtube,shorts",
    "SR_": "shorts",  # 추측
    "": "etc"
}

TYPE_MAP = {
    "PRS": "기자단",
    "VST": "방문형",
    "SHP": "배송형",
    "서울오빠_기타": "구매평"
}

class InflexerScraper(BaseScraper):
    BASE_URL = "https://inflexer.net:5000/search"
    PLATFORM_NAME = "inflexer"

    def run(self, keyword = None):
        logger.info(f"[인플렉서] 캠페인 수집 시작 — keyword={keyword}")
        df = self.scrape(keyword)
        df = self.parse(df)
        df = self.enrich(df, keyword)
        self.save(df)

    def scrape(self, keyword: str) -> pd.DataFrame:
        # API 호출
        params = {"query": keyword}
        logger.info(f"query: {params}")
        logger.info(f"BASE_URL: {self.BASE_URL}")
        resp = requests.get(self.BASE_URL, params=params, timeout=30)
        resp.raise_for_status()
        data = resp.json()

        if not data.get("is_valid"):
            logger.warning(f"API 응답 비정상: {data}")
            return pd.DataFrame()
        
        df = pd.DataFrame(data.get("result", []))

        if df.empty:
            return df
        
        df['region']      = keyword
        df['search_text'] = keyword

        return df
    
    def parse(self, df: pd.DataFrame) -> pd.DataFrame:
        if df.empty:
            return df
        
        base_df = pd.DataFrame(
            {col: pd.Series(dtype=dt) for col, dt in self.BASE_DATA_TYPES.items()},
            index=df.index
        )

        logger.info(f"sourceName >>> {self.PLATFORM_NAME}")
        base_df['source'] = self.PLATFORM_NAME

        base_df['platform'] = df['domain']

        base_df['title'] = df['title']
        base_df['company'] = df['title']

        base_df['offer'] = df['offer']

        base_df['content_link'] = df['url']
        base_df['company_link'] = df['url']

        media_norm = (
            df["media"].astype(str).str.strip()
        )
        base_df['campaign_channel'] = media_norm.map(MEDIA_MAP).fillna('etc')
        
        
        type_norm = (
            df["type"].astype(str).str.strip()
        )
        base_df['campaign_type'] = type_norm.map(TYPE_MAP).fillna("etc")
        
    
        base_df['apply_deadline'] = pd.to_datetime(df["apl_due_dt"], errors="coerce")
        base_df['review_deadline'] = pd.to_datetime(df["pub_due_dt"], errors="coerce")

        base_df['apply_from'] = pd.to_datetime(df["apl_stt_dt"], errors="coerce")
        
        # region과 search_text 필드 설정
        base_df['region'] = df['region']
        base_df['search_text'] = df['search_text']

        result = base_df.copy()
        
        # 문자열 양끝 공백 정리
        for col in result.select_dtypes(include="object").columns:
            result[col] = result[col].astype("string").str.strip()

        # NaT/NaN → None
        result = result.astype(object).where(pd.notna(result), None)

        result = result.drop_duplicates(
            subset=["platform", "title", "offer", "campaign_channel"],
            keep="first"
        ).reset_index(drop=True)
        
        return result.to_dict("records")
    
    def enrich(self, parsed_data: List[Dict[str, Any]], keyword: str = None) -> List[Dict[str, Any]]:
        """
        Inflexer: map API lat/lng → 조건부 보강 + 캐시 사용.
        """
        if not parsed_data:
            return []

        # --- 0) 기존 DB 스냅샷
        existing = self._load_existing_map()

        # --- 1) Inflexer map API
        request_url = "https://inflexer.net:5000/map"
        params = {"query": keyword, "type": "VST"}
        try:
            resp = requests.get(request_url, params=params, timeout=20)
            resp.raise_for_status()
            map_df = pd.DataFrame(resp.json().get("result", []))
        except Exception as e:
            self.logger.warning(f"[inflexer] map API 실패: {e}")
            map_df = pd.DataFrame()

        if not map_df.empty:
            map_df = map_df.rename(columns={"latitude": "lat", "longitude": "lng", "title": "title"})[
                ["title", "lat", "lng"]
            ]

        merged = pd.DataFrame(parsed_data).merge(map_df, on="title", how="left", suffixes=("", "_map"))
        for c in ("address", "lat", "lng", "category_id"):
            if c not in merged.columns:
                merged[c] = None

        # --- 2) 준비물
        engine = create_engine(self.settings.db.url)
        search_api_keys = self.get_api_keys()
        map_id = self.settings.naver_api.MAP_CLIENT_ID
        map_secret = self.settings.naver_api.MAP_CLIENT_SECRET

        # --- 3) 루프
        processed = geocoded = from_mapxy = drift_fixed = 0

        for i, row in merged.iterrows():
            key = (row["platform"], row["title"], row["offer"], row["campaign_channel"])
            db_row = existing.get(key)

            # pandas NA 값 안전 처리
            addr_val = row.get("address")
            cur_addr = None if pd.isna(addr_val) else ((addr_val or "").strip() or None)
            cur_lat = row.get("lat") or row.get("lat_map")
            cur_lng = row.get("lng") or row.get("lng_map")
            if pd.isna(cur_lat): cur_lat = None
            if pd.isna(cur_lng): cur_lng = None

            # 3-1) 주소가 없으면 local.search + mapx/mapy
            if not cur_addr and row.get("campaign_type") == "방문형":
                cache_row = self._get_local_cache(row["title"])
                if cache_row:
                    merged.at[i, "address"] = cache_row["address"]
                    merged.at[i, "lat"] = cache_row["lat"]
                    merged.at[i, "lng"] = cache_row["lng"]
                    
                    cat = cache_row["category"]
                    if isinstance(cat, str):
                        raw_id = get_or_create_raw_category(engine, cat)
                        cat = find_mapped_category_id(engine, raw_id)
                    merged.at[i, "category_id"] = cat
                    cur_addr = cache_row["address"]
                    cur_lat, cur_lng = cache_row["lat"], cache_row["lng"]

                else:
                    place = naver_local_search(search_api_keys, row["title"])
                    if place:
                        addr = place.get("roadAddress") or place.get("address")
                        raw_cat = place.get("category")
                        lat_m, lng_m = self._from_mapxy(place)

                        if addr:
                            merged.at[i, "address"] = addr
                            cur_addr = addr
                        if lat_m and lng_m:
                            merged.at[i, "lat"], merged.at[i, "lng"] = lat_m, lng_m
                            cur_lat, cur_lng = lat_m, lng_m
                            from_mapxy += 1

                        if raw_cat:
                            raw_id = get_or_create_raw_category(engine, raw_cat)
                            if raw_id:
                                merged.at[i, "category_id"] = find_mapped_category_id(engine, raw_id)
                                
                        if raw_cat:
                            raw_id = get_or_create_raw_category(engine, raw_cat)
                            mapped_id = find_mapped_category_id(engine, raw_id)
                            merged.at[i, "category_id"] = mapped_id
                            self._put_local_cache(row["title"], addr, lat_m, lng_m, mapped_id)
                                
                    

                        # local_cache
                        if addr and lat_m and lng_m:
                            self._put_local_cache(row["title"], addr, lat_m, lng_m, raw_cat)
                    time.sleep(0.2)

            # 3-2) 주소는 있는데 좌표가 없으면 geocode + 캐시
            if cur_addr and (cur_lat is None or cur_lng is None):
                cached = self._get_geocode_cache(cur_addr)
                if cached:
                    cur_lat, cur_lng = cached
                    merged.at[i, "lat"], merged.at[i, "lng"] = cur_lat, cur_lng
                else:
                    coords = naver_geocode(map_id, map_secret, cur_addr)
                    if coords:
                        cur_lat, cur_lng = coords
                        merged.at[i, "lat"], merged.at[i, "lng"] = coords
                        self._put_geocode_cache(cur_addr, *coords)
                        # ✅ local_cache에도 기록
                        self._put_local_cache(row["title"], cur_addr, coords[0], coords[1], merged.at[i, "category_id"])
                        geocoded += 1
                time.sleep(0.2)

            # 3-3) DB 좌표와 드리프트 체크
            if db_row and all(v is not None for v in (db_row.get("lat"), db_row.get("lng"), cur_lat, cur_lng)) and cur_addr:
                dist = self._haversine(float(db_row["lat"]), float(db_row["lng"]), float(cur_lat), float(cur_lng))
                if dist and dist > DRIFT_METERS:
                    coords = naver_geocode(map_id, map_secret, cur_addr)
                    if coords:
                        cur_lat, cur_lng = coords
                        merged.at[i, "lat"], merged.at[i, "lng"] = cur_lat, cur_lng
                        self._put_geocode_cache(cur_addr, *coords)
                        # ✅ local_cache도 보정값으로 갱신
                        self._put_local_cache(row["title"], cur_addr, coords[0], coords[1], merged.at[i, "category_id"])
                        drift_fixed += 1
                        geocoded += 1
                    time.sleep(0.2)

            # 3-4) 끝까지 좌표 없고 DB 좌표가 있으면 fallback
            if (merged.at[i, "lat"] is None or merged.at[i, "lng"] is None) and db_row:
                merged.at[i, "lat"] = db_row.get("lat")
                merged.at[i, "lng"] = db_row.get("lng")

            processed += 1

        self.logger.info(f"[inflexer] enrich 통계 → 처리:{processed}, mapxy:{from_mapxy}, geocode:{geocoded}, drift_fix:{drift_fixed}")

        # --- 4) 최종 반환
        final_cols = [c for c in self.RESULT_TABLE_COLUMNS if c in merged.columns]
        final_df = merged.reindex(columns=final_cols).astype(object).where(pd.notna(merged), None)
        return final_df.to_dict("records")

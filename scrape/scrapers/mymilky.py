# scrapers/mymilky.py (API 기반 최종 동작 버전)

from core.base import BaseScraper
from core.logger import get_logger
from typing import Any, List, Dict, Optional
import pandas as pd
import re
from datetime import datetime, timedelta
import time
import json
import requests
from urllib.parse import quote

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from core.enricher import (
    naver_local_search,
    naver_geocode,
    get_or_create_raw_category,
    find_mapped_category_id,
)

log = get_logger("scraper.mymilky")

class MyMilkyScraper(BaseScraper):
    PLATFORM_NAME = "mymilky"
    BASE_URL = "https://mymilky.co.kr/api/campaigns"

    def scrape(self, keyword: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        [API 버전] mymilky API를 호출하여 모든 페이지의 캠페인 데이터를 가져옵니다.
        """
        all_campaign_data = []
        page = 1
        limit = 500

        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
            'Referer': 'https://mymilky.co.kr/',
        }
        
        
        
        while True:
            params = {
                'page': page,
                'limit': limit,
                'order': 'recent',
            }
            if keyword:
                params['q'] = keyword
            
            log.info(f"API 호출 중... (Page: {page}, Keyword: {keyword or 'None'})")
            try:
                response = requests.get(
                        self.BASE_URL, 
                        params=params, 
                        headers=headers, 
                        timeout=20,
                    )
                
                response.raise_for_status()
                data = response.json()
                campaigns_on_page = data.get('data', [])
                
                if not campaigns_on_page:
                    log.info("API로부터 더 이상 데이터를 받지 못했습니다. 스크레이핑을 종료합니다.")
                    break
                    
                all_campaign_data.extend(campaigns_on_page)
                log.info(f"캠페인 {len(campaigns_on_page)}개 수집 완료. (누적: {len(all_campaign_data)} / 전체: {data.get('total')})")

                total = data.get('total', 0)
                if not total or page * limit >= total:
                    log.info("마지막 페이지에 도달했습니다.")
                    break
                page += 1
                time.sleep(1)
            except requests.RequestException as e:
                log.error(f"API 호출 중 에러 발생: {e}", exc_info=True)
                break
        return all_campaign_data


    def parse(self, api_data: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        [수정] channel 필드의 다양한 JSON 형식을 모두 처리하도록 수정합니다.
        """
        log.info(f"API 데이터 {len(api_data)}건 파싱 시작...")
        
        all_campaigns_mapped = []
        for item in api_data:
            try:
                campaign_channel = 'etc'  # 기본값
                channel_str = item.get('channel')

                if channel_str:
                    try:
                        channel_data = json.loads(channel_str)
                        
                        # 1. 파싱 결과가 리스트인 경우 (예: [{'channel': 'blog'}, ...])
                        if isinstance(channel_data, list):
                            channels = [
                                d.get('channel', '').lower()
                                for d in channel_data
                                if d.get('channel')
                            ]
                            if channels:
                                # 쉼표로 구분된 문자열로 만듭니다. 예: "blog,instagram,youtube"
                                campaign_channel = ",".join(sorted(channels))
                        
                        # 2. 파싱 결과가 딕셔너리인 경우 (예: {'channel': 'blog'})
                        elif isinstance(channel_data, dict):
                            channel_val = channel_data.get('channel')
                            if channel_val:
                                campaign_channel = channel_val.lower()

                    except (json.JSONDecodeError, TypeError):
                        # channel 필드가 JSON 문자열이 아닌 일반 텍스트인 경우
                        campaign_channel = channel_str.lower()
                # ----------------------------------------------------
                
                business_name = item.get('business_name')
                
                mapped_data = {
                    "source": self.PLATFORM_NAME,
                    "platform": item.get('platform'),
                    "company": business_name,
                    "title": business_name,
                    "offer": item.get('details'),
                    "campaign_channel": campaign_channel, # ❗️ 처리된 최종 값을 사용
                    "content_link": item.get('detail_link'),
                    "company_link": item.get('detail_link'),
                    "campaign_type": item.get('type'),
                    "region": item.get('location'),
                    "address": item.get('address') or None,
                    "apply_deadline": item.get('end_date'),
                    "review_deadline": item.get('review_deadline'),
                    "img_url": item.get('thumbnail_image'),
                    "apply_from": item.get('start_date'),
                    "search_text": f"{business_name} {item.get('details')}",
                }
                all_campaigns_mapped.append(mapped_data)
            except Exception as e:
                log.error(f"JSON 데이터 매핑 중 에러: {e}, Item: {item}")
                continue
        return all_campaigns_mapped
    
    
    def enrich(self, parsed_data: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        mapx/mapy → 1차 좌표 채우기, 필요할 때만 geocode 보강.
        - 주소 없으면 local.search로 주소/카테고리 + mapx/mapy 좌표 획득
        - 주소는 있는데 좌표가 없으면: (런타임) 캐시 → geocode
        - 기존 DB 좌표와 드리프트 > 50m면 geocode로 보정
        - 좌표가 끝내 없고 DB에는 있으면 DB 좌표 fallback
        """
        if not parsed_data:
            return []
        
        existing = self._load_existing_map()

        # --- 1) DataFrame 준비 / 전처리
        raw_df = pd.DataFrame(parsed_data)
        df = raw_df.drop_duplicates(
            subset=["platform", "title", "offer", "campaign_channel"],
            keep="first"
        )
        df = df[df["platform"] != "클라우드리뷰"].copy()
        
        for col in df.select_dtypes(include=["object"]).columns:
            df[col] = df[col].astype("string").str.strip()

        df["apply_deadline"] = pd.to_datetime(df["apply_deadline"], errors="coerce").dt.tz_localize(None)
        df["review_deadline"] = pd.to_datetime(df["review_deadline"], errors="coerce").dt.tz_localize(None)

        for c in ("lat", "lng", "category_id"):
            if c not in df.columns:
                df[c] = pd.NA

        # --- 2) 준비물
        engine = create_engine(self.settings.db.url)
        search_api_keys = self.get_api_keys()
        map_id = self.settings.naver_api.MAP_CLIENT_ID
        map_secret = self.settings.naver_api.MAP_CLIENT_SECRET

        processed = 0
        geocoded = 0
        from_mapxy = 0
        drift_fixed = 0

        # --- 3) 보강 루프
        for i, row in df.iterrows():
            key = (row["platform"], row["title"], row["offer"], row["campaign_channel"])
            db_row = existing.get(key)

            # pandas NA 값 안전 처리
            title_val = row.get("title")
            if pd.isna(title_val):
                title = ""
            else:
                title = (title_val or "").replace("[", "").replace("]", " ").strip()

            addr_val = row.get("address")
            cur_addr = None if pd.isna(addr_val) else ((addr_val or "").strip() or None)
            cur_lat  = row.get("lat")
            cur_lng  = row.get("lng")
            if pd.isna(cur_lat): cur_lat = None
            if pd.isna(cur_lng): cur_lng = None

            # 3-1) 주소가 없으면 local.search
            if not cur_addr and row.get("campaign_type") == "방문형":
                cache_row = self._get_local_cache(title)
                if cache_row:
                    df.at[i, "address"] = cache_row["address"]
                    df.at[i, "lat"] = cache_row["lat"]
                    df.at[i, "lng"] = cache_row["lng"]
                    
                    cat = cache_row["category"]
                    if isinstance(cat, str):   # ✅ 문자열이면 매핑 재시도
                        raw_id = get_or_create_raw_category(engine, cat)
                        cat = find_mapped_category_id(engine, raw_id)
                    df.at[i, "category_id"] = cat    # ✅ 항상 정수/None만 들어감
                    
                    cur_addr = cache_row["address"]
                    cur_lat, cur_lng = cache_row["lat"], cache_row["lng"]

                else:
                    place = naver_local_search(search_api_keys, title)
                    if place:
                        addr = place.get("roadAddress") or place.get("address")
                        raw_cat = place.get("category")   # ✅ 먼저 추출
                        lat_m, lng_m = self._from_mapxy(place)

                        if addr:
                            df.at[i, "address"] = addr
                            cur_addr = addr
                        if lat_m is not None and lng_m is not None:
                            df.at[i, "lat"] = lat_m
                            df.at[i, "lng"] = lng_m
                            cur_lat, cur_lng = lat_m, lng_m
                            from_mapxy += 1

                        if raw_cat:
                            raw_id = get_or_create_raw_category(engine, raw_cat)
                            mapped_id = find_mapped_category_id(engine, raw_id)
                            df.at[i, "category_id"] = mapped_id   # ✅ bigint만 들어감
                            # local_cache에도 숫자 ID 저장
                            if addr and lat_m and lng_m:
                                self._put_local_cache(title, addr, lat_m, lng_m, mapped_id)   # ✅ 변경

                    time.sleep(0.2)

            # 3-2) 주소는 있는데 좌표가 없으면 캐시 → geocode
            if cur_addr and (cur_lat is None or cur_lng is None):
                cached = self._get_geocode_cache(cur_addr)
                if cached:
                    cur_lat, cur_lng = cached
                    df.at[i, "lat"], df.at[i, "lng"] = cur_lat, cur_lng
                else:
                    coords = naver_geocode(map_id, map_secret, cur_addr)
                    if coords:
                        cur_lat, cur_lng = coords
                        df.at[i, "lat"], df.at[i, "lng"] = coords
                        self._put_geocode_cache(cur_addr, *coords)   # ✅ 캐시에 저장
                        geocoded += 1
                time.sleep(0.2)

            # 3-3) 드리프트 체크 → 50m 초과 시 geocode로 보정
            if db_row and all(v is not None for v in (db_row.get("lat"), db_row.get("lng"), cur_lat, cur_lng)) and cur_addr:
                dist = self._haversine(float(db_row["lat"]), float(db_row["lng"]), float(cur_lat), float(cur_lng))
                if dist is not None and dist > 50:
                    coords = naver_geocode(map_id, map_secret, cur_addr)
                    if coords:
                        cur_lat, cur_lng = coords
                        df.at[i, "lat"] = cur_lat
                        df.at[i, "lng"] = cur_lng
                        self._put_geocode_cache(cur_addr, *coords)   # ✅ drift_fix도 캐시에 기록
                        drift_fixed += 1
                        geocoded += 1
                    time.sleep(0.2)

            # 3-4) 여전히 좌표 없고 DB에는 있으면 fallback
            if (df.at[i, "lat"] is None or pd.isna(df.at[i, "lat"]) or
                df.at[i, "lng"] is None or pd.isna(df.at[i, "lng"])) and db_row:
                if db_row.get("lat") is not None and db_row.get("lng") is not None:
                    df.at[i, "lat"] = db_row["lat"]
                    df.at[i, "lng"] = db_row["lng"]

            processed += 1

        log.info(f"[mymilky] enrich 통계 → 처리:{processed}, mapxy:{from_mapxy}, geocode:{geocoded}, drift_fix:{drift_fixed}")

        # --- 4) 최종 반환
        final_columns = [c for c in self.RESULT_TABLE_COLUMNS if c in df.columns]
        final_df = df.reindex(columns=final_columns).astype(object).where(pd.notna(df), None)
        return final_df.to_dict("records")
    
    
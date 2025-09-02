import os
import requests
import pandas as pd
from core.base import BaseScraper
from core.logger import get_logger
import time

from typing import List, Dict, Any


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

        result = base_df.copy()
        
         # 문자열 양끝 공백 정리
        for col in result.select_dtypes(include="object").columns:
            result[col] = result[col].astype("string").str.strip()

        # NaT/NaN → None
        result = result.astype(object).where(pd.notna(result), None)

        print(result.head)
        return result.to_dict("records")
    
    def enrich(self, parsed_data: List[Dict[str, Any]], keyword: str) -> List[Dict[str, Any]]:
        """
        파싱된 데이터를 보강합니다. (예: 주소/좌표 채우기)
        """

        request_url = "https://inflexer.net:5000/map"
        params = {
            'query': keyword,
            'type': 'VST'
        }

        resp = requests.get(request_url, params=params)
        data = resp.json()
        map_df = pd.DataFrame(data.get("result", []))
        if map_df.empty:
            return []
        map_df = map_df.rename(
            columns={
                "latitude": "lat",
                "longitude": "lng",
                "title": "title",
                }
            )[
                ["title", "lat", "lng"]
                ]
        


        parsed_df = pd.DataFrame(parsed_data)
        merged_df = parsed_df.merge(map_df, on="title", how="left", suffixes=("", "_map"))
        merged_df = merged_df.astype(object).where(pd.notna(merged_df), None)

        # 임시 테이블2 구성 (필요 컬럼 보장)
        for col in ["title", "lat", "lng", "address"]:
            if col not in merged_df.columns:
                merged_df[col] = None
            

        tmp = (
            merged_df
            .query("campaign_type == '방문형'")
            [["title", "lat", "lng", "address"]]
            .copy()
            .dropna(subset=["title"])              # title 없는 건 스킵
            .drop_duplicates(subset=["title"])     # title 기준 중복 제거
            .reset_index(drop=True)
        )

        if tmp.empty:
            # 붙일 게 없으면 원본 반환
            return merged_df.astype(object).where(pd.notna(merged_df), None).to_dict("records")
        
        search_api_keys = self.get_api_keys()
        map_id = self.settings.naver_api.MAP_CLIENT_ID
        map_secret = self.settings.naver_api.MAP_CLIENT_SECRET


         # 2) address 보강 + 3) 좌표 보강
        for i, row in tmp.iterrows():
            title = (row["title"] or "").strip()
            cur_addr = row.get("address")
            cur_lat  = row.get("lat")
            cur_lng  = row.get("lng")

            # 주소가 없으면 로컬 검색
            if not cur_addr:
                place = naver_local_search(search_api_keys, title)
                if place:
                    addr = place.get("roadAddress") or place.get("address")
                    if addr:
                        tmp.at[i, "address"] = addr
                        cur_addr = addr

            # 좌표가 비어있으면 지오코딩
            need_geo = cur_lat is None or cur_lng is None
            if need_geo and cur_addr:
                coords = naver_geocode(map_id, map_secret, cur_addr)
                if coords:
                    lat, lng = coords
                    tmp.at[i, "lat"] = lat
                    tmp.at[i, "lng"] = lng

            # 너무 빠른 호출 방지 약간의 텀
            time.sleep(0.2)

        # tmp 컬럼 이름 명확화(충돌 방지)
        tmp = tmp.rename(columns={"address": "address_enriched", "lat": "lat_enriched", "lng": "lng_enriched"})

        # 4) 원본에 붙이고 보강값 우선 적용
        merged = merged_df.merge(tmp, on="title", how="left")

        # 보강값이 있으면 우선 적용
        def _prefer_enriched(row, base_col, enrich_col):
            return row[enrich_col] if pd.notna(row.get(enrich_col)) else row.get(base_col)
        
        merged["address"] = merged.apply(lambda r: _prefer_enriched(r, "address", "address_enriched"), axis=1)
        merged["lat"]     = merged.apply(lambda r: _prefer_enriched(r, "lat",     "lat_enriched"), axis=1)
        merged["lng"]     = merged.apply(lambda r: _prefer_enriched(r, "lng",     "lng_enriched"), axis=1)

        # 보강용 임시 컬럼 제거
        merged = merged.drop(columns=["address_enriched", "lat_enriched", "lng_enriched"], errors="ignore")

        # NaN → None
        merged = merged.astype(object).where(pd.notna(merged), None)

        return merged.to_dict("records")
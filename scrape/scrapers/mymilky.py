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
        [단순화 버전] 데이터를 정제하고, 주소가 비어있는 경우에만 API로 보강합니다.
        """
        log.info(f"총 {len(parsed_data)}개 데이터의 Enrich 단계 시작...")
        if not parsed_data: return []

        raw_df = pd.DataFrame(parsed_data)

        # 1. 중복 제거 및 필터링 후 독립적인 복사본 생성
        df = raw_df.drop_duplicates(subset=['platform', 'title', 'offer', 'campaign_channel'], keep='first')
        df = df[df['platform'] != '클라우드리뷰'].copy()
        log.info(f"중복 및 플랫폼 필터링 후 처리 대상: {len(df)}건")
        if df.empty: return []
        
        log.info("모든 텍스트 데이터의 양 끝 공백을 제거합니다...")
        # DataFrame에서 'object' 타입 (주로 문자열)인 컬럼들만 선택
        string_columns = df.select_dtypes(include=['object']).columns
        
        # 각 텍스트 컬럼에 대해 .str.strip() 함수를 적용
        for col in string_columns:
            df[col] = df[col].str.strip()
        log.info("공백 제거 완료.")

        # 3. 날짜 형식 변환 (API에서 받은 날짜 문자열 -> datetime 객체)
        df['apply_deadline'] = pd.to_datetime(df['apply_deadline'], errors='coerce').dt.tz_localize(None)
        df['review_deadline'] = pd.to_datetime(df['review_deadline'], errors='coerce').dt.tz_localize(None)

        # 4. 주소 정보가 비어있는 '방문형' 캠페인에 대해서만 Naver API 보강
        df['lat'] = pd.NA
        df['lng'] = pd.NA
        df['category_id'] = pd.NA

        to_enrich_df = df[(df['campaign_type'] == '방문형') & (df['address'].isnull() | (df['address'] == ''))].copy()
        
        if not to_enrich_df.empty:
            log.info(f"주소가 비어있는 '방문형' 캠페인 {len(to_enrich_df)}건에 대해 주소 보강을 시작합니다.")
            engine = create_engine(self.settings.db.url)
            search_api_keys = self.get_api_keys()
            geocoded_success_count = 0

            for index, row in to_enrich_df.iterrows():
                query = row['title'].replace('[', '').replace(']', ' ')
                place = naver_local_search(search_api_keys, query)
                if place:
                    address = place.get("roadAddress") or place.get("address")
                    lat, lng, std_id = (None, None, None)
                    if address:
                        coords = naver_geocode(self.settings.naver_api.MAP_CLIENT_ID, self.settings.naver_api.MAP_CLIENT_SECRET, address)
                        if coords: 
                            lat, lng = coords
                            geocoded_success_count += 1
                    raw_category_text = place.get("category")
                    if raw_category_text:
                        raw_id = get_or_create_raw_category(engine, raw_category_text)
                        if raw_id: std_id = find_mapped_category_id(engine, raw_id)
                    
                    df.loc[index, ['address', 'lat', 'lng', 'category_id']] = [address, lat, lng, std_id]
                time.sleep(0.5)
            log.info(f"주소 보강 완료: 총 {len(to_enrich_df)}건 중 {geocoded_success_count}건의 위도/경도 정보를 추가")

        # 4. 최종 컬럼 선택 및 반환
        final_columns = [col for col in self.RESULT_TABLE_COLUMNS if col in df.columns]
        final_df = df.reindex(columns=final_columns) # reindex로 순서 및 존재 보장
        final_df = final_df.astype(object).where(pd.notna(final_df), None)
        return final_df.to_dict('records')
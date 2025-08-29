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
        limit = 50

        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
            'Referer': 'https://mymilky.co.kr/',
        }
        
        while True:
            params = {
                'page': 2, 
                'limit': 19, 
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
        [API 버전] API JSON 데이터 리스트를 DB 스키마에 맞게 매핑합니다.
        """
        log.info(f"API 데이터 {len(api_data)}건 파싱 시작...")
        all_campaigns_mapped = []
        for item in api_data:
            try:
                channel_info = json.loads(item.get('channel', '{}'))
                business_name = item.get('business_name')
                
                mapped_data = {
                    "source": self.PLATFORM_NAME,
                    "platform": item.get('platform'),
                    "company": business_name,
                    "title": business_name,
                    "offer": item.get('details'),
                    "campaign_channel": channel_info.get('channel', 'etc').lower(),
                    "content_link": item.get('detail_link'),
                    "company_link": item.get('detail_link'),
                    "campaign_type": item.get('type'),
                    "region": item.get('location'),
                    "address": item.get('address') or None,
                    "apply_deadline": item.get('end_date'),
                    "review_deadline": item.get('review_deadline'),
                    "img_url": item.get('thumbnail_image')
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

        # 2. 날짜 형식 변환 (API에서 받은 날짜 문자열 -> datetime 객체)
        df['apply_deadline'] = pd.to_datetime(df['apply_deadline'], errors='coerce').dt.tz_localize(None)
        df['review_deadline'] = pd.to_datetime(df['review_deadline'], errors='coerce').dt.tz_localize(None)

        # 3. 주소 정보가 비어있는 '방문형' 캠페인에 대해서만 Naver API 보강
        df['lat'] = pd.NA
        df['lng'] = pd.NA
        df['category_id'] = pd.NA

        to_enrich_df = df[(df['campaign_type'] == '방문형') & (df['address'].isnull() | (df['address'] == ''))].copy()
        
        if not to_enrich_df.empty:
            log.info(f"주소가 비어있는 '방문형' 캠페인 {len(to_enrich_df)}건에 대해 주소 보강을 시작합니다.")
            engine = create_engine(self.settings.db.url)
            search_api_keys = self._get_api_keys()

            for index, row in to_enrich_df.iterrows():
                query = row['title'].replace('[', '').replace(']', ' ')
                place = naver_local_search(search_api_keys, query)
                if place:
                    address = place.get("roadAddress") or place.get("address")
                    lat, lng, std_id = (None, None, None)
                    if address:
                        coords = naver_geocode(self.settings.naver_api.MAP_CLIENT_ID, self.settings.naver_api.MAP_CLIENT_SECRET, address)
                        if coords: lat, lng = coords
                    raw_category_text = place.get("category")
                    if raw_category_text:
                        raw_id = get_or_create_raw_category(engine, raw_category_text)
                        if raw_id: std_id = find_mapped_category_id(engine, raw_id)
                    
                    df.loc[index, ['address', 'lat', 'lng', 'category_id']] = [address, lat, lng, std_id]
                time.sleep(0.5)

        # 4. 최종 컬럼 선택 및 반환
        final_columns = [col for col in self.RESULT_TABLE_COLUMNS if col in df.columns]
        final_df = df.reindex(columns=final_columns) # reindex로 순서 및 존재 보장
        final_df = final_df.astype(object).where(pd.notna(final_df), None)
        log.info(f"Enrich 최종 완료:\n{final_df.head().to_string()}")
        return final_df.to_dict('records')

    def save(self, data: List[Dict[str, Any]]) -> None:
        if not data:
            log.warning("저장할 최종 데이터가 없습니다.")
            return

        log.info(f"정제된 최종 데이터 {len(data)}건을 DB에 저장 시작...")
        engine = create_engine(self.settings.db.url)
        Session = sessionmaker(bind=engine)
        
        with Session() as session:
            try:
                # ❗️ [수정] UPSERT 구문을 DB 스키마와 완전히 일치시킵니다.
                upsert_sql = text(f"""
                    INSERT INTO campaign (
                        platform, title, offer, campaign_channel, company, content_link, 
                        company_link, source, campaign_type, region, apply_deadline, 
                        review_deadline, address, lat, lng, category_id, img_url
                    ) VALUES (
                        :platform, :title, :offer, :campaign_channel, :company, :content_link, 
                        :company_link, :source, :campaign_type, :region, :apply_deadline, 
                        :review_deadline, :address, :lat, :lng, :category_id, :img_url
                    )
                    ON CONFLICT (platform, title, offer, campaign_channel) DO UPDATE SET
                        company = EXCLUDED.company, source = EXCLUDED.source,
                        content_link = EXCLUDED.content_link, company_link = EXCLUDED.company_link,
                        campaign_type = EXCLUDED.campaign_type, region = EXCLUDED.region,
                        apply_deadline = EXCLUDED.apply_deadline, review_deadline = EXCLUDED.review_deadline,
                        address = EXCLUDED.address, lat = EXCLUDED.lat, lng = EXCLUDED.lng,
                        category_id = EXCLUDED.category_id, img_url = EXCLUDED.img_url,
                        updated_at = NOW();
                """)
                session.execute(upsert_sql, data)
                session.commit()
                log.info(f"DB 저장 완료. 총 {len(data)}건의 데이터가 성공적으로 처리되었습니다.")
            except Exception as e:
                log.error(f"DB 저장 중 에러 발생: {e}", exc_info=True)
                session.rollback()

    def _get_api_keys(self) -> list:
        keys = []
        if self.settings.naver_api.SEARCH_CLIENT_ID and self.settings.naver_api.SEARCH_CLIENT_SECRET:
            keys.append((self.settings.naver_api.SEARCH_CLIENT_ID, self.settings.naver_api.SEARCH_CLIENT_SECRET))
        if self.settings.naver_api.SEARCH_CLIENT_ID_2 and self.settings.naver_api.SEARCH_CLIENT_SECRET_2:
            keys.append((self.settings.naver_api.SEARCH_CLIENT_ID_2, self.settings.naver_api.SEARCH_CLIENT_SECRET_2))
        if self.settings.naver_api.SEARCH_CLIENT_ID_3 and self.settings.naver_api.SEARCH_CLIENT_SECRET_3:
            keys.append((self.settings.naver_api.SEARCH_CLIENT_ID_3, self.settings.naver_api.SEARCH_CLIENT_SECRET_3))
        return keys
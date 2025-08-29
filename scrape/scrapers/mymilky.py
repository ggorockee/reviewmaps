from core.base import BaseScraper
from core.logger import get_logger
from typing import Any, List, Dict
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
import pandas as pd
from bs4 import BeautifulSoup
from pprint import pformat
from typing import Optional
import re
from datetime import datetime, timedelta
from sqlalchemy import create_engine
from core.enricher import (
    naver_local_search,
    naver_geocode,
    get_or_create_raw_category,
    find_mapped_category_id,
)
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
import time
log = get_logger("mymilky")
from selenium.common.exceptions import TimeoutException # TimeoutException 임포트 추가



class MyMilkyScraper(BaseScraper):
    """
    mymilky.co.kr 사이트용 스크레이퍼입니다.
    """

    PLATFORM_NAME = "mymilky"
    BASE_URL = "https://mymilky.co.kr/"

    def scrape(self) -> str:
        """
        사이트에 접속하고 버튼 클릭 후, 초기 목록 로딩을 확인하고,
        성공했을 경우에만 최대 10번까지 무한 스크롤을 실행합니다.
        """
        log.info(f"{self.PLATFORM_NAME} 사이트 접속 시도: {self.BASE_URL}")
        self.driver.get(self.BASE_URL)

        # 1. 버튼 클릭
        button_locator = (By.XPATH, '//*[@id="__nuxt"]/div/main/section[1]/div/div[2]/div/img')
        log.info("캠페인 목록을 보기 위해 버튼 클릭을 시도합니다...")
        if not self._click_element(button_locator, timeout=15):
            log.error("버튼을 클릭하지 못해 스크레이핑을 중단합니다.")
            with open("click_fail_page.html", "w", encoding="utf-8") as f:
                f.write(self.driver.page_source)
            log.info("클릭 실패 당시의 페이지를 click_fail_page.html 로 저장했습니다.")
            return ""
        log.info("버튼 클릭 성공.")

        # 2. 초기 목록 로딩 확인 (스크레이핑 성공의 기준점)
        campaign_list_locator = (By.CSS_SELECTOR, "div.card-list > a.card-list__item")
        if not self._wait_and_find_element(campaign_list_locator, timeout=15):
            log.error("버튼 클릭 후 캠페인 목록을 찾지 못해 스크레이핑을 중단합니다.")
            with open("list_load_fail_page.html", "w", encoding="utf-8") as f:
                f.write(self.driver.page_source)
            log.info("목록 로딩 실패 당시의 페이지를 list_load_fail_page.html 로 저장했습니다.")
            return ""
        
        log.info("초기 캠페인 목록 로딩 완료. 이제 무한 스크롤을 시작합니다.")

        # 3. 무한 스크롤 실행
        # max_scrolls = 7
        scroll_count = 0
        last_height = self.driver.execute_script("return document.body.scrollHeight")

        while True:
            try:
                # 1. 스크롤 전 현재 아이템 개수 확인
                item_count_before_scroll = len(self.driver.find_elements(*campaign_list_locator))
                log.info(f"스크롤 전 아이템 개수: {item_count_before_scroll}")

                # 2. 페이지 맨 아래로 스크롤
                self.driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
                scroll_count += 1
                log.info(f"스크롤 다운 ({scroll_count}회)")

                # 3. [핵심] time.sleep() 대신, 아이템 개수가 늘어날 때까지 최대 10초간 기다림
                wait = WebDriverWait(self.driver, 10) # 10초 이상 응답이 없으면 끝으로 간주
                wait.until(
                    lambda driver: len(driver.find_elements(*campaign_list_locator)) > item_count_before_scroll
                )
                # log.info("새로운 아이템 로딩이 확인되었습니다.")
                if scroll_count == 7:
                    break

            except TimeoutException:
                # 10초간 기다려도 아이템 개수에 변화가 없으면, 페이지 끝으로 판단하고 종료
                log.info("페이지 끝에 도달하여 무한 스크롤을 종료합니다.")
                break # for 루프 탈출

        log.info("모든 캠페인 데이터 로딩 완료. 최종 페이지 소스를 반환합니다.")
        return self.driver.page_source

    
    def parse_remaining_days(self, text: str) -> Optional[int]:
        """
        "10일 남음", "오늘 마감" 등의 텍스트에서 남은 날짜를 정수(int)로 추출합니다.
        """
        if not isinstance(text, str):
            return None
            
        text = text.strip()

        # '오늘 마감'을 0으로 처리
        if "오늘 마감" in text:
            return 0
        # '마감' 또는 '종료'가 포함된 다른 경우는 -1로 처리 (이미 종료됨)
        if "마감" in text or "종료" in text:
            return -1

        # 정규표현식으로 텍스트에서 숫자(\d+)를 찾습니다.
        match = re.search(r'\d+', text)

        if match:
            # 숫자를 찾았다면 정수형으로 변환하여 반환
            return int(match.group(0))
        
        # 그 외("상시모집" 등)는 None을 반환
        return None


    def parse(self, html_content: str) -> List[Dict[str, Any]]:
        """
        HTML을 파싱하여, 정제되지 않은 데이터 딕셔너리의 리스트를 반환합니다.
        """
        log.info("HTML 파싱 시작...")
        soup = BeautifulSoup(html_content, 'lxml')
        campaign_items = soup.select("div.card-list > a.card-list__item")

        all_campaigns_data = []
        for item in campaign_items:
            try:
                if not item.select_one("div.card-content"): continue
                
                title = item.select_one("h3.card-title").get_text(strip=True)
                
                platform_elem = item.select_one("div:nth-of-type(3) > span:nth-of-type(1)")
                platform = platform_elem.get_text(strip=True) if platform_elem else None
                
                href = item['href']
                
                content_link = href if href.startswith('http') else self.BASE_URL.rstrip('/') + href
                
                offer = item.select_one("div.card-description").get_text(strip=True)
                
                tags = [tag.get_text(strip=True) for tag in item.select("div.card-tag__list > span")]
                
                days_left_text = item.select_one("span.card-date__text").get_text(strip=True)
                
                campaign_type_elem = item.select_one("div:nth-of-type(4) > span:nth-of-type(1)")
                campaign_type = campaign_type_elem.get_text(strip=True) if campaign_type_elem else None

                region_elem = item.select_one("div:nth-of-type(4) > span:nth-of-type(2)")
                region = region_elem.get_text(strip=True) if region_elem else None

                channel_img_elem = item.select_one("div.card-date img")
                campaign_channel = 'unknown'
                if channel_img_elem and 'src' in channel_img_elem.attrs:
                    channel_img_src = channel_img_elem['src']
                    if 'blog' in channel_img_src: campaign_channel = 'blog'
                    elif 'clip' in channel_img_src: campaign_channel = 'clip'
                    elif 'instagram' in channel_img_src: campaign_channel = 'instagram'
                    elif 'youtube' in channel_img_src: campaign_channel = 'youtube'
                    elif 'reels' in channel_img_src: campaign_channel = 'reels'

                days_left_elem = item.select_one("span.card-date__text")
                raw_days_left = days_left_elem.get_text(strip=True) if days_left_elem else None
                
                campaign_data = {
                    'source': self.PLATFORM_NAME,
                    'title': title,
                    'company': title,
                    'content_link': content_link,
                    'company_link': content_link,
                    'offer': offer,
                    'platform': platform,
                    'campaign_type': campaign_type,
                    'region': region,
                    'campaign_channel': campaign_channel,
                    'raw_days_left': raw_days_left,
                }
                all_campaigns_data.append(campaign_data)
            except Exception as e:
                log.error(f"개별 아이템 파싱 중 에러: {e}")
                continue
        return all_campaigns_data


    def enrich(self, parsed_data: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        파싱된 데이터 리스트를 DataFrame으로 변환하고, 데이터를 정제 및 보강합니다.
        최종적으로 다시 데이터 리스트 형태로 반환합니다.
        """
        log.info(f"총 {len(parsed_data)}개 데이터의 Enrich 단계 시작...")
        raw_df = pd.DataFrame(parsed_data)

        if raw_df.empty:
            return []
        
        # 0. 중복제거
        log.info(f"DataFrame 변환 완료. 중복 제거 전 데이터: {len(raw_df)}건")
        dedup_df = raw_df.drop_duplicates(subset=['platform', 'company', 'offer'], keep='last').copy()
        dropped_count = len(raw_df) - len(dedup_df)
        if dropped_count > 0:
            log.info(f"중복된 데이터 {dropped_count}건을 제거했습니다. 처리 대상: {len(dedup_df)}건")


        if dedup_df.empty:
            return []
        original_count = len(dedup_df)
        filterd_df = dedup_df[dedup_df['platform'] != '클라우드리뷰'].copy()
        
        filtered_count = original_count - len(filterd_df)
        if filtered_count > 0:
            log.info(f"'클라우드리뷰' 플랫폼 데이터 {filtered_count}건을 제외했습니다.")
        log.info(f"플랫폼 필터링 후 처리 대상: {len(filterd_df)}건")
        
        filterd_df['address'] = None
        filterd_df['lat'] = pd.NA
        filterd_df['lng'] = pd.NA
        filterd_df['category_id'] = pd.NA
        
        # 1. days_left 컬럼 정제
        filterd_df['days_left'] = filterd_df['raw_days_left'].apply(self._parse_remaining_days)
        enriched_df = filterd_df.drop(['raw_days_left'], axis=1)
        log.info(f"데이터 정제 및 보강 완료 (days_left 추가) 완료")

        # 2. 마감일자 계산
        enriched_df['apply_deadline'] = enriched_df['days_left'].apply(self._calculate_deadline)
        log.info(f"데이터 정제 및 보강 완료 (apply_deadline 추가) 완료:")

        engine = create_engine(self.settings.db.url)

        # .env 파일에서 Naver API 키 목록 준비
        search_api_keys = []
        if self.settings.naver_api.SEARCH_CLIENT_ID and self.settings.naver_api.SEARCH_CLIENT_SECRET:
            search_api_keys.append((self.settings.naver_api.SEARCH_CLIENT_ID, self.settings.naver_api.SEARCH_CLIENT_SECRET))
        if self.settings.naver_api.SEARCH_CLIENT_ID_2 and self.settings.naver_api.SEARCH_CLIENT_SECRET_2:
            search_api_keys.append((self.settings.naver_api.SEARCH_CLIENT_ID_2, self.settings.naver_api.SEARCH_CLIENT_SECRET_2))
        if self.settings.naver_api.SEARCH_CLIENT_ID_3 and self.settings.naver_api.SEARCH_CLIENT_SECRET_3:
            search_api_keys.append((self.settings.naver_api.SEARCH_CLIENT_ID_3, self.settings.naver_api.SEARCH_CLIENT_SECRET_3))

        if not search_api_keys:
            log.error("사용 가능한 Naver Search API 키가 없습니다. .env 파일을 확인하세요.")
            # API 키가 없으면 보강 없이 원본 데이터를 반환
            return enriched_df
        


        engine = create_engine(self.settings.db.url)


        visit_campaigns = enriched_df[enriched_df['campaign_type'] == '방문형']
        log.info(f"'방문형' 캠페인 {len(visit_campaigns)}건에 대해 주소 보강을 시작합니다.")


        if not visit_campaigns.empty and search_api_keys:
            for index, row in visit_campaigns.iterrows():
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
                    
                    # .loc를 사용하여 원본 DataFrame(df)의 값을 직접 업데이트.
                    enriched_df.loc[index, ['address', 'lat', 'lng', 'category_id']] = [address, lat, lng, std_id]
                
                time.sleep(0.5) # API 호출 간 예의를 지키는 대기


        final_columns = [col for col in self.RESULT_TABLE_COLUMNS if col in enriched_df.columns]
        final_df = enriched_df[final_columns]
        
        # 5. DB 저장을 위한 최종 데이터 타입 변환
        final_df = final_df.astype(object).where(pd.notna(final_df), None)

        # log.info(f"Enrich 최종 완료:\n{final_df.head().to_string()}")
        return final_df.to_dict('records')


    def _calculate_deadline(self, days_offset):
        today_in_seoul = datetime.now(self.settings.batch.tz).date()
        # log.info(f"마감일 계산 기준 날짜 (Asia/Seoul): {today_in_seoul}")

        # days_left 값이 유효한 숫자일 경우 (NaN이 아닐 경우)
        if pd.notna(days_offset):
            # '오늘' 날짜에 남은 일수를 더합니다.
            return today_in_seoul + timedelta(days=int(days_offset))
        # '상시모집' 등으로 인해 days_left가 NaN인 경우는 None(NaT)을 반환
        return None
    
    def _parse_remaining_days(self, text: str) -> Optional[int]:
        # 이전의 숫자 변환 함수를 내부 헬퍼 메서드로 변경
        if not isinstance(text, str): return None
        text = text.strip()
        if "오늘 마감" in text: return 0
        if "마감" in text or "종료" in text: return -1
        match = re.search(r'\d+', text)
        return int(match.group(0)) if match else None

    def save(self, data: List[Dict[str, Any]]) -> None:
        """
        Enrich가 완료된 최종 데이터를 DB에 UPSERT 방식으로 저장합니다.
        """
        if not data:
            log.warning("저장할 최종 데이터가 없습니다.")
            return

        log.info(f"정제된 최종 데이터 {len(data)}건을 DB에 저장 시작...")

        engine = create_engine(self.settings.db.url)
        Session = sessionmaker(bind=engine)        
        upsert_sql = text(f"""
                    INSERT INTO campaign (
                        -- 고유 키 --
                        platform, company, offer,
                        -- 기본 정보 --
                        title, content_link, company_link, source,
                        -- 캠페인 정보 --
                        campaign_type, region, campaign_channel, apply_deadline,
                        -- 보강된 정보 --
                        address, lat, lng, category_id
                    ) VALUES (
                        :platform, :company, :offer,
                        :title, :content_link, :company_link, :source,
                        :campaign_type, :region, :campaign_channel,
                        :apply_deadline,
                        :address, :lat, :lng, :category_id
                    )
                    ON CONFLICT (platform, company, offer) DO UPDATE SET
                        -- 업데이트할 필드들 --
                        title = EXCLUDED.title,
                        source = EXCLUDED.source,
                        content_link = EXCLUDED.content_link,
                        company_link = EXCLUDED.company_link,
                        campaign_type = EXCLUDED.campaign_type,
                        region = EXCLUDED.region,
                        campaign_channel = EXCLUDED.campaign_channel,
                        apply_deadline = EXCLUDED.apply_deadline,
                        address = EXCLUDED.address,
                        lat = EXCLUDED.lat,
                        lng = EXCLUDED.lng,
                        category_id = EXCLUDED.category_id,
                        updated_at = NOW();
                """)
        
        with Session() as session:
            try:
                session.execute(upsert_sql, data)
                session.commit()
                log.info(f"DB 저장 완료. 총 {len(data)}건의 데이터가 성공적으로 처리되었습니다.")
            except Exception as e:
                log.error(f"DB 저장 중 에러 발생: {e}", exc_info=True)
                session.rollback()


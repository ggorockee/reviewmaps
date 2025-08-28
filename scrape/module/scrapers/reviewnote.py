from __future__ import annotations
from typing import List
import pandas as pd
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException, NoSuchElementException
from selenium.webdriver import ActionChains
from selenium.webdriver.common.keys import Keys

import time
import re


from .base import BaseScraper
from module.logger import get_logger
from module.db import get_engine, upsert_rows_psycopg2

log = get_logger("scraper.reviewnote")

class ReviewNoteScraper(BaseScraper):
    PLATFORM_NAME = "리뷰노트"
    BASE_URL = "https://www.reviewnote.co.kr/campaigns"

    def _parse_dates(self, df: pd.DataFrame) -> pd.DataFrame:
        """리뷰노트의 날짜 형식('M/D (요일)')을 파싱합니다."""
        from pandas import Timestamp, to_datetime
        current_year = str(Timestamp.now(tz="Asia/Seoul").year)

        for col in ["apply_from", "apply_deadline", "review_deadline"]:
            if col in df.columns and not df[col].isnull().all():
                # '8/29 (금)' -> '8/29' 로 (요일) 부분을 제거
                s = df[col].dropna().astype(str).str.split(' ').str[0]
                
                s_with_year = current_year + "/" + s
                dt_series = to_datetime(s_with_year, format="%Y/%m/%d", errors="coerce")
                dt_series = dt_series.dt.tz_localize("Asia/Seoul")
                df[col] = dt_series.astype("object").where(dt_series.notna(), None)
        return df

    def _search(self, keyword: str):
        # 이 스크레이퍼는 키워드 검색 대신 run_once에서 직접 지역 필터링을 수행합니다.
        pass

    def _extract_dataframe(self, search_text: str) -> pd.DataFrame:
        # 이 스크레이퍼는 run_once에서 모든 로직을 처리합니다.
        return pd.DataFrame()
    
    def _extract_detail_data(self, wait: WebDriverWait) -> dict:
        """상세 페이지에서 개별 캠페인 정보를 추출합니다."""
        data = {}
        try:
            # XPath를 사용하여 텍스트 레이블을 기준으로 안정적으로 요소를 찾습니다.
            text_xpath = '//*[@id="__next"]/div/div[2]/div/div[1]/div[1]/div[1]/div[1]'
            data['company'] = wait.until(EC.presence_of_element_located((By.XPATH, text_xpath))).text.strip()
            
            # 제공내역: '제공서비스/물품' 제목을 가진 div의 형제 div에서 p 태그를 찾음
            offer_xpath = '//*[@id="__next"]/div/div[2]/div/div[1]/div[1]/div[7]/div[1]/div[1]/div[2]/p'
            data['offer'] = wait.until(EC.presence_of_element_located((By.XPATH, offer_xpath))).text.strip()

            # 주소: '방문 주소' 제목을 가진 div의 형제 div를 찾음
            address_xpath = '//*[@id="__next"]/div/div[2]/div/div[1]/div[1]/div[7]/div[1]/div[4]/div[2]'
            address_elements = self.driver.find_elements(By.XPATH, address_xpath)
            data['address'] = address_elements[0].text.strip() if address_elements else None

            # 날짜 정보 추출
            # 2. 신청 기간 텍스트 추출 및 파싱
            # apply_period_xpath = "//div[div[text()='체험단 신청기간']]/following-sibling::div"
            self._expand_schedule_section(wait)
            apply_period_xpath='//*[@id="__next"]/div/div[2]/div/div[1]/div[2]/div[2]/div[1]/div[1]/div/div[1]/div[2]'
            
            apply_period_text = wait.until(EC.presence_of_element_located((By.XPATH, apply_period_xpath))).text.strip()
            
            # 정규표현식으로 모든 날짜(M/D)를 찾음
            apply_dates = re.findall(r'(\d{1,2}/\d{1,2})', apply_period_text)
            if len(apply_dates) >= 2:
                data['apply_from'] = apply_dates[0]
                data['apply_deadline'] = apply_dates[1]
            elif len(apply_dates) == 1:
                data['apply_from'] = apply_dates[0]
                data['apply_deadline'] = apply_dates[0]
            else:
                data['apply_from'] = None
                data['apply_deadline'] = None

            # 3. 리뷰 마감일 텍스트 추출 및 파싱
            # review_deadline_xpath = "//div[div[text()='리뷰 마감']]/following-sibling::div"
            review_deadline_xpath='//*[@id="__next"]/div/div[2]/div/div[1]/div[2]/div[2]/div[1]/div[1]/div/div[4]/div[2]'
            review_deadline_text = wait.until(EC.presence_of_element_located((By.XPATH, review_deadline_xpath))).text.strip()
            
            match = re.search(r'(\d{1,2}/\d{1,2})', review_deadline_text)
            data['review_deadline'] = match.group(1) if match else None
            # --- 날짜 추출 로직 끝 ---

        except (TimeoutException, NoSuchElementException) as e:
            log.warning(f"상세 정보 일부 추출 실패: {e}")
        
        return data
    
    region_map = {
            "서울": 4,
            "경기": 5,
            "인천": 6,
            "강원": 7,
            "대전": 8,
            "세종": 9,
            "충남": 10,
            "충북": 11,
            "부산": 12,
            "울산": 13,
            "경남": 14,
            "경북": 15,
            "대구": 16,
            "광주": 17,
            "전남": 18,
            "전북": 19,
            "제주": 20,
        }

    def run_once(self, keywords: List[str], table_name: str) -> int:
        """
        지역 필터 클릭 → 필터 적용(목록 변화) 대기 → 스크롤 컨테이너 강제 스크롤 →
        상세페이지 순회 → DB upsert
        """
        from selenium.common.exceptions import StaleElementReferenceException, WebDriverException
        from selenium.webdriver import ActionChains
        from selenium.webdriver.common.keys import Keys

        def _count_cards() -> int:
            try:
                return len(self.driver.find_elements(By.CSS_SELECTOR, "a[href^='/campaigns/']"))
            except Exception:
                return 0

        def _wait_list_changed(prev_count: int, timeout: int = 8) -> None:
            """지역 클릭 후 목록이 바뀌는지(카드 수 변화) 기다림."""
            try:
                WebDriverWait(self.driver, timeout).until(
                    lambda d: len(d.find_elements(By.CSS_SELECTOR, "a[href^='/campaigns/']")) != prev_count
                )
            except TimeoutException:
                log.info("지역 필터 변화 감지 실패(타임아웃) — 그래도 진행할게요!")

        def _find_scroll_container():
            """
            실제 스크롤되는 컨테이너를 찾아 반환.
            못 찾으면 document.scrollingElement 사용.
            """
            candidates = [
                "div[role='main']",
                "main",
                ".infinite-scroll",
                ".scroll-container",
                "#__next div[role='region']",
            ]
            for sel in candidates:
                els = self.driver.find_elements(By.CSS_SELECTOR, sel)
                if not els:
                    continue
                el = els[0]
                try:
                    scrollable = self.driver.execute_script(
                        "const el=arguments[0]; return el.scrollHeight>el.clientHeight;", el
                    )
                except Exception:
                    scrollable = False
                if scrollable:
                    return el
            # fallback: window/body
            return None  # None이면 window/body로 처리

        def _force_scroll_step(container) -> None:
            """
            컨테이너/윈도우 모두에 대해 스크롤 이벤트를 강하게 발생시킴.
            """
            try:
                # A) 마지막 카드로 이동 (IntersectionObserver 트리거)
                cards = self.driver.find_elements(By.CSS_SELECTOR, "a[href^='/campaigns/']")
                if cards:
                    self.driver.execute_script("arguments[0].scrollIntoView({block:'end'});", cards[-1])
                else:
                    self.driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
            except Exception:
                pass

            try:
                # B) 컨테이너 직접 scrollTop
                if container:
                    self.driver.execute_script("arguments[0].scrollTop = arguments[0].scrollHeight;", container)
                    self.driver.execute_script("arguments[0].dispatchEvent(new Event('scroll'));", container)
                else:
                    # window/body
                    self.driver.execute_script("window.dispatchEvent(new Event('scroll'));")
            except Exception:
                pass

            try:
                # C) 키보드 스크롤 (백업)
                ActionChains(self.driver).send_keys(Keys.END).perform()
            except Exception:
                pass

        # ──────────────────────────────────────────────────────────────

        # (권장) 작은 뷰포트에서 무한스크롤이 안 걸리는 걸 방지하기 위해
        # headless에서도 적용되는 window-size 옵션을 BaseScraper에서 줘두면 좋아요.
        # (여기서는 그냥 진행)
        self.driver.get(self.BASE_URL)
        wait = WebDriverWait(self.driver, 15)
        all_data: List[dict] = []

        for key, value in self.region_map.items():
            try:
                # 0) 지역 시작 전, 페이지 리셋
                self.driver.get(self.BASE_URL)
                try:
                    WebDriverWait(self.driver, 6).until(
                        lambda d: len(d.find_elements(By.CSS_SELECTOR, "a[href^='/campaigns/']")) >= 1
                    )
                except TimeoutException:
                    pass

                log.info(f"'{key}' 지역 필터링을 시작합니다.")
                region_text = key

                # 1) 지역 버튼 찾기 (텍스트 기반 → 실패 시 인덱스 백업)
                region_xpath_text = (
                    f"//*[@id='__next']//*[(self::button or self::div or self::span)"
                    f" and (contains(@class,'filter') or contains(@class,'chip') or contains(@role,'button'))]"
                    f"[contains(normalize-space(.), '{region_text}')]"
                )
                try:
                    btn = wait.until(EC.element_to_be_clickable((By.XPATH, region_xpath_text)))
                except Exception:
                    btn = wait.until(EC.element_to_be_clickable(
                        (By.XPATH, f'//*[@id="__next"]/div/div[2]/div[1]/div[1]/div/div[2]/div[2]/div/div[1]/div/div/div[{value}]')
                    ))

                self.driver.execute_script("arguments[0].scrollIntoView({block:'center'});", btn)
                # JS 클릭 → overlay/헤더 가림 방지
                self.driver.execute_script("arguments[0].click();", btn)
                time.sleep(0.7)

                # 2) (있다면) 오버레이 제거
                try:
                    if hasattr(self, "_dismiss_overlays"):
                        self._dismiss_overlays()
                except Exception:
                    pass

                # 3) 목록 변화 대기 (이전 카드 개수와 달라질 때까지)
                before = _count_cards()
                _wait_list_changed(before, timeout=8)

                # 4) 스크롤 컨테이너 찾고, 강제 스크롤 루프 실행
                log.info("모든 캠페인 목록을 불러오기 위해 페이지를 스크롤합니다...")
                container = _find_scroll_container()
                log.info(f"스크롤 컨테이너: {'window/body' if container is None else 'element'}")

                # 증가 감시 루프 (여기서 1차로 충분히 로드)
                prev = -1
                idle = 0
                start_t = time.time()
                while True:
                    now = _count_cards()
                    log.info(f"[프리스크롤] 카드수: {prev} -> {now} (idle={idle})")
                    if now > prev:
                        idle = 0
                        prev = now
                    else:
                        idle += 1

                    _force_scroll_step(container)

                    # 증가 대기
                    try:
                        WebDriverWait(self.driver, 5).until(
                            lambda d: len(d.find_elements(By.CSS_SELECTOR, "a[href^='/campaigns/']")) > now
                        )
                    except TimeoutException:
                        pass

                    if idle >= 2:   # 프리스크롤은 가볍게 2번 연속 증가 없으면 종료
                        break
                    if time.time() - start_t > 20:
                        break
                    time.sleep(0.5)

                # 5) 정식 수집 루틴 (_load_all_campaigns)
                log.info("모든 캠페인 URL 수집 시작")
                detail_urls = self._load_all_campaigns(wait, max_idle_rounds=3, hard_timeout=100)
                detail_urls = list(dict.fromkeys(detail_urls))  # 순서 유지 중복 제거
                log.info(f"총 {len(detail_urls)}개의 상세 페이지 URL 수집 완료.")

                # 6) 상세페이지 방문 & 데이터 추출
                for idx, url in enumerate(detail_urls, 1):
                    log.info(f"상세 페이지 방문: {url} ({idx}/{len(detail_urls)})")
                    try:
                        self.driver.get(url)
                        detail_data = self._extract_detail_data(wait)
                    except (TimeoutException, StaleElementReferenceException, WebDriverException) as e:
                        log.warning(f"상세 페이지 접근 실패: {e}")
                        continue

                    if detail_data.get("company"):
                        detail_data["platform"] = self.PLATFORM_NAME
                        detail_data["company_link"] = url
                        detail_data["search_text"] = key
                        all_data.append(detail_data)

                        # 디버깅 로그(필요하면 유지, 아니면 주석)
                        log.info(
                            "추출 성공 | platform=%s | company=%s | apply_from=%s | apply_deadline=%s | review_deadline=%s",
                            detail_data.get("platform"),
                            detail_data.get("company"),
                            detail_data.get("apply_from"),
                            detail_data.get("apply_deadline"),
                            detail_data.get("review_deadline"),
                        )
                    else:
                        log.warning(f"데이터 추출 실패: {url}")

                    time.sleep(0.6)  # 살짝 쉬면 안정적

            except (TimeoutException, NoSuchElementException, WebDriverException) as e:
                log.error(f"리뷰노트 크롤링 중 오류 발생: {e}", exc_info=True)
                # 지역 하나 실패해도 다음 지역 진행하도록 continue
                continue

        if not all_data:
            log.warning("수집된 데이터가 없습니다.")
            return 0

        # 7) DF 변환 및 DB 저장
        df = pd.DataFrame(all_data)
        final_df = self._clean_dataframe(df)
        log.info(f"[{self.PLATFORM_NAME}] 중복 제거 전 {len(final_df)}건")
        final_df.sort_values(by='apply_deadline', ascending=False, na_position='last', inplace=True)
        final_df.drop_duplicates(subset=self.CONFLICT_COLS, keep='first', inplace=True)
        log.info(f"[{self.PLATFORM_NAME}] 중복 제거 후 {len(final_df)}건")

        affected = upsert_rows_psycopg2(
            self.engine, table=table_name, rows=final_df,
            conflict_cols=self.CONFLICT_COLS,
            update_cols=[c for c in self.RESULT_TABLE_COLUMNS if c not in self.CONFLICT_COLS],
        )
        return affected


    def _expand_schedule_section(self, wait: WebDriverWait) -> None:
        toggle_xpath = '//*[@id="__next"]/div/div[2]/div/div[1]/div[2]/div[2]/div[1]/div[1]/button'
        try:
            # 이미 내용이 보이는지 먼저 체크 (열려 있으면 return)
            opened_probe = self.driver.find_elements(By.XPATH,
                '//*[@id="__next"]/div/div[2]/div/div[1]/div[2]/div[2]/div[1]/div[1]/div/div[1]/div[2]'
            )
            if opened_probe and opened_probe[0].is_displayed():
                return

            toggle_btn = wait.until(EC.element_to_be_clickable((By.XPATH, toggle_xpath)))
            self.driver.execute_script("arguments[0].scrollIntoView({block: 'center'});", toggle_btn)
            self.driver.execute_script("arguments[0].click();", toggle_btn)
            log.info("체험단 일정 버튼 클릭 완료 (토글 펼침)")
            time.sleep(0.4)
        except TimeoutException:
            log.info("체험단 일정 토글 버튼을 찾지 못했으나, 계속 진행합니다.")


    def _get_campaign_anchors(self) -> List:
        # 광고/기타 링크를 최대한 배제: 캠페인 상세는 보통 /campaigns/ 로 시작 + 숫자 포함
        anchors = self.driver.find_elements(By.CSS_SELECTOR, "a[href^='/campaigns/']")
        uniq = []
        seen = set()
        for a in anchors:
            href = a.get_attribute("href") or ""
            if "/campaigns/" in href:
                if href not in seen:
                    seen.add(href)
                    uniq.append(a)
        return uniq

    def _load_all_campaigns(self, wait: WebDriverWait, max_idle_rounds: int = 3, hard_timeout: int = 90) -> List[str]:
        start = time.time()
        prev_count = -1
        idle_rounds = 0

        container = self._find_scroll_container()
        log.info(f"스크롤 컨테이너 찾음: {('window/body' if container is None else 'element')}")

        while True:
            cards = self._get_campaign_anchors()
            urls = [c.get_attribute("href") for c in cards if c.get_attribute("href")]
            new_count = len(set(urls))
            log.info(f"[스크롤] 카드수: {prev_count} -> {new_count} (idle={idle_rounds})")

            if new_count > prev_count:
                idle_rounds = 0
                prev_count = new_count
            else:
                idle_rounds += 1

            # 더보기 버튼 우선 클릭
            try:
                more = self.driver.find_element(By.XPATH, "//button[contains(., '더보기') or contains(., '더 보')]")
                if more.is_displayed() and more.is_enabled():
                    self.driver.execute_script("arguments[0].scrollIntoView({block:'center'});", more)
                    self.driver.execute_script("arguments[0].click();", more)
                    time.sleep(1.0)
            except NoSuchElementException:
                pass

            # (A) 마지막 카드로 이동
            if cards:
                self.driver.execute_script("arguments[0].scrollIntoView({block:'end'});", cards[-1])
            else:
                self.driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")

            # (B) 컨테이너 직접 스크롤(가장 확실)
            if container:
                self.driver.execute_script(
                    "arguments[0].scrollTop = arguments[0].scrollHeight;", container
                )
                self.driver.execute_script(
                    "arguments[0].dispatchEvent(new Event('scroll'));", container
                )
            else:
                self.driver.execute_script("window.dispatchEvent(new Event('scroll'));")

            # (C) 키보드 스크롤(백업)
            try:
                ActionChains(self.driver).send_keys(Keys.END).perform()
            except Exception:
                pass

            # 증가 대기
            try:
                WebDriverWait(self.driver, 5).until(
                    lambda d: len(set(a.get_attribute("href") for a in d.find_elements(By.CSS_SELECTOR, "a[href^='/campaigns/']"))) > new_count
                )
            except TimeoutException:
                pass

            # 종료 조건
            if idle_rounds >= max_idle_rounds:
                log.info("증가 없음 idle 한계 도달 → 스크롤 종료")
                break
            if time.time() - start > hard_timeout:
                log.info("무한스크롤 hard timeout 도달 → 스크롤 종료")
                break

            time.sleep(0.6)

        cards = self._get_campaign_anchors()
        return list({c.get_attribute("href") for c in cards if c.get_attribute("href")})

    
    def _find_scroll_container(self):
        """
        실제로 스크롤되는 컨테이너를 찾아 반환.
        못 찾으면 document.scrollingElement(=window/body) 반환.
        """
        # 1) 후보 셀렉터 우선 탐색
        candidates = [
            "div[role='main']",
            "main",
            ".infinite-scroll",
            ".scroll-container",
            "#__next div[role='region']",
        ]
        for sel in candidates:
            els = self.driver.find_elements(By.CSS_SELECTOR, sel)
            if not els:
                continue
            el = els[0]
            try:
                scrollable = self.driver.execute_script(
                    "const el=arguments[0]; return el.scrollHeight>el.clientHeight;", el
                )
            except Exception:
                scrollable = False
            if scrollable:
                return el

        # 2) 마지막 카드의 스크롤 가능한 조상 탐색
        cards = self.driver.find_elements(By.CSS_SELECTOR, "a[href^='/campaigns/']")
        if cards:
            last = cards[-1]
            container = self.driver.execute_script("""
                function findScrollable(el){
                while(el && el !== document.body){
                    const st = getComputedStyle(el);
                    if ((st.overflowY==='auto' || st.overflowY==='scroll') && el.scrollHeight > el.clientHeight) return el;
                    el = el.parentElement;
                }
                return document.scrollingElement || document.body;
                }
                return findScrollable(arguments[0]);
            """, last)
            return container

        # 3) 최후: window/body
        return self.driver.execute_script("return document.scrollingElement || document.body;")
    
    def _dismiss_overlays(self):
        texts = ["확인", "동의", "닫기", "나중에", "그만 보기"]
        for t in texts:
            try:
                btn = self.driver.find_element(By.XPATH, f"//button[contains(., '{t}')]")
                if btn.is_displayed():
                    self.driver.execute_script("arguments[0].click();", btn)
                    time.sleep(0.3)
            except Exception:
                pass



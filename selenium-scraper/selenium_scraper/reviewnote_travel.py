"""리뷰노트 체험단 > 카테고리 > 여행 수집.

화면 경로를 그대로 따라간다.
  1. 홈 → 상단 "체험단 검색"
  2. "카테고리" 선택 상자 → "여행"
  3. 목록을 끝까지 스크롤 (목록 API 응답을 모음)
  4. 캠페인마다 상세 페이지 진입 (상세 API /api/campaign?id= 응답을 모음, 로그인 필요)
"""

from __future__ import annotations

import logging
import random
import re
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

from selenium import webdriver
from selenium.common.exceptions import TimeoutException, WebDriverException
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

from .browser import NetworkCapture, session_user
from .reviewnote_parse import BASE_URL, campaign_url, list_objects, to_record

log = logging.getLogger("reviewnote_travel")

CATEGORY_NAME = "여행"
SEARCH_MENU_XPATH = "//*[normalize-space(text())='체험단 검색'][not(ancestor::footer)]"
CATEGORY_SELECT_XPATH = "//div[contains(@class,'MuiSelect-select')][normalize-space()='카테고리']"
CATEGORY_OPTION_XPATH = "//li[@role='option'][normalize-space()='{name}']"
MAX_SCROLLS = 300  # 무한 스크롤 안전장치
STALE_SCROLLS = 4  # 새 항목 없이 이만큼 스크롤하면 끝으로 본다
MAX_CONSECUTIVE_DETAIL_FAILURES = 5


class LoginRequired(RuntimeError):
    """로그인 세션이 없거나 만료됨. `login` 명령으로 다시 로그인해야 한다."""


@dataclass
class CrawlOptions:
    max_items: int = 0  # 0이면 제한 없음
    max_details: int = 0  # 0이면 목록 전부 상세 진입
    delay: float = 2.0  # 상세 페이지 사이 대기(초), 실제 대기는 delay~delay*1.5
    scroll_pause: float = 1.5
    include_closed: bool = False  # False면 모집 중(SELECT)만


@dataclass
class CrawlResult:
    category_id: str | None = None
    listed: int = 0
    records: list[dict[str, Any]] = field(default_factory=list)
    detail_ok: int = 0
    detail_failed: list[dict[str, Any]] = field(default_factory=list)
    login_expired: bool = False
    started_at: str = ""
    finished_at: str = ""


def _now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def _sleep_jitter(base: float) -> None:
    time.sleep(base + random.uniform(0, base * 0.5))


def open_category(driver: webdriver.Chrome, capture: NetworkCapture) -> str | None:
    """홈 → 체험단 검색 → 카테고리 → 여행. 고른 카테고리의 ID를 돌려준다."""
    wait = WebDriverWait(driver, 20)
    driver.get(BASE_URL)
    wait.until(lambda d: d.execute_script("return document.readyState") == "complete")

    if session_user(driver) is None:
        raise LoginRequired("리뷰노트 로그인이 필요합니다")

    # 상단 메뉴는 <a>가 아니라 클릭 이벤트가 걸린 <div> (2026-11-27 확인)
    menus = [m for m in driver.find_elements(By.XPATH, SEARCH_MENU_XPATH) if m.is_displayed()]
    if menus:
        menus[0].click()
    else:  # 메뉴 구조가 바뀐 경우
        log.warning("'체험단 검색' 메뉴를 못 찾아 목록 주소로 바로 이동합니다")
        driver.get(f"{BASE_URL}/campaigns")
    wait.until(lambda d: "/campaigns" in d.current_url)

    capture.reset()  # 카테고리 적용 전 전체 목록 응답은 버린다
    wait.until(EC.element_to_be_clickable((By.XPATH, CATEGORY_SELECT_XPATH))).click()
    option = wait.until(
        EC.element_to_be_clickable((By.XPATH, CATEGORY_OPTION_XPATH.format(name=CATEGORY_NAME)))
    )
    category_id = option.get_attribute("data-value") or None
    option.click()
    wait.until(lambda d: "categoryId=" in d.current_url)
    log.info("카테고리 '%s' 선택 (categoryId=%s)", CATEGORY_NAME, category_id)
    return category_id


def collect_list(
    driver: webdriver.Chrome, capture: NetworkCapture, category_id: str | None, opts: CrawlOptions
) -> list[dict[str, Any]]:
    """목록을 끝까지 스크롤하며 목록 API 응답에서 캠페인을 모은다."""
    pattern = re.compile(
        r"/api/v2/campaigns\?.*categoryId=" + (re.escape(category_id) if category_id else "")
    )
    items: dict[int, dict[str, Any]] = {}
    stale = 0
    reached_end = False

    for scroll in range(MAX_SCROLLS):
        added = 0
        for resp in capture.take(pattern):
            if resp.status != 200:
                log.warning("목록 응답 %s: %s", resp.status, resp.url)
                continue
            for obj in list_objects(resp.body):
                title = (obj.get("category") or {}).get("title")
                if title and title != CATEGORY_NAME:
                    continue
                if obj["id"] not in items:
                    items[obj["id"]] = obj
                    added += 1
            if isinstance(resp.body, dict) and resp.body.get("has_more") is False:
                reached_end = True

        stale = 0 if added else stale + 1
        if opts.max_items and len(items) >= opts.max_items:
            break
        if reached_end or stale >= STALE_SCROLLS:
            break
        driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
        time.sleep(opts.scroll_pause)
        if scroll and scroll % 10 == 0:
            log.info("목록 스크롤 %d회, %d건", scroll, len(items))
    else:
        log.warning("스크롤 안전장치(%d회)에 도달했습니다", MAX_SCROLLS)

    result = list(items.values())
    if opts.max_items:
        result = result[: opts.max_items]
    log.info("목록 수집 %d건 (끝 도달: %s)", len(result), reached_end)
    return result


def fetch_detail(
    driver: webdriver.Chrome, capture: NetworkCapture, campaign_id: int
) -> dict[str, Any] | None:
    """상세 페이지에 들어가 상세 API 응답을 받는다. 실패하면 None."""
    pattern = re.compile(rf"/api/campaign\?id={campaign_id}(?:&|$)")
    capture.reset()
    driver.get(campaign_url(campaign_id))
    resp = capture.wait_for(pattern, timeout=20)
    if resp is None:
        if "/sns/login" in driver.current_url:
            raise LoginRequired("상세 진입 중 로그인 화면으로 이동했습니다")
        return None
    if resp.status == 401:
        raise LoginRequired("상세 API가 401을 돌려줬습니다")
    if resp.status != 200 or not isinstance(resp.body, dict):
        log.warning("상세 응답 %s (id=%s)", resp.status, campaign_id)
        return None
    return resp.body


def crawl(driver: webdriver.Chrome, opts: CrawlOptions) -> CrawlResult:
    result = CrawlResult(started_at=_now())
    capture = NetworkCapture(driver)

    result.category_id = open_category(driver, capture)
    objs = collect_list(driver, capture, result.category_id, opts)
    result.listed = len(objs)
    if not opts.include_closed:
        objs = [o for o in objs if o.get("status") == "SELECT"]
        log.info("모집 중(SELECT) %d건만 상세 진입", len(objs))

    targets = objs[: opts.max_details] if opts.max_details else objs
    consecutive_failures = 0
    for idx, obj in enumerate(targets, 1):
        detail = None
        try:
            detail = fetch_detail(driver, capture, obj["id"])
        except LoginRequired as exc:
            log.error("%s → 지금까지 수집한 결과만 저장합니다", exc)
            result.login_expired = True
            break
        except (TimeoutException, WebDriverException) as exc:
            log.warning("상세 진입 실패 id=%s: %s", obj["id"], exc.__class__.__name__)

        if detail is None:
            consecutive_failures += 1
            result.detail_failed.append({"id": obj["id"], "title": obj.get("title")})
            if consecutive_failures >= MAX_CONSECUTIVE_DETAIL_FAILURES:
                log.error("상세 연속 %d회 실패로 중단합니다", consecutive_failures)
                break
        else:
            consecutive_failures = 0
            result.detail_ok += 1
        result.records.append(to_record(obj, detail, _now()))
        if idx % 10 == 0 or idx == len(targets):
            log.info("상세 %d/%d (성공 %d)", idx, len(targets), result.detail_ok)
        if idx < len(targets):
            _sleep_jitter(opts.delay)

    result.finished_at = _now()
    return result

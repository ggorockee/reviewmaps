"""명령행 진입점.

  uv run python -m selenium_scraper login              # 처음 한 번: 창에서 직접 네이버 로그인
  uv run python -m selenium_scraper crawl [옵션]        # 여행 카테고리 수집 → output/*.json

종료 코드: 0 정상, 1 수집 실패(목록 0건 또는 상세 절반 이상 실패), 2 로그인 필요
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from datetime import datetime
from pathlib import Path

from .browser import DEFAULT_PROFILE_DIR, build_driver, is_logged_in
from .reviewnote_parse import BASE_URL
from .reviewnote_travel import CrawlOptions, LoginRequired, crawl

LOGIN_TIMEOUT = 600

log = logging.getLogger("selenium_scraper")


def cmd_login(args: argparse.Namespace) -> int:
    driver = build_driver(args.profile_dir, headless=False)
    try:
        driver.get(f"{BASE_URL}/sns/login")
        print("열린 Chrome 창에서 네이버(또는 Apple)로 로그인해 주세요. 최대 10분 기다립니다.")
        deadline = time.monotonic() + LOGIN_TIMEOUT
        while time.monotonic() < deadline:
            time.sleep(3)
            if "reviewnote.co.kr" not in driver.current_url:
                continue  # 네이버 로그인 화면에 있는 동안
            if is_logged_in(driver):
                print(f"로그인 확인됨. 세션이 프로필에 저장됐습니다: {args.profile_dir}")
                return 0
        print("시간 안에 로그인이 확인되지 않았습니다.", file=sys.stderr)
        return 2
    finally:
        driver.quit()


def cmd_crawl(args: argparse.Namespace) -> int:
    opts = CrawlOptions(
        max_items=args.max_items,
        max_details=args.max_details,
        delay=args.delay,
        include_closed=args.include_closed,
    )
    driver = build_driver(args.profile_dir, headless=args.headless)
    try:
        result = crawl(driver, opts)
    except LoginRequired as exc:
        print(
            f"{exc}. 먼저 `uv run python -m selenium_scraper login`을 실행하세요.", file=sys.stderr
        )
        return 2
    finally:
        driver.quit()

    out = args.out or Path("output") / f"reviewnote-travel-{datetime.now():%Y%m%d-%H%M%S}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    with_days = sum(1 for r in result.records if r["possibleDays"] or r["impossibleDays"])
    summary = {
        "source": "리뷰노트",
        "category": "여행",
        "categoryId": result.category_id,
        "startedAt": result.started_at,
        "finishedAt": result.finished_at,
        "listed": result.listed,
        "detailAttempted": result.detail_ok + len(result.detail_failed),
        "detailOk": result.detail_ok,
        "detailFailed": result.detail_failed,
        "withAvailableDays": with_days,
        "loginExpired": result.login_expired,
    }
    out.write_text(
        json.dumps({"meta": summary, "items": result.records}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(
        f"목록 {result.listed}건 / 상세 성공 {result.detail_ok}건 / 실패 {len(result.detail_failed)}건 "
        f"/ 이용 요일 정보 있음 {with_days}건 → {out}"
    )
    if result.login_expired:
        return 2
    if result.listed == 0:
        return 1
    attempted = result.detail_ok + len(result.detail_failed)
    if attempted and result.detail_ok * 2 < attempted:
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="selenium_scraper", description="리뷰노트 여행 카테고리 수집기"
    )
    parser.add_argument(
        "--profile-dir", type=Path, default=DEFAULT_PROFILE_DIR, help="전용 Chrome 프로필 경로"
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("login", help="Chrome 창을 열어 직접 로그인 (처음 한 번, 세션 만료 시)")

    p = sub.add_parser("crawl", help="체험단 > 카테고리 > 여행 목록과 상세 수집")
    p.add_argument("--max-items", type=int, default=0, help="목록 최대 건수 (0=전부)")
    p.add_argument("--max-details", type=int, default=0, help="상세 진입 최대 건수 (0=전부)")
    p.add_argument("--delay", type=float, default=2.0, help="상세 페이지 사이 대기 초 (기본 2~3초)")
    p.add_argument("--include-closed", action="store_true", help="모집 마감 캠페인도 상세 진입")
    p.add_argument("--headless", action="store_true", help="창 없이 실행")
    p.add_argument(
        "--out", type=Path, help="결과 JSON 경로 (기본 output/reviewnote-travel-<시각>.json)"
    )

    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    if args.command == "login":
        return cmd_login(args)
    return cmd_crawl(args)


if __name__ == "__main__":
    sys.exit(main())

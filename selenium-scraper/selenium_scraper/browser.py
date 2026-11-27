"""Chrome 실행과 네트워크 응답 수집.

- 전용 Chrome 프로필(--user-data-dir)을 써서 한 번 로그인하면 쿠키가 유지된다.
- 화면 DOM 대신 브라우저가 받은 JSON 응답을 CDP 성능 로그에서 읽는다.
  (사이트가 화면 구성을 바꿔도 API 응답 구조가 같으면 수집이 깨지지 않는다)
"""

from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from selenium import webdriver
from selenium.common.exceptions import WebDriverException
from selenium.webdriver.chrome.options import Options

DEFAULT_PROFILE_DIR = Path.home() / ".reviewmaps" / "reviewnote-chrome-profile"


def build_driver(profile_dir: Path, headless: bool) -> webdriver.Chrome:
    """전용 프로필로 Chrome을 띄운다. chromedriver는 Selenium Manager가 자동으로 맞춘다."""
    profile_dir.mkdir(parents=True, exist_ok=True)
    opts = Options()
    opts.add_argument(f"--user-data-dir={profile_dir}")
    opts.add_argument("--profile-directory=Default")
    opts.add_argument("--window-size=1280,1000")
    opts.add_argument("--lang=ko-KR")
    if headless:
        opts.add_argument("--headless=new")
    opts.set_capability("goog:loggingPrefs", {"performance": "ALL"})
    driver = webdriver.Chrome(options=opts)
    driver.execute_cdp_cmd("Network.enable", {})
    return driver


@dataclass
class CapturedResponse:
    url: str
    status: int
    body: Any  # JSON 파싱 결과 (파싱 실패 시 None)


@dataclass
class NetworkCapture:
    """성능 로그를 읽어 끝난 응답의 본문을 꺼낸다.

    get_log("performance")는 읽은 만큼 버퍼를 비우므로, 이 객체가 상태를 들고 있으면서
    응답 수신(responseReceived)과 로딩 완료(loadingFinished)를 짝지어 처리한다.
    """

    driver: webdriver.Chrome
    _responses: dict[str, tuple[str, int]] = field(default_factory=dict)
    _finished: set[str] = field(default_factory=set)

    def reset(self) -> None:
        self._poll()
        self._responses.clear()
        self._finished.clear()

    def _poll(self) -> None:
        for entry in self.driver.get_log("performance"):
            try:
                msg = json.loads(entry["message"])["message"]
            except (KeyError, ValueError):
                continue
            method = msg.get("method")
            params = msg.get("params", {})
            if method == "Network.responseReceived":
                resp = params.get("response", {})
                self._responses[params["requestId"]] = (resp.get("url", ""), resp.get("status", 0))
            elif method == "Network.loadingFinished":
                self._finished.add(params["requestId"])

    def take(self, url_pattern: re.Pattern[str]) -> list[CapturedResponse]:
        """url_pattern에 맞고 로딩이 끝난 응답을 꺼낸다. 꺼낸 응답은 다시 나오지 않는다."""
        self._poll()
        out: list[CapturedResponse] = []
        for request_id in list(self._responses):
            url, status = self._responses[request_id]
            if not url_pattern.search(url):
                continue
            if request_id not in self._finished:
                continue
            del self._responses[request_id]
            self._finished.discard(request_id)
            out.append(CapturedResponse(url=url, status=status, body=self._body(request_id)))
        return out

    def wait_for(self, url_pattern: re.Pattern[str], timeout: float) -> CapturedResponse | None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            found = self.take(url_pattern)
            if found:
                return found[-1]
            time.sleep(0.3)
        return None

    def _body(self, request_id: str) -> Any:
        try:
            res = self.driver.execute_cdp_cmd("Network.getResponseBody", {"requestId": request_id})
        except WebDriverException:
            return None
        try:
            return json.loads(res.get("body", ""))
        except ValueError:
            return None


# go-scraper 상세 API에 필요한 세션 쿠키 (HttpOnly, 약 15일)
SESSION_COOKIE = "reviewNoteSession"
REVIEWNOTE_URL = "https://www.reviewnote.co.kr/"


def is_logged_in(driver: webdriver.Chrome) -> bool:
    """리뷰노트 세션 쿠키가 있는지. 로그인 상태는 next-auth 세션이 아니라 쿠키로 관리된다 (2026-11-27 확인).

    driver.get_cookies()는 현재 페이지 도메인 쿠키만 돌려줘서, 로그인 뒤 창이 네이버 등 다른 페이지에
    머물면 로그인을 못 알아챘다 (2026-11-27). CDP로 리뷰노트 주소의 쿠키를 직접 조회한다.
    """
    res = driver.execute_cdp_cmd("Network.getCookies", {"urls": [REVIEWNOTE_URL]})
    return any(c.get("name") == SESSION_COOKIE and c.get("value") for c in res.get("cookies", []))

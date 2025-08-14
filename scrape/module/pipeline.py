from __future__ import annotations
import signal
import time
from typing import List
from .config import Settings
from .logger import get_logger
from .scraper import AdvancedScraper
from .enricher import enrich_once

log = get_logger("pipeline")

class Pipeline:
    def __init__(self, settings: Settings, keywords: List[str]):
        self.settings = settings
        self.keywords = keywords
        self._stop = False

    def _install_signal_handlers(self):
        def stop_handler(signum, frame):
            log.info(f"신호({signum}) 감지. 안전 종료 시작.")
            self._stop = True
        signal.signal(signal.SIGINT, stop_handler)
        signal.signal(signal.SIGTERM, stop_handler)

    def run_forever(self, interval_sec: int = 300):
        """5분(기본)마다 스크래핑→업서트→보강→로그."""
        self._install_signal_handlers()
        log.info(f"배치 시작. 주기={interval_sec}s")

        while not self._stop:
            start = time.time()
            try:
                # 1) 스크래핑 & UPSERT
                scraper = AdvancedScraper(self.settings)
                affected = scraper.run_once(self.keywords, self.settings.table_name)
                scraper.close()
                log.info(f"Scrape UPSERT 건수: {affected}")

                # 2) 보강(주소/좌표/이미지) & 업데이트
                updated = enrich_once(self.settings)
                log.info(f"Enrich 업데이트 건수: {updated}")

                # 3) 요약 로그
                total = affected + updated
                log.info(f"배치 사이클 요약: upsert={affected}, enrich_updates={updated}, total_changes={total}")

            except Exception as e:
                log.exception(f"배치 사이클 오류: {e}")

            # 주기 보장
            elapsed = time.time() - start
            sleep_for = max(0, interval_sec - int(elapsed))
            if self._stop:
                break
            if sleep_for > 0:
                log.info(f"{sleep_for}s 대기 후 다음 사이클")
                time.sleep(sleep_for)

        log.info("배치 종료")


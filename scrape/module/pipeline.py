from __future__ import annotations
import signal
import time
from typing import List, Tuple
from .config import Settings
from .logger import get_logger
from .scraper import AdvancedScraper
from .enricher import enrich_once

from datetime import datetime, timedelta

log = get_logger("pipeline")

def _parse_hhmm(s: str) -> Tuple[int, int]:
    try:
        hh, mm = s.strip().split(":")
        return int(hh), int(mm)
    except Exception:
        return 1, 0  # fallback 01:00
    
def _next_run_at(tz, hh: int, mm: int) -> datetime:
    """오늘/내일 중 다음 실행 시각(타임존 aware) 계산"""
    now = datetime.now(tz)
    candidate = now.replace(hour=hh, minute=mm, second=0, microsecond=0)
    if candidate <= now:
        candidate = candidate + timedelta(days=1)
    return candidate

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
        
    def _one_cycle(self):
        """스크랩 → UPSERT → 보강 → 요약 로그"""
        scraper = AdvancedScraper(self.settings)
        try:
            affected = scraper.run_once(self.keywords, self.settings.table_name)
            log.info(f"Scrape UPSERT 건수: {affected}")
        finally:
            scraper.close()

        updated = enrich_once(self.settings)
        log.info(f"Enrich 업데이트 건수: {updated}")
        total = affected + updated
        log.info(f"배치 사이클 요약: upsert={affected}, enrich_updates={updated}, total_changes={total}")


    def run_interval(self):
        """고정 간격(초)으로 반복"""
        self._install_signal_handlers()
        interval = self.settings.batch_interval_seconds
        log.info(f"배치 시작 (interval={interval}s)")
        if self.settings.run_at_start:
            try: self._one_cycle()
            except Exception as e: log.exception(f"사이클 오류: {e}")
        while not self._stop:
            log.info(f"{interval}s 대기")
            for _ in range(interval):
                if self._stop: break
                time.sleep(1)
            if self._stop: break
            try:
                self._one_cycle()
            except Exception as e:
                log.exception(f"사이클 오류: {e}")
        log.info("배치 종료")
        
    def run_once(self) -> None:
        self._install_signal_handlers()
        try:
            self._one_cycle()
        except Exception as e:
            log.exception(f"사이클 오류: {e}")
        log.info("단일 실행 완료")

    def run_daily(self):
        """매일 HH:MM(타임존 기준)에 한 번 실행"""
        self._install_signal_handlers()
        hh, mm = _parse_hhmm(self.settings.batch_time_hhmm)
        tz = self.settings.tz
        log.info(f'배치 시작 (daily at {hh:02d}:{mm:02d} {self.settings.timezone})')

        # 시작 직후 한 번 실행할지
        if self.settings.run_at_start:
            try: self._one_cycle()
            except Exception as e: log.exception(f"사이클 오류: {e}")

        while not self._stop:
            target = _next_run_at(tz, hh, mm)
            now = datetime.now(tz)
            wait_sec = int((target - now).total_seconds())
            log.info(f"다음 실행 시각: {target.isoformat()} (대기 {wait_sec}s)")
            # 초 단위로 깨워서 종료 신호에 즉시 반응
            for _ in range(wait_sec):
                if self._stop:
                    break
                time.sleep(1)
            if self._stop:
                break
            try:
                self._one_cycle()
            except Exception as e:
                log.exception(f"사이클 오류: {e}")
        log.info("배치 종료")

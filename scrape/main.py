from module.config import Settings
from module.pipeline import Pipeline
from module.search_keyword import SEARCH_KEYWORDS

from module.scrapers.inflexer import InflexerScraper
from module.scrapers.reviewnote import ReviewNoteScraper


import os

if __name__ == "__main__":
    settings = Settings()
    keywords = SEARCH_KEYWORDS
    mode = os.getenv("BATCH_MODE", "once").lower()

    # 실행할 스크레이퍼 클래스 목록 정의
    scraper_to_run = [
        # InflexerScraper,
        ReviewNoteScraper,
        # 나중에 여기에 다른 스크레이퍼 클래스를 추가하기만 하면 됩니다.
    ]

    pipeline = Pipeline(settings, keywords, scraper_classes=scraper_to_run)

    if mode == "once":
        pipeline.run_once()
    elif mode == "interval":
        pipeline.run_interval()
    elif mode == "daily":
        pipeline.run_daily()
    else:
        raise ValueError(f"Unknown BATCH_MODE: {mode}")
import sys
import os
import time
import argparse
import importlib
from inspect import isclass
from typing import Optional

from core.config import settings
from core.logger import get_logger
from core.base import BaseScraper

log = get_logger("main")


def find_scraper_class(scraper_name: str) -> type[BaseScraper]:
    """
    scrapers 폴더에서 이름에 맞는 스크레이퍼 클래스를 동적으로 찾아서 반환
    """
    try:
        module_name = f"scrapers.{scraper_name}"

        module = importlib.import_module(module_name)

        for attribute_name in dir(module):
            attribute = getattr(module, attribute_name)
            if (
                isclass(attribute)
                and issubclass(attribute, BaseScraper)
                and attribute is not BaseScraper
            ):
                log.info(f"'{attribute.__name__}' 클래스를 찾았습니다.")
                return attribute

        raise TypeError(
            f"'{module_name}' 모듈에서 스크레이퍼 클래스를 찾지 못했습니다."
        )

    except ImportError:
        log.error(
            f"'{module_name}' 모듈을 찾을 수 없습니다. scrapers 폴더에 '{scraper_name}.py' 파일이 있는지 확인하세요."
        )
        sys.exit(1)
    except TypeError as e:
        log.error(e)
        sys.exit(1)


def run_job(scraper_name: str, keyword: Optional[str] = None):
    """
    지정된 스크레이퍼를 찾아 키워드와 함께 실행하는 작업(Job) 함수
    """
    log.info(
        f"========== 작업 시작: {scraper_name} (키워드: {keyword or '전체'}) =========="
    )
    try:
        ScraperClass = find_scraper_class(scraper_name)
        scraper_instance = ScraperClass()
        scraper_instance.run(keyword=keyword)  # run 메서드에 keyword를 전달합니다.
    except Exception as e:
        log.error(
            f"'{scraper_name}' 스크레이퍼 실행 중 심각한 에러 발생: {e}", exc_info=True
        )
    log.info(
        f"========== 작업 종료: {scraper_name} (키워드: {keyword or '전체'}) =========="
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="웹 스크레이퍼 실행기")
    parser.add_argument("scraper_name", help="실행할 스크레이퍼의 이름 (예: mymilky).")
    parser.add_argument(
        "--keyword",
        type=str,
        help="검색할 특정 키워드. 지정하지 않으면 전체를 대상으로 합니다.",
    )
    # 스케줄링 옵션은 k8s의 CronJob이 담당하므로 여기서는 제거하거나 유지해도 됩니다.
    # 지금은 즉시 실행 기능에 집중하기 위해 주석 처리하겠습니다.
    # parser.add_argument(
    #     "--schedule",
    #     action="store_true",
    #     help="config.py 설정에 따라 스케줄 모드로 실행합니다."
    # )
    args = parser.parse_args()

    # 터미널에서 받은 인자를 바탕으로 작업을 실행합니다.
    run_job(args.scraper_name, keyword=args.keyword)

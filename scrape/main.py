from crawling.config import Settings
from crawling.pipeline import Pipeline

if __name__ == "__main__":
    settings = Settings()
    keywords = ["서울 강남", "경기 김포"]  # 필요 시 ENV나 파일로 분리 가능
    Pipeline(settings, keywords).run_forever(interval_sec=300)  # 5분

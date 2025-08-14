from module.config import Settings
from module.pipeline import Pipeline
import os

if __name__ == "__main__":
    settings = Settings()
    keywords = ["서울 강남", "경기 김포"]  # 필요 시 ENV나 파일로 분리 가능
    mode = os.getenv("BATCH_MODE", "once").lower()

    pipeline = Pipeline(settings, keywords)

    if mode == "once":
        # 한 번만 실행하고 종료 (CronJob에 적합)
        pipeline.run_once()
    elif mode == "interval":
        # 일정 간격 반복 실행 (예: 5분)
        interval_sec = int(os.getenv("INTERVAL_SEC", 300))
        pipeline.run_forever(interval_sec=interval_sec)
    elif mode == "daily":
        # 매일 특정 시간에 실행 (예: 01:00)
        from schedule import every, run_pending
        import time
        import pytz
        from datetime import datetime

        tz = pytz.timezone(os.getenv("TIMEZONE", "Asia/Seoul"))
        run_time = os.getenv("BATCH_TIME", "01:00")

        def job():
            pipeline.run_once()

        every().day.at(run_time).do(job)

        while True:
            run_pending()
            time.sleep(1)
    else:
        raise ValueError(f"Unknown BATCH_MODE: {mode}")
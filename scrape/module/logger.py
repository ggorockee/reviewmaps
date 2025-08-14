import logging
from logging.handlers import RotatingFileHandler

def get_logger(name: str = "crawler", level: int = logging.INFO) -> logging.Logger:
    logger = logging.getLogger(name)
    logger.setLevel(level)

    if logger.handlers:
        return logger  # 이미 설정됨

    fmt = logging.Formatter("%(asctime)s - %(levelname)s - %(name)s - %(message)s")

    sh = logging.StreamHandler()
    sh.setFormatter(fmt)
    logger.addHandler(sh)

    fh = RotatingFileHandler("scraper.log", maxBytes=5_000_000, backupCount=3, encoding="utf-8")
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    return logger
# core/logger.py
import logging
import sys

def get_logger(name: str) -> logging.Logger:
    """
    표준화된 포맷의 로거를 설정하고 반환합니다.
    """
    logger = logging.getLogger(name)
    
    # 핸들러가 이미 설정되어 있다면 중복 추가를 방지합니다.
    if not logger.handlers:
        logger.setLevel(logging.INFO)
        
        # 콘솔 핸들러
        stream_handler = logging.StreamHandler(sys.stdout)
        stream_handler.setLevel(logging.INFO)
        
        # 포맷터
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        stream_handler.setFormatter(formatter)
        
        logger.addHandler(stream_handler)
        
    return logger
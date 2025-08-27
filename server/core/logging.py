import logging
from pythonjsonlogger import jsonlogger

# def setup_logging(level: str = "INFO") -> None:
#     root = logging.getLogger()
#     if root.handlers:
#         return
    
#     root.setLevel(level.upper())
#     fmt = logging.Formatter("%(asctime)s - %(levelname)s - %(name)s - %(message)s")
#     sh  = logging.StreamHandler()
#     sh.setFormatter(fmt)
#     root.addHandler(sh)

def setup_logging(level: str = "INFO") -> None:
    root = logging.getLogger()
    if root.handlers:
        # 이미 핸들러가 설정되어 있으면 중복 추가 방지
        for handler in root.handlers:
            if isinstance(handler.formatter, jsonlogger.JsonFormatter):
                return
        root.handlers.clear()

    root.setLevel(level.upper())
    
    # [수정] 일반 Formatter 대신 JsonFormatter 사용
    # 표준 로그 필드(시간, 레벨, 메시지)와 우리가 추가할 커스텀 필드를 모두 포함합니다.
    formatter = jsonlogger.JsonFormatter(
        '%(asctime)s %(name)s %(levelname)s %(message)s'
    )
    
    log_handler = logging.StreamHandler()
    log_handler.setFormatter(formatter)
    root.addHandler(log_handler)
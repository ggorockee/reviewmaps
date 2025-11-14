import logging
from pythonjsonlogger import jsonlogger
import sys

def setup_logging(level: str = "INFO") -> None:
    # [수정] Uvicorn의 기본 'access' 로거만 가져와서 핸들러를 비활성화합니다.
    # 이렇게 하면 uvicorn.error 같은 다른 중요한 로거는 영향을 받지 않습니다.
    uvicorn_access_logger = logging.getLogger("uvicorn.access")
    uvicorn_access_logger.handlers = []
    uvicorn_access_logger.propagate = False # 로그가 상위 로거로 전파되는 것을 막음

    # [수정] root 로거 대신, 우리 앱 전용의 새로운 로거를 설정합니다.
    # 이렇게 하면 다른 라이브러리의 로거 설정과 충돌하지 않습니다.
    app_logger = logging.getLogger() # root logger를 가져옵니다.
    
    # 이미 핸들러가 설정되어 있으면 중복 추가를 방지합니다.
    if any(isinstance(h, logging.StreamHandler) for h in app_logger.handlers):
        # 기존 핸들러 중 JsonFormatter가 있는 경우만 제외하고 정리
        has_json_formatter = any(isinstance(h.formatter, jsonlogger.JsonFormatter) for h in app_logger.handlers)
        if has_json_formatter:
            return
        app_logger.handlers.clear()

    app_logger.setLevel(level.upper())
    
    log_format = (
        '%(asctime)s %(levelname)s %(name)s %(message)s '
        '%(client_host)s %(method)s %(url_path)s %(status_code)s %(process_time_ms)s'
    )
    
    formatter = jsonlogger.JsonFormatter(log_format)
    
    log_handler = logging.StreamHandler(sys.stdout)
    log_handler.setFormatter(formatter)
    app_logger.addHandler(log_handler)


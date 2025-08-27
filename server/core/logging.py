import logging
from pythonjsonlogger import jsonlogger
import sys

def setup_logging(level: str = "INFO") -> None:
    # Uvicorn의 기본 로거를 가져와서 핸들러를 비활성화합니다.
    # 이렇게 하면 우리가 만든 미들웨어 로그만 남게 됩니다.
    uvicorn_access_logger = logging.getLogger("uvicorn.access")
    uvicorn_access_logger.handlers = []
    uvicorn_access_logger.propagate = False # 로그가 상위 로거로 전파되는 것을 막음

    root = logging.getLogger()
    if any(isinstance(h.formatter, jsonlogger.JsonFormatter) for h in root.handlers):
        return # 이미 JSON 포맷터가 설정되어 있으면 중복 실행 방지

    root.handlers.clear()
    root.setLevel(level.upper())
    
    # [수정] 최종 JSON에 포함될 모든 필드를 명시적으로 정의합니다.
    # Loki에서 자동으로 파싱될 필드들입니다.
    log_format = (
        '%(asctime)s %(levelname)s %(name)s %(message)s '
        '%(client_host)s %(method)s %(url_path)s %(status_code)s %(process_time_ms)s'
    )
    
    formatter = jsonlogger.JsonFormatter(log_format)
    
    # stdout (터미널)으로 로그를 출력합니다.
    log_handler = logging.StreamHandler(sys.stdout)
    log_handler.setFormatter(formatter)
    root.addHandler(log_handler)
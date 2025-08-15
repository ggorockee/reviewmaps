from fastapi import FastAPI, APIRouter, status
import uvicorn

# --- 사용자가 작성한 코드 부분 ---
router = APIRouter(tags=["healthcheck"])

@router.get("/healthz", status_code=status.HTTP_200_OK)
def healthz():
    """
    서버의 상태를 확인하는 Health Check 엔드포인트입니다.
    서버가 정상적으로 실행 중이면 200 OK와 함께 상태 메시지를 반환합니다.
    """
    return {
        "status": "ok"
    }
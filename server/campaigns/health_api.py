from ninja import Router

router = Router()


@router.get("/healthz", summary="헬스체크")
def health_check():
    """
    Kubernetes 헬스체크 엔드포인트
    서버가 정상적으로 실행 중이면 200 OK 반환

    Note: Django Ninja에서 타입 힌트 없는 파라미터는 쿼리 파라미터로 해석되므로
    헬스체크처럼 파라미터가 필요 없는 경우 함수 시그니처에서 제거해야 함
    """
    return {
        "status": "healthy",
        "service": "reviewmaps-server",
        "version": "1.0.0"
    }

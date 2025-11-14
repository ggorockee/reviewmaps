from ninja import Router

router = Router()


@router.get("/healthz", summary="헬스체크")
def health_check(request):
    """
    Kubernetes 헬스체크 엔드포인트
    서버가 정상적으로 실행 중이면 200 OK 반환
    """
    return {
        "status": "healthy",
        "service": "reviewmaps-server",
        "version": "1.0.0"
    }

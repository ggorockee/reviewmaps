"""
Prometheus 메트릭 수집 미들웨어

예외 추적, API 요청 시간 측정, 서비스 상태 체크를 담당합니다.
"""

import time
import logging
from django.utils.deprecation import MiddlewareMixin

from core.metrics import (
    record_exception,
    record_api_request,
    update_service_status,
)

logger = logging.getLogger(__name__)


class MetricsMiddleware(MiddlewareMixin):
    """
    API 요청/응답 메트릭 수집 미들웨어

    수집하는 메트릭:
    - reviewmaps_api_requests_total: API 요청 횟수
    - reviewmaps_api_request_duration_seconds: API 요청 처리 시간
    - reviewmaps_exceptions_total: 예외 발생 횟수
    """

    def process_request(self, request):
        """요청 시작 시간 기록"""
        request._metrics_start_time = time.time()

    def process_response(self, request, response):
        """응답 완료 시 메트릭 기록"""
        # 시작 시간이 없으면 스킵 (미들웨어 순서 문제 방지)
        if not hasattr(request, '_metrics_start_time'):
            return response

        # 처리 시간 계산
        duration = time.time() - request._metrics_start_time

        # 엔드포인트 정규화 (ID 등 동적 값 제거)
        endpoint = self._normalize_endpoint(request.path)

        # /metrics, /static 등 제외
        if self._should_skip_metrics(endpoint):
            return response

        # 상태 코드 범주화
        status = self._categorize_status(response.status_code)

        # 메트릭 기록
        record_api_request(
            method=request.method,
            endpoint=endpoint,
            status=status,
            duration=duration
        )

        return response

    def process_exception(self, request, exception):
        """예외 발생 시 메트릭 기록"""
        # 뷰 이름 추출
        view_name = self._get_view_name(request)

        # 예외 타입 추출
        exception_type = type(exception).__name__

        # 메트릭 기록
        record_exception(
            exception_type=exception_type,
            view_name=view_name
        )

        # 로깅
        logger.error(
            f"Exception in {view_name}: {exception_type} - {str(exception)}",
            exc_info=True,
            extra={
                'view_name': view_name,
                'exception_type': exception_type,
                'path': request.path,
                'method': request.method,
            }
        )

        # 예외를 다시 발생시켜 Django가 처리하도록 함
        return None

    def _normalize_endpoint(self, path: str) -> str:
        """
        엔드포인트 정규화 (카디널리티 감소)

        예: /v1/campaigns/123 -> /v1/campaigns/{id}
        """
        parts = path.strip('/').split('/')

        normalized_parts = []
        for part in parts:
            # 숫자만으로 된 부분은 {id}로 치환
            if part.isdigit():
                normalized_parts.append('{id}')
            # UUID 패턴 감지
            elif len(part) == 36 and part.count('-') == 4:
                normalized_parts.append('{uuid}')
            else:
                normalized_parts.append(part)

        return '/' + '/'.join(normalized_parts)

    def _should_skip_metrics(self, endpoint: str) -> bool:
        """메트릭 수집에서 제외할 엔드포인트"""
        skip_prefixes = [
            '/metrics',
            '/static',
            '/favicon',
            '/health',
        ]
        return any(endpoint.startswith(prefix) for prefix in skip_prefixes)

    def _categorize_status(self, status_code: int) -> str:
        """상태 코드 범주화"""
        if status_code < 400:
            return 'success'
        elif status_code < 500:
            return 'client_error'
        else:
            return 'server_error'

    def _get_view_name(self, request) -> str:
        """요청에서 뷰 이름 추출"""
        if hasattr(request, 'resolver_match') and request.resolver_match:
            return request.resolver_match.view_name or 'unknown'
        return 'unknown'


class ServiceHealthMiddleware(MiddlewareMixin):
    """
    서비스 상태 체크 미들웨어

    요청 처리 시 서비스 상태를 확인하고 메트릭에 반영합니다.
    """

    def __init__(self, get_response=None):
        super().__init__(get_response)
        # 앱 시작 시 Django 서비스 UP 설정
        update_service_status('django', True)

    def process_request(self, request):
        """요청 처리 시 서비스 상태 확인"""
        # Django가 요청을 받으면 UP 상태
        update_service_status('django', True)

    def process_exception(self, request, exception):
        """
        심각한 예외 발생 시 서비스 상태 업데이트

        주의: 일반적인 예외는 서비스 DOWN으로 처리하지 않음
        """
        # 데이터베이스 연결 오류 등 심각한 오류만 처리
        from django.db import OperationalError

        if isinstance(exception, OperationalError):
            update_service_status('database', False)
            logger.critical(
                f"Database connection error: {str(exception)}",
                exc_info=True
            )

        return None

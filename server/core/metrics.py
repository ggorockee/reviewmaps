"""
ReviewMaps 커스텀 Prometheus 메트릭 정의

네이밍 컨벤션:
- Prefix: reviewmaps_
- 단위 명시: _seconds, _bytes, _total
- Counter: 누적 값 (증가만 가능)
- Gauge: 현재 값 (증감 가능)
- Histogram: 분포 측정 (응답 시간 등)
"""

from prometheus_client import Counter, Gauge, Histogram


# =============================================================================
# 1. 비즈니스 로직 메트릭
# =============================================================================

# Campaign 관리
campaign_active_total = Gauge(
    'reviewmaps_campaign_active_total',
    '현재 활성 캠페인 수',
    ['region']
)

campaign_expired_total = Counter(
    'reviewmaps_campaign_expired_total',
    '만료된 캠페인 누적 수',
    ['region']
)

# 데이터 enrichment (향후 확장용)
enrichment_total = Counter(
    'reviewmaps_enrichment_total',
    'Enrichment 작업 횟수',
    ['scope', 'status']  # scope: region/all, status: success/failed
)

enrichment_duration_seconds = Histogram(
    'reviewmaps_enrichment_duration_seconds',
    'Enrichment 소요 시간',
    ['scope'],
    buckets=[0.1, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0]
)


# =============================================================================
# 2. 외부 API 호출 추적
# =============================================================================

# Naver API (향후 확장용)
naver_api_calls_total = Counter(
    'reviewmaps_naver_api_calls_total',
    'Naver API 호출 횟수',
    ['endpoint', 'status_code']
)

naver_api_duration_seconds = Histogram(
    'reviewmaps_naver_api_duration_seconds',
    'Naver API 응답 시간',
    ['endpoint'],
    buckets=[0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
)

naver_api_rate_limit_hits = Counter(
    'reviewmaps_naver_api_rate_limit_hits_total',
    'Naver API Rate limit 도달 횟수'
)


# =============================================================================
# 3. 데이터베이스 테이블별 메트릭
# =============================================================================

# 테이블 크기 추적
table_rows_total = Gauge(
    'reviewmaps_table_rows_total',
    '테이블 행 수',
    ['table_name']
)

table_size_bytes = Gauge(
    'reviewmaps_table_size_bytes',
    '테이블 크기 (바이트)',
    ['table_name']
)

# Cleanup 작업
cleanup_deleted_rows = Counter(
    'reviewmaps_cleanup_deleted_rows_total',
    '정리된 행 수',
    ['table_name']
)


# =============================================================================
# 4. 애플리케이션 헬스 메트릭
# =============================================================================

# 서비스 상태
service_up = Gauge(
    'reviewmaps_service_up',
    '서비스 UP/DOWN 상태 (1/0)',
    ['service']  # django, database
)

# 에러 추적
exceptions_total = Counter(
    'reviewmaps_exceptions_total',
    '발생한 예외 타입별 횟수',
    ['exception_type', 'view_name']
)


# =============================================================================
# 5. API 엔드포인트 메트릭
# =============================================================================

# API 요청 추적 (상세)
api_requests_total = Counter(
    'reviewmaps_api_requests_total',
    'API 요청 횟수 (엔드포인트별)',
    ['method', 'endpoint', 'status']
)

api_request_duration_seconds = Histogram(
    'reviewmaps_api_request_duration_seconds',
    'API 요청 처리 시간',
    ['method', 'endpoint'],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
)


# =============================================================================
# 6. 인증 관련 메트릭
# =============================================================================

auth_attempts_total = Counter(
    'reviewmaps_auth_attempts_total',
    '인증 시도 횟수',
    ['method', 'status']  # method: email/kakao/google/apple, status: success/failed
)

active_users_total = Gauge(
    'reviewmaps_active_users_total',
    '활성 사용자 수 (최근 24시간 로그인)'
)


# =============================================================================
# 7. 키워드 알람 메트릭
# =============================================================================

keyword_alerts_sent_total = Counter(
    'reviewmaps_keyword_alerts_sent_total',
    '발송된 키워드 알람 수',
    ['status']  # success/failed
)

fcm_devices_active_total = Gauge(
    'reviewmaps_fcm_devices_active_total',
    '활성 FCM 디바이스 수',
    ['device_type']  # android/ios
)


# =============================================================================
# 헬퍼 함수
# =============================================================================

def record_exception(exception_type: str, view_name: str = 'unknown'):
    """예외 발생 시 메트릭 기록"""
    exceptions_total.labels(
        exception_type=exception_type,
        view_name=view_name
    ).inc()


def record_api_request(method: str, endpoint: str, status: str, duration: float):
    """API 요청 메트릭 기록"""
    api_requests_total.labels(
        method=method,
        endpoint=endpoint,
        status=status
    ).inc()
    api_request_duration_seconds.labels(
        method=method,
        endpoint=endpoint
    ).observe(duration)


def record_auth_attempt(method: str, success: bool):
    """인증 시도 메트릭 기록"""
    auth_attempts_total.labels(
        method=method,
        status='success' if success else 'failed'
    ).inc()


def update_service_status(service: str, is_up: bool):
    """서비스 상태 업데이트"""
    service_up.labels(service=service).set(1 if is_up else 0)

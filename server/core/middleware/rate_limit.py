"""
Rate Limiting Middleware
Django Admin에서 설정 가능한 API Rate Limiting
"""
import time
from django.core.cache import cache
from django.http import JsonResponse
from django.utils.deprecation import MiddlewareMixin
from app_config.models import RateLimitConfig
import logging

logger = logging.getLogger(__name__)


class RateLimitMiddleware(MiddlewareMixin):
    """
    Rate Limiting Middleware
    - Django Admin에서 설정한 Rate Limit 규칙을 적용
    - IP 주소 기반으로 요청 제한
    - 인증된 사용자는 user_id로 추가 추적 가능
    """

    def __init__(self, get_response):
        self.get_response = get_response
        super().__init__(get_response)
        # 설정 캐시 (60초마다 갱신)
        self._config_cache = None
        self._config_cache_time = 0
        self._config_cache_ttl = 60

    def _get_configs(self):
        """Rate Limit 설정을 캐시에서 가져오기 (60초 TTL)"""
        now = time.time()
        if self._config_cache is None or (now - self._config_cache_time) > self._config_cache_ttl:
            self._config_cache = list(
                RateLimitConfig.objects.filter(is_enabled=True).order_by('-priority', 'endpoint')
            )
            self._config_cache_time = now
        return self._config_cache

    def _get_client_identifier(self, request):
        """클라이언트 식별자 추출 (IP 주소 + User ID)"""
        # X-Forwarded-For 헤더에서 실제 IP 추출 (프록시/로드밸런서 환경)
        x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
        if x_forwarded_for:
            ip = x_forwarded_for.split(',')[0].strip()
        else:
            ip = request.META.get('REMOTE_ADDR', '')

        # 인증된 사용자인 경우 user_id 추가
        user_id = None
        if hasattr(request, 'user') and request.user.is_authenticated:
            user_id = request.user.id

        return ip, user_id

    def _is_user_authenticated(self, request):
        """사용자 인증 여부 확인"""
        return hasattr(request, 'user') and request.user.is_authenticated

    def _get_rate_limit_key(self, config_id, identifier, prefix="ratelimit"):
        """Rate Limit 추적을 위한 캐시 키 생성"""
        return f"{prefix}:{config_id}:{identifier}"

    def _get_block_key(self, config_id, identifier, prefix="ratelimit_block"):
        """차단 추적을 위한 캐시 키 생성"""
        return f"{prefix}:{config_id}:{identifier}"

    def _check_rate_limit(self, config, identifier):
        """
        Rate Limit 체크
        Returns: (allowed: bool, remaining: int, retry_after: int)
        """
        cache_key = self._get_rate_limit_key(config.id, identifier)
        block_key = self._get_block_key(config.id, identifier)

        # 차단 상태 확인
        if config.block_duration_seconds > 0:
            blocked_until = cache.get(block_key)
            if blocked_until:
                retry_after = max(0, int(blocked_until - time.time()))
                if retry_after > 0:
                    return False, 0, retry_after

        # 현재 요청 수 가져오기
        request_data = cache.get(cache_key, {'count': 0, 'reset_at': time.time() + config.window_seconds})

        # 시간 윈도우가 만료되면 리셋
        if time.time() >= request_data['reset_at']:
            request_data = {'count': 0, 'reset_at': time.time() + config.window_seconds}

        # 요청 수 증가
        request_data['count'] += 1
        remaining = max(0, config.max_requests - request_data['count'])

        # 캐시에 저장
        cache.set(cache_key, request_data, config.window_seconds)

        # Rate Limit 초과 확인
        if request_data['count'] > config.max_requests:
            # 차단 시간 설정
            if config.block_duration_seconds > 0:
                blocked_until = time.time() + config.block_duration_seconds
                cache.set(block_key, blocked_until, config.block_duration_seconds)
                retry_after = config.block_duration_seconds
            else:
                retry_after = int(request_data['reset_at'] - time.time())

            return False, 0, retry_after

        return True, remaining, 0

    def process_request(self, request):
        """요청 처리 전 Rate Limit 체크"""
        # Health check 엔드포인트는 제외
        if request.path in ['/health/', '/readiness/', '/liveness/']:
            return None

        # Admin 페이지는 제외 (선택적)
        if request.path.startswith('/admin/'):
            return None

        # 설정 가져오기
        configs = self._get_configs()
        if not configs:
            return None

        # 클라이언트 식별
        ip, user_id = self._get_client_identifier(request)
        identifier = f"{ip}:{user_id}" if user_id else ip
        is_authenticated = self._is_user_authenticated(request)

        # 매칭되는 설정 찾기 (우선순위 순)
        for config in configs:
            if not config.matches_path(request.path):
                continue

            # 인증 여부에 따라 적용 여부 결정
            if is_authenticated and not config.apply_to_authenticated:
                continue
            if not is_authenticated and not config.apply_to_anonymous:
                continue

            # Rate Limit 체크
            allowed, remaining, retry_after = self._check_rate_limit(config, identifier)

            if not allowed:
                logger.warning(
                    f"Rate limit exceeded: {request.path} from {ip} "
                    f"(user_id={user_id}, config={config.endpoint})"
                )
                return JsonResponse(
                    {
                        'error': 'Rate limit exceeded',
                        'message': f'너무 많은 요청을 보내셨습니다. {retry_after}초 후에 다시 시도해주세요.',
                        'retry_after': retry_after,
                    },
                    status=429
                )

            # 첫 번째 매칭되는 설정만 적용
            break

        return None




"""
앱 버전 API 테스트
GET /api/v1/app-config/version
"""
import pytest
from django.test import AsyncClient
from app_config.models import AppVersion


@pytest.mark.django_db
class TestVersionCheckAPI:
    """버전 체크 API 테스트"""

    @pytest.fixture
    async def android_version_config(self):
        """Android 버전 설정 fixture"""
        return await AppVersion.objects.acreate(
            platform='android',
            version='1.4.0',
            build_number=140,
            minimum_version='1.3.0',
            force_update=False,
            update_message='더 안정적인 서비스 이용을 위해 업데이트해 주세요.',
            store_url='https://play.google.com/store/apps/details?id=com.reviewmaps.mobile&pli=1',
            is_active=True
        )

    @pytest.fixture
    async def ios_version_config(self):
        """iOS 버전 설정 fixture"""
        return await AppVersion.objects.acreate(
            platform='ios',
            version='1.4.0',
            build_number=140,
            minimum_version='1.3.0',
            force_update=False,
            update_message='더 안정적인 서비스 이용을 위해 업데이트해 주세요.',
            store_url='https://apps.apple.com/kr',
            is_active=True
        )

    @pytest.mark.asyncio
    async def test_force_update_required(self, android_version_config):
        """
        강제 업데이트 시나리오: current < min_version
        """
        client = AsyncClient()
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'android', 'current_version': '1.2.0'}
        )

        assert response.status_code == 200
        data = response.json()

        assert data['latest_version'] == '1.4.0'
        assert data['min_version'] == '1.3.0'
        assert data['force_update'] is True
        assert data['message_title'] == '필수 업데이트 안내'
        assert '더 이상 지원되지 않습니다' in data['message_body']
        assert data['store_url'] == 'https://play.google.com/store/apps/details?id=com.reviewmaps.mobile&pli=1'

    @pytest.mark.asyncio
    async def test_recommended_update(self, android_version_config):
        """
        권장 업데이트 시나리오: min_version ≤ current < latest_version
        """
        client = AsyncClient()
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'android', 'current_version': '1.3.0'}
        )

        assert response.status_code == 200
        data = response.json()

        assert data['latest_version'] == '1.4.0'
        assert data['min_version'] == '1.3.0'
        assert data['force_update'] is False
        assert data['message_title'] == '업데이트 안내'
        assert '더 안정적인 서비스' in data['message_body']

    @pytest.mark.asyncio
    async def test_no_update_needed_same_version(self, android_version_config):
        """
        업데이트 불필요 시나리오: current == latest_version
        """
        client = AsyncClient()
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'android', 'current_version': '1.4.0'}
        )

        assert response.status_code == 200
        data = response.json()

        assert data['latest_version'] == '1.4.0'
        assert data['min_version'] == '1.3.0'
        assert data['force_update'] is False
        assert data['message_title'] == '최신 버전'
        assert '최신 버전을 사용 중' in data['message_body']

    @pytest.mark.asyncio
    async def test_no_update_needed_ahead_of_latest(self, android_version_config):
        """
        업데이트 불필요 시나리오: current > latest_version (개발 버전)
        """
        client = AsyncClient()
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'android', 'current_version': '1.5.0'}
        )

        assert response.status_code == 200
        data = response.json()

        assert data['latest_version'] == '1.4.0'
        assert data['force_update'] is False
        assert data['message_title'] == '최신 버전'

    @pytest.mark.asyncio
    async def test_ios_platform(self, ios_version_config):
        """iOS 플랫폼 버전 체크"""
        client = AsyncClient()
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'ios', 'current_version': '1.3.5'}
        )

        assert response.status_code == 200
        data = response.json()

        assert data['latest_version'] == '1.4.0'
        assert data['force_update'] is False
        assert data['store_url'] == 'https://apps.apple.com/kr'

    @pytest.mark.asyncio
    async def test_custom_update_message(self, android_version_config):
        """커스텀 업데이트 메시지 사용"""
        # 커스텀 메시지 설정
        android_version_config.update_message = "새로운 기능이 추가되었습니다!"
        await android_version_config.asave()

        client = AsyncClient()
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'android', 'current_version': '1.3.5'}
        )

        assert response.status_code == 200
        data = response.json()
        assert data['message_body'] == "새로운 기능이 추가되었습니다!"

    @pytest.mark.asyncio
    async def test_invalid_version_format(self, android_version_config):
        """잘못된 버전 형식"""
        client = AsyncClient()
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'android', 'current_version': '1.3'}
        )

        assert response.status_code == 404
        assert '잘못된 버전 형식' in response.json()['detail']

    @pytest.mark.asyncio
    async def test_no_active_version_config(self):
        """활성화된 버전 설정이 없는 경우"""
        # 비활성 버전만 생성
        await AppVersion.objects.acreate(
            platform='android',
            version='1.0.0',
            build_number=100,
            minimum_version='1.0.0',
            store_url='https://play.google.com',
            is_active=False
        )

        client = AsyncClient()
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'android', 'current_version': '1.0.0'}
        )

        assert response.status_code == 404
        assert '활성화된 버전 정보가 없습니다' in response.json()['detail']

    @pytest.mark.asyncio
    async def test_platform_not_found(self):
        """존재하지 않는 플랫폼"""
        client = AsyncClient()
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'windows', 'current_version': '1.0.0'}
        )

        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_multiple_active_versions_uses_latest(self):
        """여러 활성 버전이 있을 때 가장 최신 것 사용"""
        # 오래된 버전
        await AppVersion.objects.acreate(
            platform='android',
            version='1.3.0',
            build_number=130,
            minimum_version='1.2.0',
            store_url='https://play.google.com',
            is_active=True
        )

        # 최신 버전
        latest = await AppVersion.objects.acreate(
            platform='android',
            version='1.5.0',
            build_number=150,
            minimum_version='1.4.0',
            store_url='https://play.google.com',
            is_active=True
        )

        client = AsyncClient()
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'android', 'current_version': '1.4.0'}
        )

        assert response.status_code == 200
        data = response.json()
        assert data['latest_version'] == '1.5.0'
        assert data['min_version'] == '1.4.0'


@pytest.mark.django_db
class TestVersionCheckEdgeCases:
    """버전 체크 API 엣지 케이스 테스트"""

    @pytest.mark.asyncio
    async def test_version_with_leading_zeros(self):
        """버전 번호에 선행 0이 있는 경우"""
        await AppVersion.objects.acreate(
            platform='android',
            version='1.4.0',
            build_number=140,
            minimum_version='1.3.0',
            store_url='https://play.google.com',
            is_active=True
        )

        client = AsyncClient()
        # 선행 0은 정수로 파싱되므로 동일하게 처리됨
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'android', 'current_version': '1.04.00'}
        )

        # 잘못된 형식으로 처리 (1.04.00는 1.4.0과 다름)
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_major_version_jump(self):
        """Major 버전 점프 (1.x.x → 2.x.x)"""
        await AppVersion.objects.acreate(
            platform='android',
            version='2.0.0',
            build_number=200,
            minimum_version='1.9.0',
            store_url='https://play.google.com',
            is_active=True
        )

        client = AsyncClient()

        # 1.8.0 → 강제 업데이트
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'android', 'current_version': '1.8.0'}
        )
        assert response.status_code == 200
        assert response.json()['force_update'] is True

        # 1.9.5 → 권장 업데이트
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'android', 'current_version': '1.9.5'}
        )
        assert response.status_code == 200
        assert response.json()['force_update'] is False

    @pytest.mark.asyncio
    async def test_patch_version_only_difference(self):
        """Patch 버전만 다른 경우"""
        await AppVersion.objects.acreate(
            platform='android',
            version='1.3.5',
            build_number=135,
            minimum_version='1.3.0',
            store_url='https://play.google.com',
            is_active=True
        )

        client = AsyncClient()

        # 1.3.4 → 권장 업데이트
        response = await client.get(
            '/api/v1/app-config/version',
            {'platform': 'android', 'current_version': '1.3.4'}
        )
        assert response.status_code == 200
        data = response.json()
        assert data['force_update'] is False
        assert data['message_title'] == '업데이트 안내'

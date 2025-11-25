"""
앱 버전 체크 API 테스트
GET /api/v1/app-config/version
"""
from django.test import TestCase
from ninja.testing import TestAsyncClient
from app_config.models import AppVersion
from app_config.api import router


class VersionCheckAPITest(TestCase):
    """버전 체크 API 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        self.client = TestAsyncClient(router)

        # Android 버전 설정
        AppVersion.objects.create(
            platform='android',
            version='1.4.0',
            build_number=140,
            minimum_version='1.3.0',
            force_update=False,
            update_message='더 안정적인 서비스 이용을 위해 업데이트해 주세요.',
            store_url='https://play.google.com/store/apps/details?id=com.reviewmaps.mobile&pli=1',
            is_active=True
        )

        # iOS 버전 설정
        AppVersion.objects.create(
            platform='ios',
            version='1.4.0',
            build_number=140,
            minimum_version='1.3.0',
            force_update=False,
            update_message='더 안정적인 서비스 이용을 위해 업데이트해 주세요.',
            store_url='https://apps.apple.com/kr',
            is_active=True
        )

    async def test_force_update_required(self):
        """
        강제 업데이트 시나리오: current < min_version
        """
        response = await self.client.get('/version?platform=android&current_version=1.2.0')

        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertEqual(data['latest_version'], '1.4.0')
        self.assertEqual(data['min_version'], '1.3.0')
        self.assertTrue(data['force_update'])
        self.assertEqual(data['message_title'], '필수 업데이트 안내')
        self.assertIn('더 이상 지원되지 않습니다', data['message_body'])
        self.assertEqual(
            data['store_url'],
            'https://play.google.com/store/apps/details?id=com.reviewmaps.mobile&pli=1'
        )

    async def test_recommended_update(self):
        """
        권장 업데이트 시나리오: min_version ≤ current < latest_version
        """
        response = await self.client.get('/version?platform=android&current_version=1.3.0')

        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertEqual(data['latest_version'], '1.4.0')
        self.assertEqual(data['min_version'], '1.3.0')
        self.assertFalse(data['force_update'])
        self.assertEqual(data['message_title'], '업데이트 안내')
        self.assertIn('더 안정적인 서비스', data['message_body'])

    async def test_no_update_needed_same_version(self):
        """
        업데이트 불필요 시나리오: current == latest_version
        """
        response = await self.client.get('/version?platform=android&current_version=1.4.0')

        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertEqual(data['latest_version'], '1.4.0')
        self.assertEqual(data['min_version'], '1.3.0')
        self.assertFalse(data['force_update'])
        self.assertEqual(data['message_title'], '최신 버전')
        self.assertIn('최신 버전을 사용 중', data['message_body'])

    async def test_no_update_needed_ahead_of_latest(self):
        """
        업데이트 불필요 시나리오: current > latest_version (개발 버전)
        """
        response = await self.client.get('/version?platform=android&current_version=1.5.0')

        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertEqual(data['latest_version'], '1.4.0')
        self.assertFalse(data['force_update'])
        self.assertEqual(data['message_title'], '최신 버전')

    async def test_ios_platform(self):
        """iOS 플랫폼 버전 체크"""
        response = await self.client.get('/version?platform=ios&current_version=1.3.5')

        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertEqual(data['latest_version'], '1.4.0')
        self.assertFalse(data['force_update'])
        self.assertEqual(data['store_url'], 'https://apps.apple.com/kr')

    async def test_custom_update_message(self):
        """커스텀 업데이트 메시지 사용"""
        # 커스텀 메시지로 업데이트
        version = await AppVersion.objects.aget(platform='android', is_active=True)
        version.update_message = "새로운 기능이 추가되었습니다!"
        await version.asave()

        response = await self.client.get('/version?platform=android&current_version=1.3.5')

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['message_body'], "새로운 기능이 추가되었습니다!")

    async def test_invalid_version_format(self):
        """잘못된 버전 형식"""
        response = await self.client.get('/version?platform=android&current_version=1.3')

        self.assertEqual(response.status_code, 404)
        self.assertIn('잘못된 버전 형식', response.json()['detail'])

    async def test_no_active_version_config(self):
        """활성화된 버전 설정이 없는 경우"""
        # 모든 버전을 비활성화
        await AppVersion.objects.filter(platform='android').aupdate(is_active=False)

        response = await self.client.get('/version?platform=android&current_version=1.0.0')

        self.assertEqual(response.status_code, 404)
        self.assertIn('활성화된 버전 정보가 없습니다', response.json()['detail'])

    async def test_platform_not_found(self):
        """존재하지 않는 플랫폼"""
        response = await self.client.get('/version?platform=windows&current_version=1.0.0')

        self.assertEqual(response.status_code, 404)

    async def test_missing_platform_parameter(self):
        """platform 파라미터 누락"""
        response = await self.client.get('/version?current_version=1.0.0')

        self.assertEqual(response.status_code, 422)  # Validation error

    async def test_missing_current_version_parameter(self):
        """current_version 파라미터 누락"""
        response = await self.client.get('/version?platform=android')

        self.assertEqual(response.status_code, 422)  # Validation error


class VersionCheckEdgeCasesTest(TestCase):
    """버전 체크 API 엣지 케이스 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        self.client = TestAsyncClient(router)

    async def test_major_version_jump(self):
        """Major 버전 점프 (1.x.x → 2.x.x)"""
        AppVersion.objects.create(
            platform='android',
            version='2.0.0',
            build_number=200,
            minimum_version='1.9.0',
            store_url='https://play.google.com',
            is_active=True
        )

        # 1.8.0 → 강제 업데이트
        response = await self.client.get('/version?platform=android&current_version=1.8.0')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()['force_update'])

        # 1.9.5 → 권장 업데이트
        response = await self.client.get('/version?platform=android&current_version=1.9.5')
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json()['force_update'])

    async def test_patch_version_only_difference(self):
        """Patch 버전만 다른 경우"""
        AppVersion.objects.create(
            platform='android',
            version='1.3.5',
            build_number=135,
            minimum_version='1.3.0',
            store_url='https://play.google.com',
            is_active=True
        )

        # 1.3.4 → 권장 업데이트
        response = await self.client.get('/version?platform=android&current_version=1.3.4')
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertFalse(data['force_update'])
        self.assertEqual(data['message_title'], '업데이트 안내')

    async def test_multiple_active_versions_uses_latest(self):
        """여러 활성 버전이 있을 때 가장 최신 것 사용"""
        # 오래된 버전 (먼저 생성)
        AppVersion.objects.create(
            platform='android',
            version='1.3.0',
            build_number=130,
            minimum_version='1.2.0',
            store_url='https://play.google.com',
            is_active=True
        )

        # 최신 버전 (나중에 생성)
        AppVersion.objects.create(
            platform='android',
            version='1.5.0',
            build_number=150,
            minimum_version='1.4.0',
            store_url='https://play.google.com',
            is_active=True
        )

        response = await self.client.get('/version?platform=android&current_version=1.4.0')

        self.assertEqual(response.status_code, 200)
        data = response.json()
        # created_at 기준으로 가장 최신 것이 반환됨
        self.assertEqual(data['latest_version'], '1.5.0')
        self.assertEqual(data['min_version'], '1.4.0')

    async def test_version_boundary_conditions(self):
        """버전 경계 조건 테스트"""
        AppVersion.objects.create(
            platform='android',
            version='1.3.0',
            build_number=130,
            minimum_version='1.3.0',
            store_url='https://play.google.com',
            is_active=True
        )

        # current == min_version == latest_version
        response = await self.client.get('/version?platform=android&current_version=1.3.0')
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertFalse(data['force_update'])
        self.assertEqual(data['message_title'], '최신 버전')

    async def test_zero_version(self):
        """0.x.x 버전 처리"""
        AppVersion.objects.create(
            platform='android',
            version='0.9.0',
            build_number=90,
            minimum_version='0.8.0',
            store_url='https://play.google.com',
            is_active=True
        )

        response = await self.client.get('/version?platform=android&current_version=0.7.5')
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data['force_update'])
        self.assertEqual(data['latest_version'], '0.9.0')


class VersionCheckRealWorldScenariosTest(TestCase):
    """실제 사용 시나리오 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        self.client = TestAsyncClient(router)

    async def test_gradual_rollout_scenario(self):
        """
        점진적 배포 시나리오:
        - latest_version: 1.5.0 (새 버전)
        - min_version: 1.3.0 (최소 지원)
        - 1.2.x 사용자 → 강제 업데이트
        - 1.3.x ~ 1.4.x 사용자 → 권장 업데이트
        - 1.5.0 사용자 → 업데이트 불필요
        """
        AppVersion.objects.create(
            platform='android',
            version='1.5.0',
            build_number=150,
            minimum_version='1.3.0',
            update_message='성능 개선 및 버그 수정이 포함되었습니다.',
            store_url='https://play.google.com',
            is_active=True
        )

        # 1.2.9 → 강제 업데이트
        response = await self.client.get('/version?platform=android&current_version=1.2.9')
        data = response.json()
        self.assertTrue(data['force_update'])
        self.assertEqual(data['message_title'], '필수 업데이트 안내')

        # 1.3.5 → 권장 업데이트
        response = await self.client.get('/version?platform=android&current_version=1.3.5')
        data = response.json()
        self.assertFalse(data['force_update'])
        self.assertEqual(data['message_title'], '업데이트 안내')
        self.assertIn('성능 개선', data['message_body'])

        # 1.5.0 → 업데이트 불필요
        response = await self.client.get('/version?platform=android&current_version=1.5.0')
        data = response.json()
        self.assertFalse(data['force_update'])
        self.assertEqual(data['message_title'], '최신 버전')

    async def test_emergency_hotfix_scenario(self):
        """
        긴급 핫픽스 시나리오:
        - 심각한 버그로 인해 모든 이전 버전 차단
        - min_version == latest_version
        """
        AppVersion.objects.create(
            platform='ios',
            version='1.6.1',
            build_number=161,
            minimum_version='1.6.1',  # 긴급 핫픽스: 최소 버전 = 최신 버전
            update_message='보안 문제 해결을 위한 긴급 업데이트입니다.',
            store_url='https://apps.apple.com/kr',
            is_active=True
        )

        # 1.6.0 → 강제 업데이트
        response = await self.client.get('/version?platform=ios&current_version=1.6.0')
        data = response.json()
        self.assertTrue(data['force_update'])
        self.assertIn('보안 문제', data['message_body'])

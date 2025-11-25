"""
앱 버전 체크 API 테스트
GET /api/v1/app-config/version

현재 API 스펙:
- 서버는 정보만 제공 (latest_version, min_version, force_update, store_url, message)
- 모든 버전 비교 로직은 클라이언트(Flutter)에서 수행
"""
from django.test import TestCase
from ninja.testing import TestAsyncClient
from app_config.models import AppVersion
from app_config.api import router
from asgiref.sync import sync_to_async


class VersionCheckAPITest(TestCase):
    """버전 체크 API 테스트 - 정보 제공만 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        self.client = TestAsyncClient(router)

        # Android 버전 설정 (force_update=False)
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

        # iOS 버전 설정 (force_update=True)
        AppVersion.objects.create(
            platform='ios',
            version='2.0.0',
            build_number=200,
            minimum_version='2.0.0',
            force_update=True,
            update_message='중요한 보안 업데이트입니다.',
            store_url='https://apps.apple.com/kr/app/reviewmaps/id123456789',
            is_active=True
        )

    async def test_get_android_version_info(self):
        """Android 버전 정보 조회"""
        response = await self.client.get('/version?platform=android')

        self.assertEqual(response.status_code, 200)
        data = response.json()

        # 서버는 모델 값만 반환
        self.assertEqual(data['latest_version'], '1.4.0')
        self.assertEqual(data['min_version'], '1.3.0')
        self.assertFalse(data['force_update'])  # 모델의 force_update 값
        self.assertEqual(
            data['store_url'],
            'https://play.google.com/store/apps/details?id=com.reviewmaps.mobile&pli=1'
        )
        self.assertEqual(data['message_title'], '업데이트 안내')
        self.assertIn('더 안정적인 서비스', data['message_body'])

    async def test_get_ios_version_info(self):
        """iOS 버전 정보 조회 - force_update=True 확인"""
        response = await self.client.get('/version?platform=ios')

        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertEqual(data['latest_version'], '2.0.0')
        self.assertEqual(data['min_version'], '2.0.0')
        self.assertTrue(data['force_update'])  # 모델의 force_update=True
        self.assertEqual(data['store_url'], 'https://apps.apple.com/kr/app/reviewmaps/id123456789')
        self.assertIn('보안 업데이트', data['message_body'])

    async def test_force_update_reflects_model_value(self):
        """force_update 값이 모델 값을 정확히 반영하는지 확인"""
        # Android force_update를 True로 변경
        await AppVersion.objects.filter(platform='android').aupdate(force_update=True)

        response = await self.client.get('/version?platform=android')
        data = response.json()

        self.assertTrue(data['force_update'])  # 변경된 값 반영 확인

    async def test_custom_update_message(self):
        """커스텀 업데이트 메시지가 반환되는지 확인"""
        version = await AppVersion.objects.aget(platform='android', is_active=True)
        version.update_message = "새로운 기능이 추가되었습니다!"
        await version.asave()

        response = await self.client.get('/version?platform=android')
        data = response.json()

        self.assertEqual(data['message_body'], "새로운 기능이 추가되었습니다!")

    async def test_default_message_when_no_custom_message(self):
        """update_message가 없을 때 기본 메시지 반환"""
        await AppVersion.objects.filter(platform='android').aupdate(update_message=None)

        response = await self.client.get('/version?platform=android')
        data = response.json()

        self.assertIn('더 안정적이고 편리한 서비스', data['message_body'])

    async def test_no_active_version_returns_404(self):
        """활성화된 버전 설정이 없는 경우 404"""
        await AppVersion.objects.filter(platform='android').aupdate(is_active=False)

        response = await self.client.get('/version?platform=android')

        self.assertEqual(response.status_code, 404)

    async def test_nonexistent_platform_returns_404(self):
        """존재하지 않는 플랫폼 조회 시 404"""
        response = await self.client.get('/version?platform=windows')

        self.assertEqual(response.status_code, 404)

    async def test_missing_platform_parameter_returns_422(self):
        """platform 파라미터 누락 시 422"""
        response = await self.client.get('/version')

        self.assertEqual(response.status_code, 422)

    async def test_response_schema_structure(self):
        """응답 스키마 구조 검증"""
        response = await self.client.get('/version?platform=android')
        data = response.json()

        # 필수 필드 존재 확인
        self.assertIn('latest_version', data)
        self.assertIn('min_version', data)
        self.assertIn('force_update', data)
        self.assertIn('store_url', data)
        self.assertIn('message_title', data)
        self.assertIn('message_body', data)

        # 타입 확인
        self.assertIsInstance(data['latest_version'], str)
        self.assertIsInstance(data['min_version'], str)
        self.assertIsInstance(data['force_update'], bool)
        self.assertIsInstance(data['store_url'], str)
        self.assertIsInstance(data['message_title'], str)
        self.assertIsInstance(data['message_body'], str)


class VersionCheckEdgeCasesTest(TestCase):
    """버전 체크 API 엣지 케이스 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        self.client = TestAsyncClient(router)

    async def test_multiple_active_versions_returns_first(self):
        """여러 활성 버전이 있을 때 첫 번째 반환"""
        # 먼저 생성된 버전
        await sync_to_async(AppVersion.objects.create)(
            platform='android',
            version='1.3.0',
            build_number=130,
            minimum_version='1.2.0',
            force_update=False,
            store_url='https://play.google.com',
            is_active=True
        )

        # 나중에 생성된 버전
        await sync_to_async(AppVersion.objects.create)(
            platform='android',
            version='1.5.0',
            build_number=150,
            minimum_version='1.4.0',
            force_update=True,
            store_url='https://play.google.com',
            is_active=True
        )

        response = await self.client.get('/version?platform=android')

        self.assertEqual(response.status_code, 200)
        # afirst()로 조회하므로 결과가 반환됨
        data = response.json()
        self.assertIn(data['latest_version'], ['1.3.0', '1.5.0'])

    async def test_force_update_toggle(self):
        """force_update 토글 테스트"""
        # force_update=False로 생성
        await sync_to_async(AppVersion.objects.create)(
            platform='android',
            version='1.0.0',
            build_number=100,
            minimum_version='1.0.0',
            force_update=False,
            store_url='https://play.google.com',
            is_active=True
        )

        # False 확인
        response = await self.client.get('/version?platform=android')
        self.assertFalse(response.json()['force_update'])

        # True로 변경
        await AppVersion.objects.filter(platform='android').aupdate(force_update=True)

        # True 확인
        response = await self.client.get('/version?platform=android')
        self.assertTrue(response.json()['force_update'])

    async def test_version_string_formats(self):
        """다양한 버전 문자열 형식 지원"""
        await sync_to_async(AppVersion.objects.create)(
            platform='android',
            version='2.0.0-beta',
            build_number=200,
            minimum_version='1.9.0',
            force_update=False,
            store_url='https://play.google.com',
            is_active=True
        )

        response = await self.client.get('/version?platform=android')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['latest_version'], '2.0.0-beta')

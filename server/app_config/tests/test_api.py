"""
app_config API 테스트
TDD 방식으로 작성된 비동기 API 테스트
"""
from django.test import TestCase
from ninja.testing import TestAsyncClient
from app_config.models import AdConfig, AppVersion, AppSetting
from app_config.api import router
from asgiref.sync import sync_to_async


class AdConfigAPITest(TestCase):
    """광고 설정 API 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        self.client = TestAsyncClient(router)

        # Android 광고 설정
        AdConfig.objects.create(
            platform='android',
            ad_network='admob',
            is_enabled=True,
            ad_unit_ids={
                'banner_id': 'ca-app-pub-android-banner',
                'interstitial_id': 'ca-app-pub-android-interstitial'
            },
            priority=1
        )

        # iOS 광고 설정
        AdConfig.objects.create(
            platform='ios',
            ad_network='admob',
            is_enabled=True,
            ad_unit_ids={
                'banner_id': 'ca-app-pub-ios-banner',
                'interstitial_id': 'ca-app-pub-ios-interstitial'
            },
            priority=1
        )

        # 비활성 광고 설정
        AdConfig.objects.create(
            platform='android',
            ad_network='applovin',
            is_enabled=False,
            ad_unit_ids={},
            priority=2
        )

    async def test_get_ads_android(self):
        """Android 광고 설정 조회 테스트"""
        response = await self.client.get('/ads?platform=android')
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertIsInstance(data, list)
        # is_enabled=True인 Android 광고만 반환
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['platform'], 'android')
        self.assertEqual(data[0]['ad_network'], 'admob')
        self.assertTrue(data[0]['is_enabled'])

    async def test_get_ads_ios(self):
        """iOS 광고 설정 조회 테스트"""
        response = await self.client.get('/ads?platform=ios')
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['platform'], 'ios')

    async def test_get_ads_without_platform(self):
        """platform 파라미터 없이 조회 시 400 에러"""
        response = await self.client.get('/ads')
        self.assertEqual(response.status_code, 422)  # Validation error

    async def test_get_ads_invalid_platform(self):
        """잘못된 platform 조회 시 빈 배열 반환"""
        response = await self.client.get('/ads?platform=windows')
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(len(data), 0)

    async def test_get_ads_ordering(self):
        """광고 설정 우선순위 정렬 테스트"""
        # 추가 광고 설정 생성
        await sync_to_async(AdConfig.objects.create)(
            platform='android',
            ad_network='unity',
            is_enabled=True,
            ad_unit_ids={},
            priority=3
        )

        response = await self.client.get('/ads?platform=android')
        data = response.json()

        # priority 높은 순서로 정렬
        self.assertEqual(len(data), 2)
        self.assertEqual(data[0]['priority'], 3)  # unity
        self.assertEqual(data[1]['priority'], 1)  # admob


class AppVersionAPITest(TestCase):
    """앱 버전 API 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        self.client = TestAsyncClient(router)

        # Android 최신 버전
        AppVersion.objects.create(
            platform='android',
            version='1.3.5',
            build_number=50,
            minimum_version='1.0.0',
            force_update=False,
            update_message='새로운 기능이 추가되었습니다.',
            store_url='https://play.google.com/store/apps/details?id=com.reviewmaps',
            is_active=True
        )

        # iOS 최신 버전 (강제 업데이트)
        AppVersion.objects.create(
            platform='ios',
            version='1.4.0',
            build_number=60,
            minimum_version='1.2.0',
            force_update=True,
            update_message='중요한 보안 업데이트입니다. 즉시 업데이트해주세요.',
            store_url='https://apps.apple.com/app/id123456789',
            is_active=True
        )

    async def test_check_version_no_update_needed(self):
        """업데이트 불필요 (최신 버전 사용 중)"""
        response = await self.client.get('/version?platform=android&current_version=1.3.5')
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertFalse(data['needs_update'])
        self.assertFalse(data['force_update'])
        self.assertEqual(data['latest_version'], '1.3.5')

    async def test_check_version_update_available(self):
        """업데이트 가능 (구버전 사용 중)"""
        response = await self.client.get('/version?platform=android&current_version=1.2.0')
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertTrue(data['needs_update'])
        self.assertFalse(data['force_update'])
        self.assertEqual(data['latest_version'], '1.3.5')
        self.assertIn('새로운 기능', data['message'])
        self.assertIn('play.google.com', data['store_url'])

    async def test_check_version_force_update(self):
        """강제 업데이트 필요 (minimum_version 미만)"""
        response = await self.client.get('/version?platform=ios&current_version=1.1.0')
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertTrue(data['needs_update'])
        self.assertTrue(data['force_update'])
        self.assertEqual(data['latest_version'], '1.4.0')
        self.assertIn('보안 업데이트', data['message'])

    async def test_check_version_minimum_version_boundary(self):
        """minimum_version 경계값 테스트"""
        # minimum_version과 동일한 버전 사용 시 업데이트 권장 (강제X)
        response = await self.client.get('/version?platform=ios&current_version=1.2.0')
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertTrue(data['needs_update'])
        self.assertTrue(data['force_update'])  # iOS는 force_update=True로 설정됨

    async def test_check_version_without_platform(self):
        """platform 파라미터 없이 조회 시 에러"""
        response = await self.client.get('/version?current_version=1.0.0')
        self.assertEqual(response.status_code, 422)

    async def test_check_version_without_current_version(self):
        """current_version 파라미터 없이 조회 시 에러"""
        response = await self.client.get('/version?platform=android')
        self.assertEqual(response.status_code, 422)

    async def test_check_version_no_active_version(self):
        """활성 버전이 없을 때 404 에러"""
        # 모든 버전 비활성화
        await sync_to_async(AppVersion.objects.all().update)(is_active=False)

        response = await self.client.get('/version?platform=android&current_version=1.0.0')
        self.assertEqual(response.status_code, 404)


class AppSettingAPITest(TestCase):
    """일반 설정 API 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        self.client = TestAsyncClient(router)

        # 활성 설정
        AppSetting.objects.create(
            key='maintenance_mode',
            value={'enabled': False, 'message': ''},
            description='점검 모드 설정',
            is_active=True
        )
        AppSetting.objects.create(
            key='feature_flags',
            value={'new_ui': True, 'beta_feature': False},
            description='기능 플래그',
            is_active=True
        )

        # 비활성 설정
        AppSetting.objects.create(
            key='deprecated_setting',
            value={'old': 'value'},
            description='사용 중단된 설정',
            is_active=False
        )

    async def test_get_all_settings(self):
        """모든 활성 설정 조회 테스트"""
        response = await self.client.get('/settings')
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertIsInstance(data, list)
        # is_active=True인 설정만 반환
        self.assertEqual(len(data), 2)

        keys = [setting['key'] for setting in data]
        self.assertIn('maintenance_mode', keys)
        self.assertIn('feature_flags', keys)
        self.assertNotIn('deprecated_setting', keys)

    async def test_get_setting_by_key(self):
        """특정 키로 설정 조회 테스트"""
        response = await self.client.get('/settings/maintenance_mode')
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(data['key'], 'maintenance_mode')
        self.assertFalse(data['value']['enabled'])
        self.assertEqual(data['description'], '점검 모드 설정')

    async def test_get_setting_by_key_not_found(self):
        """존재하지 않는 키 조회 시 404 에러"""
        response = await self.client.get('/settings/nonexistent_key')
        self.assertEqual(response.status_code, 404)

    async def test_get_setting_inactive_key(self):
        """비활성 설정 조회 시 404 에러"""
        response = await self.client.get('/settings/deprecated_setting')
        self.assertEqual(response.status_code, 404)

    async def test_settings_json_structure(self):
        """설정 JSON 구조 검증"""
        response = await self.client.get('/settings/feature_flags')
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertTrue(data['value']['new_ui'])
        self.assertFalse(data['value']['beta_feature'])

    async def test_settings_ordering(self):
        """설정 정렬 테스트 (key ASC)"""
        response = await self.client.get('/settings')
        data = response.json()

        # key 알파벳 순서로 정렬
        self.assertEqual(data[0]['key'], 'feature_flags')
        self.assertEqual(data[1]['key'], 'maintenance_mode')


class APIErrorHandlingTest(TestCase):
    """API 에러 처리 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        self.client = TestAsyncClient(router)

    async def test_ads_empty_result(self):
        """광고 설정이 없을 때 빈 배열 반환"""
        response = await self.client.get('/ads?platform=android')
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(len(data), 0)

    async def test_settings_empty_result(self):
        """설정이 없을 때 빈 배열 반환"""
        response = await self.client.get('/settings')
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(len(data), 0)

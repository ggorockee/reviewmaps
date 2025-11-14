"""
app_config 모델 테스트
TDD 방식으로 작성된 테스트 코드
"""
from django.test import TestCase
from django.utils import timezone
from django.db import IntegrityError
from app_config.models import AdConfig, AppVersion, AppSetting
import json


class AdConfigModelTest(TestCase):
    """AdConfig 모델 테스트"""

    def test_create_ad_config_android(self):
        """Android 광고 설정 생성 테스트"""
        ad_config = AdConfig.objects.create(
            platform='android',
            ad_network='admob',
            is_enabled=True,
            ad_unit_ids={
                'banner_id': 'ca-app-pub-xxx/banner',
                'interstitial_id': 'ca-app-pub-xxx/interstitial',
                'native_id': 'ca-app-pub-xxx/native',
                'rewarded_id': 'ca-app-pub-xxx/rewarded'
            },
            priority=1
        )
        self.assertEqual(ad_config.platform, 'android')
        self.assertEqual(ad_config.ad_network, 'admob')
        self.assertTrue(ad_config.is_enabled)
        self.assertEqual(ad_config.priority, 1)
        self.assertIsNotNone(ad_config.created_at)

    def test_create_ad_config_ios(self):
        """iOS 광고 설정 생성 테스트"""
        ad_config = AdConfig.objects.create(
            platform='ios',
            ad_network='applovin',
            is_enabled=True,
            ad_unit_ids={
                'banner_id': 'xxx-banner',
                'interstitial_id': 'xxx-interstitial'
            },
            priority=2
        )
        self.assertEqual(ad_config.platform, 'ios')
        self.assertEqual(ad_config.ad_network, 'applovin')

    def test_ad_config_json_field(self):
        """JSON 필드 테스트"""
        ad_unit_ids = {
            'banner_id': 'test-banner',
            'interstitial_id': 'test-interstitial',
            'native_id': 'test-native'
        }
        ad_config = AdConfig.objects.create(
            platform='android',
            ad_network='admob',
            is_enabled=True,
            ad_unit_ids=ad_unit_ids,
            priority=1
        )
        # 데이터베이스에서 다시 조회
        saved_config = AdConfig.objects.get(id=ad_config.id)
        self.assertEqual(saved_config.ad_unit_ids, ad_unit_ids)
        self.assertEqual(saved_config.ad_unit_ids['banner_id'], 'test-banner')

    def test_ad_config_default_enabled(self):
        """기본값 is_enabled=True 테스트"""
        ad_config = AdConfig.objects.create(
            platform='android',
            ad_network='admob',
            ad_unit_ids={},
            priority=1
        )
        self.assertTrue(ad_config.is_enabled)

    def test_ad_config_default_priority(self):
        """기본값 priority=0 테스트"""
        ad_config = AdConfig.objects.create(
            platform='android',
            ad_network='admob',
            ad_unit_ids={}
        )
        self.assertEqual(ad_config.priority, 0)

    def test_ad_config_ordering(self):
        """우선순위 정렬 테스트 (priority DESC)"""
        AdConfig.objects.create(
            platform='android',
            ad_network='admob',
            ad_unit_ids={},
            priority=1
        )
        AdConfig.objects.create(
            platform='android',
            ad_network='applovin',
            ad_unit_ids={},
            priority=3
        )
        AdConfig.objects.create(
            platform='android',
            ad_network='unity',
            ad_unit_ids={},
            priority=2
        )

        configs = list(AdConfig.objects.all())
        self.assertEqual(configs[0].ad_network, 'applovin')  # priority 3
        self.assertEqual(configs[1].ad_network, 'unity')      # priority 2
        self.assertEqual(configs[2].ad_network, 'admob')      # priority 1

    def test_ad_config_str_representation(self):
        """문자열 표현 테스트"""
        ad_config = AdConfig.objects.create(
            platform='android',
            ad_network='admob',
            ad_unit_ids={},
            priority=1
        )
        self.assertIn('android', str(ad_config))
        self.assertIn('admob', str(ad_config))

    def test_ad_config_updated_at(self):
        """updated_at 자동 갱신 테스트"""
        ad_config = AdConfig.objects.create(
            platform='android',
            ad_network='admob',
            ad_unit_ids={},
            priority=1
        )
        old_updated_at = ad_config.updated_at

        # 약간의 시간 대기
        import time
        time.sleep(0.1)

        ad_config.is_enabled = False
        ad_config.save()

        self.assertGreater(ad_config.updated_at, old_updated_at)


class AppVersionModelTest(TestCase):
    """AppVersion 모델 테스트"""

    def test_create_app_version_android(self):
        """Android 앱 버전 생성 테스트"""
        version = AppVersion.objects.create(
            platform='android',
            version='1.3.5',
            build_number=50,
            minimum_version='1.0.0',
            force_update=False,
            update_message='새로운 기능이 추가되었습니다.',
            store_url='https://play.google.com/store/apps/details?id=com.example',
            is_active=True
        )
        self.assertEqual(version.platform, 'android')
        self.assertEqual(version.version, '1.3.5')
        self.assertEqual(version.build_number, 50)
        self.assertFalse(version.force_update)

    def test_create_app_version_ios(self):
        """iOS 앱 버전 생성 테스트"""
        version = AppVersion.objects.create(
            platform='ios',
            version='1.3.5',
            build_number=50,
            minimum_version='1.0.0',
            force_update=True,
            update_message='중요한 보안 업데이트입니다.',
            store_url='https://apps.apple.com/app/id123456789',
            is_active=True
        )
        self.assertEqual(version.platform, 'ios')
        self.assertTrue(version.force_update)

    def test_app_version_default_force_update(self):
        """기본값 force_update=False 테스트"""
        version = AppVersion.objects.create(
            platform='android',
            version='1.0.0',
            build_number=1,
            minimum_version='1.0.0',
            store_url='https://play.google.com'
        )
        self.assertFalse(version.force_update)

    def test_app_version_default_is_active(self):
        """기본값 is_active=True 테스트"""
        version = AppVersion.objects.create(
            platform='android',
            version='1.0.0',
            build_number=1,
            minimum_version='1.0.0',
            store_url='https://play.google.com'
        )
        self.assertTrue(version.is_active)

    def test_app_version_nullable_fields(self):
        """nullable 필드 테스트"""
        version = AppVersion.objects.create(
            platform='android',
            version='1.0.0',
            build_number=1,
            minimum_version='1.0.0',
            store_url='https://play.google.com',
            update_message=None  # nullable
        )
        self.assertIsNone(version.update_message)

    def test_app_version_str_representation(self):
        """문자열 표현 테스트"""
        version = AppVersion.objects.create(
            platform='android',
            version='1.3.5',
            build_number=50,
            minimum_version='1.0.0',
            store_url='https://play.google.com'
        )
        self.assertIn('android', str(version))
        self.assertIn('1.3.5', str(version))
        self.assertIn('50', str(version))

    def test_app_version_ordering(self):
        """정렬 테스트 (is_active DESC, created_at DESC)"""
        # 비활성 버전
        AppVersion.objects.create(
            platform='android',
            version='1.0.0',
            build_number=1,
            minimum_version='1.0.0',
            store_url='https://play.google.com',
            is_active=False
        )
        # 활성 버전 (나중에 생성)
        import time
        time.sleep(0.1)
        AppVersion.objects.create(
            platform='android',
            version='1.1.0',
            build_number=2,
            minimum_version='1.0.0',
            store_url='https://play.google.com',
            is_active=True
        )

        versions = list(AppVersion.objects.all())
        # 첫 번째는 활성 버전이어야 함
        self.assertTrue(versions[0].is_active)
        self.assertEqual(versions[0].version, '1.1.0')


class AppSettingModelTest(TestCase):
    """AppSetting 모델 테스트"""

    def test_create_app_setting(self):
        """앱 설정 생성 테스트"""
        setting = AppSetting.objects.create(
            key='maintenance_mode',
            value={'enabled': False, 'message': ''},
            description='점검 모드 설정'
        )
        self.assertEqual(setting.key, 'maintenance_mode')
        self.assertEqual(setting.value['enabled'], False)
        self.assertEqual(setting.description, '점검 모드 설정')

    def test_app_setting_unique_key(self):
        """key 유니크 제약 테스트"""
        AppSetting.objects.create(
            key='test_key',
            value={'test': 'value'}
        )
        with self.assertRaises(IntegrityError):
            AppSetting.objects.create(
                key='test_key',
                value={'another': 'value'}
            )

    def test_app_setting_json_value(self):
        """JSON value 필드 테스트"""
        value_data = {
            'string': '문자열',
            'number': 123,
            'boolean': True,
            'array': [1, 2, 3],
            'nested': {'key': 'value'}
        }
        setting = AppSetting.objects.create(
            key='complex_setting',
            value=value_data
        )

        # 데이터베이스에서 다시 조회
        saved_setting = AppSetting.objects.get(key='complex_setting')
        self.assertEqual(saved_setting.value, value_data)
        self.assertEqual(saved_setting.value['string'], '문자열')
        self.assertEqual(saved_setting.value['nested']['key'], 'value')

    def test_app_setting_default_is_active(self):
        """기본값 is_active=True 테스트"""
        setting = AppSetting.objects.create(
            key='test_setting',
            value={'test': True}
        )
        self.assertTrue(setting.is_active)

    def test_app_setting_nullable_description(self):
        """description nullable 테스트"""
        setting = AppSetting.objects.create(
            key='test_setting',
            value={'test': True},
            description=None
        )
        self.assertIsNone(setting.description)

    def test_app_setting_str_representation(self):
        """문자열 표현 테스트"""
        setting = AppSetting.objects.create(
            key='test_setting',
            value={'test': True}
        )
        self.assertEqual(str(setting), 'test_setting')

    def test_app_setting_ordering(self):
        """정렬 테스트 (key ASC)"""
        AppSetting.objects.create(key='zebra', value={})
        AppSetting.objects.create(key='alpha', value={})
        AppSetting.objects.create(key='beta', value={})

        settings = list(AppSetting.objects.all())
        self.assertEqual(settings[0].key, 'alpha')
        self.assertEqual(settings[1].key, 'beta')
        self.assertEqual(settings[2].key, 'zebra')

    def test_app_setting_filter_by_is_active(self):
        """is_active 필터링 테스트"""
        AppSetting.objects.create(
            key='active_setting',
            value={'test': True},
            is_active=True
        )
        AppSetting.objects.create(
            key='inactive_setting',
            value={'test': False},
            is_active=False
        )

        active_settings = AppSetting.objects.filter(is_active=True)
        self.assertEqual(active_settings.count(), 1)
        self.assertEqual(active_settings.first().key, 'active_setting')

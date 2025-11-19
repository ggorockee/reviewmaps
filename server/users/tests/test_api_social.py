"""
SNS 로그인 API 통합 테스트
email + login_method 조합으로 별도 계정이 생성되는지 검증
"""
from django.test import TestCase
from django.contrib.auth import get_user_model
from users.models import SocialAccount

User = get_user_model()


class SNSLoginIntegrationTest(TestCase):
    """SNS 로그인 통합 테스트 - email 중복 허용, email+login_method unique"""

    def setUp(self):
        """테스트용 데이터 초기화"""
        self.email = "test@example.com"
        self.kakao_user_id = "kakao_123"
        self.google_user_id = "google_456"
        self.apple_user_id = "apple_789"

    def test_same_email_creates_separate_accounts_for_different_providers(self):
        """
        같은 이메일로 여러 SNS 제공자를 통해 가입하면 별도 계정이 생성되는지 테스트
        핵심: email은 중복 가능, email+login_method가 unique key
        """
        # 1. Kakao 로그인으로 첫 번째 계정 생성
        user_kakao, created_kakao = User.objects.get_or_create(
            email=self.email,
            login_method='kakao',
        )
        social_kakao = SocialAccount.objects.create(
            user=user_kakao,
            provider='kakao',
            provider_user_id=self.kakao_user_id,
            email=self.email,
            name='Test User Kakao',
        )

        # 2. Google 로그인으로 두 번째 계정 생성 (같은 이메일)
        user_google, created_google = User.objects.get_or_create(
            email=self.email,
            login_method='google',
        )
        social_google = SocialAccount.objects.create(
            user=user_google,
            provider='google',
            provider_user_id=self.google_user_id,
            email=self.email,
            name='Test User Google',
        )

        # 3. Apple 로그인으로 세 번째 계정 생성 (같은 이메일)
        user_apple, created_apple = User.objects.get_or_create(
            email=self.email,
            login_method='apple',
        )
        social_apple = SocialAccount.objects.create(
            user=user_apple,
            provider='apple',
            provider_user_id=self.apple_user_id,
            email=self.email,
            name='Test User Apple',
        )

        # 검증 1: 모두 새로운 계정이 생성되었는지 확인
        self.assertTrue(created_kakao)
        self.assertTrue(created_google)
        self.assertTrue(created_apple)

        # 검증 2: 세 개의 User 레코드가 서로 다른 객체인지 확인
        self.assertNotEqual(user_kakao.id, user_google.id)
        self.assertNotEqual(user_kakao.id, user_apple.id)
        self.assertNotEqual(user_google.id, user_apple.id)

        # 검증 3: 같은 이메일을 가진 User가 3개 존재하는지 확인
        self.assertEqual(User.objects.filter(email=self.email).count(), 3)

        # 검증 4: 각 User의 username이 다른지 확인 (email_loginmethod 형식)
        self.assertEqual(user_kakao.username, f"{self.email}_kakao")
        self.assertEqual(user_google.username, f"{self.email}_google")
        self.assertEqual(user_apple.username, f"{self.email}_apple")

        # 검증 5: 각 User의 login_method가 올바른지 확인
        self.assertEqual(user_kakao.login_method, 'kakao')
        self.assertEqual(user_google.login_method, 'google')
        self.assertEqual(user_apple.login_method, 'apple')

        # 검증 6: SocialAccount가 올바른 User와 연결되었는지 확인
        self.assertEqual(social_kakao.user.id, user_kakao.id)
        self.assertEqual(social_google.user.id, user_google.id)
        self.assertEqual(social_apple.user.id, user_apple.id)

    def test_get_or_create_with_existing_account(self):
        """
        같은 email + login_method로 다시 가입 시도하면 기존 계정을 반환하는지 테스트
        """
        # 첫 번째 가입
        user1, created1 = User.objects.get_or_create(
            email=self.email,
            login_method='kakao',
        )
        self.assertTrue(created1)

        # 같은 email + login_method로 두 번째 시도
        user2, created2 = User.objects.get_or_create(
            email=self.email,
            login_method='kakao',
        )
        self.assertFalse(created2)  # 생성되지 않아야 함
        self.assertEqual(user1.id, user2.id)  # 같은 사용자여야 함

    def test_social_account_unique_constraint(self):
        """
        같은 provider + provider_user_id로 중복 SocialAccount 생성 시도 시 에러 발생 테스트
        """
        user = User.objects.create_user(
            email=self.email,
            password="test123",
            login_method='kakao',
        )

        # 첫 번째 SocialAccount 생성
        SocialAccount.objects.create(
            user=user,
            provider='kakao',
            provider_user_id=self.kakao_user_id,
            email=self.email,
        )

        # 같은 provider + provider_user_id로 두 번째 생성 시도 시 에러 발생
        from django.db import IntegrityError
        with self.assertRaises(IntegrityError):
            SocialAccount.objects.create(
                user=user,
                provider='kakao',
                provider_user_id=self.kakao_user_id,
                email=self.email,
            )

    def test_user_can_have_multiple_social_accounts(self):
        """
        한 User가 여러 개의 SocialAccount를 가질 수 있는지 테스트
        (email 로그인 후 SNS 연동 등의 시나리오)
        """
        # Email 로그인으로 가입한 사용자
        user_email = User.objects.create_user(
            email=self.email,
            password="test123",
            login_method='email',
        )

        # 이 사용자가 Kakao 계정도 연동
        social_kakao = SocialAccount.objects.create(
            user=user_email,
            provider='kakao',
            provider_user_id=self.kakao_user_id,
            email=self.email,
        )

        # 이 사용자가 Google 계정도 연동
        social_google = SocialAccount.objects.create(
            user=user_email,
            provider='google',
            provider_user_id=self.google_user_id,
            email=self.email,
        )

        # 검증: 한 User가 여러 SocialAccount를 가질 수 있음
        self.assertEqual(user_email.social_accounts.count(), 2)
        self.assertIn(social_kakao, user_email.social_accounts.all())
        self.assertIn(social_google, user_email.social_accounts.all())

    def test_email_domain_normalization(self):
        """
        이메일 도메인이 소문자로 정규화되는지 테스트
        API에서는 BaseUserManager.normalize_email()을 사용
        참고: RFC 5321에 따라 local part는 대소문자 구분 가능하므로 domain만 정규화됨
        """
        from django.contrib.auth.models import BaseUserManager

        email_mixed_case = "User@EXAMPLE.COM"
        expected_normalized = "User@example.com"  # domain만 소문자

        # API에서 하는 것처럼 정규화 후 get_or_create
        normalized_email = BaseUserManager.normalize_email(email_mixed_case)
        user1, _ = User.objects.get_or_create(
            email=normalized_email,
            login_method='kakao',
        )

        # 도메인이 소문자로 정규화되어 저장됨
        self.assertEqual(user1.email, expected_normalized)

    def test_realistic_woohaen88_scenario(self):
        """
        실제 사용자 시나리오 재현: woohaen88@gmail.com이 4개의 계정을 가져야 함
        """
        email = "woohaen88@gmail.com"

        # 1. Email 로그인으로 가입
        user_email = User.objects.create_user(
            email=email,
            password="test123",
            login_method='email',
        )

        # 2. Kakao 로그인으로 가입
        user_kakao, _ = User.objects.get_or_create(
            email=email,
            login_method='kakao',
        )
        SocialAccount.objects.create(
            user=user_kakao,
            provider='kakao',
            provider_user_id='kakao_woohaen88',
            email=email,
        )

        # 3. Google 로그인으로 가입
        user_google, _ = User.objects.get_or_create(
            email=email,
            login_method='google',
        )
        SocialAccount.objects.create(
            user=user_google,
            provider='google',
            provider_user_id='google_woohaen88',
            email=email,
        )

        # 4. Apple 로그인으로 가입
        user_apple, _ = User.objects.get_or_create(
            email=email,
            login_method='apple',
        )
        SocialAccount.objects.create(
            user=user_apple,
            provider='apple',
            provider_user_id='apple_woohaen88',
            email=email,
        )

        # 검증: 4개의 별도 계정이 존재
        users = User.objects.filter(email=email)
        self.assertEqual(users.count(), 4)

        # 각 계정의 login_method 확인
        login_methods = set(users.values_list('login_method', flat=True))
        self.assertEqual(login_methods, {'email', 'kakao', 'google', 'apple'})

        # 각 계정의 username 확인
        usernames = set(users.values_list('username', flat=True))
        expected_usernames = {
            f"{email}_email",
            f"{email}_kakao",
            f"{email}_google",
            f"{email}_apple",
        }
        self.assertEqual(usernames, expected_usernames)

        # SNS 계정은 3개 (email 로그인은 SocialAccount 없음)
        self.assertEqual(SocialAccount.objects.filter(email=email).count(), 3)

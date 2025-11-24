"""
Custom Authentication Backend 테스트
"""
from django.test import TestCase
from django.contrib.auth import authenticate, get_user_model

User = get_user_model()


class EmailAuthBackendTestCase(TestCase):
    """EmailAuthBackend 테스트"""

    def setUp(self):
        """테스트용 사용자 생성"""
        self.email = 'test@example.com'
        self.password = 'testpass123'

        # email 로그인 방식 사용자
        self.email_user = User.objects.create_user(
            email=self.email,
            password=self.password,
            login_method='email'
        )

        # kakao 로그인 방식 사용자 (같은 이메일)
        self.kakao_user = User.objects.create_user(
            email=self.email,
            password='kakaopass',  # SNS 사용자는 비밀번호 불필요하지만 테스트용
            login_method='kakao'
        )

    def test_authenticate_with_email_success(self):
        """email + password로 로그인 성공"""
        user = authenticate(username=self.email, password=self.password)
        self.assertIsNotNone(user)
        self.assertEqual(user.email, self.email)
        self.assertEqual(user.login_method, 'email')

    def test_authenticate_with_email_param_success(self):
        """email 파라미터로 로그인 성공"""
        user = authenticate(email=self.email, password=self.password)
        self.assertIsNotNone(user)
        self.assertEqual(user.email, self.email)

    def test_authenticate_wrong_password(self):
        """잘못된 비밀번호로 로그인 실패"""
        user = authenticate(username=self.email, password='wrongpass')
        self.assertIsNone(user)

    def test_authenticate_nonexistent_email(self):
        """존재하지 않는 이메일로 로그인 실패"""
        user = authenticate(username='nonexistent@example.com', password=self.password)
        self.assertIsNone(user)

    def test_authenticate_sns_user_fails(self):
        """SNS 사용자는 email/password 인증 실패"""
        # kakao 사용자의 비밀번호로 로그인 시도
        user = authenticate(username=self.email, password='kakaopass')
        self.assertIsNone(user)

    def test_authenticate_only_email_login_method(self):
        """login_method='email'인 사용자만 인증됨"""
        # email 사용자가 있어도, SNS 비밀번호로는 인증 안됨
        user = authenticate(username=self.email, password=self.password)
        self.assertEqual(user.login_method, 'email')
        self.assertNotEqual(user.id, self.kakao_user.id)

    def test_authenticate_inactive_user(self):
        """비활성 사용자 로그인 실패"""
        self.email_user.is_active = False
        self.email_user.save()

        user = authenticate(username=self.email, password=self.password)
        self.assertIsNone(user)

    def test_create_superuser_with_email_only(self):
        """email만으로 superuser 생성"""
        admin = User.objects.create_superuser(
            email='admin@example.com',
            password='adminpass123'
        )
        self.assertEqual(admin.email, 'admin@example.com')
        self.assertEqual(admin.login_method, 'email')
        self.assertEqual(admin.username, 'admin@example.com_email')
        self.assertTrue(admin.is_staff)
        self.assertTrue(admin.is_superuser)

    def test_superuser_can_authenticate(self):
        """superuser email로 로그인 가능"""
        User.objects.create_superuser(
            email='admin@example.com',
            password='adminpass123'
        )

        user = authenticate(username='admin@example.com', password='adminpass123')
        self.assertIsNotNone(user)
        self.assertTrue(user.is_superuser)


class UserCreationTestCase(TestCase):
    """사용자 생성 테스트"""

    def test_create_user_generates_username(self):
        """사용자 생성 시 username 자동 생성"""
        user = User.objects.create_user(
            email='user@example.com',
            password='pass123',
            login_method='email'
        )
        self.assertEqual(user.username, 'user@example.com_email')

    def test_create_kakao_user_generates_username(self):
        """Kakao 사용자 생성 시 username 자동 생성"""
        user = User.objects.create_user(
            email='user@example.com',
            password='pass123',
            login_method='kakao'
        )
        self.assertEqual(user.username, 'user@example.com_kakao')

    def test_same_email_different_login_method(self):
        """같은 이메일, 다른 login_method는 별도 계정"""
        email_user = User.objects.create_user(
            email='user@example.com',
            password='pass1',
            login_method='email'
        )
        google_user = User.objects.create_user(
            email='user@example.com',
            password='pass2',
            login_method='google'
        )

        self.assertNotEqual(email_user.id, google_user.id)
        self.assertEqual(email_user.email, google_user.email)
        self.assertNotEqual(email_user.username, google_user.username)

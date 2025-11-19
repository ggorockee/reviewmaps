from django.test import TestCase
from django.contrib.auth import get_user_model

User = get_user_model()


class CustomUserModelTest(TestCase):
    """Custom User 모델 테스트"""

    def test_create_user_with_email(self):
        """email로 사용자 생성 테스트"""
        email = "test@example.com"
        password = "testpass123"
        user = User.objects.create_user(email=email, password=password)

        self.assertEqual(user.email, email)
        self.assertTrue(user.check_password(password))
        self.assertTrue(user.is_active)
        self.assertFalse(user.is_staff)
        self.assertFalse(user.is_superuser)

    def test_create_user_without_email_raises_error(self):
        """email 없이 사용자 생성 시 에러 발생 테스트"""
        with self.assertRaises(ValueError):
            User.objects.create_user(email="", password="testpass123")

    def test_create_superuser(self):
        """슈퍼유저 생성 테스트"""
        email = "admin@example.com"
        password = "adminpass123"
        user = User.objects.create_superuser(email=email, password=password)

        self.assertEqual(user.email, email)
        self.assertTrue(user.check_password(password))
        self.assertTrue(user.is_active)
        self.assertTrue(user.is_staff)
        self.assertTrue(user.is_superuser)

    def test_user_str_representation(self):
        """User 모델의 문자열 표현 테스트"""
        email = "test@example.com"
        user = User.objects.create_user(email=email, password="testpass123")

        self.assertEqual(str(user), f"{email} (email)")

    def test_email_normalization(self):
        """이메일 정규화 테스트"""
        email = "test@EXAMPLE.COM"
        user = User.objects.create_user(email=email, password="testpass123")

        self.assertEqual(user.email, "test@example.com")

    def test_username_auto_generation(self):
        """username 자동 생성 테스트"""
        email = "test@example.com"
        user = User.objects.create_user(email=email, password="testpass123", login_method="kakao")

        self.assertEqual(user.username, f"{email}_kakao")

    def test_same_email_different_login_methods(self):
        """같은 이메일이지만 다른 로그인 방식으로 별도 계정 생성 테스트"""
        email = "woohaen88@gmail.com"
        password = "testpass123"

        # 1. 일반 이메일 로그인 계정
        user_email = User.objects.create_user(
            email=email,
            password=password,
            login_method='email'
        )

        # 2. Kakao 로그인 계정
        user_kakao = User.objects.create_user(
            email=email,
            password=password,
            login_method='kakao'
        )

        # 3. Google 로그인 계정
        user_google = User.objects.create_user(
            email=email,
            password=password,
            login_method='google'
        )

        # 4. Apple 로그인 계정
        user_apple = User.objects.create_user(
            email=email,
            password=password,
            login_method='apple'
        )

        # 모두 다른 계정인지 확인
        self.assertNotEqual(user_email.id, user_kakao.id)
        self.assertNotEqual(user_email.id, user_google.id)
        self.assertNotEqual(user_email.id, user_apple.id)
        self.assertNotEqual(user_kakao.id, user_google.id)

        # username이 모두 다른지 확인
        self.assertEqual(user_email.username, f"{email}_email")
        self.assertEqual(user_kakao.username, f"{email}_kakao")
        self.assertEqual(user_google.username, f"{email}_google")
        self.assertEqual(user_apple.username, f"{email}_apple")

        # 총 4개의 계정이 생성되었는지 확인
        self.assertEqual(User.objects.filter(email=email).count(), 4)

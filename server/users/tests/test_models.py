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

        self.assertEqual(str(user), email)

    def test_email_normalization(self):
        """이메일 정규화 테스트"""
        email = "test@EXAMPLE.COM"
        user = User.objects.create_user(email=email, password="testpass123")

        self.assertEqual(user.email, "test@example.com")

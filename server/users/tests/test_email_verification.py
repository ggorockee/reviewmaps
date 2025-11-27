"""
이메일 인증 기반 회원가입 API 테스트
- send-code: 인증코드 발송
- verify-code: 인증코드 확인
- signup: 회원가입 (verification_token 필수, 비밀번호 8자 이상)
"""
from django.test import TestCase, override_settings
from django.contrib.auth import get_user_model
from django.utils import timezone
from datetime import timedelta
from users.models import EmailVerification
from unittest.mock import patch
import json

User = get_user_model()


@override_settings(
    EMAIL_VERIFICATION_EXPIRE_MINUTES=60,
    EMAIL_VERIFICATION_RESEND_COOLDOWN_SECONDS=60,
    EMAIL_VERIFICATION_MAX_ATTEMPTS=5,
)
class EmailSendCodeAPITestCase(TestCase):
    """이메일 인증코드 발송 API 테스트"""

    def setUp(self):
        """테스트 데이터 준비"""
        self.email = 'newuser@example.com'
        self.existing_email = 'existing@example.com'

        # 이미 가입된 사용자 (email 로그인)
        User.objects.create_user(
            email=self.existing_email,
            password='testpass123',
            login_method='email',
        )

    @patch('users.api.send_mail')
    def test_send_code_success(self, mock_send_mail):
        """인증코드 발송 성공 테스트"""
        mock_send_mail.return_value = 1

        response = self.client.post(
            '/v1/auth/email/send-code',
            data=json.dumps({'email': self.email}),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn('message', data)
        self.assertIn('expires_in', data)
        self.assertEqual(data['expires_in'], 3600)  # 60분 = 3600초

        # DB 확인
        verification = EmailVerification.objects.get(email=self.email)
        self.assertEqual(len(verification.code), 6)
        self.assertFalse(verification.is_verified)
        self.assertEqual(verification.send_count, 1)

        # 이메일 발송 확인
        mock_send_mail.assert_called_once()

    def test_send_code_already_registered_email(self):
        """이미 가입된 이메일로 발송 시도 시 에러"""
        response = self.client.post(
            '/v1/auth/email/send-code',
            data=json.dumps({'email': self.existing_email}),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('이미 가입된', response.json()['detail'])

    def test_send_code_invalid_email_format(self):
        """잘못된 이메일 형식으로 발송 시도 시 에러"""
        response = self.client.post(
            '/v1/auth/email/send-code',
            data=json.dumps({'email': 'invalid-email'}),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('이메일 형식', response.json()['detail'])

    @patch('users.api.send_mail')
    def test_send_code_first_resend_no_cooldown(self, mock_send_mail):
        """첫 번째 재발송은 쿨다운 없이 바로 가능"""
        mock_send_mail.return_value = 1

        # 첫 번째 발송
        self.client.post(
            '/v1/auth/email/send-code',
            data=json.dumps({'email': self.email}),
            content_type='application/json',
        )

        # 두 번째 발송 (첫 번째 재발송) - 바로 가능
        response = self.client.post(
            '/v1/auth/email/send-code',
            data=json.dumps({'email': self.email}),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)

        # send_count가 2로 증가했는지 확인
        verification = EmailVerification.objects.get(email=self.email)
        self.assertEqual(verification.send_count, 2)

    @patch('users.api.send_mail')
    def test_send_code_second_resend_cooldown(self, mock_send_mail):
        """두 번째 이후 재발송은 60초 쿨다운 적용"""
        mock_send_mail.return_value = 1

        # 첫 번째 발송
        self.client.post(
            '/v1/auth/email/send-code',
            data=json.dumps({'email': self.email}),
            content_type='application/json',
        )

        # 두 번째 발송
        self.client.post(
            '/v1/auth/email/send-code',
            data=json.dumps({'email': self.email}),
            content_type='application/json',
        )

        # 세 번째 발송 시도 (쿨다운 적용됨)
        response = self.client.post(
            '/v1/auth/email/send-code',
            data=json.dumps({'email': self.email}),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 429)
        self.assertIn('초 후에 다시', response.json()['detail'])

    def test_send_code_different_login_method_allowed(self):
        """같은 이메일이지만 다른 login_method로 가입한 경우 발송 가능"""
        # Google로 가입한 사용자
        User.objects.create_user(
            email=self.email,
            password=None,
            login_method='google',
        )

        with patch('users.api.send_mail') as mock_send_mail:
            mock_send_mail.return_value = 1

            # email 로그인으로 가입 시도 - 가능해야 함
            response = self.client.post(
                '/v1/auth/email/send-code',
                data=json.dumps({'email': self.email}),
                content_type='application/json',
            )

            self.assertEqual(response.status_code, 200)


@override_settings(
    EMAIL_VERIFICATION_EXPIRE_MINUTES=60,
    EMAIL_VERIFICATION_MAX_ATTEMPTS=5,
)
class EmailVerifyCodeAPITestCase(TestCase):
    """이메일 인증코드 확인 API 테스트"""

    def setUp(self):
        """테스트 데이터 준비"""
        self.email = 'test@example.com'
        self.code = '123456'

        # 인증 레코드 생성
        self.verification = EmailVerification.objects.create(
            email=self.email,
            code=self.code,
            expires_at=timezone.now() + timedelta(minutes=60),
        )

    def test_verify_code_success(self):
        """인증코드 확인 성공 테스트"""
        response = self.client.post(
            '/v1/auth/email/verify-code',
            data=json.dumps({'email': self.email, 'code': self.code}),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data['verified'])
        self.assertIn('verification_token', data)
        self.assertTrue(len(data['verification_token']) > 0)

        # DB 확인
        self.verification.refresh_from_db()
        self.assertTrue(self.verification.is_verified)
        self.assertEqual(self.verification.verification_token, data['verification_token'])

    def test_verify_code_wrong_code(self):
        """잘못된 인증코드로 확인 시도"""
        response = self.client.post(
            '/v1/auth/email/verify-code',
            data=json.dumps({'email': self.email, 'code': '999999'}),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('일치하지 않습니다', response.json()['detail'])

        # 시도 횟수 증가 확인
        self.verification.refresh_from_db()
        self.assertEqual(self.verification.attempts, 1)

    def test_verify_code_expired(self):
        """만료된 인증코드로 확인 시도"""
        # 만료된 레코드로 업데이트
        self.verification.expires_at = timezone.now() - timedelta(minutes=1)
        self.verification.save()

        response = self.client.post(
            '/v1/auth/email/verify-code',
            data=json.dumps({'email': self.email, 'code': self.code}),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('만료', response.json()['detail'])

    def test_verify_code_max_attempts_exceeded(self):
        """5회 초과 시도 시 에러"""
        self.verification.attempts = 5
        self.verification.save()

        response = self.client.post(
            '/v1/auth/email/verify-code',
            data=json.dumps({'email': self.email, 'code': self.code}),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 429)
        self.assertIn('시도 횟수를 초과', response.json()['detail'])

    def test_verify_code_no_verification_record(self):
        """인증 요청 기록이 없는 경우"""
        response = self.client.post(
            '/v1/auth/email/verify-code',
            data=json.dumps({'email': 'unknown@example.com', 'code': '123456'}),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('인증 요청을 찾을 수 없습니다', response.json()['detail'])

    def test_verify_code_remaining_attempts_shown(self):
        """잘못된 코드 입력 시 남은 시도 횟수 표시"""
        response = self.client.post(
            '/v1/auth/email/verify-code',
            data=json.dumps({'email': self.email, 'code': '999999'}),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('4회 남음', response.json()['detail'])


@override_settings(
    EMAIL_VERIFICATION_EXPIRE_MINUTES=60,
)
class SignupWithVerificationAPITestCase(TestCase):
    """이메일 인증 기반 회원가입 API 테스트"""

    def setUp(self):
        """테스트 데이터 준비"""
        self.email = 'newuser@example.com'
        self.verification_token = 'valid_token_123'

        # 인증 완료된 레코드 생성
        EmailVerification.objects.create(
            email=self.email,
            code='123456',
            expires_at=timezone.now() + timedelta(minutes=60),
            is_verified=True,
            verification_token=self.verification_token,
        )

    def test_signup_success_with_verification(self):
        """인증 완료 후 회원가입 성공"""
        response = self.client.post(
            '/v1/auth/signup',
            data=json.dumps({
                'email': self.email,
                'password': 'password123',
                'verification_token': self.verification_token,
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn('access_token', data)
        self.assertIn('refresh_token', data)
        self.assertEqual(data['token_type'], 'bearer')

        # DB 확인
        user = User.objects.get(email=self.email)
        self.assertEqual(user.login_method, 'email')

        # 인증 레코드 삭제 확인
        self.assertFalse(
            EmailVerification.objects.filter(email=self.email).exists()
        )

    def test_signup_success_with_name(self):
        """이름 포함 회원가입 성공"""
        response = self.client.post(
            '/v1/auth/signup',
            data=json.dumps({
                'email': self.email,
                'password': 'password123',
                'name': '홍길동',
                'verification_token': self.verification_token,
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)

        # DB 확인
        user = User.objects.get(email=self.email)
        self.assertEqual(user.name, '홍길동')

    def test_signup_without_name(self):
        """이름 없이 회원가입 성공 (선택 필드)"""
        response = self.client.post(
            '/v1/auth/signup',
            data=json.dumps({
                'email': self.email,
                'password': 'password123',
                'verification_token': self.verification_token,
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)

        # DB 확인 - 이름이 빈 문자열
        user = User.objects.get(email=self.email)
        self.assertEqual(user.name, '')

    def test_signup_without_verification(self):
        """인증 없이 회원가입 시도 시 에러"""
        response = self.client.post(
            '/v1/auth/signup',
            data=json.dumps({
                'email': 'unverified@example.com',
                'password': 'password123',
                'verification_token': 'invalid_token',
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('이메일 인증이 필요', response.json()['detail'])

    def test_signup_password_too_short(self):
        """8자 미만 비밀번호로 가입 시도 시 에러"""
        response = self.client.post(
            '/v1/auth/signup',
            data=json.dumps({
                'email': self.email,
                'password': '1234567',  # 7자
                'verification_token': self.verification_token,
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('8자 이상', response.json()['detail'])

    def test_signup_password_exactly_8_chars(self):
        """8자 비밀번호로 가입 성공"""
        response = self.client.post(
            '/v1/auth/signup',
            data=json.dumps({
                'email': self.email,
                'password': '12345678',  # 정확히 8자
                'verification_token': self.verification_token,
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)

    def test_signup_already_registered_email(self):
        """이미 가입된 이메일로 가입 시도 시 에러"""
        # 먼저 가입
        User.objects.create_user(
            email=self.email,
            password='password123',
            login_method='email',
        )

        response = self.client.post(
            '/v1/auth/signup',
            data=json.dumps({
                'email': self.email,
                'password': 'password123',
                'verification_token': self.verification_token,
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('이미 가입된', response.json()['detail'])

    def test_signup_different_login_method_allowed(self):
        """같은 이메일이지만 다른 login_method로 가입된 경우 가입 가능"""
        # Google로 가입한 사용자
        User.objects.create_user(
            email=self.email,
            password=None,
            login_method='google',
        )

        response = self.client.post(
            '/v1/auth/signup',
            data=json.dumps({
                'email': self.email,
                'password': 'password123',
                'verification_token': self.verification_token,
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)

        # 같은 이메일로 2개의 계정 존재
        self.assertEqual(User.objects.filter(email=self.email).count(), 2)


class EmailVerificationModelTestCase(TestCase):
    """EmailVerification 모델 테스트"""

    def test_model_creation(self):
        """모델 생성 테스트"""
        verification = EmailVerification.objects.create(
            email='test@example.com',
            code='123456',
            expires_at=timezone.now() + timedelta(minutes=60),
        )

        self.assertEqual(verification.email, 'test@example.com')
        self.assertEqual(verification.code, '123456')
        self.assertEqual(verification.attempts, 0)
        self.assertFalse(verification.is_verified)
        self.assertEqual(verification.verification_token, '')
        self.assertEqual(verification.send_count, 1)

    def test_model_str(self):
        """모델 문자열 표현 테스트"""
        verification = EmailVerification.objects.create(
            email='test@example.com',
            code='123456',
            expires_at=timezone.now() + timedelta(minutes=60),
        )

        self.assertIn('test@example.com', str(verification))
        self.assertIn('미인증', str(verification))

        verification.is_verified = True
        verification.save()
        self.assertIn('인증완료', str(verification))


class IntegrationTestCase(TestCase):
    """이메일 인증 → 회원가입 통합 테스트"""

    @patch('users.api.send_mail')
    def test_full_signup_flow(self, mock_send_mail):
        """전체 회원가입 플로우 테스트"""
        mock_send_mail.return_value = 1
        email = 'integration@example.com'

        # 1. 인증코드 발송
        response = self.client.post(
            '/v1/auth/email/send-code',
            data=json.dumps({'email': email}),
            content_type='application/json',
        )
        self.assertEqual(response.status_code, 200)

        # 발송된 코드 확인
        verification = EmailVerification.objects.get(email=email)
        code = verification.code

        # 2. 인증코드 확인
        response = self.client.post(
            '/v1/auth/email/verify-code',
            data=json.dumps({'email': email, 'code': code}),
            content_type='application/json',
        )
        self.assertEqual(response.status_code, 200)
        verification_token = response.json()['verification_token']

        # 3. 회원가입
        response = self.client.post(
            '/v1/auth/signup',
            data=json.dumps({
                'email': email,
                'password': 'securepassword123',
                'name': '테스트유저',
                'verification_token': verification_token,
            }),
            content_type='application/json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn('access_token', response.json())

        # 4. 사용자 생성 확인
        user = User.objects.get(email=email, login_method='email')
        self.assertEqual(user.name, '테스트유저')

        # 5. 인증 레코드 삭제 확인
        self.assertFalse(
            EmailVerification.objects.filter(email=email).exists()
        )

    @patch('users.api.send_mail')
    def test_resend_flow(self, mock_send_mail):
        """재발송 플로우 테스트"""
        mock_send_mail.return_value = 1
        email = 'resend@example.com'

        # 1. 첫 번째 발송
        self.client.post(
            '/v1/auth/email/send-code',
            data=json.dumps({'email': email}),
            content_type='application/json',
        )
        first_code = EmailVerification.objects.get(email=email).code

        # 2. 첫 번째 재발송 (바로 가능)
        response = self.client.post(
            '/v1/auth/email/send-code',
            data=json.dumps({'email': email}),
            content_type='application/json',
        )
        self.assertEqual(response.status_code, 200)

        # 코드가 변경되었는지 확인
        verification = EmailVerification.objects.get(email=email)
        self.assertNotEqual(verification.code, first_code)
        self.assertEqual(verification.send_count, 2)
        self.assertEqual(verification.attempts, 0)  # 재발송 시 시도 횟수 리셋

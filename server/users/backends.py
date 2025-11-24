from django.contrib.auth.backends import ModelBackend
from django.contrib.auth import get_user_model

User = get_user_model()


class EmailAuthBackend(ModelBackend):
    """
    Email 기반 인증 백엔드

    로그인 시 email + password로 인증하되,
    login_method='email'인 사용자만 대상으로 함.

    SNS 로그인(kakao, google, apple)은 별도의 OAuth flow를 통해 처리되므로
    이 백엔드는 email 직접 가입 사용자만 인증함.
    """

    def authenticate(self, request, username=None, password=None, **kwargs):
        """
        email과 password로 사용자 인증

        Django Admin과 호환성을 위해 username 파라미터도 받지만,
        실제로는 email로 처리함.
        """
        # username 또는 email 파라미터 사용
        email = kwargs.get('email') or username

        if email is None or password is None:
            return None

        try:
            # email + login_method='email'인 사용자만 찾음
            user = User.objects.get(email=email, login_method='email')
        except User.DoesNotExist:
            # 타이밍 공격 방지를 위해 password hasher 실행
            User().set_password(password)
            return None

        if user.check_password(password) and self.user_can_authenticate(user):
            return user

        return None

    def get_user(self, user_id):
        """user_id로 사용자 조회"""
        try:
            return User.objects.get(pk=user_id)
        except User.DoesNotExist:
            return None

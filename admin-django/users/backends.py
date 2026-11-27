"""Custom authentication backend for email-based login."""

from django.contrib.auth.backends import ModelBackend

from .models import User


class EmailBackend(ModelBackend):
    """
    Authenticate using email instead of username.

    For admin users, login_method is always 'email'.
    """

    def authenticate(self, request, username=None, password=None, **kwargs):
        # username field in login form contains email
        email = username
        if email is None:
            return None

        try:
            # Admin users always use 'email' login method
            user = User.objects.get(email=email, login_method="email")
        except User.DoesNotExist:
            # Run the default password hasher to reduce timing attacks
            User().set_password(password)
            return None

        if user.check_password(password) and self.user_can_authenticate(user):
            return user
        return None

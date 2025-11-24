"""
Custom createsuperuser 명령어

email만 입력받아 superuser를 생성합니다.
username은 email + login_method 조합으로 자동 생성됩니다.
"""

from django.contrib.auth.management.commands.createsuperuser import Command as BaseCommand
from django.core.management import CommandError


class Command(BaseCommand):
    help = 'Create a superuser with email and password'

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # USERNAME_FIELD를 email로 오버라이드
        self.UserModel._meta.get_field('email')
        self.username_field = self.UserModel._meta.get_field('email')

    def add_arguments(self, parser):
        parser.add_argument(
            '--email',
            dest='email',
            default=None,
            help='Email address for the superuser.',
        )
        parser.add_argument(
            '--noinput', '--no-input',
            action='store_false',
            dest='interactive',
            help=(
                'Tells Django to NOT prompt the user for input of any kind. '
                'You must use --email with --noinput.'
            ),
        )
        parser.add_argument(
            '--database',
            default='default',
            help='Specifies the database to use. Default is "default".',
        )

    def handle(self, *args, **options):
        email = options.get('email')
        database = options.get('database')
        interactive = options.get('interactive')

        # Non-interactive mode
        if not interactive:
            if not email:
                raise CommandError('--email is required when using --noinput')

            # Check if user exists
            if self.UserModel._default_manager.db_manager(database).filter(
                email=email, login_method='email'
            ).exists():
                raise CommandError(f'User with email {email} and login_method=email already exists.')

            password = options.get('password')
            if not password:
                raise CommandError('Password is required when using --noinput')

            user = self.UserModel._default_manager.db_manager(database).create_superuser(
                email=email,
                password=password,
            )
            if options.get('verbosity', 1) >= 1:
                self.stdout.write(f'Superuser created successfully: {user.email}')
            return

        # Interactive mode
        if not email:
            email = input('Email: ')

        if not email:
            raise CommandError('Email is required.')

        # Validate email
        try:
            email = self.UserModel.objects.normalize_email(email)
        except Exception as e:
            raise CommandError(str(e))

        # Check if user exists
        if self.UserModel._default_manager.db_manager(database).filter(
            email=email, login_method='email'
        ).exists():
            raise CommandError(f'User with email {email} and login_method=email already exists.')

        # Get password
        password = None
        while password is None:
            password = self.get_input_password()

        # Create user
        user = self.UserModel._default_manager.db_manager(database).create_superuser(
            email=email,
            password=password,
        )

        if options.get('verbosity', 1) >= 1:
            self.stdout.write(self.style.SUCCESS(f'Superuser created successfully: {user.email}'))

    def get_input_password(self):
        """Get password from user input with confirmation."""
        import getpass

        password = getpass.getpass('Password: ')
        password2 = getpass.getpass('Password (again): ')

        if password != password2:
            self.stderr.write('Error: Your passwords didn\'t match.')
            return None

        if password.strip() == '':
            self.stderr.write('Error: Blank passwords aren\'t allowed.')
            return None

        return password

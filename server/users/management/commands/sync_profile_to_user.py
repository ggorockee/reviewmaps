"""
기존 사용자의 프로필 정보를 SocialAccount에서 User 모델로 동기화하는 명령어

Usage:
    python manage.py sync_profile_to_user
    python manage.py sync_profile_to_user --dry-run  # 실제 저장 없이 확인만
"""
from django.core.management.base import BaseCommand
from django.db import transaction
from users.models import User, SocialAccount


class Command(BaseCommand):
    help = 'SocialAccount의 name, profile_image를 User 모델로 동기화'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='실제 저장 없이 변경될 내용만 출력',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']

        if dry_run:
            self.stdout.write(self.style.WARNING('=== DRY RUN MODE ==='))

        updated_count = 0
        skipped_count = 0

        # User 모델에서 name이나 profile_image가 비어있는 사용자 조회
        users_to_update = User.objects.filter(
            login_method__in=['kakao', 'google']  # Apple은 프로필 이미지 없음
        ).exclude(
            name__isnull=False,
            profile_image__isnull=False
        ).exclude(
            name__gt='',
            profile_image__gt=''
        )

        # 모든 SNS 로그인 사용자 대상으로 확인
        all_social_users = User.objects.filter(login_method__in=['kakao', 'google'])

        self.stdout.write(f'총 SNS 로그인 사용자 수: {all_social_users.count()}')

        with transaction.atomic():
            for user in all_social_users:
                # 해당 사용자의 SocialAccount 조회
                social_account = SocialAccount.objects.filter(
                    user=user,
                    provider=user.login_method
                ).first()

                if not social_account:
                    self.stdout.write(
                        f'  SKIP: {user.email} - SocialAccount 없음'
                    )
                    skipped_count += 1
                    continue

                # 업데이트 필요 여부 확인
                need_update = False
                updates = []

                if (not user.name or user.name == '') and social_account.name:
                    updates.append(f'name: "" -> "{social_account.name}"')
                    if not dry_run:
                        user.name = social_account.name
                    need_update = True

                if (not user.profile_image or user.profile_image == '') and social_account.profile_image:
                    updates.append(f'profile_image: "" -> "{social_account.profile_image[:50]}..."')
                    if not dry_run:
                        user.profile_image = social_account.profile_image
                    need_update = True

                if need_update:
                    if not dry_run:
                        user.save(update_fields=['name', 'profile_image'])
                    self.stdout.write(
                        self.style.SUCCESS(f'  UPDATE: {user.email} ({user.login_method})')
                    )
                    for update in updates:
                        self.stdout.write(f'    - {update}')
                    updated_count += 1
                else:
                    self.stdout.write(
                        f'  OK: {user.email} - 이미 동기화됨 (name={user.name}, profile_image={bool(user.profile_image)})'
                    )
                    skipped_count += 1

        self.stdout.write('')
        self.stdout.write(self.style.SUCCESS(f'업데이트된 사용자: {updated_count}'))
        self.stdout.write(f'스킵된 사용자: {skipped_count}')

        if dry_run:
            self.stdout.write(self.style.WARNING('=== DRY RUN 완료 (실제 변경 없음) ==='))

# Generated manually to sync Django migration state with actual DB state

from django.db import migrations


class Migration(migrations.Migration):
    """
    Django 마이그레이션 상태 동기화

    0005에서 RunPython으로 인덱스 이름을 변경했으나,
    Django 내부 상태가 업데이트되지 않아 계속 마이그레이션이 필요하다고 표시됨.

    이 마이그레이션은 실제 DB 변경 없이 Django 상태만 동기화함.

    상황:
    - 로컬 DB: 0005 실행으로 인덱스 이름 변경 완료
    - 운영 DB: 0005 실행으로 인덱스 이름 변경 완료 (또는 예정)
    - Django state: 여전히 old_name으로 추적 중

    해결:
    - state_operations로 Django 내부 상태만 업데이트
    - 실제 DB 변경은 수행하지 않음 (이미 0005에서 처리됨)
    """

    dependencies = [
        ('keyword_alerts', '0005_rename_keyword_ale_user_id_fcm_idx_fcm_user_active_idx_and_more'),
    ]

    operations = [
        # state_operations: Django 내부 상태만 변경, 실제 DB 변경 없음
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.RenameIndex(
                    model_name='fcmdevice',
                    new_name='fcm_user_active_idx',
                    old_name='keyword_ale_user_id_fcm_idx',
                ),
                migrations.RenameIndex(
                    model_name='fcmdevice',
                    new_name='fcm_anon_active_idx',
                    old_name='keyword_ale_anon_fcm_idx',
                ),
                migrations.RenameIndex(
                    model_name='fcmdevice',
                    new_name='fcm_token_idx',
                    old_name='keyword_ale_token_idx',
                ),
            ],
            database_operations=[
                # 실제 DB 변경 없음 - 0005에서 이미 처리됨
            ],
        ),
    ]

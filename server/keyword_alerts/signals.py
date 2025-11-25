"""
캠페인 생성 시 키워드 알림 생성 시그널
- 새로운 캠페인이 생성되면 활성화된 키워드와 매칭하여 알림 생성
- 매칭된 키워드 소유자에게 FCM 푸시 알림 전송
"""
from django.db.models.signals import post_save
from django.dispatch import receiver

from campaigns.models import Campaign
from .models import Keyword, KeywordAlert, FCMDevice


def send_push_notifications_for_alerts(alerts: list[KeywordAlert], campaign):
    """
    알림이 생성된 키워드 소유자들에게 FCM 푸시 전송

    Args:
        alerts: 생성된 KeywordAlert 리스트
        campaign: 매칭된 캠페인
    """
    try:
        from .firebase_service import firebase_push_service
    except ImportError as e:
        print(f"[Signal] Firebase service import error: {e}", flush=True)
        return

    # 키워드별로 그룹화 (같은 사용자에게 중복 푸시 방지)
    user_ids = set()
    session_ids = set()

    for alert in alerts:
        keyword = alert.keyword
        if keyword.user_id:
            user_ids.add(keyword.user_id)
        elif keyword.anonymous_session_id:
            session_ids.add(keyword.anonymous_session_id)

    # 활성 FCM 토큰 조회
    tokens = []

    if user_ids:
        user_devices = FCMDevice.objects.filter(
            user_id__in=user_ids,
            is_active=True
        ).values_list('fcm_token', flat=True)
        tokens.extend(list(user_devices))

    if session_ids:
        session_devices = FCMDevice.objects.filter(
            anonymous_session_id__in=session_ids,
            is_active=True
        ).values_list('fcm_token', flat=True)
        tokens.extend(list(session_devices))

    if not tokens:
        print(f"[Signal] 전송할 FCM 토큰 없음", flush=True)
        return

    # 중복 제거
    tokens = list(set(tokens))
    print(f"[Signal] FCM 푸시 전송 대상: {len(tokens)}개 디바이스", flush=True)

    # 푸시 알림 전송
    title = "새로운 캠페인 알림"
    body = f"관심 키워드와 매칭되는 캠페인: {campaign.title[:50]}"
    data = {
        "type": "keyword_alert",
        "campaign_id": str(campaign.id),
    }

    result = firebase_push_service.send_push_to_multiple(
        tokens=tokens,
        title=title,
        body=body,
        data=data
    )

    print(f"[Signal] FCM 푸시 결과 - 성공: {result['success_count']}, 실패: {result['failure_count']}", flush=True)

    # 실패한 토큰 비활성화
    if result['failed_tokens']:
        FCMDevice.objects.filter(fcm_token__in=result['failed_tokens']).update(is_active=False)
        print(f"[Signal] {len(result['failed_tokens'])}개의 비활성 토큰 처리됨", flush=True)


@receiver(post_save, sender=Campaign)
def create_keyword_alerts_on_campaign_save(sender, instance, created, **kwargs):
    """
    캠페인 저장 시 키워드 매칭 알림 생성
    - 새로 생성된 캠페인만 처리 (created=True)
    - 활성화된 키워드(is_active=True)만 매칭
    - 캠페인 제목(title) 또는 제안 내용(offer)에서 키워드 검색
    """
    print(f"[Signal] Campaign post_save 호출됨 - ID: {instance.id}, created: {created}", flush=True)

    if not created:
        print(f"[Signal] 업데이트된 캠페인이므로 스킵 - ID: {instance.id}", flush=True)
        return

    # 활성화된 모든 키워드 조회
    active_keywords = Keyword.objects.filter(is_active=True)
    print(f"[Signal] 활성 키워드 수: {active_keywords.count()}", flush=True)

    # 캠페인 제목과 제안 내용
    campaign_title = instance.title or ""
    campaign_offer = instance.offer or ""

    alerts_to_create = []

    for keyword in active_keywords:
        keyword_text = keyword.keyword.lower()
        matched_field = None

        # 제목에서 키워드 매칭
        if keyword_text in campaign_title.lower():
            matched_field = "title"
        # 제안 내용에서 키워드 매칭
        elif keyword_text in campaign_offer.lower():
            matched_field = "offer"

        if matched_field:
            # 중복 알림 방지 (같은 키워드 + 같은 캠페인)
            existing_alert = KeywordAlert.objects.filter(
                keyword=keyword,
                campaign=instance
            ).exists()

            if not existing_alert:
                alerts_to_create.append(
                    KeywordAlert(
                        keyword=keyword,
                        campaign=instance,
                        matched_field=matched_field,
                        is_read=False
                    )
                )

    # 벌크 생성으로 성능 최적화
    if alerts_to_create:
        created_alerts = KeywordAlert.objects.bulk_create(alerts_to_create)
        print(f"[Signal] {len(created_alerts)}개의 알림 생성 완료 - 캠페인 ID: {instance.id}", flush=True)

        # FCM 푸시 알림 전송
        send_push_notifications_for_alerts(created_alerts, instance)
    else:
        print(f"[Signal] 매칭된 키워드 없음 - 캠페인 ID: {instance.id}, 제목: {campaign_title[:50]}", flush=True)

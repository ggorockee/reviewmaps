"""
캠페인 생성 시 키워드 알림 생성 시그널
- 새로운 캠페인이 생성되면 활성화된 키워드와 매칭하여 알림 생성
"""
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.db.models import Q

from campaigns.models import Campaign
from .models import Keyword, KeywordAlert


@receiver(post_save, sender=Campaign)
def create_keyword_alerts_on_campaign_save(sender, instance, created, **kwargs):
    """
    캠페인 저장 시 키워드 매칭 알림 생성
    - 새로 생성된 캠페인만 처리 (created=True)
    - 활성화된 키워드(is_active=True)만 매칭
    - 캠페인 제목(title) 또는 제안 내용(offer)에서 키워드 검색
    """
    if not created:
        return

    # 활성화된 모든 키워드 조회
    active_keywords = Keyword.objects.filter(is_active=True)

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
        KeywordAlert.objects.bulk_create(alerts_to_create)

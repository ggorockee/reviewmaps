"""
캠페인 생성 시 키워드 알림 생성 시그널
- 새로운 캠페인이 생성되면 활성화된 키워드와 매칭하여 알림 생성
- 매칭된 키워드 소유자에게 FCM 푸시 알림 전송
- 공백/특수문자 제거 후 정규화된 매칭으로 검색 정확도 향상
- 검색 대상: 업체명(company), 제공내역(offer)
"""
import re
import logging
from django.db.models.signals import post_save
from django.dispatch import receiver

from campaigns.models import Campaign
from .models import Keyword, KeywordAlert, FCMDevice

logger = logging.getLogger(__name__)


def normalize_text(text: str) -> str:
    """
    텍스트 정규화: 공백, 특수문자 제거 및 소문자 변환
    - "스타 벅스" → "스타벅스"
    - "CU 편의점" → "cu편의점"
    - "BBQ치킨!" → "bbq치킨"
    """
    if not text:
        return ""
    # 공백, 특수문자 제거 (한글, 영문, 숫자만 유지)
    normalized = re.sub(r'[^\w가-힣]', '', text.lower())
    return normalized


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
        logger.info(f"[Signal] Firebase service import error: {e}")
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
        logger.info(f"[Signal] 전송할 FCM 토큰 없음")
        return

    # 중복 제거
    tokens = list(set(tokens))
    logger.info(f"[Signal] FCM 푸시 전송 대상: {len(tokens)}개 디바이스")

    # 푸시 알림 전송
    title = "새로운 체험단 알림"
    body = "관심 키워드와 매칭되는 캠페인이 등록되었습니다. 앱에서 확인해보세요."
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

    logger.info(f"[Signal] FCM 푸시 결과 - 성공: {result['success_count']}, 실패: {result['failure_count']}")

    # 실패한 토큰 비활성화
    if result['failed_tokens']:
        FCMDevice.objects.filter(fcm_token__in=result['failed_tokens']).update(is_active=False)
        logger.info(f"[Signal] {len(result['failed_tokens'])}개의 비활성 토큰 처리됨")


@receiver(post_save, sender=Campaign)
def create_keyword_alerts_on_campaign_save(sender, instance, created, **kwargs):
    """
    캠페인 저장 시 키워드 매칭 알림 생성
    - 새로 생성된 캠페인만 처리 (created=True)
    - 활성화된 키워드(is_active=True)만 매칭
    - 캠페인 업체명(company) 또는 제공내역(offer)에서 키워드 검색
    - 공백/특수문자 제거 후 정규화된 매칭
    """
    logger.info(f"[Signal] Campaign post_save 호출됨 - ID: {instance.id}, created: {created}")

    if not created:
        logger.info(f"[Signal] 업데이트된 캠페인이므로 스킵 - ID: {instance.id}")
        return

    # 활성화된 모든 키워드 조회 (필요한 필드만)
    active_keywords = list(Keyword.objects.filter(is_active=True).only('id', 'keyword', 'user_id', 'anonymous_session_id'))
    logger.info(f"[Signal] 활성 키워드 수: {len(active_keywords)}")

    if not active_keywords:
        logger.info(f"[Signal] 활성 키워드 없음 - 스킵")
        return

    # 캠페인 텍스트 정규화 (공백/특수문자 제거)
    # 업체명(company), 제목(title), 제공내역(offer)에서 검색
    campaign_company_normalized = normalize_text(instance.company)
    campaign_title_normalized = normalize_text(instance.title)  # title 필드 추가
    campaign_offer_normalized = normalize_text(instance.offer)

    # 원본 텍스트도 유지 (로깅용)
    campaign_company_original = instance.company or ""
    campaign_title_original = instance.title or ""

    logger.info(f"[Signal] 캠페인 업체명(정규화): '{campaign_company_normalized}'")
    logger.info(f"[Signal] 캠페인 제목(정규화): '{campaign_title_normalized[:100] if campaign_title_normalized else ''}'")
    logger.info(f"[Signal] 캠페인 제공내역(정규화): '{campaign_offer_normalized[:100]}...'")

    # 이미 존재하는 알림 조회 (한 번에 조회하여 N+1 방지)
    existing_alerts = set(
        KeywordAlert.objects.filter(
            keyword_id__in=[k.id for k in active_keywords],
            campaign=instance
        ).values_list('keyword_id', flat=True)
    )

    alerts_to_create = []

    for keyword in active_keywords:
        # 이미 알림이 존재하면 스킵
        if keyword.id in existing_alerts:
            continue

        # 키워드 정규화
        keyword_normalized = normalize_text(keyword.keyword)

        if not keyword_normalized:
            continue

        matched_field = None

        # 업체명에서 키워드 매칭 (정규화된 텍스트에서)
        if keyword_normalized in campaign_company_normalized:
            matched_field = "company"
        # 제목에서 키워드 매칭 (title 필드 - "[김포] 꾸미오가구" 같은 형식)
        elif campaign_title_normalized and keyword_normalized in campaign_title_normalized:
            matched_field = "title"
        # 제공내역에서 키워드 매칭
        elif keyword_normalized in campaign_offer_normalized:
            matched_field = "offer"

        if matched_field:
            alerts_to_create.append(
                KeywordAlert(
                    keyword=keyword,
                    campaign=instance,
                    matched_field=matched_field,
                    is_read=False
                )
            )
            logger.info(f"[Signal] 매칭됨 - 키워드: '{keyword.keyword}' → {matched_field}")

    # 벌크 생성으로 성능 최적화
    if alerts_to_create:
        created_alerts = KeywordAlert.objects.bulk_create(alerts_to_create)
        logger.info(f"[Signal] {len(created_alerts)}개의 알림 생성 완료 - 캠페인 ID: {instance.id}")

        # FCM 푸시 알림 전송
        send_push_notifications_for_alerts(created_alerts, instance)
    else:
        logger.info(f"[Signal] 매칭된 키워드 없음 - 캠페인 ID: {instance.id}, 업체명: {campaign_company_original[:50]}, 제목: {campaign_title_original[:50]}")

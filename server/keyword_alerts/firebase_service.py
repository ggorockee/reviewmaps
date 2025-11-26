"""
import logging
Firebase Admin SDK 초기화 및 FCM 푸시 전송 서비스

환경변수:
    FIREBASE_CREDENTIALS: Firebase Admin SDK 서비스 계정 JSON (문자열)
"""
import json
import os
from typing import Optional

import firebase_admin
from firebase_admin import credentials, messaging


logger = logging.getLogger(__name__)

class FirebasePushService:
    """
    Firebase Cloud Messaging 서비스
    - 싱글톤 패턴으로 앱 전체에서 하나의 인스턴스만 사용
    - Kubernetes Secret에서 환경변수로 주입된 credentials 사용
    """
    _instance = None
    _initialized = False

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self):
        if not self._initialized:
            self._initialize_firebase()
            FirebasePushService._initialized = True

    def _initialize_firebase(self):
        """Firebase Admin SDK 초기화"""
        try:
            # 이미 초기화되어 있으면 스킵
            if firebase_admin._apps:
                logger.info("[Firebase] Already initialized")
                return

            # 환경변수에서 credentials JSON 가져오기
            cred_json = os.getenv('FIREBASE_CREDENTIALS')

            if not cred_json:
                logger.info("[Firebase] FIREBASE_CREDENTIALS 환경변수가 설정되지 않았습니다.")
                return

            # JSON 문자열을 dict로 파싱
            cred_dict = json.loads(cred_json)
            cred = credentials.Certificate(cred_dict)
            firebase_admin.initialize_app(cred)
            logger.info("[Firebase] Successfully initialized from environment variable")

        except json.JSONDecodeError as e:
            logger.info(f"[Firebase] Invalid JSON in FIREBASE_CREDENTIALS: {e}")
        except Exception as e:
            logger.info(f"[Firebase] Initialization error: {e}")

    def send_push_notification(
        self,
        token: str,
        title: str,
        body: str,
        data: Optional[dict] = None
    ) -> bool:
        """
        단일 디바이스에 푸시 알림 전송

        Args:
            token: FCM 디바이스 토큰
            title: 알림 제목
            body: 알림 내용
            data: 추가 데이터 (선택)

        Returns:
            성공 여부
        """
        try:
            if not firebase_admin._apps:
                logger.info("[Firebase] Not initialized, skipping push")
                return False

            message = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                data=data or {},
                token=token,
            )

            response = messaging.send(message)
            logger.info(f"[Firebase] Push sent successfully: {response}")
            return True

        except messaging.UnregisteredError:
            # 토큰이 유효하지 않음 - 디바이스 비활성화 필요
            logger.info(f"[Firebase] Token unregistered: {token[:20]}...")
            return False

        except Exception as e:
            logger.info(f"[Firebase] Push error: {e}")
            return False

    def send_push_to_multiple(
        self,
        tokens: list[str],
        title: str,
        body: str,
        data: Optional[dict] = None
    ) -> dict:
        """
        여러 디바이스에 푸시 알림 전송

        Args:
            tokens: FCM 디바이스 토큰 리스트
            title: 알림 제목
            body: 알림 내용
            data: 추가 데이터 (선택)

        Returns:
            {success_count, failure_count, failed_tokens}
        """
        result = {
            "success_count": 0,
            "failure_count": 0,
            "failed_tokens": []
        }

        if not firebase_admin._apps:
            logger.info("[Firebase] Not initialized, skipping push")
            result["failure_count"] = len(tokens)
            result["failed_tokens"] = tokens
            return result

        if not tokens:
            return result

        try:
            message = messaging.MulticastMessage(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                data=data or {},
                tokens=tokens,
            )

            response = messaging.send_each_for_multicast(message)
            result["success_count"] = response.success_count
            result["failure_count"] = response.failure_count

            # 실패한 토큰 수집
            for idx, send_response in enumerate(response.responses):
                if not send_response.success:
                    result["failed_tokens"].append(tokens[idx])

            logger.info(f"[Firebase] Multicast sent - success: {result['success_count']}, failure: {result['failure_count']}")

        except Exception as e:
            logger.info(f"[Firebase] Multicast error: {e}")
            result["failure_count"] = len(tokens)
            result["failed_tokens"] = tokens

        return result


# 싱글톤 인스턴스
firebase_push_service = FirebasePushService()

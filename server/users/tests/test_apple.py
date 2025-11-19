"""
Apple OAuth 검증 서비스 테스트
"""
from django.test import TestCase
from unittest.mock import patch, MagicMock
from users.services.apple import (
    get_apple_public_keys,
    verify_apple_token,
)
import jwt
import time


class AppleJWTVerificationTestCase(TestCase):
    """Apple JWT 검증 테스트"""

    def setUp(self):
        """테스트 데이터 준비"""
        # 테스트용 RSA 키 페어 생성 (실제 Apple 키는 아님)
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.backends import default_backend

        # RSA 키 생성
        self.private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )

        self.public_key = self.private_key.public_key()

        # 공개 키를 PEM 형식으로 변환
        self.public_key_pem = self.public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )

        # JWT 페이로드
        self.payload = {
            'sub': '001234.abcd1234efgh5678ijkl90mnop.1234',  # Apple 사용자 ID
            'email': 'test@privaterelay.appleid.com',
            'iat': int(time.time()),
            'exp': int(time.time()) + 3600,  # 1시간 후 만료
            'aud': 'com.reviewmaps.app',  # audience
            'iss': 'https://appleid.apple.com',
        }

    @patch('users.services.apple.httpx.AsyncClient')
    async def test_get_apple_public_keys_success(self, mock_client):
        """Apple 공개 키 가져오기 성공 테스트"""
        # Mock 응답 설정
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            'keys': [
                {
                    'kty': 'RSA',
                    'kid': 'test-key-id',
                    'use': 'sig',
                    'alg': 'RS256',
                    'n': 'test-n-value',
                    'e': 'AQAB',
                }
            ]
        }

        mock_client_instance = MagicMock()
        mock_client_instance.__aenter__.return_value = mock_client_instance
        mock_client_instance.__aexit__.return_value = None
        mock_client_instance.get.return_value = mock_response
        mock_client.return_value = mock_client_instance

        # 함수 실행
        keys = await get_apple_public_keys()

        # 검증
        self.assertIsNotNone(keys)
        self.assertIn('test-key-id', keys)

    @patch('users.services.apple.httpx.AsyncClient')
    async def test_get_apple_public_keys_failure(self, mock_client):
        """Apple 공개 키 가져오기 실패 테스트"""
        # Mock 응답 설정 (HTTP 500 에러)
        mock_response = MagicMock()
        mock_response.status_code = 500

        mock_client_instance = MagicMock()
        mock_client_instance.__aenter__.return_value = mock_client_instance
        mock_client_instance.__aexit__.return_value = None
        mock_client_instance.get.return_value = mock_response
        mock_client.return_value = mock_client_instance

        # 함수 실행
        keys = await get_apple_public_keys()

        # 검증 (실패 시 None 반환)
        self.assertIsNone(keys)

    @patch('users.services.apple.get_apple_public_keys')
    async def test_verify_apple_token_success(self, mock_get_keys):
        """Apple 토큰 검증 성공 테스트"""
        # JWT 생성 (테스트용 private key로 서명)
        identity_token = jwt.encode(
            self.payload,
            self.private_key,
            algorithm='RS256',
            headers={'kid': 'test-key-id'}
        )

        # Mock 공개 키 설정
        mock_get_keys.return_value = {
            'test-key-id': self.public_key
        }

        # 함수 실행
        user_info = await verify_apple_token(identity_token)

        # 검증
        self.assertIsNotNone(user_info)
        self.assertEqual(user_info['id'], '001234.abcd1234efgh5678ijkl90mnop.1234')
        self.assertEqual(user_info['email'], 'test@privaterelay.appleid.com')
        self.assertEqual(user_info['name'], '')  # Apple은 JWT에 이름 미포함
        self.assertEqual(user_info['profile_image'], '')  # Apple은 프로필 이미지 미제공

    @patch('users.services.apple.get_apple_public_keys')
    async def test_verify_apple_token_expired(self, mock_get_keys):
        """만료된 Apple 토큰 검증 실패 테스트"""
        # 만료된 JWT 생성
        expired_payload = self.payload.copy()
        expired_payload['exp'] = int(time.time()) - 3600  # 1시간 전 만료

        identity_token = jwt.encode(
            expired_payload,
            self.private_key,
            algorithm='RS256',
            headers={'kid': 'test-key-id'}
        )

        # Mock 공개 키 설정
        mock_get_keys.return_value = {
            'test-key-id': self.public_key
        }

        # 함수 실행
        user_info = await verify_apple_token(identity_token)

        # 검증 (만료된 토큰은 None 반환)
        self.assertIsNone(user_info)

    @patch('users.services.apple.get_apple_public_keys')
    async def test_verify_apple_token_invalid_signature(self, mock_get_keys):
        """잘못된 서명의 Apple 토큰 검증 실패 테스트"""
        # 다른 키로 서명된 JWT 생성
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.backends import default_backend

        wrong_private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )

        identity_token = jwt.encode(
            self.payload,
            wrong_private_key,  # 다른 키로 서명
            algorithm='RS256',
            headers={'kid': 'test-key-id'}
        )

        # Mock 공개 키 설정 (올바른 공개 키)
        mock_get_keys.return_value = {
            'test-key-id': self.public_key
        }

        # 함수 실행
        user_info = await verify_apple_token(identity_token)

        # 검증 (잘못된 서명은 None 반환)
        self.assertIsNone(user_info)

    @patch('users.services.apple.get_apple_public_keys')
    async def test_verify_apple_token_missing_kid(self, mock_get_keys):
        """kid가 없는 Apple 토큰 검증 실패 테스트"""
        # kid 없이 JWT 생성
        identity_token = jwt.encode(
            self.payload,
            self.private_key,
            algorithm='RS256',
            # headers에 kid 누락
        )

        # 함수 실행
        user_info = await verify_apple_token(identity_token)

        # 검증 (kid 없으면 None 반환)
        self.assertIsNone(user_info)

    @patch('users.services.apple.get_apple_public_keys')
    async def test_verify_apple_token_missing_sub(self, mock_get_keys):
        """sub(사용자 ID)가 없는 Apple 토큰 검증 실패 테스트"""
        # sub 없는 페이로드
        payload_without_sub = self.payload.copy()
        del payload_without_sub['sub']

        identity_token = jwt.encode(
            payload_without_sub,
            self.private_key,
            algorithm='RS256',
            headers={'kid': 'test-key-id'}
        )

        # Mock 공개 키 설정
        mock_get_keys.return_value = {
            'test-key-id': self.public_key
        }

        # 함수 실행
        user_info = await verify_apple_token(identity_token)

        # 검증 (sub 없으면 None 반환)
        self.assertIsNone(user_info)

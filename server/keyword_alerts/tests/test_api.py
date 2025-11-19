"""
키워드 알람 API 테스트
"""
from django.test import TestCase
from django.contrib.auth import get_user_model
from keyword_alerts.models import Keyword, KeywordAlert
from campaigns.models import Campaign, Category
from app_config.models import AppSetting
import json

User = get_user_model()


class KeywordAPITestCase(TestCase):
    """키워드 API 테스트"""

    def setUp(self):
        """테스트 데이터 준비"""
        # 테스트 사용자 생성
        self.user = User.objects.create_user(
            email='test@example.com',
            password='testpass123'
        )

        # JWT 토큰 생성
        from users.utils import create_access_token
        self.token = create_access_token(self.user.id, self.user.email)

        # 테스트 카테고리 생성
        self.category = Category.objects.create(
            name='테스트 카테고리',
            display_order=1
        )

        # 테스트 캠페인 생성
        self.campaign = Campaign.objects.create(
            platform='네이버',
            company='테스트 업체',
            offer='헬스장 무료 이용권',
            category=self.category,
            lat=37.5665,
            lng=126.9780
        )

        # 키워드 제한 설정
        AppSetting.objects.create(
            key='keyword_limit',
            value={
                'max_active_keywords': 3,
                'max_inactive_keywords': 0
            },
            is_active=True
        )

    def test_create_keyword_success(self):
        """키워드 등록 성공 테스트"""
        response = self.client.post(
            '/api/v1/keyword-alerts/keywords',
            data=json.dumps({'keyword': '헬스장'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.token}'
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['keyword'], '헬스장')
        self.assertTrue(data['is_active'])

        # DB 확인
        self.assertTrue(
            Keyword.objects.filter(user=self.user, keyword='헬스장').exists()
        )

    def test_create_keyword_duplicate(self):
        """중복 키워드 등록 실패 테스트"""
        # 첫 번째 등록
        Keyword.objects.create(user=self.user, keyword='헬스장', is_active=True)

        # 두 번째 등록 시도 (중복)
        response = self.client.post(
            '/api/v1/keyword-alerts/keywords',
            data=json.dumps({'keyword': '헬스장'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.token}'
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('이미 등록된 키워드', response.json()['detail'])

    def test_create_keyword_limit_exceeded(self):
        """키워드 등록 개수 제한 테스트"""
        # 3개까지 등록 (제한값)
        for i in range(3):
            Keyword.objects.create(
                user=self.user,
                keyword=f'키워드{i}',
                is_active=True
            )

        # 4번째 등록 시도 (제한 초과)
        response = self.client.post(
            '/api/v1/keyword-alerts/keywords',
            data=json.dumps({'keyword': '헬스장'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.token}'
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('최대 3개', response.json()['detail'])

    def test_list_keywords(self):
        """키워드 목록 조회 테스트"""
        # 테스트 키워드 생성
        Keyword.objects.create(user=self.user, keyword='헬스장', is_active=True)
        Keyword.objects.create(user=self.user, keyword='PT', is_active=True)

        response = self.client.get(
            '/api/v1/keyword-alerts/keywords',
            HTTP_AUTHORIZATION=f'Bearer {self.token}'
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(len(data['keywords']), 2)
        self.assertEqual(data['keywords'][0]['keyword'], 'PT')  # 최신순

    def test_delete_keyword(self):
        """키워드 삭제(비활성화) 테스트"""
        keyword = Keyword.objects.create(
            user=self.user,
            keyword='헬스장',
            is_active=True
        )

        response = self.client.delete(
            f'/api/v1/keyword-alerts/keywords/{keyword.id}',
            HTTP_AUTHORIZATION=f'Bearer {self.token}'
        )

        self.assertEqual(response.status_code, 200)

        # DB 확인 (soft delete)
        keyword.refresh_from_db()
        self.assertFalse(keyword.is_active)

    def test_toggle_keyword(self):
        """키워드 활성화/비활성화 토글 테스트"""
        keyword = Keyword.objects.create(
            user=self.user,
            keyword='헬스장',
            is_active=True
        )

        # 비활성화
        response = self.client.patch(
            f'/api/v1/keyword-alerts/keywords/{keyword.id}/toggle',
            HTTP_AUTHORIZATION=f'Bearer {self.token}'
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertFalse(data['is_active'])

        # DB 확인
        keyword.refresh_from_db()
        self.assertFalse(keyword.is_active)

        # 다시 활성화
        response = self.client.patch(
            f'/api/v1/keyword-alerts/keywords/{keyword.id}/toggle',
            HTTP_AUTHORIZATION=f'Bearer {self.token}'
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data['is_active'])

    def test_list_alerts(self):
        """알람 목록 조회 테스트"""
        # 키워드 생성
        keyword = Keyword.objects.create(
            user=self.user,
            keyword='헬스장',
            is_active=True
        )

        # 알람 생성
        KeywordAlert.objects.create(
            keyword=keyword,
            campaign=self.campaign,
            matched_field='offer',
            is_read=False
        )

        response = self.client.get(
            '/api/v1/keyword-alerts/alerts',
            HTTP_AUTHORIZATION=f'Bearer {self.token}'
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(len(data['alerts']), 1)
        self.assertEqual(data['unread_count'], 1)
        self.assertEqual(data['alerts'][0]['keyword'], '헬스장')

    def test_mark_alerts_read(self):
        """알람 읽음 처리 테스트"""
        # 키워드 생성
        keyword = Keyword.objects.create(
            user=self.user,
            keyword='헬스장',
            is_active=True
        )

        # 알람 생성
        alert = KeywordAlert.objects.create(
            keyword=keyword,
            campaign=self.campaign,
            matched_field='offer',
            is_read=False
        )

        response = self.client.post(
            '/api/v1/keyword-alerts/alerts/read',
            data=json.dumps({'alert_ids': [alert.id]}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.token}'
        )

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['updated_count'], 1)

        # DB 확인
        alert.refresh_from_db()
        self.assertTrue(alert.is_read)

    def test_unauthorized_access(self):
        """인증 없이 접근 시도 테스트"""
        response = self.client.get('/api/v1/keyword-alerts/keywords')

        self.assertEqual(response.status_code, 401)
        self.assertIn('로그인이 필요', response.json()['detail'])

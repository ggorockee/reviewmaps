from django.test import TestCase
from django.utils import timezone
from ninja.testing import TestAsyncClient
from decimal import Decimal
from campaigns.models import Category, Campaign
from campaigns.api import router
from asgiref.sync import async_to_sync


class CampaignAPITest(TestCase):
    """Campaign API 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        # 카테고리 생성
        self.category = Category.objects.create(name="맛집", display_order=1)

        # 테스트 캠페인 생성
        self.campaign1 = Campaign.objects.create(
            category=self.category,
            platform="네이버",
            company="강남맛집",
            offer="10,000원 상당 무료 제공",
            lat=Decimal("37.497952"),
            lng=Decimal("127.027619"),
            promotion_level=5,
            apply_deadline=timezone.now() + timezone.timedelta(days=7)
        )

        self.campaign2 = Campaign.objects.create(
            category=self.category,
            platform="인스타그램",
            company="홍대카페",
            offer="5,000원 할인",
            lat=Decimal("37.556495"),
            lng=Decimal("126.922854"),
            promotion_level=3,
            apply_deadline=timezone.now() + timezone.timedelta(days=14)
        )

        # 만료된 캠페인
        self.expired_campaign = Campaign.objects.create(
            category=self.category,
            platform="네이버",
            company="만료업체",
            offer="만료됨",
            apply_deadline=timezone.now() - timezone.timedelta(days=1)
        )

        self.client = TestAsyncClient(router)

    def _get(self, path):
        """비동기 GET 요청을 동기로 실행"""
        return async_to_sync(self.client.get)(path)

    def test_list_campaigns_basic(self):
        """기본 캠페인 목록 조회 테스트"""
        response = self._get("/")
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertIn("total", data)
        self.assertIn("items", data)
        self.assertIn("limit", data)
        self.assertIn("offset", data)

    def test_list_campaigns_excludes_expired(self):
        """만료된 캠페인 제외 테스트"""
        response = self._get("/")
        data = response.json()

        # 만료된 캠페인은 제외되어야 함
        campaign_ids = [item["id"] for item in data["items"]]
        self.assertNotIn(self.expired_campaign.id, campaign_ids)

    def test_list_campaigns_with_category_filter(self):
        """카테고리 필터 테스트"""
        response = self._get(f"/?category_id={self.category.id}")
        self.assertEqual(response.status_code, 200)

        data = response.json()
        for item in data["items"]:
            if item.get("category"):
                self.assertEqual(item["category"]["id"], self.category.id)

    def test_list_campaigns_with_platform_filter(self):
        """플랫폼 필터 테스트"""
        response = self._get("/?platform=네이버")
        self.assertEqual(response.status_code, 200)

        data = response.json()
        for item in data["items"]:
            self.assertEqual(item["platform"], "네이버")

    def test_list_campaigns_with_company_search(self):
        """업체명 검색 테스트"""
        response = self._get("/?company=강남")
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertTrue(any("강남" in item["company"] for item in data["items"]))

    def test_list_campaigns_with_offer_search(self):
        """오퍼 검색 테스트"""
        response = self._get("/?offer=10,000")
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertTrue(any("10,000" in item["offer"] for item in data["items"]))

    def test_list_campaigns_sort_by_promotion_level(self):
        """프로모션 레벨 정렬 테스트"""
        response = self._get("/?sort=-promotion_level")
        self.assertEqual(response.status_code, 200)

        data = response.json()
        items = data["items"]
        if len(items) >= 2:
            # 첫 번째 항목이 더 높은 promotion_level을 가져야 함
            self.assertGreaterEqual(
                items[0]["promotion_level"],
                items[-1]["promotion_level"]
            )

    def test_list_campaigns_with_pagination(self):
        """페이지네이션 테스트"""
        response = self._get("/?limit=1&offset=0")
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(data["limit"], 1)
        self.assertEqual(len(data["items"]), min(1, data["total"]))

    def test_list_campaigns_distance_sort_requires_location(self):
        """거리 정렬 시 위치 파라미터 필수 테스트"""
        response = self._get("/?sort=distance")
        # lat, lng 없으면 400 에러
        self.assertEqual(response.status_code, 400)

    def test_list_campaigns_distance_sort_with_location(self):
        """거리 정렬 테스트"""
        # 강남 위치
        response = self._get(
            "/?sort=distance&lat=37.497952&lng=127.027619"
        )
        self.assertEqual(response.status_code, 200)

        data = response.json()
        items = data["items"]
        if items:
            # distance 필드가 있어야 함
            self.assertIn("distance", items[0])

    def test_get_campaign_by_id(self):
        """캠페인 상세 조회 테스트"""
        response = self._get(f"/{self.campaign1.id}")
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(data["id"], self.campaign1.id)
        self.assertEqual(data["company"], "강남맛집")
        self.assertEqual(data["platform"], "네이버")

    def test_get_campaign_not_found(self):
        """존재하지 않는 캠페인 조회 테스트"""
        response = self._get("/999999")
        self.assertEqual(response.status_code, 404)

    def test_list_campaigns_with_bounding_box(self):
        """바운딩 박스 필터 테스트"""
        # 강남 지역 바운딩 박스
        response = self._get(
            "/?sw_lat=37.4&sw_lng=127.0&ne_lat=37.6&ne_lng=127.1"
        )
        self.assertEqual(response.status_code, 200)

        data = response.json()
        # 결과가 있어야 함 (강남맛집이 포함됨)
        self.assertGreater(data["total"], 0)

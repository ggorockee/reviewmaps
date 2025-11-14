from django.test import TestCase
from django.utils import timezone
from campaigns.models import Category, Campaign, RawCategory, CategoryMapping
from decimal import Decimal


class CategoryModelTest(TestCase):
    """Category 모델 테스트"""

    def test_create_category(self):
        """카테고리 생성 테스트"""
        category = Category.objects.create(
            name="맛집",
            display_order=1
        )
        self.assertEqual(category.name, "맛집")
        self.assertEqual(category.display_order, 1)
        self.assertIsNotNone(category.created_at)

    def test_category_str_representation(self):
        """카테고리 문자열 표현 테스트"""
        category = Category.objects.create(name="카페")
        self.assertEqual(str(category), "카페")

    def test_category_unique_name(self):
        """카테고리 이름 중복 테스트"""
        Category.objects.create(name="헬스장")
        with self.assertRaises(Exception):
            Category.objects.create(name="헬스장")

    def test_category_default_display_order(self):
        """카테고리 기본 표시 순서 테스트"""
        category = Category.objects.create(name="뷰티")
        self.assertEqual(category.display_order, 99)


class CampaignModelTest(TestCase):
    """Campaign 모델 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        self.category = Category.objects.create(name="맛집", display_order=1)

    def test_create_campaign(self):
        """캠페인 생성 테스트"""
        campaign = Campaign.objects.create(
            category=self.category,
            platform="네이버",
            company="강남맛집",
            offer="10,000원 상당 무료 제공",
            lat=Decimal("37.497952"),
            lng=Decimal("127.027619")
        )
        self.assertEqual(campaign.company, "강남맛집")
        self.assertEqual(campaign.platform, "네이버")
        self.assertEqual(campaign.category, self.category)
        self.assertIsNotNone(campaign.created_at)

    def test_campaign_with_deadlines(self):
        """마감일이 있는 캠페인 테스트"""
        apply_deadline = timezone.now() + timezone.timedelta(days=7)
        review_deadline = timezone.now() + timezone.timedelta(days=14)

        campaign = Campaign.objects.create(
            platform="인스타그램",
            company="테스트업체",
            offer="무료 체험",
            apply_deadline=apply_deadline,
            review_deadline=review_deadline
        )
        self.assertEqual(campaign.apply_deadline, apply_deadline)
        self.assertEqual(campaign.review_deadline, review_deadline)

    def test_campaign_with_location(self):
        """위치 정보가 있는 캠페인 테스트"""
        campaign = Campaign.objects.create(
            platform="네이버",
            company="강남헬스장",
            offer="PT 1회 무료",
            address="서울시 강남구",
            lat=Decimal("37.497952"),
            lng=Decimal("127.027619")
        )
        self.assertEqual(campaign.address, "서울시 강남구")
        self.assertEqual(campaign.lat, Decimal("37.497952"))
        self.assertEqual(campaign.lng, Decimal("127.027619"))

    def test_campaign_promotion_level(self):
        """프로모션 레벨 테스트"""
        campaign = Campaign.objects.create(
            platform="네이버",
            company="프리미엄업체",
            offer="특가",
            promotion_level=5
        )
        self.assertEqual(campaign.promotion_level, 5)

    def test_campaign_default_promotion_level(self):
        """기본 프로모션 레벨 테스트"""
        campaign = Campaign.objects.create(
            platform="네이버",
            company="일반업체",
            offer="할인"
        )
        self.assertEqual(campaign.promotion_level, 0)

    def test_campaign_str_representation(self):
        """캠페인 문자열 표현 테스트"""
        campaign = Campaign.objects.create(
            platform="네이버",
            company="테스트업체",
            offer="이것은 매우 긴 오퍼 텍스트입니다. 50자가 넘으면 잘려야 합니다."
        )
        self.assertIn("테스트업체", str(campaign))
        self.assertTrue(len(str(campaign)) <= 100)


class RawCategoryModelTest(TestCase):
    """RawCategory 모델 테스트"""

    def test_create_raw_category(self):
        """원본 카테고리 생성 테스트"""
        raw_category = RawCategory.objects.create(raw_text="맛집/카페")
        self.assertEqual(raw_category.raw_text, "맛집/카페")
        self.assertIsNotNone(raw_category.created_at)

    def test_raw_category_unique(self):
        """원본 카테고리 중복 테스트"""
        RawCategory.objects.create(raw_text="헬스/PT")
        with self.assertRaises(Exception):
            RawCategory.objects.create(raw_text="헬스/PT")


class CategoryMappingModelTest(TestCase):
    """CategoryMapping 모델 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        self.category = Category.objects.create(name="맛집")
        self.raw_category = RawCategory.objects.create(raw_text="맛집/카페")

    def test_create_category_mapping(self):
        """카테고리 매핑 생성 테스트"""
        mapping = CategoryMapping.objects.create(
            raw_category=self.raw_category,
            standard_category=self.category
        )
        self.assertEqual(mapping.raw_category, self.raw_category)
        self.assertEqual(mapping.standard_category, self.category)

    def test_category_mapping_str_representation(self):
        """카테고리 매핑 문자열 표현 테스트"""
        mapping = CategoryMapping.objects.create(
            raw_category=self.raw_category,
            standard_category=self.category
        )
        self.assertIn("맛집/카페", str(mapping))
        self.assertIn("맛집", str(mapping))

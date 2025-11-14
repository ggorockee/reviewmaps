from django.test import TestCase
from ninja.testing import TestClient
from campaigns.models import Category, RawCategory, CategoryMapping
from campaigns.category_api import router


class CategoryAPITest(TestCase):
    """Category API 테스트"""

    def setUp(self):
        """테스트 데이터 설정"""
        self.client = TestClient(router)

        # 테스트 카테고리 생성
        self.category1 = Category.objects.create(name="맛집", display_order=1)
        self.category2 = Category.objects.create(name="카페", display_order=2)
        self.category3 = Category.objects.create(name="헬스장", display_order=3)

        # 원본 카테고리 생성
        self.raw_category1 = RawCategory.objects.create(raw_text="맛집/카페")
        self.raw_category2 = RawCategory.objects.create(raw_text="헬스/PT")

        # 카테고리 매핑 생성 (raw_category1만 매핑)
        CategoryMapping.objects.create(
            raw_category=self.raw_category1,
            standard_category=self.category1
        )

    def test_list_categories(self):
        """카테고리 목록 조회 테스트"""
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(len(data), 3)
        self.assertEqual(data[0]["name"], "맛집")

    def test_get_category_by_id(self):
        """카테고리 상세 조회 테스트"""
        response = self.client.get(f"/{self.category1.id}")
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(data["id"], self.category1.id)
        self.assertEqual(data["name"], "맛집")
        self.assertEqual(data["display_order"], 1)

    def test_get_category_not_found(self):
        """존재하지 않는 카테고리 조회 테스트"""
        response = self.client.get("/999999")
        self.assertEqual(response.status_code, 404)

    def test_create_category(self):
        """카테고리 생성 테스트"""
        response = self.client.post(
            "/",
            json={"name": "뷰티", "display_order": 4}
        )
        self.assertEqual(response.status_code, 201)

        data = response.json()
        self.assertEqual(data["name"], "뷰티")
        self.assertEqual(data["display_order"], 4)

        # DB 확인
        self.assertTrue(Category.objects.filter(name="뷰티").exists())

    def test_create_category_duplicate_name(self):
        """중복된 이름으로 카테고리 생성 테스트"""
        response = self.client.post(
            "/",
            json={"name": "맛집", "display_order": 10}
        )
        self.assertEqual(response.status_code, 409)

    def test_update_category(self):
        """카테고리 수정 테스트"""
        response = self.client.put(
            f"/{self.category1.id}",
            json={"name": "맛집_수정", "display_order": 10}
        )
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertEqual(data["name"], "맛집_수정")
        self.assertEqual(data["display_order"], 10)

        # DB 확인
        self.category1.refresh_from_db()
        self.assertEqual(self.category1.name, "맛집_수정")

    def test_update_category_duplicate_name(self):
        """다른 카테고리와 중복된 이름으로 수정 테스트"""
        response = self.client.put(
            f"/{self.category1.id}",
            json={"name": "카페", "display_order": 1}
        )
        self.assertEqual(response.status_code, 409)

    def test_update_category_not_found(self):
        """존재하지 않는 카테고리 수정 테스트"""
        response = self.client.put(
            "/999999",
            json={"name": "테스트", "display_order": 1}
        )
        self.assertEqual(response.status_code, 404)

    def test_delete_category(self):
        """카테고리 삭제 테스트"""
        response = self.client.delete(f"/{self.category3.id}")
        self.assertEqual(response.status_code, 204)

        # DB 확인
        self.assertFalse(Category.objects.filter(id=self.category3.id).exists())

    def test_delete_category_not_found(self):
        """존재하지 않는 카테고리 삭제 테스트"""
        response = self.client.delete("/999999")
        self.assertEqual(response.status_code, 404)

    def test_list_unmapped_categories(self):
        """매핑되지 않은 원본 카테고리 조회 테스트"""
        response = self.client.get("/unmapped-categories")
        self.assertEqual(response.status_code, 200)

        data = response.json()
        # raw_category2만 매핑되지 않음
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]["raw_text"], "헬스/PT")

    def test_create_category_mapping(self):
        """카테고리 매핑 생성 테스트"""
        response = self.client.post(
            "/category-mappings",
            json={
                "raw_category_id": self.raw_category2.id,
                "standard_category_id": self.category3.id
            }
        )
        self.assertEqual(response.status_code, 200)

        # DB 확인
        self.assertTrue(
            CategoryMapping.objects.filter(
                raw_category=self.raw_category2,
                standard_category=self.category3
            ).exists()
        )

    def test_create_category_mapping_duplicate(self):
        """중복 매핑 생성 테스트"""
        response = self.client.post(
            "/category-mappings",
            json={
                "raw_category_id": self.raw_category1.id,
                "standard_category_id": self.category2.id
            }
        )
        # raw_category1은 이미 매핑되어 있음 (OneToOneField)
        self.assertEqual(response.status_code, 409)

    def test_update_category_order(self):
        """카테고리 순서 업데이트 테스트"""
        # 순서 변경: category3 -> category1 -> category2
        response = self.client.put(
            "/order",
            json={
                "ordered_ids": [self.category3.id, self.category1.id, self.category2.id]
            }
        )
        self.assertEqual(response.status_code, 204)

        # DB 확인
        self.category1.refresh_from_db()
        self.category2.refresh_from_db()
        self.category3.refresh_from_db()

        self.assertEqual(self.category3.display_order, 1)
        self.assertEqual(self.category1.display_order, 2)
        self.assertEqual(self.category2.display_order, 3)

    def test_update_category_order_invalid_ids(self):
        """잘못된 ID 목록으로 순서 업데이트 테스트"""
        # 존재하지 않는 ID 포함
        response = self.client.put(
            "/order",
            json={
                "ordered_ids": [self.category1.id, 999999]
            }
        )
        self.assertEqual(response.status_code, 400)

    def test_update_category_order_missing_ids(self):
        """누락된 ID로 순서 업데이트 테스트"""
        # 일부 카테고리 ID 누락
        response = self.client.put(
            "/order",
            json={
                "ordered_ids": [self.category1.id, self.category2.id]
            }
        )
        self.assertEqual(response.status_code, 400)

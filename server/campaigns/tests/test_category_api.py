import pytest
from django.test import AsyncClient
from campaigns.models import Category, RawCategory, CategoryMapping
import json


@pytest.mark.django_db(transaction=True)
class TestCategoryAPI:
    """Category API 테스트 (비동기)"""

    async def _setup_data(self):
        """테스트 데이터 설정 헬퍼"""
        self.client = AsyncClient()

        # 테스트 카테고리 생성
        self.category1 = await Category.objects.acreate(name="맛집", display_order=1)
        self.category2 = await Category.objects.acreate(name="카페", display_order=2)
        self.category3 = await Category.objects.acreate(name="헬스장", display_order=3)

        # 원본 카테고리 생성
        self.raw_category1 = await RawCategory.objects.acreate(raw_text="맛집/카페")
        self.raw_category2 = await RawCategory.objects.acreate(raw_text="헬스/PT")

        # 카테고리 매핑 생성 (raw_category1만 매핑)
        await CategoryMapping.objects.acreate(
            raw_category=self.raw_category1,
            standard_category=self.category1
        )

    @pytest.mark.asyncio
    async def test_list_categories(self):
        """카테고리 목록 조회 테스트"""
        await self._setup_data()
        response = await self.client.get("/api/v1/categories/")
        assert response.status_code == 200

        data = response.json()
        assert len(data) == 3
        assert data[0]["name"] == "맛집"

    @pytest.mark.asyncio
    async def test_get_category_by_id(self):
        """카테고리 상세 조회 테스트"""
        await self._setup_data()
        response = await self.client.get(f"/api/v1/categories/{self.category1.id}")
        assert response.status_code == 200

        data = response.json()
        assert data["id"] == self.category1.id
        assert data["name"] == "맛집"
        assert data["display_order"] == 1

    @pytest.mark.asyncio
    async def test_get_category_not_found(self):
        """존재하지 않는 카테고리 조회 테스트"""
        await self._setup_data()
        response = await self.client.get("/api/v1/categories/999999")
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_create_category(self):
        """카테고리 생성 테스트"""
        await self._setup_data()
        response = await self.client.post(
            "/api/v1/categories/",
            data=json.dumps({"name": "뷰티", "display_order": 4}),
            content_type="application/json"
        )
        assert response.status_code == 201

        data = response.json()
        assert data["name"] == "뷰티"
        assert data["display_order"] == 4

        # DB 확인
        exists = await Category.objects.filter(name="뷰티").aexists()
        assert exists is True

    @pytest.mark.asyncio
    async def test_create_category_duplicate_name(self):
        """중복된 이름으로 카테고리 생성 테스트"""
        await self._setup_data()
        response = await self.client.post(
            "/api/v1/categories/",
            data=json.dumps({"name": "맛집", "display_order": 10}),
            content_type="application/json"
        )
        assert response.status_code == 409

    @pytest.mark.asyncio
    async def test_update_category(self):
        """카테고리 수정 테스트"""
        await self._setup_data()
        response = await self.client.put(
            f"/api/v1/categories/{self.category1.id}",
            data=json.dumps({"name": "맛집_수정", "display_order": 10}),
            content_type="application/json"
        )
        assert response.status_code == 200

        data = response.json()
        assert data["name"] == "맛집_수정"
        assert data["display_order"] == 10

        # DB 확인
        await self.category1.arefresh_from_db()
        assert self.category1.name == "맛집_수정"

    @pytest.mark.asyncio
    async def test_update_category_duplicate_name(self):
        """다른 카테고리와 중복된 이름으로 수정 테스트"""
        await self._setup_data()
        response = await self.client.put(
            f"/api/v1/categories/{self.category1.id}",
            data=json.dumps({"name": "카페", "display_order": 1}),
            content_type="application/json"
        )
        assert response.status_code == 409

    @pytest.mark.asyncio
    async def test_update_category_not_found(self):
        """존재하지 않는 카테고리 수정 테스트"""
        await self._setup_data()
        response = await self.client.put(
            "/api/v1/categories/999999",
            data=json.dumps({"name": "테스트", "display_order": 1}),
            content_type="application/json"
        )
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_delete_category(self):
        """카테고리 삭제 테스트"""
        await self._setup_data()
        response = await self.client.delete(f"/api/v1/categories/{self.category3.id}")
        assert response.status_code == 204

        # DB 확인
        exists = await Category.objects.filter(id=self.category3.id).aexists()
        assert exists is False

    @pytest.mark.asyncio
    async def test_delete_category_not_found(self):
        """존재하지 않는 카테고리 삭제 테스트"""
        await self._setup_data()
        response = await self.client.delete("/api/v1/categories/999999")
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_list_unmapped_categories(self):
        """매핑되지 않은 원본 카테고리 조회 테스트"""
        await self._setup_data()
        response = await self.client.get("/api/v1/categories/unmapped-categories")
        assert response.status_code == 200

        data = response.json()
        # raw_category2만 매핑되지 않음
        assert len(data) == 1
        assert data[0]["raw_text"] == "헬스/PT"

    @pytest.mark.asyncio
    async def test_create_category_mapping(self):
        """카테고리 매핑 생성 테스트"""
        await self._setup_data()
        response = await self.client.post(
            "/api/v1/categories/category-mappings",
            data=json.dumps({
                "raw_category_id": self.raw_category2.id,
                "standard_category_id": self.category3.id
            }),
            content_type="application/json"
        )
        assert response.status_code == 200

        # DB 확인
        exists = await CategoryMapping.objects.filter(
            raw_category=self.raw_category2,
            standard_category=self.category3
        ).aexists()
        assert exists is True

    @pytest.mark.asyncio
    async def test_create_category_mapping_duplicate(self):
        """중복 매핑 생성 테스트"""
        await self._setup_data()
        response = await self.client.post(
            "/api/v1/categories/category-mappings",
            data=json.dumps({
                "raw_category_id": self.raw_category1.id,
                "standard_category_id": self.category2.id
            }),
            content_type="application/json"
        )
        # raw_category1은 이미 매핑되어 있음 (OneToOneField)
        assert response.status_code == 409

    @pytest.mark.asyncio
    async def test_update_category_order(self):
        """카테고리 순서 업데이트 테스트"""
        await self._setup_data()
        # 순서 변경: category3 -> category1 -> category2
        response = await self.client.put(
            "/api/v1/categories/order",
            data=json.dumps({
                "ordered_ids": [self.category3.id, self.category1.id, self.category2.id]
            }),
            content_type="application/json"
        )
        assert response.status_code == 204

        # DB 확인
        await self.category1.arefresh_from_db()
        await self.category2.arefresh_from_db()
        await self.category3.arefresh_from_db()

        assert self.category3.display_order == 1
        assert self.category1.display_order == 2
        assert self.category2.display_order == 3

    @pytest.mark.asyncio
    async def test_update_category_order_invalid_ids(self):
        """잘못된 ID 목록으로 순서 업데이트 테스트"""
        await self._setup_data()
        # 존재하지 않는 ID 포함
        response = await self.client.put(
            "/api/v1/categories/order",
            data=json.dumps({
                "ordered_ids": [self.category1.id, 999999]
            }),
            content_type="application/json"
        )
        assert response.status_code == 400

    @pytest.mark.asyncio
    async def test_update_category_order_missing_ids(self):
        """누락된 ID로 순서 업데이트 테스트"""
        await self._setup_data()
        # 일부 카테고리 ID 누락
        response = await self.client.put(
            "/api/v1/categories/order",
            data=json.dumps({
                "ordered_ids": [self.category1.id, self.category2.id]
            }),
            content_type="application/json"
        )
        assert response.status_code == 400

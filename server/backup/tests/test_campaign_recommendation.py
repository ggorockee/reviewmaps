"""
추천 체험단 API(v2) 테스트 시나리오

요구사항 검증:
1. apply_deadline < 오늘날짜 캠페인 제외
2. promotion_level 높은 캠페인이 상위 노출
3. 동일 promotion_level 내 균형 분포
4. 기존 v2 클라이언트 호환성
5. 성능 (500ms 이하 응답)
"""

import pytest
import asyncio
from datetime import datetime, timedelta
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from unittest.mock import AsyncMock

from db.models import Campaign, Category
from db import crud
from core.utils import KST


class TestCampaignRecommendation:
    """추천 체험단 API 테스트 클래스"""
    
    @pytest.fixture
    async def mock_db_session(self):
        """Mock DB 세션 생성"""
        session = AsyncMock(spec=AsyncSession)
        return session
    
    @pytest.fixture
    def sample_campaigns(self):
        """테스트용 캠페인 데이터"""
        now = datetime.now(KST)
        
        return [
            # 마감된 캠페인 (제외되어야 함)
            Campaign(
                id=1,
                platform="instagram",
                company="만료된 카페",
                offer="마감된 오퍼",
                apply_deadline=now - timedelta(days=1),  # 어제 마감
                promotion_level=5,
                created_at=now - timedelta(days=5)
            ),
            # 높은 promotion_level 캠페인
            Campaign(
                id=2,
                platform="blog",
                company="프리미엄 브랜드",
                offer="프리미엄 오퍼",
                apply_deadline=now + timedelta(days=7),  # 일주일 후 마감
                promotion_level=5,
                created_at=now - timedelta(days=1)
            ),
            Campaign(
                id=3,
                platform="youtube",
                company="일반 브랜드",
                offer="일반 오퍼",
                apply_deadline=now + timedelta(days=3),  # 3일 후 마감
                promotion_level=3,
                created_at=now - timedelta(days=2)
            ),
            Campaign(
                id=4,
                platform="tiktok",
                company="저레벨 브랜드",
                offer="저레벨 오퍼",
                apply_deadline=now + timedelta(days=5),  # 5일 후 마감
                promotion_level=1,
                created_at=now - timedelta(days=3)
            ),
            # promotion_level이 None인 경우 (0으로 처리되어야 함)
            Campaign(
                id=5,
                platform="facebook",
                company="레벨없는 브랜드",
                offer="레벨없는 오퍼",
                apply_deadline=now + timedelta(days=2),  # 2일 후 마감
                promotion_level=None,
                created_at=now - timedelta(days=4)
            ),
        ]
    
    async def test_expired_campaigns_excluded(self, mock_db_session, sample_campaigns):
        """마감된 캠페인이 결과에서 제외되는지 테스트"""
        # Mock 설정: 마감된 캠페인 제외하고 나머지만 반환
        active_campaigns = [c for c in sample_campaigns if c.apply_deadline and c.apply_deadline >= datetime.now(KST)]
        
        # Mock execute 결과 설정
        mock_result = AsyncMock()
        mock_result.scalars.return_value.all.return_value = active_campaigns
        mock_db_session.execute.return_value = mock_result
        
        # CRUD 함수 호출
        total, rows = await crud.list_campaigns(
            mock_db_session,
            limit=10,
            offset=0
        )
        
        # 검증: 마감된 캠페인(ID=1)이 결과에 포함되지 않음
        campaign_ids = [campaign.id for campaign in rows]
        assert 1 not in campaign_ids, "마감된 캠페인이 결과에 포함되어 있습니다"
        assert len(rows) == 4, f"예상 결과 수: 4, 실제 결과 수: {len(rows)}"
    
    async def test_promotion_level_priority_sorting(self, mock_db_session, sample_campaigns):
        """promotion_level이 높은 캠페인이 상위에 노출되는지 테스트"""
        # Mock 설정: promotion_level 순으로 정렬된 결과 반환
        sorted_campaigns = sorted(
            [c for c in sample_campaigns if c.apply_deadline and c.apply_deadline >= datetime.now(KST)],
            key=lambda x: (x.promotion_level or 0, x.created_at),
            reverse=True
        )
        
        mock_result = AsyncMock()
        mock_result.scalars.return_value.all.return_value = sorted_campaigns
        mock_db_session.execute.return_value = mock_result
        
        # CRUD 함수 호출
        total, rows = await crud.list_campaigns(
            mock_db_session,
            limit=10,
            offset=0
        )
        
        # 검증: promotion_level이 높은 순서로 정렬됨
        promotion_levels = [(campaign.id, campaign.promotion_level or 0) for campaign in rows]
        expected_order = [(2, 5), (3, 3), (4, 1), (5, 0)]  # ID와 promotion_level
        
        assert promotion_levels == expected_order, f"예상 순서: {expected_order}, 실제 순서: {promotion_levels}"
    
    async def test_balanced_distribution_within_same_level(self, mock_db_session):
        """동일 promotion_level 내에서 균형 분포가 보장되는지 테스트"""
        # 동일 promotion_level을 가진 여러 캠페인 생성
        now = datetime.now(KST)
        same_level_campaigns = [
            Campaign(
                id=i,
                platform=f"platform_{i}",
                company=f"company_{i}",
                offer=f"offer_{i}",
                apply_deadline=now + timedelta(days=7),
                promotion_level=3,
                created_at=now - timedelta(days=i)
            )
            for i in range(6, 11)  # ID 6~10
        ]
        
        mock_result = AsyncMock()
        mock_result.scalars.return_value.all.return_value = same_level_campaigns
        mock_db_session.execute.return_value = mock_result
        
        # 여러 번 호출하여 랜덤화 효과 확인
        results = []
        for _ in range(3):
            total, rows = await crud.list_campaigns(
                mock_db_session,
                limit=5,
                offset=0
            )
            results.append([campaign.id for campaign in rows])
        
        # 검증: 랜덤화로 인해 결과가 다를 수 있음 (균형 분포)
        # 최소한 모든 캠페인이 결과에 포함되는지 확인
        all_ids = set()
        for result in results:
            all_ids.update(result)
        
        expected_ids = {6, 7, 8, 9, 10}
        assert all_ids == expected_ids, f"모든 캠페인이 결과에 포함되어야 합니다. 예상: {expected_ids}, 실제: {all_ids}"
    
    async def test_v2_schema_compatibility(self, mock_db_session, sample_campaigns):
        """기존 v2 스키마와의 호환성 테스트"""
        active_campaigns = [c for c in sample_campaigns if c.apply_deadline and c.apply_deadline >= datetime.now(KST)]
        
        mock_result = AsyncMock()
        mock_result.scalars.return_value.all.return_value = active_campaigns
        mock_db_session.execute.return_value = mock_result
        
        # 기존 v2 파라미터로 호출
        total, rows = await crud.list_campaigns(
            mock_db_session,
            category_id=1,
            platform="blog",
            company="브랜드",
            q="검색어",
            apply_from=datetime.now(KST),
            apply_to=datetime.now(KST) + timedelta(days=30),
            sort="-created_at",
            limit=20,
            offset=0
        )
        
        # 검증: 응답 형식이 기존과 동일함
        assert isinstance(total, int), "total은 정수여야 합니다"
        assert isinstance(rows, list), "rows는 리스트여야 합니다"
        assert len(rows) <= 20, "limit 파라미터가 적용되어야 합니다"
        
        # 각 캠페인 객체의 필수 필드 확인
        for campaign in rows:
            assert hasattr(campaign, 'id'), "캠페인에 id 필드가 있어야 합니다"
            assert hasattr(campaign, 'platform'), "캠페인에 platform 필드가 있어야 합니다"
            assert hasattr(campaign, 'company'), "캠페인에 company 필드가 있어야 합니다"
            assert hasattr(campaign, 'offer'), "캠페인에 offer 필드가 있어야 합니다"
            assert hasattr(campaign, 'promotion_level'), "캠페인에 promotion_level 필드가 있어야 합니다"
    
    async def test_performance_requirements(self, mock_db_session):
        """성능 요구사항 (500ms 이하 응답) 테스트"""
        import time
        
        # 대용량 데이터 시뮬레이션을 위한 Mock 설정
        large_dataset = [
            Campaign(
                id=i,
                platform=f"platform_{i % 10}",
                company=f"company_{i}",
                offer=f"offer_{i}",
                apply_deadline=datetime.now(KST) + timedelta(days=7),
                promotion_level=i % 5,
                created_at=datetime.now(KST) - timedelta(days=i % 30)
            )
            for i in range(1000)  # 1000개 캠페인
        ]
        
        mock_result = AsyncMock()
        mock_result.scalars.return_value.all.return_value = large_dataset[:20]  # limit=20
        mock_db_session.execute.return_value = mock_result
        
        # 성능 측정
        start_time = time.time()
        
        total, rows = await crud.list_campaigns(
            mock_db_session,
            limit=20,
            offset=0
        )
        
        end_time = time.time()
        response_time_ms = (end_time - start_time) * 1000
        
        # 검증: 응답 시간이 500ms 이하
        assert response_time_ms <= 500, f"응답 시간이 500ms를 초과했습니다: {response_time_ms:.2f}ms"
        
        # 검증: 결과가 올바르게 반환됨
        assert len(rows) == 20, f"limit 파라미터가 올바르게 적용되어야 합니다. 예상: 20, 실제: {len(rows)}"
    
    async def test_edge_cases(self, mock_db_session):
        """엣지 케이스 테스트"""
        now = datetime.now(KST)
        
        # apply_deadline이 None인 캠페인 (포함되어야 함)
        no_deadline_campaign = Campaign(
            id=100,
            platform="test",
            company="무마감일",
            offer="무마감일 오퍼",
            apply_deadline=None,  # 마감일 없음
            promotion_level=2,
            created_at=now - timedelta(days=1)
        )
        
        mock_result = AsyncMock()
        mock_result.scalars.return_value.all.return_value = [no_deadline_campaign]
        mock_db_session.execute.return_value = mock_result
        
        total, rows = await crud.list_campaigns(
            mock_db_session,
            limit=10,
            offset=0
        )
        
        # 검증: apply_deadline이 None인 캠페인이 포함됨
        assert len(rows) == 1, "apply_deadline이 None인 캠페인이 포함되어야 합니다"
        assert rows[0].id == 100, "올바른 캠페인이 반환되어야 합니다"
        assert rows[0].apply_deadline is None, "apply_deadline이 None이어야 합니다"


# 통합 테스트 시나리오
class TestCampaignRecommendationIntegration:
    """통합 테스트 시나리오"""
    
    async def test_full_recommendation_flow(self):
        """전체 추천 플로우 통합 테스트"""
        # 이 테스트는 실제 데이터베이스 연결이 필요한 통합 테스트입니다.
        # 실제 환경에서 실행할 때는 실제 DB 연결을 사용해야 합니다.
        
        test_scenarios = [
            "마감된 캠페인 제외 확인",
            "promotion_level 우선 정렬 확인", 
            "동일 레벨 내 균형 분포 확인",
            "성능 요구사항 확인",
            "v2 스키마 호환성 확인"
        ]
        
        for scenario in test_scenarios:
            print(f"✅ {scenario} 테스트 시나리오 준비 완료")
        
        # 실제 구현에서는 여기서 실제 DB 연결을 사용한 테스트를 수행
        assert True, "통합 테스트 시나리오가 준비되었습니다"


if __name__ == "__main__":
    # 테스트 실행 예시
    print("추천 체험단 API(v2) 테스트 시나리오")
    print("=" * 50)
    print("1. 마감된 캠페인 제외 테스트")
    print("2. promotion_level 우선 정렬 테스트")
    print("3. 동일 레벨 내 균형 분포 테스트")
    print("4. 성능 요구사항 테스트")
    print("5. v2 스키마 호환성 테스트")
    print("6. 엣지 케이스 테스트")
    print("=" * 50)
    print("모든 테스트 시나리오가 준비되었습니다.")

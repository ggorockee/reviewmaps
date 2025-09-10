"""
PostgreSQL 성능 최적화 검증을 위한 테스트 엔드포인트

이 모듈은 다음을 제공합니다:
1. EXPLAIN ANALYZE 기반 쿼리 성능 분석
2. 인덱스 사용 통계 조회
3. 다양한 시나리오별 성능 벤치마크
4. 인덱스 활용도 검증
"""

from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional
import json

from api.deps import get_db_session
from db import crud

router = APIRouter(prefix="/performance", tags=["performance"])


@router.get("/explain-analyze", summary="쿼리 실행 계획 분석")
async def explain_analyze_query(
    db: AsyncSession = Depends(get_db_session),
    region: Optional[str] = Query(None, description="지역 필터"),
    category_id: Optional[int] = Query(None, description="카테고리 ID"),
    platform: Optional[str] = Query(None, description="플랫폼"),
    company: Optional[str] = Query(None, description="회사명"),
    sw_lat: Optional[float] = Query(None, description="남서쪽 위도"),
    sw_lng: Optional[float] = Query(None, description="남서쪽 경도"),
    ne_lat: Optional[float] = Query(None, description="북동쪽 위도"),
    ne_lng: Optional[float] = Query(None, description="북동쪽 경도"),
    lat: Optional[float] = Query(None, description="사용자 위도"),
    lng: Optional[float] = Query(None, description="사용자 경도"),
    sort: str = Query("-created_at", description="정렬 방식"),
    limit: int = Query(20, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    """
    ✨ EXPLAIN ANALYZE를 통한 쿼리 성능 분석
    
    반환값:
    - 실행 계획 (JSON)
    - 인덱스 활용도
    - 실행 시간
    - 버퍼 사용량
    """
    try:
        explain_result = await crud.explain_analyze_campaign_query(
            db=db,
            region=region,
            category_id=category_id,
            platform=platform,
            company=company,
            sw_lat=sw_lat,
            sw_lng=sw_lng,
            ne_lat=ne_lat,
            ne_lng=ne_lng,
            lat=lat,
            lng=lng,
            sort=sort,
            limit=limit,
            offset=offset,
        )
        
        return {
            "status": "success",
            "explain_analyze": json.loads(explain_result),
            "query_params": {
                "region": region,
                "category_id": category_id,
                "platform": platform,
                "company": company,
                "sw_lat": sw_lat,
                "sw_lng": sw_lng,
                "ne_lat": ne_lat,
                "ne_lng": ne_lng,
                "lat": lat,
                "lng": lng,
                "sort": sort,
                "limit": limit,
                "offset": offset,
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"EXPLAIN ANALYZE 실행 실패: {str(e)}")


@router.get("/index-stats", summary="인덱스 사용 통계")
async def get_index_statistics(db: AsyncSession = Depends(get_db_session)):
    """
    ✨ 인덱스 사용 통계 조회
    
    반환값:
    - 각 인덱스별 스캔 횟수
    - 읽은 튜플 수
    - 인덱스 크기
    - 효율성 지표
    """
    try:
        stats = await crud.get_index_usage_stats(db)
        return {
            "status": "success",
            "index_statistics": stats
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"인덱스 통계 조회 실패: {str(e)}")


@router.get("/benchmark", summary="성능 벤치마크")
async def run_performance_benchmark(db: AsyncSession = Depends(get_db_session)):
    """
    ✨ 다양한 시나리오별 성능 벤치마크
    
    테스트 시나리오:
    1. 추천 체험단 쿼리 (promotion_level 우선 정렬)
    2. 지도 뷰포트 쿼리 - 좁은 범위 (B-Tree 인덱스 활용)
    3. 지도 뷰포트 쿼리 - 넓은 범위 (GiST 인덱스 활용)
    4. 거리순 정렬 쿼리
    """
    try:
        benchmarks = await crud.benchmark_campaign_queries(db)
        
        # 성능 분석
        analysis = {
            "recommendation_query": {
                "time_ms": benchmarks["recommendation_query"]["execution_time_ms"],
                "status": "✅ 우수" if benchmarks["recommendation_query"]["execution_time_ms"] < 100 else "⚠️ 개선 필요"
            },
            "map_viewport_narrow": {
                "time_ms": benchmarks["map_viewport_narrow"]["execution_time_ms"],
                "status": "✅ 우수" if benchmarks["map_viewport_narrow"]["execution_time_ms"] < 50 else "⚠️ 개선 필요"
            },
            "map_viewport_wide": {
                "time_ms": benchmarks["map_viewport_wide"]["execution_time_ms"],
                "status": "✅ 우수" if benchmarks["map_viewport_wide"]["execution_time_ms"] < 200 else "⚠️ 개선 필요"
            },
            "distance_sort_query": {
                "time_ms": benchmarks["distance_sort_query"]["execution_time_ms"],
                "status": "✅ 우수" if benchmarks["distance_sort_query"]["execution_time_ms"] < 150 else "⚠️ 개선 필요"
            }
        }
        
        return {
            "status": "success",
            "benchmarks": benchmarks,
            "analysis": analysis,
            "summary": {
                "total_tests": len(benchmarks),
                "passed_tests": sum(1 for test in analysis.values() if "✅" in test["status"]),
                "average_time_ms": sum(test["time_ms"] for test in analysis.values()) / len(analysis)
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"벤치마크 실행 실패: {str(e)}")


@router.get("/index-verification", summary="인덱스 활용도 검증")
async def verify_index_usage(
    db: AsyncSession = Depends(get_db_session),
    test_type: str = Query("recommendation", description="테스트 유형: recommendation, map_narrow, map_wide, distance")
):
    """
    ✨ 특정 인덱스 활용도 검증
    
    테스트 유형:
    - recommendation: idx_campaign_promo_deadline_lat_lng 활용 검증
    - map_narrow: 좁은 범위에서 B-Tree 인덱스 활용 검증
    - map_wide: 넓은 범위에서 GiST 인덱스 활용 검증
    - distance: 거리순 정렬에서 인덱스 활용 검증
    """
    try:
        # 테스트 파라미터 설정
        test_params = {
            "recommendation": {
                "description": "추천 체험단 쿼리 - idx_campaign_promo_deadline_lat_lng 활용",
                "params": {"limit": 20, "offset": 0}
            },
            "map_narrow": {
                "description": "지도 뷰포트 쿼리 (좁은 범위) - B-Tree 인덱스 활용",
                "params": {
                    "sw_lat": 37.5, "sw_lng": 127.0,
                    "ne_lat": 37.6, "ne_lng": 127.1,
                    "limit": 20, "offset": 0
                }
            },
            "map_wide": {
                "description": "지도 뷰포트 쿼리 (넓은 범위) - GiST 인덱스 활용",
                "params": {
                    "sw_lat": 37.0, "sw_lng": 126.0,
                    "ne_lat": 38.0, "ne_lng": 128.0,
                    "limit": 20, "offset": 0
                }
            },
            "distance": {
                "description": "거리순 정렬 쿼리 - 복합 인덱스 활용",
                "params": {
                    "lat": 37.5665, "lng": 126.9780,
                    "sort": "distance",
                    "limit": 20, "offset": 0
                }
            }
        }
        
        if test_type not in test_params:
            raise HTTPException(
                status_code=400, 
                detail=f"지원하지 않는 테스트 유형: {test_type}. 지원 유형: {list(test_params.keys())}"
            )
        
        # EXPLAIN ANALYZE 실행
        explain_result = await crud.explain_analyze_campaign_query(
            db=db,
            **test_params[test_type]["params"]
        )
        
        explain_data = json.loads(explain_result)
        
        # 인덱스 활용도 분석
        def analyze_index_usage(plan):
            """실행 계획에서 인덱스 사용 패턴 분석"""
            if isinstance(plan, dict):
                if "Index Scan" in plan.get("Node Type", ""):
                    return {
                        "index_used": True,
                        "index_name": plan.get("Index Name", "unknown"),
                        "scan_type": plan.get("Node Type", ""),
                        "execution_time": plan.get("Execution Time", 0),
                        "planning_time": plan.get("Planning Time", 0)
                    }
                elif "Seq Scan" in plan.get("Node Type", ""):
                    return {
                        "index_used": False,
                        "scan_type": "Sequential Scan",
                        "execution_time": plan.get("Execution Time", 0),
                        "planning_time": plan.get("Planning Time", 0)
                    }
                
                # 하위 노드 재귀 분석
                for key, value in plan.items():
                    if isinstance(value, (list, dict)):
                        result = analyze_index_usage(value)
                        if result:
                            return result
            
            elif isinstance(plan, list):
                for item in plan:
                    result = analyze_index_usage(item)
                    if result:
                        return result
            
            return None
        
        index_analysis = analyze_index_usage(explain_data[0] if explain_data else {})
        
        return {
            "status": "success",
            "test_type": test_type,
            "description": test_params[test_type]["description"],
            "test_params": test_params[test_type]["params"],
            "explain_analyze": explain_data,
            "index_analysis": index_analysis,
            "verification_result": {
                "index_utilized": index_analysis["index_used"] if index_analysis else False,
                "performance_acceptable": index_analysis["execution_time"] < 100 if index_analysis else False,
                "recommendations": [
                    "✅ 인덱스가 올바르게 활용되고 있습니다" if index_analysis and index_analysis["index_used"] else "⚠️ 인덱스 활용을 개선해야 합니다",
                    "✅ 실행 시간이 양호합니다" if index_analysis and index_analysis["execution_time"] < 100 else "⚠️ 실행 시간을 개선해야 합니다"
                ]
            }
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"인덱스 검증 실패: {str(e)}")


@router.get("/health", summary="성능 모니터링 헬스체크")
async def performance_health_check(db: AsyncSession = Depends(get_db_session)):
    """
    ✨ 성능 모니터링 시스템 헬스체크
    
    확인 항목:
    - 데이터베이스 연결 상태
    - 인덱스 존재 여부
    - 기본 쿼리 실행 가능 여부
    """
    try:
        # 기본 쿼리 실행 테스트
        total, rows = await crud.list_campaigns_optimized(db=db, limit=1, offset=0)
        
        # 인덱스 존재 여부 확인
        index_check_query = """
            SELECT indexname 
            FROM pg_indexes 
            WHERE tablename = 'campaign' 
            AND indexname IN (
                'idx_campaign_promo_deadline_lat_lng',
                'idx_campaign_lat_lng'
            )
        """
        
        from sqlalchemy import text
        result = await db.execute(text(index_check_query))
        existing_indexes = [row[0] for row in result.fetchall()]
        
        return {
            "status": "healthy",
            "database_connection": "✅ 연결 정상",
            "basic_query_execution": "✅ 실행 정상",
            "required_indexes": {
                "idx_campaign_promo_deadline_lat_lng": "✅ 존재" if "idx_campaign_promo_deadline_lat_lng" in existing_indexes else "❌ 누락",
                "idx_campaign_lat_lng": "✅ 존재" if "idx_campaign_lat_lng" in existing_indexes else "❌ 누락"
            },
            "test_results": {
                "total_campaigns": total,
                "sample_returned": len(rows)
            }
        }
        
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e),
            "database_connection": "❌ 연결 실패",
            "basic_query_execution": "❌ 실행 실패"
        }

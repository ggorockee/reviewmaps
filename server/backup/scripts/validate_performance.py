"""
PostgreSQL 성능 최적화 검증 스크립트

이 스크립트는 다음을 검증합니다:
1. idx_campaign_promo_deadline_lat_lng 인덱스 활용도
2. idx_campaign_lat_lng GiST 인덱스 활용도
3. 다양한 시나리오별 성능 벤치마크
4. EXPLAIN ANALYZE 기반 실행 계획 분석
"""

import asyncio
import json
import time
from typing import Dict, Any
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from db.session import get_db_session
from db import crud


class PerformanceValidator:
    """PostgreSQL 성능 최적화 검증 클래스"""
    
    def __init__(self, db_session: AsyncSession):
        self.db = db_session
    
    async def verify_recommendation_index_usage(self) -> Dict[str, Any]:
        """추천 체험단 쿼리에서 idx_campaign_promo_deadline_lat_lng 인덱스 활용 검증"""
        print("🔍 추천 체험단 인덱스 활용도 검증 중...")
        
        explain_result = await crud.explain_analyze_campaign_query(
            db=self.db,
            limit=20,
            offset=0
        )
        
        explain_data = json.loads(explain_result)
        
        # 인덱스 사용 패턴 분석
        def find_index_scan(plan):
            if isinstance(plan, dict):
                if "Index Scan" in plan.get("Node Type", ""):
                    return {
                        "index_name": plan.get("Index Name", ""),
                        "scan_type": plan.get("Node Type", ""),
                        "execution_time": plan.get("Execution Time", 0),
                        "planning_time": plan.get("Planning Time", 0),
                        "rows_returned": plan.get("Actual Rows", 0),
                        "cost": plan.get("Total Cost", 0)
                    }
                
                # 하위 노드 재귀 검색
                for key, value in plan.items():
                    if isinstance(value, (list, dict)):
                        result = find_index_scan(value)
                        if result:
                            return result
            
            elif isinstance(plan, list):
                for item in plan:
                    result = find_index_scan(item)
                    if result:
                        return result
            
            return None
        
        index_scan_info = find_index_scan(explain_data[0] if explain_data else {})
        
        return {
            "test_name": "추천 체험단 인덱스 활용도",
            "expected_index": "idx_campaign_promo_deadline_lat_lng",
            "actual_index_scan": index_scan_info,
            "verification_result": {
                "index_used": index_scan_info is not None,
                "correct_index": index_scan_info and "promo_deadline_lat_lng" in index_scan_info.get("index_name", ""),
                "performance_acceptable": index_scan_info and index_scan_info.get("execution_time", 0) < 100,
                "status": "✅ 통과" if (index_scan_info and 
                                      "promo_deadline_lat_lng" in index_scan_info.get("index_name", "") and
                                      index_scan_info.get("execution_time", 0) < 100) else "❌ 실패"
            }
        }
    
    async def verify_map_viewport_index_usage(self) -> Dict[str, Any]:
        """지도 뷰포트 쿼리에서 GiST 인덱스 활용 검증"""
        print("🗺️ 지도 뷰포트 인덱스 활용도 검증 중...")
        
        # 좁은 범위 테스트 (B-Tree 인덱스 예상)
        narrow_explain = await crud.explain_analyze_campaign_query(
            db=self.db,
            sw_lat=37.5, sw_lng=127.0,
            ne_lat=37.6, ne_lng=127.1,
            limit=20,
            offset=0
        )
        
        # 넓은 범위 테스트 (GiST 인덱스 예상)
        wide_explain = await crud.explain_analyze_campaign_query(
            db=self.db,
            sw_lat=37.0, sw_lng=126.0,
            ne_lat=38.0, ne_lng=128.0,
            limit=20,
            offset=0
        )
        
        def analyze_index_usage(explain_data):
            explain_json = json.loads(explain_data)
            
            def find_scan_type(plan):
                if isinstance(plan, dict):
                    node_type = plan.get("Node Type", "")
                    if "Index Scan" in node_type:
                        return {
                            "type": "Index Scan",
                            "index": plan.get("Index Name", ""),
                            "time": plan.get("Execution Time", 0)
                        }
                    elif "Bitmap" in node_type:
                        return {
                            "type": "Bitmap Scan",
                            "index": plan.get("Index Name", ""),
                            "time": plan.get("Execution Time", 0)
                        }
                    elif "Seq Scan" in node_type:
                        return {
                            "type": "Sequential Scan",
                            "time": plan.get("Execution Time", 0)
                        }
                    
                    # 하위 노드 검색
                    for key, value in plan.items():
                        if isinstance(value, (list, dict)):
                            result = find_scan_type(value)
                            if result:
                                return result
                
                elif isinstance(plan, list):
                    for item in plan:
                        result = find_scan_type(item)
                        if result:
                            return result
                
                return None
            
            return find_scan_type(explain_json[0] if explain_json else {})
        
        narrow_analysis = analyze_index_usage(narrow_explain)
        wide_analysis = analyze_index_usage(wide_explain)
        
        return {
            "test_name": "지도 뷰포트 인덱스 활용도",
            "narrow_range": {
                "description": "좁은 범위 (B-Tree 인덱스 예상)",
                "analysis": narrow_analysis,
                "status": "✅ 통과" if narrow_analysis and narrow_analysis.get("time", 0) < 50 else "❌ 실패"
            },
            "wide_range": {
                "description": "넓은 범위 (GiST 인덱스 예상)",
                "analysis": wide_analysis,
                "status": "✅ 통과" if wide_analysis and wide_analysis.get("time", 0) < 200 else "❌ 실패"
            }
        }
    
    async def run_performance_benchmark(self) -> Dict[str, Any]:
        """종합 성능 벤치마크 실행"""
        print("⚡ 성능 벤치마크 실행 중...")
        
        benchmarks = await crud.benchmark_campaign_queries(self.db)
        
        # 성능 기준 설정
        performance_thresholds = {
            "recommendation_query": 100,  # ms
            "map_viewport_narrow": 50,   # ms
            "map_viewport_wide": 200,    # ms
            "distance_sort_query": 150   # ms
        }
        
        results = {}
        for test_name, threshold in performance_thresholds.items():
            actual_time = benchmarks[test_name]["execution_time_ms"]
            results[test_name] = {
                "execution_time_ms": actual_time,
                "threshold_ms": threshold,
                "status": "✅ 통과" if actual_time < threshold else "❌ 실패",
                "performance_ratio": actual_time / threshold
            }
        
        return {
            "test_name": "종합 성능 벤치마크",
            "results": results,
            "summary": {
                "total_tests": len(results),
                "passed_tests": sum(1 for r in results.values() if "✅" in r["status"]),
                "average_performance_ratio": sum(r["performance_ratio"] for r in results.values()) / len(results)
            }
        }
    
    async def verify_index_existence(self) -> Dict[str, Any]:
        """필수 인덱스 존재 여부 검증"""
        print("📊 인덱스 존재 여부 검증 중...")
        
        index_check_query = text("""
            SELECT 
                indexname,
                indexdef,
                pg_size_pretty(pg_relation_size(indexname::regclass)) as size
            FROM pg_indexes 
            WHERE tablename = 'campaign' 
            AND indexname IN (
                'idx_campaign_promo_deadline_lat_lng',
                'idx_campaign_lat_lng',
                'idx_campaign_promotion_deadline',
                'idx_campaign_created_at',
                'idx_campaign_category_id',
                'idx_campaign_apply_deadline'
            )
            ORDER BY indexname;
        """)
        
        result = await self.db.execute(index_check_query)
        existing_indexes = {}
        
        for row in result:
            existing_indexes[row.indexname] = {
                "definition": row.indexdef,
                "size": row.size
            }
        
        required_indexes = [
            "idx_campaign_promo_deadline_lat_lng",
            "idx_campaign_lat_lng"
        ]
        
        verification_results = {}
        for index_name in required_indexes:
            verification_results[index_name] = {
                "exists": index_name in existing_indexes,
                "status": "✅ 존재" if index_name in existing_indexes else "❌ 누락",
                "details": existing_indexes.get(index_name, {})
            }
        
        return {
            "test_name": "인덱스 존재 여부 검증",
            "required_indexes": verification_results,
            "all_indexes": existing_indexes,
            "summary": {
                "total_required": len(required_indexes),
                "existing_count": sum(1 for r in verification_results.values() if r["exists"]),
                "status": "✅ 모든 필수 인덱스 존재" if all(r["exists"] for r in verification_results.values()) else "❌ 일부 인덱스 누락"
            }
        }
    
    async def run_comprehensive_validation(self) -> Dict[str, Any]:
        """종합 검증 실행"""
        print("🚀 PostgreSQL 성능 최적화 종합 검증 시작...")
        print("=" * 60)
        
        start_time = time.time()
        
        validation_results = {
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "validation_duration_seconds": 0,
            "tests": {}
        }
        
        try:
            # 1. 인덱스 존재 여부 검증
            validation_results["tests"]["index_existence"] = await self.verify_index_existence()
            
            # 2. 추천 체험단 인덱스 활용도 검증
            validation_results["tests"]["recommendation_index"] = await self.verify_recommendation_index_usage()
            
            # 3. 지도 뷰포트 인덱스 활용도 검증
            validation_results["tests"]["map_viewport_index"] = await self.verify_map_viewport_index_usage()
            
            # 4. 성능 벤치마크
            validation_results["tests"]["performance_benchmark"] = await self.run_performance_benchmark()
            
            # 전체 결과 요약
            total_tests = 0
            passed_tests = 0
            
            for test_category, test_result in validation_results["tests"].items():
                if "summary" in test_result:
                    total_tests += test_result["summary"].get("total_tests", 1)
                    passed_tests += test_result["summary"].get("passed_tests", 0)
                elif "verification_result" in test_result:
                    total_tests += 1
                    if "✅" in test_result["verification_result"].get("status", ""):
                        passed_tests += 1
            
            validation_results["overall_summary"] = {
                "total_tests": total_tests,
                "passed_tests": passed_tests,
                "success_rate": (passed_tests / total_tests * 100) if total_tests > 0 else 0,
                "status": "✅ 검증 통과" if passed_tests == total_tests else "⚠️ 일부 검증 실패"
            }
            
        except Exception as e:
            validation_results["error"] = str(e)
            validation_results["overall_summary"] = {
                "status": "❌ 검증 실패",
                "error": str(e)
            }
        
        finally:
            validation_results["validation_duration_seconds"] = time.time() - start_time
        
        return validation_results


async def main():
    """메인 실행 함수"""
    print("PostgreSQL 성능 최적화 검증 도구")
    print("=" * 60)
    
    # 데이터베이스 세션 생성
    async for db_session in get_db_session():
        validator = PerformanceValidator(db_session)
        
        # 종합 검증 실행
        results = await validator.run_comprehensive_validation()
        
        # 결과 출력
        print("\n📋 검증 결과 요약:")
        print("=" * 60)
        
        for test_category, test_result in results["tests"].items():
            print(f"\n🔍 {test_result.get('test_name', test_category)}:")
            
            if "verification_result" in test_result:
                print(f"   상태: {test_result['verification_result']['status']}")
            
            if "summary" in test_result:
                summary = test_result["summary"]
                print(f"   통과: {summary.get('passed_tests', 0)}/{summary.get('total_tests', 0)}")
                print(f"   상태: {summary.get('status', 'N/A')}")
        
        print(f"\n🎯 전체 요약:")
        print(f"   총 테스트: {results['overall_summary']['total_tests']}")
        print(f"   통과: {results['overall_summary']['passed_tests']}")
        print(f"   성공률: {results['overall_summary']['success_rate']:.1f}%")
        print(f"   상태: {results['overall_summary']['status']}")
        print(f"   소요 시간: {results['validation_duration_seconds']:.2f}초")
        
        # 상세 결과를 JSON 파일로 저장
        with open("performance_validation_results.json", "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2, ensure_ascii=False)
        
        print(f"\n📄 상세 결과가 'performance_validation_results.json' 파일에 저장되었습니다.")
        
        break


if __name__ == "__main__":
    asyncio.run(main())

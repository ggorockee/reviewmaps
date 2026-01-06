#!/bin/bash

# Status Field 테스트 스크립트
# 소량의 데이터만 수집하여 status 필드가 제대로 작동하는지 확인

set -e

echo "======================================"
echo "Status Field Integration Test"
echo "======================================"
echo ""

# 1. 환경 변수 확인
echo "1. Checking environment variables..."
if [ ! -f .env ]; then
    echo "Error: .env file not found!"
    echo "Please create .env file with required configuration."
    exit 1
fi

# 2. 기존 데이터 백업
echo ""
echo "2. Checking existing reviewnote campaigns..."
EXISTING_COUNT=$(psql $DATABASE_URL -t -c "SELECT COUNT(*) FROM campaign WHERE platform = '리뷰노트';")
echo "   Existing reviewnote campaigns: $EXISTING_COUNT"

# 3. MaxItems 설정하여 제한적 실행
echo ""
echo "3. Running scraper with MaxItems=10 (test mode)..."
echo "   This will collect only 10 campaigns for testing."
echo ""

# MaxItems 환경변수 설정
export SCRAPE_MAX_ITEMS=10

# 스크레이퍼 실행
go run cmd/scraper/main.go reviewnote

# 4. 결과 확인
echo ""
echo "======================================"
echo "4. Verification Results"
echo "======================================"
echo ""

# 4.1. 새로 수집된 데이터 확인
echo "4.1. Recently collected campaigns with status field:"
psql $DATABASE_URL -c "
SELECT id, title, status, created_at
FROM campaign
WHERE platform = '리뷰노트'
ORDER BY created_at DESC
LIMIT 10;
"

echo ""
echo "4.2. Status field distribution:"
psql $DATABASE_URL -c "
SELECT
    status,
    COUNT(*) as count
FROM campaign
WHERE platform = '리뷰노트'
GROUP BY status
ORDER BY count DESC;
"

echo ""
echo "4.3. Checking if any non-SELECT status campaigns were saved:"
NON_SELECT=$(psql $DATABASE_URL -t -c "SELECT COUNT(*) FROM campaign WHERE platform = '리뷰노트' AND status IS NOT NULL AND status != 'SELECT';")
if [ "$NON_SELECT" -gt 0 ]; then
    echo "   WARNING: Found $NON_SELECT non-SELECT campaigns!"
    echo "   This should not happen. Please check the filter logic."
else
    echo "   ✅ PASS: All campaigns have status = 'SELECT'"
fi

echo ""
echo "4.4. Checking NULL status campaigns (should be only old data):"
NULL_COUNT=$(psql $DATABASE_URL -t -c "SELECT COUNT(*) FROM campaign WHERE platform = '리뷰노트' AND status IS NULL;")
echo "   NULL status campaigns: $NULL_COUNT (legacy data)"

echo ""
echo "======================================"
echo "Test Complete"
echo "======================================"
echo ""
echo "Summary:"
echo "  - Total reviewnote campaigns: $EXISTING_COUNT"
echo "  - Campaigns with NULL status: $NULL_COUNT"
echo "  - Non-SELECT campaigns: $NON_SELECT"
echo ""
echo "Next steps:"
echo "  1. Review the results above"
echo "  2. Check logs for 'Skip non-active campaign' messages"
echo "  3. If all looks good, run full scraper without MaxItems limit"
echo ""

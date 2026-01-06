#!/bin/bash

# Server API Status Field 통합 테스트
# status 필드가 API 응답에 제대로 포함되는지 확인

set -e

echo "======================================"
echo "Server API Status Field Integration Test"
echo "======================================"
echo ""

# API 베이스 URL (환경에 맞게 수정)
API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"

# 1. Health Check
echo "1. Checking API health..."
HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$API_BASE_URL/v1/healthz")
if [ "$HEALTH_CHECK" != "200" ]; then
    echo "   Error: API is not responding (HTTP $HEALTH_CHECK)"
    echo "   Please start the server first: cd server && make run"
    exit 1
fi
echo "   ✅ API is running"

# 2. 캠페인 목록 조회 (리뷰노트만)
echo ""
echo "2. Fetching reviewnote campaigns..."
RESPONSE=$(curl -s "$API_BASE_URL/v1/campaigns?platform=리뷰노트&limit=5")

# 3. status 필드 확인
echo ""
echo "3. Checking status field in API response..."
echo ""
echo "Sample response:"
echo "$RESPONSE" | jq '.'

echo ""
echo "4. Extracting status fields:"
STATUS_FIELDS=$(echo "$RESPONSE" | jq -r '.campaigns[].status // "NULL"')
echo "$STATUS_FIELDS"

echo ""
echo "5. Validation:"

# 5.1. status 필드가 존재하는지 확인
HAS_STATUS=$(echo "$RESPONSE" | jq 'has("campaigns") and (.campaigns[0] | has("status"))')
if [ "$HAS_STATUS" = "true" ]; then
    echo "   ✅ PASS: status field exists in API response"
else
    echo "   ❌ FAIL: status field is missing in API response"
    echo "   Please check server/internal/models/campaign.go"
    exit 1
fi

# 5.2. status 값이 SELECT인지 확인
SELECT_COUNT=$(echo "$STATUS_FIELDS" | grep -c "SELECT" || echo "0")
NULL_COUNT=$(echo "$STATUS_FIELDS" | grep -c "NULL" || echo "0")

echo "   - Campaigns with status='SELECT': $SELECT_COUNT"
echo "   - Campaigns with status=NULL: $NULL_COUNT (legacy data)"

# 5.3. non-SELECT 캠페인이 있는지 확인
NON_SELECT=$(echo "$STATUS_FIELDS" | grep -v "SELECT" | grep -v "NULL" | wc -l)
if [ "$NON_SELECT" -gt 0 ]; then
    echo "   ⚠️  WARNING: Found $NON_SELECT non-SELECT campaigns!"
    echo "   This might indicate old data or scraper issues."
fi

echo ""
echo "6. Full campaign details with status:"
echo "$RESPONSE" | jq '.campaigns[] | {id, title, status, platform, created_at}'

echo ""
echo "======================================"
echo "Test Complete"
echo "======================================"
echo ""
echo "Summary:"
echo "  - API Health: OK"
echo "  - Status field in response: $([ "$HAS_STATUS" = "true" ] && echo "✅ YES" || echo "❌ NO")"
echo "  - Campaigns with SELECT: $SELECT_COUNT"
echo "  - Campaigns with NULL: $NULL_COUNT"
echo "  - Campaigns with other status: $NON_SELECT"
echo ""

if [ "$HAS_STATUS" = "true" ]; then
    echo "✅ Server API integration test PASSED"
    exit 0
else
    echo "❌ Server API integration test FAILED"
    exit 1
fi

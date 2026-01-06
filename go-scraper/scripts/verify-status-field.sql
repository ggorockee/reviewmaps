-- DB 마이그레이션 검증 SQL
-- 실행: psql -h [HOST] -U [USER] -d [DATABASE] -f scripts/verify-status-field.sql

\echo '======================================'
\echo 'Status Field Migration Verification'
\echo '======================================'
\echo ''

-- 1. 컬럼 존재 확인
\echo '1. Checking if status column exists:'
SELECT column_name, data_type, is_nullable, character_maximum_length
FROM information_schema.columns
WHERE table_name = 'campaign' AND column_name = 'status';

\echo ''
\echo '2. Checking status index:'
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'campaign' AND indexname = 'idx_campaign_status';

\echo ''
\echo '3. Checking status field distribution:'
SELECT
    status,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM campaign
WHERE platform = '리뷰노트'
GROUP BY status
ORDER BY count DESC;

\echo ''
\echo '4. Sample data with status field:'
SELECT id, title, status, platform, created_at
FROM campaign
WHERE platform = '리뷰노트'
ORDER BY created_at DESC
LIMIT 5;

\echo ''
\echo '5. Checking NULL status campaigns:'
SELECT COUNT(*) as null_status_count
FROM campaign
WHERE platform = '리뷰노트' AND status IS NULL;

\echo ''
\echo '======================================'
\echo 'Verification Complete'
\echo '======================================'

-- Migration: (keyword_id, campaign_id) 부분 유니크 인덱스 추가 (soft-delete 제외)
-- Created: 2026-11-14
-- Purpose: 같은 키워드-캠페인 알림 중복 생성 방지
--   - GORM 모델에는 uniqueIndex가 정의돼 있었으나 기존 중복 데이터로 운영 DB에 생성되지 않았음
--   - soft-deleted 행은 재생성 방지 목적으로 보존되므로 deleted_at IS NULL 행만 유니크 대상
-- 사전 조건: 살아있는 (keyword_id, campaign_id) 중복이 없어야 함 (아래 1단계로 정리)
-- 주의: CREATE INDEX CONCURRENTLY는 트랜잭션 블록 안에서 실행할 수 없으므로 BEGIN/COMMIT 없이 실행

-- 1. 살아있는 중복 정리: 백업 후 그룹당 1건(읽음 우선, id 오름차순)만 남기고 soft-delete
CREATE TABLE IF NOT EXISTS keyword_alerts_alerts_dup_backup_20261114 AS
SELECT a.* FROM keyword_alerts_alerts a
WHERE a.id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (
            PARTITION BY keyword_id, campaign_id ORDER BY is_read DESC, id
        ) AS rn
        FROM keyword_alerts_alerts
        WHERE deleted_at IS NULL AND campaign_id IS NOT NULL
    ) r WHERE r.rn > 1
);

UPDATE keyword_alerts_alerts
SET deleted_at = NOW(), updated_at = NOW()
WHERE id IN (SELECT id FROM keyword_alerts_alerts_dup_backup_20261114)
  AND deleted_at IS NULL;

-- 2. 부분 유니크 인덱스 생성 (쓰기 차단 없이)
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS keyword_alerts_keyword_campaign_unique
ON keyword_alerts_alerts (keyword_id, campaign_id)
WHERE deleted_at IS NULL;

-- Rollback script (if needed):
-- DROP INDEX CONCURRENTLY IF EXISTS keyword_alerts_keyword_campaign_unique;
-- UPDATE keyword_alerts_alerts SET deleted_at = NULL
--   WHERE id IN (SELECT id FROM keyword_alerts_alerts_dup_backup_20261114);

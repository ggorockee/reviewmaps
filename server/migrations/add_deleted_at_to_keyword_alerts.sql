-- Migration: Add deleted_at column to keyword_alerts_alerts table for soft delete support
-- Created: 2026-05-05
-- Purpose: Fix "column keyword_alerts_alerts.deleted_at does not exist" error

BEGIN;

ALTER TABLE keyword_alerts_alerts
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_keyword_ale_deleted ON keyword_alerts_alerts(deleted_at);

COMMIT;

-- Rollback script (if needed):
-- BEGIN;
-- DROP INDEX IF EXISTS idx_keyword_ale_deleted;
-- ALTER TABLE keyword_alerts_alerts DROP COLUMN IF EXISTS deleted_at;
-- COMMIT;

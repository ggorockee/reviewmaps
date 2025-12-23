-- Migration: Add deleted_at column to campaign table for soft delete support
-- Created: 2025-12-23
-- Purpose: Fix "column campaign.deleted_at does not exist" error

BEGIN;

-- Add deleted_at column (nullable timestamp with timezone)
ALTER TABLE campaign
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;

-- Create index for soft delete queries (matching GORM definition)
CREATE INDEX IF NOT EXISTS idx_cpg_deleted ON campaign(deleted_at);

COMMIT;

-- Rollback script (if needed):
-- BEGIN;
-- DROP INDEX IF EXISTS idx_cpg_deleted;
-- ALTER TABLE campaign DROP COLUMN IF EXISTS deleted_at;
-- COMMIT;

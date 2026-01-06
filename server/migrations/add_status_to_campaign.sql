-- Add status column to campaign table
-- Migration: add_status_to_campaign
-- Date: 2026-01-07
-- Purpose: Track campaign status from reviewnote API to filter closed/ended campaigns

-- Add status column (nullable for backward compatibility)
ALTER TABLE campaign
ADD COLUMN IF NOT EXISTS status VARCHAR(20) NULL;

-- Add index for status filtering
CREATE INDEX IF NOT EXISTS idx_campaign_status ON campaign(status);

-- Add comment
COMMENT ON COLUMN campaign.status IS 'Campaign status from source API (e.g., SELECT, CLOSED, ENDED). NULL for legacy data.';

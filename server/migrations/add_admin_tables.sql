-- Migration: 관리자 콘솔(Go /admin/v1) 세션·변경 기록 테이블
-- Created: 2026-11-27
-- Purpose: Django 관리자를 Go + Nuxt로 옮기면서 로그인 세션과 변경 기록을 저장
--   admin_sessions: 세션 토큰의 SHA-256만 저장 (토큰 원문은 쿠키에만 있음)
--   admin_audit_logs: 관리자 변경 기록 (누가, 무엇을, 전후 값)
-- 적용: 운영 DB 쓰기이므로 개발자 승인 후 적용. 기존 테이블은 건드리지 않음 (IF NOT EXISTS)

BEGIN;

CREATE TABLE IF NOT EXISTS admin_sessions (
    token_hash  bytea       PRIMARY KEY,
    email       text        NOT NULL,
    expires_at  timestamptz NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS admin_sessions_expires ON admin_sessions (expires_at);

CREATE TABLE IF NOT EXISTS admin_audit_logs (
    id           bigserial   PRIMARY KEY,
    admin_email  text        NOT NULL,
    action       text        NOT NULL,
    entity       text        NOT NULL,
    entity_id    text        NOT NULL DEFAULT '',
    before       jsonb,
    after        jsonb,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS admin_audit_logs_created ON admin_audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS admin_audit_logs_entity ON admin_audit_logs (entity, entity_id);

COMMIT;

-- Rollback script (if needed):
-- BEGIN;
-- DROP TABLE IF EXISTS admin_audit_logs;
-- DROP TABLE IF EXISTS admin_sessions;
-- COMMIT;

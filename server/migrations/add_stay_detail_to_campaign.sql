-- Add stay detail (available days etc.) columns to campaign table
-- Migration: add_stay_detail_to_campaign
-- Date: 2026-11-27
-- Purpose: 리뷰노트 여행 카테고리 상세 API의 이용 조건(체험 가능·불가 요일, 가능 시간, 당일 방문, 예약 주의사항)을
--          go-scraper가 저장하고 앱이 제공 내역 아래에 보여주기 위함. 모두 NULL 허용(다른 출처·기존 데이터는 NULL).

ALTER TABLE campaign ADD COLUMN IF NOT EXISTS possible_days TEXT NULL;
ALTER TABLE campaign ADD COLUMN IF NOT EXISTS impossible_days TEXT NULL;
ALTER TABLE campaign ADD COLUMN IF NOT EXISTS possible_time TEXT NULL;
ALTER TABLE campaign ADD COLUMN IF NOT EXISTS same_day_visit BOOLEAN NULL;
ALTER TABLE campaign ADD COLUMN IF NOT EXISTS reservation_notice TEXT NULL;
ALTER TABLE campaign ADD COLUMN IF NOT EXISTS detail_fetched_at TIMESTAMPTZ NULL;

-- 상세 값 보관 테이블 (원본). campaign 행은 수집 때마다 DELETE 후 INSERT 되므로 상세 값을 따로 보관하고,
-- go-scraper가 campaign 행에 복사한다. 소유: go-scraper (reviewnote-detail 이 쓰고, reviewnote 가 읽음)
CREATE TABLE IF NOT EXISTS campaign_stay_detail (
    platform           VARCHAR(20)  NOT NULL,
    content_link       TEXT         NOT NULL,
    source_id          INTEGER      NULL,
    possible_days      TEXT         NULL,
    impossible_days    TEXT         NULL,
    possible_time      TEXT         NULL,
    same_day_visit     BOOLEAN      NULL,
    reservation_notice TEXT         NULL,
    fetched_at         TIMESTAMPTZ  NOT NULL,
    PRIMARY KEY (platform, content_link)
);
COMMENT ON TABLE campaign_stay_detail IS '상세 이용 조건 원본 (go-scraper reviewnote-detail, campaign 컬럼으로 복사됨)';

COMMENT ON COLUMN campaign.possible_days IS '체험 가능 요일 (원본 표기, 예: 월 / 화 / 수 / 목 / 일)';
COMMENT ON COLUMN campaign.impossible_days IS '체험 불가 요일 (원본 표기)';
COMMENT ON COLUMN campaign.possible_time IS '체험 가능 시간 (원본 표기)';
COMMENT ON COLUMN campaign.same_day_visit IS '당일 예약·방문 가능 여부';
COMMENT ON COLUMN campaign.reservation_notice IS '예약 시 주의사항 (원본 scheduleInformation)';
COMMENT ON COLUMN campaign.detail_fetched_at IS '상세 API에서 마지막으로 받은 시각';

-- 되돌리기:
-- DROP TABLE IF EXISTS campaign_stay_detail;
-- ALTER TABLE campaign DROP COLUMN IF EXISTS possible_days, DROP COLUMN IF EXISTS impossible_days,
--   DROP COLUMN IF EXISTS possible_time, DROP COLUMN IF EXISTS same_day_visit,
--   DROP COLUMN IF EXISTS reservation_notice, DROP COLUMN IF EXISTS detail_fetched_at;

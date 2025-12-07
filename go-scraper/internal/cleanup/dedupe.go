package cleanup

import (
	"context"
	"fmt"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/logger"
)

// DeduplicateCampaigns 중복 캠페인 정리
// (platform, title, offer, campaign_channel) 기준으로 중복된 레코드 중
// 가장 최신(updated_at 기준) 레코드만 남기고 삭제
func (c *Cleaner) DeduplicateCampaigns(ctx context.Context) error {
	log := logger.GetLogger("cleanup.dedupe")
	startTime := time.Now()

	log.Info("===== 중복 캠페인 정리 시작 =====")

	// 1. 중복 그룹 개수 확인
	countQuery := `
		SELECT COUNT(*) as dup_groups
		FROM (
			SELECT platform, title, offer, campaign_channel
			FROM campaign
			GROUP BY platform, title, offer, campaign_channel
			HAVING COUNT(*) > 1
		) as duplicates
	`

	var dupGroups int
	if err := c.database.Pool.QueryRow(ctx, countQuery).Scan(&dupGroups); err != nil {
		return fmt.Errorf("중복 그룹 카운트 실패: %w", err)
	}

	if dupGroups == 0 {
		log.Info("중복된 캠페인이 없습니다.")
		return nil
	}

	log.Infof("중복 그룹 발견: %d개", dupGroups)

	// 2. 중복 레코드 총 개수 (삭제 대상)
	totalDupQuery := `
		SELECT COALESCE(SUM(cnt - 1), 0)
		FROM (
			SELECT platform, title, offer, campaign_channel, COUNT(*) as cnt
			FROM campaign
			GROUP BY platform, title, offer, campaign_channel
			HAVING COUNT(*) > 1
		) as duplicates
	`

	var totalDuplicates int64
	if err := c.database.Pool.QueryRow(ctx, totalDupQuery).Scan(&totalDuplicates); err != nil {
		return fmt.Errorf("중복 레코드 카운트 실패: %w", err)
	}

	log.Infof("삭제 대상 중복 레코드: %d개", totalDuplicates)

	// 3. 중복 삭제 (가장 최신 updated_at 레코드만 유지)
	// CTE를 사용하여 각 그룹에서 가장 최신 레코드의 ID를 찾고
	// 그 외의 레코드를 삭제
	deleteQuery := `
		WITH ranked AS (
			SELECT id,
				   ROW_NUMBER() OVER (
					   PARTITION BY platform, title, offer, campaign_channel
					   ORDER BY updated_at DESC NULLS LAST, id DESC
				   ) as rn
			FROM campaign
		),
		to_delete AS (
			SELECT id FROM ranked WHERE rn > 1
		)
		DELETE FROM campaign
		WHERE id IN (SELECT id FROM to_delete)
	`

	result, err := c.database.Pool.Exec(ctx, deleteQuery)
	if err != nil {
		return fmt.Errorf("중복 캠페인 삭제 실패: %w", err)
	}

	rowsAffected := result.RowsAffected()
	log.Infof("중복 캠페인 삭제 완료: %d개 레코드 삭제됨", rowsAffected)

	// 4. 삭제 후 검증
	var remainingDups int
	if err := c.database.Pool.QueryRow(ctx, countQuery).Scan(&remainingDups); err != nil {
		log.Warnf("검증 쿼리 실패: %v", err)
	} else if remainingDups > 0 {
		log.Warnf("아직 %d개 중복 그룹이 남아있습니다.", remainingDups)
	} else {
		log.Info("모든 중복이 제거되었습니다. ✓")
	}

	// 메트릭 기록
	if c.telemetry != nil {
		c.telemetry.AddCleanupDeleted(ctx, rowsAffected)
		c.telemetry.RecordCleanupDuration(ctx, time.Since(startTime))
	}

	log.Infof("===== 중복 캠페인 정리 종료 (소요시간: %v) =====", time.Since(startTime))
	return nil
}

// AddUniqueConstraint UNIQUE 제약조건 추가
// 중복 정리 후에만 실행 가능
func (c *Cleaner) AddUniqueConstraint(ctx context.Context) error {
	log := logger.GetLogger("cleanup.dedupe")

	log.Info("===== UNIQUE 제약조건 추가 시작 =====")

	// 1. 기존 제약조건 확인
	checkQuery := `
		SELECT COUNT(*)
		FROM pg_constraint
		WHERE conname = 'uq_campaign_platform_title_offer_channel'
	`

	var exists int
	if err := c.database.Pool.QueryRow(ctx, checkQuery).Scan(&exists); err != nil {
		return fmt.Errorf("제약조건 확인 실패: %w", err)
	}

	if exists > 0 {
		log.Info("UNIQUE 제약조건이 이미 존재합니다.")
		return nil
	}

	// 2. 중복 확인
	dupCheckQuery := `
		SELECT COUNT(*)
		FROM (
			SELECT platform, title, offer, campaign_channel
			FROM campaign
			GROUP BY platform, title, offer, campaign_channel
			HAVING COUNT(*) > 1
		) as duplicates
	`

	var dupCount int
	if err := c.database.Pool.QueryRow(ctx, dupCheckQuery).Scan(&dupCount); err != nil {
		return fmt.Errorf("중복 확인 실패: %w", err)
	}

	if dupCount > 0 {
		return fmt.Errorf("중복 데이터가 %d개 그룹 존재합니다. 먼저 dedupe를 실행하세요", dupCount)
	}

	// 3. UNIQUE 제약조건 추가
	alterQuery := `
		ALTER TABLE campaign
		ADD CONSTRAINT uq_campaign_platform_title_offer_channel
		UNIQUE (platform, title, offer, campaign_channel)
	`

	if _, err := c.database.Pool.Exec(ctx, alterQuery); err != nil {
		return fmt.Errorf("UNIQUE 제약조건 추가 실패: %w", err)
	}

	log.Info("UNIQUE 제약조건 추가 완료 ✓")
	log.Info("===== UNIQUE 제약조건 추가 종료 =====")

	return nil
}

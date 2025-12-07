package cleanup

import (
	"context"
	"fmt"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/db"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/logger"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/telemetry"
)

// Cleaner 만료된 캠페인 정리
type Cleaner struct {
	config    *config.Config
	database  *db.DB
	telemetry *telemetry.Telemetry
}

// New 새로운 Cleaner 생성
func New(cfg *config.Config, database *db.DB, tel *telemetry.Telemetry) *Cleaner {
	return &Cleaner{
		config:    cfg,
		database:  database,
		telemetry: tel,
	}
}

// Run 만료된 캠페인 삭제 실행
// 삭제 조건: apply_deadline < TODAY (자정이 지난 경우)
// apply_deadline >= TODAY인 경우는 오늘까지 지원 가능하므로 유지
func (c *Cleaner) Run(ctx context.Context) error {
	log := logger.GetLogger("cleanup")
	startTime := time.Now()

	// 메트릭: cleanup 시작
	if c.telemetry != nil {
		c.telemetry.IncrementCleanupTotal(ctx)
	}

	// 오늘 날짜 (자정 기준)
	today := time.Now().In(c.config.Batch.Location()).Truncate(24 * time.Hour)

	log.Infof("===== 만료 캠페인 정리 시작 (기준일: %s) =====", today.Format("2006-01-02"))

	// 삭제 대상 카운트
	countQuery := `
		SELECT COUNT(*)
		FROM campaign
		WHERE apply_deadline IS NOT NULL
		  AND apply_deadline < $1
	`

	var count int
	if err := c.database.Pool.QueryRow(ctx, countQuery, today).Scan(&count); err != nil {
		if c.telemetry != nil {
			c.telemetry.IncrementCleanupErrors(ctx)
		}
		return fmt.Errorf("삭제 대상 카운트 실패: %w", err)
	}

	if count == 0 {
		log.Info("삭제할 만료 캠페인이 없습니다.")
		// 메트릭: duration 기록
		if c.telemetry != nil {
			c.telemetry.RecordCleanupDuration(ctx, time.Since(startTime))
		}
		return nil
	}

	log.Infof("삭제 대상: %d개 캠페인 (apply_deadline < %s)", count, today.Format("2006-01-02"))

	// 1. 관련 알림의 campaign_id를 NULL로 설정 (FK constraint 해결)
	nullifyQuery := `
		UPDATE keyword_alerts_alerts
		SET campaign_id = NULL
		WHERE campaign_id IN (
			SELECT id FROM campaign
			WHERE apply_deadline IS NOT NULL
			  AND apply_deadline < $1
		)
	`
	nullifyResult, err := c.database.Pool.Exec(ctx, nullifyQuery, today)
	if err != nil {
		log.Warnf("알림 campaign_id NULL 설정 실패: %v", err)
	} else if nullifyResult.RowsAffected() > 0 {
		log.Infof("관련 알림 %d건의 campaign_id를 NULL로 설정", nullifyResult.RowsAffected())
	}

	// 2. 배치 삭제 실행
	deleteQuery := `
		DELETE FROM campaign
		WHERE apply_deadline IS NOT NULL
		  AND apply_deadline < $1
	`

	result, err := c.database.Pool.Exec(ctx, deleteQuery, today)
	if err != nil {
		if c.telemetry != nil {
			c.telemetry.IncrementCleanupErrors(ctx)
		}
		return fmt.Errorf("캠페인 삭제 실패: %w", err)
	}

	rowsAffected := result.RowsAffected()
	log.Infof("삭제 완료: %d개 캠페인 정리됨", rowsAffected)

	// 메트릭: 삭제 개수 및 duration 기록
	if c.telemetry != nil {
		c.telemetry.AddCleanupDeleted(ctx, rowsAffected)
		c.telemetry.RecordCleanupDuration(ctx, time.Since(startTime))
	}

	log.Info("===== 만료 캠페인 정리 종료 =====")
	return nil
}

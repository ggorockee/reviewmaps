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

	log.Infof("Soft delete 대상: %d개 캠페인 (apply_deadline < %s)", count, today.Format("2006-01-02"))

	// Soft delete: deleted_at만 설정 (알림 히스토리 보존)
	softDeleteQuery := `
		UPDATE campaign
		SET deleted_at = NOW()
		WHERE apply_deadline IS NOT NULL
		  AND apply_deadline < $1
		  AND deleted_at IS NULL
	`

	result, err := c.database.Pool.Exec(ctx, softDeleteQuery, today)
	if err != nil {
		if c.telemetry != nil {
			c.telemetry.IncrementCleanupErrors(ctx)
		}
		return fmt.Errorf("캠페인 soft delete 실패: %w", err)
	}

	rowsAffected := result.RowsAffected()
	log.Infof("Soft delete 완료: %d개 캠페인 정리됨 (히스토리 보존)", rowsAffected)

	// 메트릭: 삭제 개수 및 duration 기록
	if c.telemetry != nil {
		c.telemetry.AddCleanupDeleted(ctx, rowsAffected)
		c.telemetry.RecordCleanupDuration(ctx, time.Since(startTime))
	}

	log.Info("===== 만료 캠페인 정리 종료 =====")
	return nil
}

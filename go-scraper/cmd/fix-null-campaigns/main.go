package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/jackc/pgx/v5/pgxpool"
)

// 이미 NULL로 처리된 alert들의 campaign_id를 복원하는 스크립트
func main() {
	ctx := context.Background()

	// DB 연결
	cfg := config.LoadConfig()
	dbURL := cfg.Database.URL()

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("DB 연결 실패: %v", err)
	}
	defer pool.Close()

	log.Println("NULL campaign_id 복원 시작...")

	// campaign_id가 NULL인 alert 조회
	query := `
		SELECT DISTINCT a.id, c.id as campaign_id
		FROM keyword_alerts_alerts a
		JOIN keyword k ON a.keyword_id = k.id
		JOIN campaign c ON (
			LOWER(c.title) LIKE '%' || LOWER(k.keyword) || '%'
			OR LOWER(c.offer) LIKE '%' || LOWER(k.keyword) || '%'
			OR LOWER(c.company) LIKE '%' || LOWER(k.keyword) || '%'
		)
		WHERE a.campaign_id IS NULL
		AND a.created_at >= NOW() - INTERVAL '7 days'
		ORDER BY a.id
	`

	rows, err := pool.Query(ctx, query)
	if err != nil {
		log.Fatalf("Query 실패: %v", err)
	}
	defer rows.Close()

	type Match struct {
		AlertID    int
		CampaignID int
	}
	var matches []Match

	for rows.Next() {
		var m Match
		if err := rows.Scan(&m.AlertID, &m.CampaignID); err != nil {
			log.Printf("Scan 실패: %v", err)
			continue
		}
		matches = append(matches, m)
	}

	log.Printf("복원 대상 발견: %d건", len(matches))

	if len(matches) == 0 {
		log.Println("복원할 alert가 없습니다.")
		return
	}

	// Batch update
	updateQuery := `
		UPDATE keyword_alerts_alerts
		SET campaign_id = $2
		WHERE id = $1 AND campaign_id IS NULL
	`

	updated := 0
	failed := 0
	for _, m := range matches {
		result, err := pool.Exec(ctx, updateQuery, m.AlertID, m.CampaignID)
		if err != nil {
			log.Printf("Alert %d 업데이트 실패: %v", m.AlertID, err)
			failed++
			continue
		}
		if result.RowsAffected() > 0 {
			updated++
		}
	}

	log.Printf("복원 완료: 성공 %d건, 실패 %d건", updated, failed)

	// 복원 후 남은 NULL 개수 확인
	var remainingNull int
	pool.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM keyword_alerts_alerts
		WHERE campaign_id IS NULL
		AND created_at >= NOW() - INTERVAL '7 days'
	`).Scan(&remainingNull)

	log.Printf("최근 7일 내 남은 NULL campaign_id: %d건", remainingNull)
}

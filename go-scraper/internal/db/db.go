package db

import (
	"context"
	"crypto/sha1"
	"fmt"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/runstats"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/logger"
	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// DB 데이터베이스 연결 풀
type DB struct {
	Pool *pgxpool.Pool
}

// New 새로운 DB 연결 생성
func New(cfg *config.DatabaseConfig) (*DB, error) {
	log := logger.GetLogger("db")

	poolConfig, err := pgxpool.ParseConfig(cfg.URL())
	if err != nil {
		return nil, fmt.Errorf("failed to parse database config: %w", err)
	}

	// 연결 풀 설정
	poolConfig.MaxConns = 10
	poolConfig.MinConns = 2
	poolConfig.MaxConnLifetime = time.Hour
	poolConfig.MaxConnIdleTime = 30 * time.Minute

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create connection pool: %w", err)
	}

	// 연결 테스트
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	log.Info("Database connection established")

	return &DB{
		Pool: pool,
	}, nil
}

// Close 데이터베이스 연결 종료
func (db *DB) Close() {
	if db.Pool != nil {
		db.Pool.Close()
	}
}

// LoadExistingCampaigns 기존 캠페인 맵 로딩
func (db *DB) LoadExistingCampaigns(ctx context.Context) (map[string]*models.CampaignKey, error) {
	log := logger.GetLogger("db")

	query := `
		SELECT platform, title, offer, campaign_channel, address, lat, lng, category_id
		FROM campaign
	`

	rows, err := db.Pool.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query campaigns: %w", err)
	}
	defer rows.Close()

	result := make(map[string]*models.CampaignKey)
	for rows.Next() {
		var ck models.CampaignKey
		err := rows.Scan(
			&ck.Platform,
			&ck.Title,
			&ck.Offer,
			&ck.CampaignChannel,
			&ck.Address,
			&ck.Lat,
			&ck.Lng,
			&ck.CategoryID,
		)
		if err != nil {
			log.Warnf("Failed to scan campaign row: %v", err)
			continue
		}
		key := ck.Key()
		result[key] = &ck
	}

	log.Infof("Loaded %d existing campaigns", len(result))
	return result, nil
}

// UpsertCampaigns 캠페인 데이터 저장 (DELETE + INSERT 방식)
// 기존 레코드를 삭제하고 새로 INSERT하여 created_at도 갱신
// 반환값: 신규 캠페인 ID 목록만 (기존에 있던 캠페인은 제외)
func (db *DB) UpsertCampaigns(ctx context.Context, campaigns []models.Campaign) ([]uint, error) {
	log := logger.GetLogger("db")

	if len(campaigns) == 0 {
		log.Warn("저장할 최종 데이터가 없습니다.")
		return nil, nil
	}

	log.Infof("정제된 최종 데이터 %d건을 DB에 저장 시작...", len(campaigns))

	// 트랜잭션 시작
	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("트랜잭션 시작 실패: %w", err)
	}
	defer tx.Rollback(ctx)

	// 1. 기존 캠페인 조회 (이미 존재하는지 체크용)
	// 같은 키의 중복 레코드가 있을 수 있으므로 해당 키의 ID를 모두 조회 (3단계 DELETE가 키 기준으로 전부 삭제)
	findQuery := `
		SELECT id FROM campaign
		WHERE (platform, title, offer, campaign_channel) = ($1, $2, $3, $4)
	`

	// 기존에 있던 캠페인 키 추적 (신규 여부 판단 + 알림 복원 매핑용)
	existingKeys := make(map[string]bool)
	oldIDsByKey := make(map[string][]uint)
	var campaignIDsToDelete []uint
	for _, c := range campaigns {
		key := campaignKey(c)
		if _, seen := oldIDsByKey[key]; seen {
			continue
		}
		rows, err := tx.Query(ctx, findQuery, c.Platform, c.Title, c.Offer, c.CampaignChannel)
		if err != nil {
			return nil, fmt.Errorf("기존 캠페인 조회 실패: %w", err)
		}
		ids, err := pgx.CollectRows(rows, pgx.RowTo[uint])
		if err != nil {
			return nil, fmt.Errorf("기존 캠페인 조회 실패: %w", err)
		}
		oldIDsByKey[key] = ids
		if len(ids) > 0 {
			existingKeys[key] = true // 기존에 있던 캠페인
			campaignIDsToDelete = append(campaignIDsToDelete, ids...)
		}
	}

	// 2. 관련 알림의 campaign_id를 NULL로 설정 (FK constraint 해결)
	// NULL 처리 전에 "알림 → 기존 캠페인" 연결을 기록해 두었다가 5단계에서 정확히 그 알림만 복원
	// (soft-deleted 알림 포함: 삭제 상태를 유지한 채 캠페인 연결만 복원)
	alertIDsByCampaign := make(map[uint][]uint)
	if len(campaignIDsToDelete) > 0 {
		rows, err := tx.Query(ctx, `
			SELECT id, campaign_id FROM keyword_alerts_alerts
			WHERE campaign_id = ANY($1)
		`, campaignIDsToDelete)
		if err != nil {
			return nil, fmt.Errorf("관련 알림 조회 실패: %w", err)
		}
		for rows.Next() {
			var alertID, campaignID uint
			if err := rows.Scan(&alertID, &campaignID); err != nil {
				rows.Close()
				return nil, fmt.Errorf("관련 알림 조회 실패: %w", err)
			}
			alertIDsByCampaign[campaignID] = append(alertIDsByCampaign[campaignID], alertID)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return nil, fmt.Errorf("관련 알림 조회 실패: %w", err)
		}

		nullifyQuery := `
			UPDATE keyword_alerts_alerts
			SET campaign_id = NULL
			WHERE campaign_id = ANY($1)
		`
		result, err := tx.Exec(ctx, nullifyQuery, campaignIDsToDelete)
		if err != nil {
			return nil, fmt.Errorf("알림 campaign_id NULL 설정 실패: %w", err)
		} else if result.RowsAffected() > 0 {
			log.Infof("관련 알림 %d건의 campaign_id를 NULL로 설정", result.RowsAffected())
		}
	}

	// 3. 기존 레코드 삭제 (DELETE)
	deleteQuery := `
		DELETE FROM campaign
		WHERE (platform, title, offer, campaign_channel) = ($1, $2, $3, $4)
	`

	deleteBatch := &pgx.Batch{}
	for _, c := range campaigns {
		deleteBatch.Queue(deleteQuery, c.Platform, c.Title, c.Offer, c.CampaignChannel)
	}

	deleteBr := tx.SendBatch(ctx, deleteBatch)
	deletedCount := int64(0)
	for i := 0; i < len(campaigns); i++ {
		result, err := deleteBr.Exec()
		if err != nil {
			log.Warnf("기존 캠페인 삭제 실패 (index %d): %v", i, err)
		} else {
			deletedCount += result.RowsAffected()
		}
	}
	deleteBr.Close()

	if deletedCount > 0 {
		log.Infof("기존 캠페인 %d건 삭제 완료", deletedCount)
	}

	// 4. 새로 INSERT (RETURNING id로 저장된 ID 수집)
	insertQuery := `
		INSERT INTO campaign (
			platform, title, offer, campaign_channel, company, content_link,
			company_link, source, campaign_type, region, apply_deadline,
			review_deadline, address, lat, lng, category_id, img_url, status
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18
		) RETURNING id
	`

	var newCampaignIDs []uint // 신규 캠페인 ID만
	var allInsertedCount int
	campaignIDMap := make(map[string]uint) // key -> new campaign_id 매핑
	for _, c := range campaigns {
		var id uint
		err := tx.QueryRow(ctx, insertQuery,
			c.Platform, c.Title, c.Offer, c.CampaignChannel, c.Company, c.ContentLink,
			c.CompanyLink, c.Source, c.CampaignType, c.Region, c.ApplyDeadline,
			c.ReviewDeadline, c.Address, c.Lat, c.Lng, c.CategoryID, c.ImgURL, c.Status,
		).Scan(&id)
		if err != nil {
			log.Errorf("캠페인 INSERT 실패: %v", err)
			continue
		}
		allInsertedCount++

		key := campaignKey(c)
		campaignIDMap[key] = id

		// 기존에 없던 신규 캠페인만 알림 대상에 추가
		if !existingKeys[key] {
			newCampaignIDs = append(newCampaignIDs, id)
		}
	}

	// 5. NULL로 설정했던 알림을 "원래 연결돼 있던 캠페인의 새 ID"로 복원 (알림 ID 단위)
	// 주의: campaign_id IS NULL 조건만으로 복원하면 테이블의 모든 NULL 알림이 첫 캠페인에 붙음 (2026-11-14 발견)
	plan := buildAlertRestorePlan(oldIDsByKey, alertIDsByCampaign, campaignIDMap)
	if len(plan) > 0 {
		// 같은 키의 중복 캠페인들에 같은 키워드 알림이 있었다면 하나의 새 캠페인으로 합쳐지므로,
		// 키워드별 1건(읽음 우선, 살아있는 알림 우선)만 남기고 나머지는 soft-delete
		// → (keyword_id, campaign_id) WHERE deleted_at IS NULL 부분 유니크 인덱스 위반 방지
		restoreQuery := `
			WITH target AS (
				SELECT id,
					   ROW_NUMBER() OVER (
						   PARTITION BY keyword_id
						   ORDER BY (deleted_at IS NULL) DESC, is_read DESC, id
					   ) AS rn
				FROM keyword_alerts_alerts
				WHERE id = ANY($2) AND campaign_id IS NULL
			)
			UPDATE keyword_alerts_alerts a
			SET campaign_id = $1,
				deleted_at = CASE WHEN t.rn > 1 THEN COALESCE(a.deleted_at, NOW()) ELSE a.deleted_at END
			FROM target t
			WHERE a.id = t.id
		`
		restoredCount := int64(0)
		for newID, alertIDs := range plan {
			result, err := tx.Exec(ctx, restoreQuery, newID, alertIDs)
			if err != nil {
				return nil, fmt.Errorf("알림 campaign_id 복원 실패: %w", err)
			}
			restoredCount += result.RowsAffected()
		}
		log.Infof("NULL 처리된 알림 %d건의 campaign_id를 새 ID로 복원", restoredCount)
	}

	// 트랜잭션 커밋
	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("트랜잭션 커밋 실패: %w", err)
	}

	log.Infof("DB 저장 완료. 총 %d건 처리 (기존 갱신: %d, 신규: %d)",
		allInsertedCount, deletedCount, len(newCampaignIDs))
	runstats.SetItems(runstats.StageSaved, int(allInsertedCount))
	runstats.SetItems(runstats.StageUpdated, int(deletedCount))
	runstats.SetItems(runstats.StageNew, len(newCampaignIDs))
	return newCampaignIDs, nil
}

// campaignKey 캠페인 동일성 키 (platform, title, offer, campaign_channel)
func campaignKey(c models.Campaign) string {
	return fmt.Sprintf("%s|%s|%s|%s", c.Platform, c.Title, c.Offer, c.CampaignChannel)
}

// buildAlertRestorePlan 새 캠페인 ID → 복원할 알림 ID 목록
//
// oldIDsByKey: 키 → 삭제된 기존 캠페인 ID들, alertIDsByCampaign: 기존 캠페인 ID → 연결돼 있던 알림 ID들,
// newIDByKey: 키 → 새로 INSERT된 캠페인 ID. INSERT에 실패한 키의 알림은 복원 대상에서 제외(NULL 유지).
func buildAlertRestorePlan(oldIDsByKey map[string][]uint, alertIDsByCampaign map[uint][]uint, newIDByKey map[string]uint) map[uint][]uint {
	plan := make(map[uint][]uint)
	for key, oldIDs := range oldIDsByKey {
		newID, ok := newIDByKey[key]
		if !ok {
			continue
		}
		for _, oldID := range oldIDs {
			plan[newID] = append(plan[newID], alertIDsByCampaign[oldID]...)
		}
		if len(plan[newID]) == 0 {
			delete(plan, newID)
		}
	}
	return plan
}

// GetGeocodeCache geocode 캐시 조회
func (db *DB) GetGeocodeCache(ctx context.Context, address string) (lat, lng float64, found bool) {
	log := logger.GetLogger("db")

	if address == "" {
		return 0, 0, false
	}

	hash := sha1Hash(address)
	query := `SELECT lat, lng FROM geocode_cache WHERE address_hash = $1`

	err := db.Pool.QueryRow(ctx, query, hash).Scan(&lat, &lng)
	if err != nil {
		if err == pgx.ErrNoRows {
			log.Infof("[geocode_cache] MISS %s", address)
			return 0, 0, false
		}
		log.Warnf("[geocode_cache] Query error: %v", err)
		return 0, 0, false
	}

	log.Infof("[geocode_cache] HIT %s → (%.6f, %.6f)", address, lat, lng)
	return lat, lng, true
}

// PutGeocodeCache geocode 캐시 저장
func (db *DB) PutGeocodeCache(ctx context.Context, address string, lat, lng float64) error {
	log := logger.GetLogger("db")

	if address == "" {
		return nil
	}

	hash := sha1Hash(address)
	query := `
		INSERT INTO geocode_cache (address_hash, address, lat, lng, updated_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (address_hash) DO UPDATE
		SET address = EXCLUDED.address,
			lat = EXCLUDED.lat,
			lng = EXCLUDED.lng,
			updated_at = NOW()
	`

	_, err := db.Pool.Exec(ctx, query, hash, address, lat, lng)
	if err != nil {
		return fmt.Errorf("failed to put geocode cache: %w", err)
	}

	log.Infof("[geocode_cache] PUT %s → (%.6f, %.6f)", address, lat, lng)
	return nil
}

// GetLocalCache local search 캐시 조회
func (db *DB) GetLocalCache(ctx context.Context, title string) (*models.LocalCacheEntry, bool) {
	log := logger.GetLogger("db")

	if title == "" {
		return nil, false
	}

	hash := sha1Hash(title)
	query := `
		SELECT address, lat, lng, category, updated_at
		FROM local_search_cache
		WHERE title_hash = $1
		AND updated_at > NOW() - INTERVAL '30 days'
	`

	var entry models.LocalCacheEntry
	err := db.Pool.QueryRow(ctx, query, hash).Scan(
		&entry.Address,
		&entry.Lat,
		&entry.Lng,
		&entry.CategoryText, // DB의 category는 text 타입
		&entry.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			log.Infof("[local_cache] MISS %s", title)
			return nil, false
		}
		log.Warnf("[local_cache] Query error: %v", err)
		return nil, false
	}

	log.Infof("[local_cache] HIT %s (updated_at=%v)", title, entry.UpdatedAt)
	return &entry, true
}

// PutLocalCache local search 캐시 저장
// categoryText: 네이버 API에서 받은 원본 카테고리 문자열 (DB에 text로 저장)
func (db *DB) PutLocalCache(ctx context.Context, title, address string, lat, lng float64, categoryText *string) error {
	log := logger.GetLogger("db")

	if title == "" {
		return nil
	}

	hash := sha1Hash(title)
	query := `
		INSERT INTO local_search_cache (title_hash, title, address, lat, lng, category, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW())
		ON CONFLICT (title_hash) DO UPDATE
		SET address = EXCLUDED.address,
			lat = EXCLUDED.lat,
			lng = EXCLUDED.lng,
			category = EXCLUDED.category,
			updated_at = NOW()
	`

	_, err := db.Pool.Exec(ctx, query, hash, title, address, lat, lng, categoryText)
	if err != nil {
		return fmt.Errorf("failed to put local cache: %w", err)
	}

	log.Infof("[local_cache] PUT %s → (%.6f, %.6f)", title, lat, lng)
	return nil
}

// GetOrCreateRawCategory raw_categories 테이블에서 ID 조회 또는 생성
func (db *DB) GetOrCreateRawCategory(ctx context.Context, rawText string) (*int64, error) {
	log := logger.GetLogger("db")

	if rawText == "" {
		return nil, nil
	}

	// 먼저 ID를 조회
	var id int64
	findQuery := `SELECT id FROM raw_categories WHERE raw_text = $1`
	err := db.Pool.QueryRow(ctx, findQuery, rawText).Scan(&id)
	if err == nil {
		return &id, nil
	}
	if err != pgx.ErrNoRows {
		return nil, fmt.Errorf("failed to find raw category: %w", err)
	}

	// 없으면 새로 생성
	log.Infof("새로운 원본 카테고리 발견: '%s'", rawText)
	insertQuery := `
		INSERT INTO raw_categories (raw_text) VALUES ($1)
		ON CONFLICT (raw_text) DO NOTHING
		RETURNING id
	`
	err = db.Pool.QueryRow(ctx, insertQuery, rawText).Scan(&id)
	if err == pgx.ErrNoRows {
		// ON CONFLICT DO NOTHING으로 INSERT가 안됐을 수 있으므로 다시 조회
		err = db.Pool.QueryRow(ctx, findQuery, rawText).Scan(&id)
		if err != nil {
			return nil, fmt.Errorf("failed to get raw category after insert: %w", err)
		}
	} else if err != nil {
		return nil, fmt.Errorf("failed to insert raw category: %w", err)
	}

	return &id, nil
}

// FindMappedCategoryID category_mappings 테이블에서 매핑된 standard_category_id 찾기
func (db *DB) FindMappedCategoryID(ctx context.Context, rawCategoryID int64) (*int64, error) {
	query := `SELECT standard_category_id FROM category_mappings WHERE raw_category_id = $1`

	var mappedID int64
	err := db.Pool.QueryRow(ctx, query, rawCategoryID).Scan(&mappedID)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to find mapped category: %w", err)
	}

	return &mappedID, nil
}

// sha1Hash SHA1 해시 생성
func sha1Hash(s string) []byte {
	h := sha1.New()
	h.Write([]byte(s))
	return h.Sum(nil)
}

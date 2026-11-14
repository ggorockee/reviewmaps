package services

import (
	"context"
	"fmt"
	"log"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
	"github.com/ggorockee/reviewmaps/server/pkg/firebase"
	"gorm.io/gorm/clause"
)

// KeywordMatchService handles keyword matching and alert creation
type KeywordMatchService struct {
	db *database.DB
}

// NewKeywordMatchService creates a new KeywordMatchService
func NewKeywordMatchService(db *database.DB) *KeywordMatchService {
	return &KeywordMatchService{db: db}
}

var nonAlphanumericRegex = regexp.MustCompile(`[^\w가-힣]`)

// normalizeText removes whitespace and special characters, converts to lowercase
func normalizeText(text string) string {
	if text == "" {
		return ""
	}
	// Remove whitespace and special characters (keep Korean, English, numbers)
	normalized := nonAlphanumericRegex.ReplaceAllString(strings.ToLower(text), "")
	return normalized
}

const (
	// matchCampaignChunkSize 한 번의 IN 조회에 넣을 최대 캠페인 수 (Postgres 파라미터 한도 여유 확보)
	matchCampaignChunkSize = 1000
	// alertInsertBatchSize 알림 일괄 INSERT 1회당 최대 행 수
	alertInsertBatchSize = 500
)

// AlertKey (키워드, 캠페인) 조합 — 기존 알림 중복 판정용
type AlertKey struct {
	KeywordID  uint
	CampaignID uint
}

// PreparedKeyword 정규화를 미리 끝낸 활성 키워드
type PreparedKeyword struct {
	ID         uint
	Keyword    string
	Normalized string
	CreatedAt  time.Time
}

// PrepareKeywords 활성 키워드를 1회만 정규화 (정규화 결과가 빈 키워드는 매칭 대상에서 제외)
func PrepareKeywords(keywords []models.Keyword) []PreparedKeyword {
	prepared := make([]PreparedKeyword, 0, len(keywords))
	for _, kw := range keywords {
		normalized := normalizeText(kw.Keyword)
		if normalized == "" {
			continue
		}
		prepared = append(prepared, PreparedKeyword{
			ID:         kw.ID,
			Keyword:    kw.Keyword,
			Normalized: normalized,
			CreatedAt:  kw.CreatedAt,
		})
	}
	return prepared
}

// MatchKeywordAlerts 캠페인 × 키워드 매칭으로 생성할 알림 목록 계산 (DB 접근 없음)
//
// 매칭 규칙:
//   - 이미 알림이 있는 (키워드, 캠페인) 조합은 제외 (soft-deleted 포함 — existing에 반영)
//   - 키워드 등록 시점보다 먼저 생성된 캠페인은 제외
//   - 제목(title) 우선, 없으면 제공내역(offer)에서 부분 일치 (정규화 후 비교)
func MatchKeywordAlerts(campaigns []models.Campaign, keywords []PreparedKeyword, existing map[AlertKey]struct{}) []models.KeywordAlert {
	var alerts []models.KeywordAlert

	for i := range campaigns {
		campaign := &campaigns[i]

		var titleNormalized string
		if campaign.Title != nil {
			titleNormalized = normalizeText(*campaign.Title)
		}
		offerNormalized := normalizeText(campaign.Offer)

		for _, kw := range keywords {
			if _, ok := existing[AlertKey{KeywordID: kw.ID, CampaignID: campaign.ID}]; ok {
				continue
			}
			if campaign.CreatedAt.Before(kw.CreatedAt) {
				continue
			}

			var matchedField string
			if titleNormalized != "" && strings.Contains(titleNormalized, kw.Normalized) {
				matchedField = "title"
			} else if strings.Contains(offerNormalized, kw.Normalized) {
				matchedField = "offer"
			}
			if matchedField == "" {
				continue
			}

			campaignID := campaign.ID
			alerts = append(alerts, models.KeywordAlert{
				KeywordID:    kw.ID,
				CampaignID:   &campaignID,
				MatchedField: matchedField,
				IsRead:       false,
			})
		}
	}

	return alerts
}

// ProcessCampaignsKeywordMatching 여러 캠페인을 한 번에 키워드 매칭하고 생성된 알림 ID 반환
//
// 캠페인 수와 무관하게 활성 키워드 조회 1회, 청크(1000개)당 캠페인/기존 알림 조회 각 1회,
// 알림 일괄 INSERT로 처리합니다. (기존: 캠페인 1개당 쿼리 3~4회 + 키워드별 goroutine)
//
// 동시 요청으로 같은 (키워드, 캠페인) 알림이 경합하면 유니크 인덱스 충돌은 무시(ON CONFLICT DO NOTHING)하고,
// 실제로 INSERT된 알림 ID만 반환하여 중복 푸시를 방지합니다.
func (s *KeywordMatchService) ProcessCampaignsKeywordMatching(ctx context.Context, campaignIDs []uint) ([]uint, error) {
	campaignIDs = uniqueIDs(campaignIDs)
	if len(campaignIDs) == 0 {
		return nil, nil
	}

	db := s.db.WithContext(ctx)

	var activeKeywords []models.Keyword
	if err := db.Where("is_active = ?", true).Find(&activeKeywords).Error; err != nil {
		return nil, fmt.Errorf("활성 키워드 조회 실패: %w", err)
	}
	keywords := PrepareKeywords(activeKeywords)
	if len(keywords) == 0 {
		log.Printf("[KeywordMatch] No active keywords found")
		return nil, nil
	}

	keywordIDs := make([]uint, len(keywords))
	for i, kw := range keywords {
		keywordIDs[i] = kw.ID
	}

	var createdIDs []uint
	var foundCampaigns, matchedAlerts int

	for start := 0; start < len(campaignIDs); start += matchCampaignChunkSize {
		chunk := campaignIDs[start:min(start+matchCampaignChunkSize, len(campaignIDs))]

		// 매칭에 필요한 컬럼만 조회
		var campaigns []models.Campaign
		if err := db.Select("id", "title", "offer", "created_at").
			Where("id IN ?", chunk).Find(&campaigns).Error; err != nil {
			return createdIDs, fmt.Errorf("캠페인 조회 실패: %w", err)
		}
		foundCampaigns += len(campaigns)
		if len(campaigns) == 0 {
			continue
		}

		// Unscoped(): soft-deleted 포함 → 유저가 삭제한 알림도 재생성 방지
		var existingAlerts []models.KeywordAlert
		if err := db.Unscoped().Select("keyword_id", "campaign_id").
			Where("campaign_id IN ? AND keyword_id IN ?", chunk, keywordIDs).
			Find(&existingAlerts).Error; err != nil {
			return createdIDs, fmt.Errorf("기존 알림 조회 실패: %w", err)
		}
		existing := make(map[AlertKey]struct{}, len(existingAlerts))
		for _, a := range existingAlerts {
			if a.CampaignID != nil {
				existing[AlertKey{KeywordID: a.KeywordID, CampaignID: *a.CampaignID}] = struct{}{}
			}
		}

		alerts := MatchKeywordAlerts(campaigns, keywords, existing)
		if len(alerts) == 0 {
			continue
		}
		matchedAlerts += len(alerts)

		if err := db.Clauses(clause.OnConflict{DoNothing: true}).
			CreateInBatches(&alerts, alertInsertBatchSize).Error; err != nil {
			return createdIDs, fmt.Errorf("알림 생성 실패: %w", err)
		}

		// ON CONFLICT로 건너뛴 행은 ID가 채워지지 않으므로 0이 아닌 ID만 수집
		// (RETURNING 결과가 순서대로 매핑되므로 행-ID 대응은 보장되지 않지만, ID 집합은 정확함)
		for _, a := range alerts {
			if a.ID != 0 {
				createdIDs = append(createdIDs, a.ID)
			}
		}
	}

	if missing := len(campaignIDs) - foundCampaigns; missing > 0 {
		log.Printf("[KeywordMatch] %d campaigns not found (requested %d)", missing, len(campaignIDs))
	}
	log.Printf("[KeywordMatch] Matched %d campaigns × %d keywords → %d matches, %d alerts created",
		foundCampaigns, len(keywords), matchedAlerts, len(createdIDs))

	return createdIDs, nil
}

// uniqueIDs 순서를 유지하며 중복 ID 제거
func uniqueIDs(ids []uint) []uint {
	seen := make(map[uint]struct{}, len(ids))
	out := make([]uint, 0, len(ids))
	for _, id := range ids {
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}

// SendPushForRecentAlerts sends push notifications for recently created alerts
// Call this after batch processing to avoid duplicate pushes
func (s *KeywordMatchService) SendPushForRecentAlerts(ctx context.Context, alertIDs []uint) {
	if len(alertIDs) == 0 {
		return
	}

	log.Printf("[KeywordMatch] Sending push for %d alerts", len(alertIDs))

	// Get alerts with keyword and campaign info
	var alerts []models.KeywordAlert
	if err := s.db.Preload("Keyword").Preload("Campaign").Where("id IN ?", alertIDs).Find(&alerts).Error; err != nil {
		log.Printf("[KeywordMatch] Failed to get alerts: %v", err)
		return
	}

	if len(alerts) == 0 {
		return
	}

	fcm := firebase.GetFCMService()
	if !fcm.IsInitialized() {
		log.Println("[KeywordMatch] FCM not initialized, skipping push")
		return
	}

	// Group alerts by user
	userAlerts := make(map[uint][]models.KeywordAlert)
	for _, alert := range alerts {
		if alert.Keyword.UserID != nil {
			userAlerts[*alert.Keyword.UserID] = append(userAlerts[*alert.Keyword.UserID], alert)
		}
	}

	if len(userAlerts) == 0 {
		log.Println("[KeywordMatch] No user alerts found for push")
		return
	}

	// Get user IDs
	userIDs := make([]uint, 0, len(userAlerts))
	for userID := range userAlerts {
		userIDs = append(userIDs, userID)
	}

	// Get active FCM tokens
	var devices []models.FCMDevice
	if err := s.db.Where("user_id IN ? AND is_active = ?", userIDs, true).Find(&devices).Error; err != nil {
		log.Printf("[KeywordMatch] Failed to get FCM devices: %v", err)
		return
	}

	if len(devices) == 0 {
		log.Println("[KeywordMatch] No active FCM tokens found")
		return
	}

	// Group devices by user
	userDevices := make(map[uint][]string)
	for _, device := range devices {
		if device.UserID != nil {
			userDevices[*device.UserID] = append(userDevices[*device.UserID], device.FCMToken)
		}
	}

	// Send push per user per keyword
	var totalSuccess, totalFailure int
	var allFailedTokens []string

	for userID, tokens := range userDevices {
		alerts := userAlerts[userID]
		if len(alerts) == 0 || len(tokens) == 0 {
			continue
		}

		// Group alerts by keyword
		keywordAlerts := make(map[string]int)
		for _, alert := range alerts {
			keywordAlerts[alert.Keyword.Keyword]++
		}

		// Send one push per keyword
		for keyword, count := range keywordAlerts {
			title := fmt.Sprintf("\"%s\" 체험단 등록", keyword)
			body := fmt.Sprintf("%d건의 새로운 체험단이 등록되었습니다. 리뷰맵에서 확인해보세요!", count)

			data := map[string]string{
				"type":        "keyword_alert",
				"keyword":     keyword,
				"alert_count": strconv.Itoa(count),
			}

			result := fcm.SendPushMultiple(ctx, tokens, title, body, data)
			totalSuccess += result.SuccessCount
			totalFailure += result.FailureCount
			allFailedTokens = append(allFailedTokens, result.FailedTokens...)

			log.Printf("[KeywordMatch] Push sent to user %d - keyword: '%s', count: %d, success: %d, failure: %d",
				userID, keyword, count, result.SuccessCount, result.FailureCount)
		}
	}

	log.Printf("[KeywordMatch] Push total - success: %d, failure: %d", totalSuccess, totalFailure)

	// Deactivate failed tokens (only once)
	if len(allFailedTokens) > 0 {
		s.db.Model(&models.FCMDevice{}).Where("fcm_token IN ?", allFailedTokens).Update("is_active", false)
		log.Printf("[KeywordMatch] Deactivated %d invalid tokens", len(allFailedTokens))
	}
}

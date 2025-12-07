package services

import (
	"context"
	"log"
	"regexp"
	"strings"
	"sync"

	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
	"github.com/ggorockee/reviewmaps/server/pkg/firebase"
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

// MatchResult represents a keyword match
type MatchResult struct {
	KeywordID    uint
	MatchedField string
}

// ProcessCampaignKeywordMatching matches keywords against a new campaign
func (s *KeywordMatchService) ProcessCampaignKeywordMatching(ctx context.Context, campaign *models.Campaign) {
	log.Printf("[KeywordMatch] Processing campaign ID: %d", campaign.ID)

	// Get all active keywords
	var activeKeywords []models.Keyword
	if err := s.db.Where("is_active = ?", true).Find(&activeKeywords).Error; err != nil {
		log.Printf("[KeywordMatch] Failed to get active keywords: %v", err)
		return
	}

	if len(activeKeywords) == 0 {
		log.Printf("[KeywordMatch] No active keywords found")
		return
	}

	log.Printf("[KeywordMatch] Active keywords count: %d", len(activeKeywords))

	// Normalize campaign text
	companyNormalized := normalizeText(campaign.Company)
	var titleNormalized string
	if campaign.Title != nil {
		titleNormalized = normalizeText(*campaign.Title)
	}
	offerNormalized := normalizeText(campaign.Offer)

	// Get existing alerts to avoid duplicates
	keywordIDs := make([]uint, len(activeKeywords))
	for i, kw := range activeKeywords {
		keywordIDs[i] = kw.ID
	}

	var existingAlerts []models.KeywordAlert
	s.db.Where("keyword_id IN ? AND campaign_id = ?", keywordIDs, campaign.ID).Find(&existingAlerts)

	existingMap := make(map[uint]bool)
	for _, alert := range existingAlerts {
		existingMap[alert.KeywordID] = true
	}

	// Match keywords in parallel
	var alertsToCreate []models.KeywordAlert
	var mu sync.Mutex
	var wg sync.WaitGroup

	for _, keyword := range activeKeywords {
		if existingMap[keyword.ID] {
			continue
		}

		wg.Add(1)
		go func(kw models.Keyword) {
			defer wg.Done()

			keywordNormalized := normalizeText(kw.Keyword)
			if keywordNormalized == "" {
				return
			}

			var matchedField string

			// Match against company
			if strings.Contains(companyNormalized, keywordNormalized) {
				matchedField = "company"
			} else if titleNormalized != "" && strings.Contains(titleNormalized, keywordNormalized) {
				matchedField = "title"
			} else if strings.Contains(offerNormalized, keywordNormalized) {
				matchedField = "offer"
			}

			if matchedField != "" {
				mu.Lock()
				alertsToCreate = append(alertsToCreate, models.KeywordAlert{
					KeywordID:  kw.ID,
					CampaignID: campaign.ID,
					IsRead:     false,
					IsSent:     false,
				})
				mu.Unlock()
				log.Printf("[KeywordMatch] Matched - keyword: '%s' → %s", kw.Keyword, matchedField)
			}
		}(keyword)
	}

	wg.Wait()

	// Bulk create alerts
	if len(alertsToCreate) > 0 {
		if err := s.db.Create(&alertsToCreate).Error; err != nil {
			log.Printf("[KeywordMatch] Failed to create alerts: %v", err)
			return
		}
		log.Printf("[KeywordMatch] Created %d alerts for campaign ID: %d", len(alertsToCreate), campaign.ID)

		// Send push notifications
		go s.sendPushNotifications(ctx, alertsToCreate, campaign)
	} else {
		log.Printf("[KeywordMatch] No keywords matched for campaign ID: %d", campaign.ID)
	}
}

// sendPushNotifications sends FCM push to matched keyword owners
func (s *KeywordMatchService) sendPushNotifications(ctx context.Context, alerts []models.KeywordAlert, campaign *models.Campaign) {
	fcm := firebase.GetFCMService()
	if !fcm.IsInitialized() {
		log.Println("[KeywordMatch] FCM not initialized, skipping push")
		return
	}

	// Get unique user IDs from alerts
	keywordIDs := make([]uint, len(alerts))
	for i, alert := range alerts {
		keywordIDs[i] = alert.KeywordID
	}

	var keywords []models.Keyword
	if err := s.db.Where("id IN ?", keywordIDs).Find(&keywords).Error; err != nil {
		log.Printf("[KeywordMatch] Failed to get keywords: %v", err)
		return
	}

	userIDs := make([]uint, 0)
	for _, kw := range keywords {
		userIDs = append(userIDs, kw.UserID)
	}

	if len(userIDs) == 0 {
		log.Println("[KeywordMatch] No user IDs found for push")
		return
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

	// Collect unique tokens
	tokenSet := make(map[string]bool)
	for _, device := range devices {
		tokenSet[device.Token] = true
	}

	tokens := make([]string, 0, len(tokenSet))
	for token := range tokenSet {
		tokens = append(tokens, token)
	}

	log.Printf("[KeywordMatch] Sending push to %d devices", len(tokens))

	// Send push notifications
	title := "새로운 체험단 알림"
	body := "관심 키워드와 매칭되는 캠페인이 등록되었습니다. 앱에서 확인해보세요."
	data := map[string]string{
		"type":        "keyword_alert",
		"campaign_id": string(rune(campaign.ID)),
	}

	result := fcm.SendPushMultiple(ctx, tokens, title, body, data)
	log.Printf("[KeywordMatch] Push result - success: %d, failure: %d", result.SuccessCount, result.FailureCount)

	// Deactivate failed tokens
	if len(result.FailedTokens) > 0 {
		s.db.Model(&models.FCMDevice{}).Where("token IN ?", result.FailedTokens).Update("is_active", false)
		log.Printf("[KeywordMatch] Deactivated %d invalid tokens", len(result.FailedTokens))
	}

	// Mark alerts as sent
	alertIDs := make([]uint, len(alerts))
	for i, alert := range alerts {
		alertIDs[i] = alert.ID
	}
	s.db.Model(&models.KeywordAlert{}).Where("id IN ?", alertIDs).Update("is_sent", true)
}

// ProcessCampaignKeywordMatchingByID processes keyword matching for a campaign by its ID
// Returns the number of alerts created
func (s *KeywordMatchService) ProcessCampaignKeywordMatchingByID(ctx context.Context, campaignID uint) int {
	log.Printf("[KeywordMatch] Processing campaign by ID: %d", campaignID)

	// Get campaign from DB
	var campaign models.Campaign
	if err := s.db.First(&campaign, campaignID).Error; err != nil {
		log.Printf("[KeywordMatch] Failed to get campaign ID %d: %v", campaignID, err)
		return 0
	}

	// Get all active keywords
	var activeKeywords []models.Keyword
	if err := s.db.Where("is_active = ?", true).Find(&activeKeywords).Error; err != nil {
		log.Printf("[KeywordMatch] Failed to get active keywords: %v", err)
		return 0
	}

	if len(activeKeywords) == 0 {
		log.Printf("[KeywordMatch] No active keywords found")
		return 0
	}

	log.Printf("[KeywordMatch] Active keywords count: %d", len(activeKeywords))

	// Normalize campaign text (title + offer)
	var titleNormalized string
	if campaign.Title != nil {
		titleNormalized = normalizeText(*campaign.Title)
	}
	offerNormalized := normalizeText(campaign.Offer)

	// Get existing alerts to avoid duplicates
	keywordIDs := make([]uint, len(activeKeywords))
	for i, kw := range activeKeywords {
		keywordIDs[i] = kw.ID
	}

	var existingAlerts []models.KeywordAlert
	s.db.Where("keyword_id IN ? AND campaign_id = ?", keywordIDs, campaign.ID).Find(&existingAlerts)

	existingMap := make(map[uint]bool)
	for _, alert := range existingAlerts {
		existingMap[alert.KeywordID] = true
	}

	// Match keywords in parallel
	var alertsToCreate []models.KeywordAlert
	var mu sync.Mutex
	var wg sync.WaitGroup

	for _, keyword := range activeKeywords {
		if existingMap[keyword.ID] {
			continue
		}

		// 키워드 등록 시점보다 나중에 생성된 캠페인만 매칭
		if campaign.CreatedAt.Before(keyword.CreatedAt) {
			continue
		}

		wg.Add(1)
		go func(kw models.Keyword) {
			defer wg.Done()

			keywordNormalized := normalizeText(kw.Keyword)
			if keywordNormalized == "" {
				return
			}

			var matchedField string

			// Match against title and offer only (as per user requirement)
			if titleNormalized != "" && strings.Contains(titleNormalized, keywordNormalized) {
				matchedField = "title"
			} else if strings.Contains(offerNormalized, keywordNormalized) {
				matchedField = "offer"
			}

			if matchedField != "" {
				mu.Lock()
				alertsToCreate = append(alertsToCreate, models.KeywordAlert{
					KeywordID:  kw.ID,
					CampaignID: campaign.ID,
					IsRead:     false,
					IsSent:     false,
				})
				mu.Unlock()
				log.Printf("[KeywordMatch] Matched - keyword: '%s' → %s", kw.Keyword, matchedField)
			}
		}(keyword)
	}

	wg.Wait()

	// Bulk create alerts
	if len(alertsToCreate) > 0 {
		if err := s.db.Create(&alertsToCreate).Error; err != nil {
			log.Printf("[KeywordMatch] Failed to create alerts: %v", err)
			return 0
		}
		log.Printf("[KeywordMatch] Created %d alerts for campaign ID: %d", len(alertsToCreate), campaign.ID)

		// Send push notifications
		go s.sendPushNotifications(ctx, alertsToCreate, &campaign)
		return len(alertsToCreate)
	}

	log.Printf("[KeywordMatch] No keywords matched for campaign ID: %d", campaign.ID)
	return 0
}

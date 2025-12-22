package services

import (
	"errors"
	"math"
	"sort"
	"time"

	"github.com/ggorockee/reviewmaps/server/internal/config"
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
)

type KeywordAlertService struct {
	db  *database.DB
	cfg *config.Config
}

func NewKeywordAlertService(db *database.DB, cfg *config.Config) *KeywordAlertService {
	return &KeywordAlertService{db: db, cfg: cfg}
}

type CreateKeywordRequest struct {
	Keyword string `json:"keyword"`
}

type MarkReadRequest struct {
	AlertIDs []uint `json:"alert_ids"`
}

type FCMRegisterRequest struct {
	Token    string `json:"fcm_token"`
	Platform string `json:"device_type"`
}

type FCMUnregisterRequest struct {
	Token string `json:"token"`
}

type AlertWithDistance struct {
	models.KeywordAlert
	Distance *float64 `json:"distance,omitempty"` // Distance in kilometers
}

type AlertListResponse struct {
	Items       []AlertWithDistance `json:"items"`
	Total       int64               `json:"total"`
	Page        int                 `json:"page"`
	Limit       int                 `json:"limit"`
	TotalPages  int                 `json:"total_pages"`
	UnreadCount int64               `json:"unread_count"`
}

// CreateKeyword creates a new keyword for a user
func (s *KeywordAlertService) CreateKeyword(userID uint, req *CreateKeywordRequest) (*models.Keyword, error) {
	// Check keyword limit
	var count int64
	s.db.Model(&models.Keyword{}).Where("user_id = ?", userID).Count(&count)

	// Get limit from settings (default 10)
	limit := 10
	var setting models.AppSetting
	if err := s.db.Where("key = ?", "keyword_limit").First(&setting).Error; err == nil {
		// Parse limit from setting
	}

	if int(count) >= limit {
		return nil, errors.New("keyword limit reached")
	}

	keyword := models.Keyword{
		UserID:   &userID,
		Keyword:  req.Keyword,
		IsActive: true,
	}

	if err := s.db.Create(&keyword).Error; err != nil {
		return nil, err
	}

	return &keyword, nil
}

// ListKeywords retrieves all keywords for a user
func (s *KeywordAlertService) ListKeywords(userID uint) ([]models.Keyword, error) {
	var keywords []models.Keyword
	err := s.db.Where("user_id = ?", userID).Order("created_at DESC").Find(&keywords).Error
	return keywords, err
}

// DeleteKeyword deletes a keyword
func (s *KeywordAlertService) DeleteKeyword(userID, keywordID uint) error {
	result := s.db.Where("id = ? AND user_id = ?", keywordID, userID).Delete(&models.Keyword{})
	if result.RowsAffected == 0 {
		return errors.New("keyword not found")
	}
	return result.Error
}

// ToggleKeyword toggles keyword active status
func (s *KeywordAlertService) ToggleKeyword(userID, keywordID uint) (*models.Keyword, error) {
	var keyword models.Keyword
	if err := s.db.Where("id = ? AND user_id = ?", keywordID, userID).First(&keyword).Error; err != nil {
		return nil, errors.New("keyword not found")
	}

	keyword.IsActive = !keyword.IsActive
	if err := s.db.Save(&keyword).Error; err != nil {
		return nil, err
	}

	return &keyword, nil
}

// ListAlerts retrieves alerts for a user with optional distance calculation and sorting
func (s *KeywordAlertService) ListAlerts(userID uint, page, limit int, lat, lng *float64, sortBy string) (*AlertListResponse, error) {
	var alerts []models.KeywordAlert
	var total int64

	// Get user's keyword IDs
	var keywordIDs []uint
	s.db.Model(&models.Keyword{}).Where("user_id = ?", userID).Pluck("id", &keywordIDs)

	// Return empty if no keywords
	if len(keywordIDs) == 0 {
		return &AlertListResponse{
			Items:       []AlertWithDistance{},
			Total:       0,
			Page:        page,
			Limit:       limit,
			TotalPages:  0,
			UnreadCount: 0,
		}, nil
	}

	// Get alert retention days from app settings (default 3 days)
	appConfigService := NewAppConfigService(s.db)
	retentionDays, _ := appConfigService.GetAlertRetentionDays()

	// Calculate retention cutoff time
	retentionCutoff := time.Now().AddDate(0, 0, -retentionDays)

	query := s.db.Model(&models.KeywordAlert{}).
		Preload("Keyword").
		Preload("Campaign").
		Preload("Campaign.Category").
		Where("keyword_id IN ?", keywordIDs).
		Where("created_at >= ?", retentionCutoff)

	query.Count(&total)

	// Count unread alerts
	var unreadCount int64
	s.db.Model(&models.KeywordAlert{}).
		Where("keyword_id IN ?", keywordIDs).
		Where("is_read = ?", false).
		Where("created_at >= ?", retentionCutoff).
		Count(&unreadCount)

	// Apply sorting (distance sorting will be done in memory after calculation)
	orderClause := "created_at DESC"
	if sortBy == "created_at" {
		orderClause = "created_at DESC"
	}

	offset := (page - 1) * limit
	if err := query.Order(orderClause).Offset(offset).Limit(limit).Find(&alerts).Error; err != nil {
		return nil, err
	}

	// Calculate distances and create response items
	items := make([]AlertWithDistance, len(alerts))
	for i, alert := range alerts {
		item := AlertWithDistance{
			KeywordAlert: alert,
		}

		// Calculate distance if lat/lng provided and campaign has location
		if lat != nil && lng != nil && alert.Campaign != nil {
			if alert.Campaign.Lat != nil && alert.Campaign.Lng != nil {
				distance := calculateDistance(*lat, *lng, *alert.Campaign.Lat, *alert.Campaign.Lng)
				item.Distance = &distance
			}
		}

		items[i] = item
	}

	// Sort by distance if requested (in-memory sort after distance calculation)
	if sortBy == "distance" && lat != nil && lng != nil {
		// Stable sort: items with distance first (sorted by distance), then items without distance
		sortAlertsByDistance(items)
	}

	totalPages := int(total) / limit
	if int(total)%limit > 0 {
		totalPages++
	}

	return &AlertListResponse{
		Items:       items,
		Total:       total,
		Page:        page,
		Limit:       limit,
		TotalPages:  totalPages,
		UnreadCount: unreadCount,
	}, nil
}

// MarkAlertsRead marks alerts as read
func (s *KeywordAlertService) MarkAlertsRead(userID uint, alertIDs []uint) (int64, error) {
	// Verify ownership through keywords
	var keywordIDs []uint
	s.db.Model(&models.Keyword{}).Where("user_id = ?", userID).Pluck("id", &keywordIDs)

	result := s.db.Model(&models.KeywordAlert{}).
		Where("id IN ? AND keyword_id IN ?", alertIDs, keywordIDs).
		Update("is_read", true)

	return result.RowsAffected, result.Error
}

// DeleteAlert deletes an alert
func (s *KeywordAlertService) DeleteAlert(userID, alertID uint) error {
	var keywordIDs []uint
	s.db.Model(&models.Keyword{}).Where("user_id = ?", userID).Pluck("id", &keywordIDs)

	result := s.db.Where("id = ? AND keyword_id IN ?", alertID, keywordIDs).Delete(&models.KeywordAlert{})
	if result.RowsAffected == 0 {
		return errors.New("alert not found")
	}
	return result.Error
}

// RegisterFCM registers an FCM token
func (s *KeywordAlertService) RegisterFCM(userID uint, req *FCMRegisterRequest) (*models.FCMDevice, error) {
	// 1. 같은 user_id + device_type의 기존 토큰 비활성화
	s.db.Model(&models.FCMDevice{}).
		Where("user_id = ? AND device_type = ? AND fcm_token != ?", userID, req.Platform, req.Token).
		Update("is_active", false)

	// 2. 토큰으로 기존 디바이스 조회
	var device models.FCMDevice
	err := s.db.Where("fcm_token = ?", req.Token).First(&device).Error

	if err != nil {
		// Create new
		device = models.FCMDevice{
			UserID:     &userID,
			FCMToken:   req.Token,
			DeviceType: req.Platform,
			IsActive:   true,
		}
		if err := s.db.Create(&device).Error; err != nil {
			return nil, err
		}
	} else {
		// Update existing - 다른 유저가 사용하던 토큰이면 현재 유저로 변경
		device.UserID = &userID
		device.DeviceType = req.Platform
		device.IsActive = true
		if err := s.db.Save(&device).Error; err != nil {
			return nil, err
		}
	}

	return &device, nil
}

// UnregisterFCM unregisters an FCM token
func (s *KeywordAlertService) UnregisterFCM(userID uint, token string) error {
	result := s.db.Where("user_id = ? AND fcm_token = ?", userID, token).Delete(&models.FCMDevice{})
	if result.RowsAffected == 0 {
		return errors.New("device not found")
	}
	return result.Error
}

// calculateDistance calculates the distance between two coordinates using Haversine formula
// Returns distance in kilometers
func calculateDistance(lat1, lng1, lat2, lng2 float64) float64 {
	const earthRadius = 6371.0 // Earth radius in kilometers

	// Convert degrees to radians
	lat1Rad := lat1 * math.Pi / 180
	lng1Rad := lng1 * math.Pi / 180
	lat2Rad := lat2 * math.Pi / 180
	lng2Rad := lng2 * math.Pi / 180

	// Haversine formula
	dLat := lat2Rad - lat1Rad
	dLng := lng2Rad - lng1Rad

	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1Rad)*math.Cos(lat2Rad)*
			math.Sin(dLng/2)*math.Sin(dLng/2)

	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	distance := earthRadius * c

	return distance
}

// sortAlertsByDistance sorts alerts by distance (items with distance first, then items without)
func sortAlertsByDistance(items []AlertWithDistance) {
	sort.SliceStable(items, func(i, j int) bool {
		// Items with distance come before items without distance
		if items[i].Distance == nil && items[j].Distance != nil {
			return false
		}
		if items[i].Distance != nil && items[j].Distance == nil {
			return true
		}

		// Both have distance: sort by distance value
		if items[i].Distance != nil && items[j].Distance != nil {
			return *items[i].Distance < *items[j].Distance
		}

		// Both have no distance: maintain original order (stable sort)
		return false
	})
}

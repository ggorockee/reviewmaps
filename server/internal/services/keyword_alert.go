package services

import (
	"errors"

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
	Token    string `json:"token"`
	Platform string `json:"platform"`
}

type FCMUnregisterRequest struct {
	Token string `json:"token"`
}

type AlertListResponse struct {
	Items      []models.KeywordAlert `json:"items"`
	Total      int64                 `json:"total"`
	Page       int                   `json:"page"`
	Limit      int                   `json:"limit"`
	TotalPages int                   `json:"total_pages"`
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

// ListAlerts retrieves alerts for a user
func (s *KeywordAlertService) ListAlerts(userID uint, page, limit int) (*AlertListResponse, error) {
	var alerts []models.KeywordAlert
	var total int64

	// Get user's keyword IDs
	var keywordIDs []uint
	s.db.Model(&models.Keyword{}).Where("user_id = ?", userID).Pluck("id", &keywordIDs)

	query := s.db.Model(&models.KeywordAlert{}).
		Preload("Keyword").
		Preload("Campaign").
		Preload("Campaign.Category").
		Where("keyword_id IN ?", keywordIDs)

	query.Count(&total)

	offset := (page - 1) * limit
	if err := query.Order("created_at DESC").Offset(offset).Limit(limit).Find(&alerts).Error; err != nil {
		return nil, err
	}

	totalPages := int(total) / limit
	if int(total)%limit > 0 {
		totalPages++
	}

	return &AlertListResponse{
		Items:      alerts,
		Total:      total,
		Page:       page,
		Limit:      limit,
		TotalPages: totalPages,
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
	// Upsert: update if exists, create if not
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
		// Update existing
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

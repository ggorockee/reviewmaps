package services

import (
	"errors"
	"strconv"

	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
)

type AppConfigService struct {
	db *database.DB
}

func NewAppConfigService(db *database.DB) *AppConfigService {
	return &AppConfigService{db: db}
}

type VersionCheckResponse struct {
	NeedsUpdate     bool    `json:"needs_update"`
	ForceUpdate     bool    `json:"force_update"`
	LatestVersion   string  `json:"latest_version"`
	MinVersion      string  `json:"min_version"`
	UpdateMessage   *string `json:"update_message,omitempty"`
	StoreURL        *string `json:"store_url,omitempty"`
	MaintenanceMode bool    `json:"maintenance_mode"`
}

type SetKeywordLimitRequest struct {
	Limit int `json:"limit"`
}

// GetAdConfigs retrieves ad configurations
func (s *AppConfigService) GetAdConfigs(platform string) ([]models.AdConfig, error) {
	var configs []models.AdConfig
	query := s.db.Where("is_active = ?", true)

	if platform != "" {
		query = query.Where("platform = ?", platform)
	}

	err := query.Find(&configs).Error
	return configs, err
}

// CheckVersion checks app version against requirements
func (s *AppConfigService) CheckVersion(platform, currentVersion string) (*VersionCheckResponse, error) {
	var appVersion models.AppVersion
	if err := s.db.Where("platform = ?", platform).First(&appVersion).Error; err != nil {
		return nil, errors.New("platform not found")
	}

	needsUpdate := compareVersions(currentVersion, appVersion.LatestVersion) < 0
	forceUpdate := compareVersions(currentVersion, appVersion.MinVersion) < 0

	return &VersionCheckResponse{
		NeedsUpdate:     needsUpdate,
		ForceUpdate:     forceUpdate || appVersion.ForceUpdate,
		LatestVersion:   appVersion.LatestVersion,
		MinVersion:      appVersion.MinVersion,
		UpdateMessage:   appVersion.UpdateMessage,
		StoreURL:        appVersion.StoreURL,
		MaintenanceMode: appVersion.MaintenanceMode,
	}, nil
}

// ListSettings retrieves all app settings
func (s *AppConfigService) ListSettings() ([]models.AppSetting, error) {
	var settings []models.AppSetting
	err := s.db.Find(&settings).Error
	return settings, err
}

// GetSetting retrieves a specific setting
func (s *AppConfigService) GetSetting(key string) (*models.AppSetting, error) {
	var setting models.AppSetting
	if err := s.db.Where("key = ?", key).First(&setting).Error; err != nil {
		return nil, errors.New("setting not found")
	}
	return &setting, nil
}

// GetKeywordLimit retrieves the keyword limit setting
func (s *AppConfigService) GetKeywordLimit() (int, error) {
	setting, err := s.GetSetting("keyword_limit")
	if err != nil {
		return 10, nil // Default
	}

	limit, err := strconv.Atoi(setting.Value)
	if err != nil {
		return 10, nil
	}
	return limit, nil
}

// SetKeywordLimit sets the keyword limit setting
func (s *AppConfigService) SetKeywordLimit(limit int) error {
	var setting models.AppSetting
	err := s.db.Where("key = ?", "keyword_limit").First(&setting).Error

	if err != nil {
		// Create new
		setting = models.AppSetting{
			Key:       "keyword_limit",
			Value:     strconv.Itoa(limit),
			ValueType: "int",
		}
		return s.db.Create(&setting).Error
	}

	// Update existing
	setting.Value = strconv.Itoa(limit)
	return s.db.Save(&setting).Error
}

// compareVersions compares two version strings
// Returns -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
func compareVersions(v1, v2 string) int {
	// Simple version comparison (major.minor.patch)
	// In production, use a proper semver library
	if v1 == v2 {
		return 0
	}
	if v1 < v2 {
		return -1
	}
	return 1
}

package services

import (
	"encoding/json"
	"errors"

	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
)

type AppConfigService struct {
	db *database.DB
}

func NewAppConfigService(db *database.DB) *AppConfigService {
	return &AppConfigService{db: db}
}

// VersionCheckResponse - 모바일 클라이언트와 호환되는 응답 구조
type VersionCheckResponse struct {
	NeedsUpdate   bool    `json:"needs_update"`
	ForceUpdate   bool    `json:"force_update"`
	LatestVersion string  `json:"latest_version"`
	MinVersion    string  `json:"min_version"` // 모바일에서 min_version으로 파싱
	UpdateMessage *string `json:"update_message,omitempty"`
	StoreURL      *string `json:"store_url,omitempty"`
}

type SetKeywordLimitRequest struct {
	Limit int `json:"limit"`
}

// GetAdConfigs retrieves ad configurations
func (s *AppConfigService) GetAdConfigs(platform string) ([]models.AdConfig, error) {
	var configs []models.AdConfig
	query := s.db.Where("is_enabled = ?", true)

	if platform != "" {
		query = query.Where("platform = ?", platform)
	}

	err := query.Order("priority DESC").Find(&configs).Error
	return configs, err
}

// CheckVersion checks app version against requirements
// currentVersion이 빈 문자열이면 버전 비교 없이 정책 정보만 반환 (모바일 클라이언트가 자체 비교)
func (s *AppConfigService) CheckVersion(platform, currentVersion string) (*VersionCheckResponse, error) {
	var appVersion models.AppVersion
	if err := s.db.Where("platform = ? AND is_active = ?", platform, true).First(&appVersion).Error; err != nil {
		return nil, errors.New("platform not found")
	}

	// 버전 비교 로직 (currentVersion이 제공된 경우에만)
	needsUpdate := false
	forceUpdate := appVersion.ForceUpdate // 서버 정책 기본값

	if currentVersion != "" {
		needsUpdate = compareVersions(currentVersion, appVersion.Version) < 0
		// 현재 버전이 최소 버전보다 낮으면 강제 업데이트
		if compareVersions(currentVersion, appVersion.MinimumVersion) < 0 {
			forceUpdate = true
		}
	}

	return &VersionCheckResponse{
		NeedsUpdate:   needsUpdate,
		ForceUpdate:   forceUpdate,
		LatestVersion: appVersion.Version,
		MinVersion:    appVersion.MinimumVersion,
		UpdateMessage: appVersion.UpdateMessage,
		StoreURL:      appVersion.StoreURL,
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

	var limit int
	if err := json.Unmarshal(setting.Value, &limit); err != nil {
		return 10, nil
	}
	return limit, nil
}

// SetKeywordLimit sets the keyword limit setting
func (s *AppConfigService) SetKeywordLimit(limit int) error {
	var setting models.AppSetting
	err := s.db.Where("key = ?", "keyword_limit").First(&setting).Error

	valueJSON, _ := json.Marshal(limit)

	if err != nil {
		// Create new
		setting = models.AppSetting{
			Key:      "keyword_limit",
			Value:    valueJSON,
			IsActive: true,
		}
		return s.db.Create(&setting).Error
	}

	// Update existing
	setting.Value = valueJSON
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

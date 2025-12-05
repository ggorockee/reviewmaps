package models

import (
	"time"
)

// AdConfig represents advertisement configuration
type AdConfig struct {
	ID             uint      `gorm:"primaryKey" json:"id"`
	Platform       string    `gorm:"size:20;not null" json:"platform"`
	AdType         string    `gorm:"size:50;not null" json:"ad_type"`
	UnitID         string    `gorm:"size:255;not null" json:"unit_id"`
	IsActive       bool      `gorm:"default:true" json:"is_active"`
	ShowFrequency  int       `gorm:"default:1" json:"show_frequency"`
	ShowAfterCount int       `gorm:"default:0" json:"show_after_count"`
	CreatedAt      time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt      time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (AdConfig) TableName() string {
	return "ad_configs"
}

// AppVersion represents app version information
type AppVersion struct {
	ID              uint      `gorm:"primaryKey" json:"id"`
	Platform        string    `gorm:"size:20;not null" json:"platform"`
	MinVersion      string    `gorm:"size:20;not null" json:"min_version"`
	LatestVersion   string    `gorm:"size:20;not null" json:"latest_version"`
	ForceUpdate     bool      `gorm:"default:false" json:"force_update"`
	UpdateMessage   *string   `gorm:"type:text" json:"update_message,omitempty"`
	StoreURL        *string   `gorm:"size:500" json:"store_url,omitempty"`
	MaintenanceMode bool      `gorm:"default:false" json:"maintenance_mode"`
	CreatedAt       time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt       time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (AppVersion) TableName() string {
	return "app_versions"
}

// AppSetting represents general app settings
type AppSetting struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Key       string    `gorm:"size:100;not null;uniqueIndex" json:"key"`
	Value     string    `gorm:"type:text;not null" json:"value"`
	ValueType string    `gorm:"size:20;default:string" json:"value_type"`
	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (AppSetting) TableName() string {
	return "app_settings"
}

// RateLimitConfig represents rate limiting configuration
type RateLimitConfig struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Endpoint     string    `gorm:"size:255;not null" json:"endpoint"`
	MaxRequests  int       `gorm:"default:100" json:"max_requests"`
	WindowSec    int       `gorm:"default:60" json:"window_sec"`
	IsActive     bool      `gorm:"default:true" json:"is_active"`
	CreatedAt    time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt    time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (RateLimitConfig) TableName() string {
	return "rate_limit_configs"
}

package models

import (
	"encoding/json"
	"time"
)

// AdConfig represents advertisement configuration - matches actual DB schema
type AdConfig struct {
	ID        uint            `gorm:"primaryKey" json:"id"`
	Platform  string          `gorm:"size:20;not null" json:"platform"`
	AdNetwork string          `gorm:"size:50;not null" json:"ad_network"`
	IsEnabled bool            `gorm:"not null" json:"is_enabled"`
	AdUnitIDs json.RawMessage `gorm:"type:jsonb;not null" json:"ad_unit_ids" swaggertype:"object"` // JSONB map
	Priority  int             `gorm:"not null" json:"priority"`
	CreatedAt time.Time       `gorm:"not null" json:"created_at"`
	UpdatedAt time.Time       `gorm:"not null" json:"updated_at"`
}

func (AdConfig) TableName() string {
	return "ad_configs"
}

// AppVersion represents app version information - matches actual DB schema
type AppVersion struct {
	ID             uint      `gorm:"primaryKey" json:"id"`
	Platform       string    `gorm:"size:20;not null" json:"platform"`
	Version        string    `gorm:"size:20;not null" json:"version"`
	MinimumVersion string    `gorm:"column:minimum_version;size:20;not null" json:"minimum_version"`
	BuildNumber    int       `gorm:"default:0" json:"build_number"`
	IsActive       bool      `gorm:"default:true" json:"is_active"`
	ForceUpdate    bool      `gorm:"default:false" json:"force_update"`
	UpdateMessage  *string   `gorm:"type:text" json:"update_message,omitempty"`
	StoreURL       *string   `gorm:"size:500" json:"store_url,omitempty"`
	CreatedAt      time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt      time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (AppVersion) TableName() string {
	return "app_versions"
}

// AppSetting represents general app settings - matches actual DB schema
type AppSetting struct {
	ID          uint            `gorm:"primaryKey" json:"id"`
	Key         string          `gorm:"size:100;not null;uniqueIndex" json:"key"`
	Value       json.RawMessage `gorm:"type:jsonb;not null" json:"value" swaggertype:"object"` // JSONB value
	Description *string         `gorm:"type:text" json:"description,omitempty"`
	IsActive    bool            `gorm:"not null" json:"is_active"`
	CreatedAt   time.Time       `gorm:"not null" json:"created_at"`
	UpdatedAt   time.Time       `gorm:"not null" json:"updated_at"`
}

func (AppSetting) TableName() string {
	return "app_settings"
}

// RateLimitConfig represents rate limiting configuration - matches actual DB schema
type RateLimitConfig struct {
	ID                   uint      `gorm:"primaryKey" json:"id"`
	Endpoint             string    `gorm:"size:255;not null" json:"endpoint"`
	Description          *string   `gorm:"type:text" json:"description,omitempty"`
	MaxRequests          int       `gorm:"default:100" json:"max_requests"`
	WindowSeconds        int       `gorm:"column:window_seconds;default:60" json:"window_seconds"`
	BlockDurationSeconds int       `gorm:"column:block_duration_seconds;default:0" json:"block_duration_seconds"`
	ApplyToAuthenticated bool      `gorm:"column:apply_to_authenticated;default:true" json:"apply_to_authenticated"`
	ApplyToAnonymous     bool      `gorm:"column:apply_to_anonymous;default:true" json:"apply_to_anonymous"`
	IsEnabled            bool      `gorm:"default:true" json:"is_enabled"`
	Priority             int       `gorm:"default:0" json:"priority"`
	CreatedAt            time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt            time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

func (RateLimitConfig) TableName() string {
	return "rate_limit_configs"
}

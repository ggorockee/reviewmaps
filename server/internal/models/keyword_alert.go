package models

import (
	"time"
)

// FCMDevice represents FCM device tokens
type FCMDevice struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	UserID    uint      `gorm:"index;not null" json:"user_id"`
	Token     string    `gorm:"size:500;not null;uniqueIndex" json:"token"`
	Platform  string    `gorm:"size:20;not null" json:"platform"`
	IsActive  bool      `gorm:"default:true" json:"is_active"`
	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time `gorm:"autoUpdateTime" json:"updated_at"`

	// Relations
	User User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

func (FCMDevice) TableName() string {
	return "keyword_alerts_fcm_devices"
}

// Keyword represents user keywords for alerts
type Keyword struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	UserID    uint      `gorm:"not null;uniqueIndex:idx_keyword_user_kw" json:"user_id"`
	Keyword   string    `gorm:"size:100;not null;uniqueIndex:idx_keyword_user_kw" json:"keyword"`
	IsActive  bool      `gorm:"default:true" json:"is_active"`
	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt time.Time `gorm:"autoUpdateTime" json:"updated_at"`

	// Relations
	User   User           `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Alerts []KeywordAlert `gorm:"foreignKey:KeywordID" json:"alerts,omitempty"`
}

func (Keyword) TableName() string {
	return "keyword_alerts_keywords"
}

// KeywordAlert represents keyword match alerts
type KeywordAlert struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	KeywordID    uint      `gorm:"not null;uniqueIndex:idx_alert_kw_cpg" json:"keyword_id"`
	CampaignID   uint      `gorm:"not null;uniqueIndex:idx_alert_kw_cpg;index:idx_alert_campaign" json:"campaign_id"`
	MatchedField string    `gorm:"size:50;default:'title'" json:"matched_field"`
	IsRead       bool      `gorm:"default:false;index:idx_alert_read" json:"is_read"`
	CreatedAt    time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt    time.Time `gorm:"autoUpdateTime" json:"updated_at"`

	// Relations
	Keyword  Keyword  `gorm:"foreignKey:KeywordID" json:"keyword,omitempty"`
	Campaign Campaign `gorm:"foreignKey:CampaignID" json:"campaign,omitempty"`
}

func (KeywordAlert) TableName() string {
	return "keyword_alerts_alerts"
}

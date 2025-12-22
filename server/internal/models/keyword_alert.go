package models

import (
	"time"
)

// FCMDevice represents FCM device tokens
// DB: keyword_alerts_fcm_devices
type FCMDevice struct {
	ID                 uint      `gorm:"primaryKey" json:"id"`
	UserID             *uint     `gorm:"column:user_id;index:fcm_user_active_idx" json:"user_id"`
	AnonymousSessionID *string   `gorm:"column:anonymous_session_id;size:255;index:fcm_anon_active_idx" json:"anonymous_session_id"`
	FCMToken           string    `gorm:"column:fcm_token;size:500;not null;uniqueIndex:keyword_alerts_fcm_devices_fcm_token_key" json:"fcm_token"`
	DeviceType         string    `gorm:"column:device_type;size:20;not null" json:"device_type"`
	IsActive           bool      `gorm:"not null" json:"is_active"`
	CreatedAt          time.Time `gorm:"not null" json:"created_at"`
	UpdatedAt          time.Time `gorm:"not null" json:"updated_at"`

	// Relations
	User *User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

func (FCMDevice) TableName() string {
	return "keyword_alerts_fcm_devices"
}

// Keyword represents user keywords for alerts
// DB: keyword_alerts_keywords
type Keyword struct {
	ID                 uint      `gorm:"primaryKey" json:"id"`
	UserID             *uint     `gorm:"column:user_id;index:keyword_ale_user_id_e18c3d_idx" json:"user_id"`
	AnonymousSessionID *string   `gorm:"column:anonymous_session_id;size:255;index:keyword_ale_anonymo_2936ec_idx" json:"anonymous_session_id"`
	Keyword            string    `gorm:"column:keyword;size:100;not null;index:keyword_ale_keyword_5c7b32_idx" json:"keyword"`
	IsActive           bool      `gorm:"not null" json:"is_active"`
	CreatedAt          time.Time `gorm:"not null" json:"created_at"`
	UpdatedAt          time.Time `gorm:"not null" json:"updated_at"`

	// Relations
	User   *User          `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Alerts []KeywordAlert `gorm:"foreignKey:KeywordID" json:"alerts,omitempty"`
}

func (Keyword) TableName() string {
	return "keyword_alerts_keywords"
}

// KeywordAlert represents keyword match alerts
// DB: keyword_alerts_alerts
type KeywordAlert struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	KeywordID    uint      `gorm:"column:keyword_id;not null;uniqueIndex:keyword_alerts_keyword_campaign_unique,priority:1;index:keyword_ale_keyword_3d44d6_idx" json:"keyword_id"`
	CampaignID   *uint     `gorm:"column:campaign_id;uniqueIndex:keyword_alerts_keyword_campaign_unique,priority:2;index:keyword_ale_campaig_2f61a0_idx" json:"campaign_id"`
	MatchedField string    `gorm:"column:matched_field;size:50;not null" json:"matched_field"`
	IsRead       bool      `gorm:"not null" json:"is_read"`
	CreatedAt    time.Time `gorm:"not null;index:keyword_ale_created_704aa6_idx,sort:desc" json:"created_at"`
	UpdatedAt    time.Time `gorm:"not null" json:"updated_at"`

	// Relations
	Keyword  Keyword   `gorm:"foreignKey:KeywordID" json:"keyword,omitempty"`
	Campaign *Campaign `gorm:"foreignKey:CampaignID" json:"campaign,omitempty"`
}

func (KeywordAlert) TableName() string {
	return "keyword_alerts_alerts"
}

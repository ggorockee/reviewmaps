package models

import (
	"time"
)

// User represents the users table
type User struct {
	ID           uint       `gorm:"primaryKey" json:"id"`
	Username     string     `gorm:"uniqueIndex;size:255;not null" json:"username"`
	Email        string     `gorm:"size:255;not null" json:"email"`
	Password     string     `gorm:"size:255" json:"-"`
	LoginMethod  string     `gorm:"size:20;default:email" json:"login_method"`
	Name         *string    `gorm:"size:100" json:"name,omitempty"`
	ProfileImage *string    `gorm:"size:500" json:"profile_image,omitempty"`
	IsActive     bool       `gorm:"default:true" json:"is_active"`
	IsStaff      bool       `gorm:"default:false" json:"is_staff"`
	IsSuperuser  bool       `gorm:"default:false" json:"is_superuser"`
	DateJoined   time.Time  `gorm:"autoCreateTime" json:"date_joined"`
	LastLogin    *time.Time `json:"last_login,omitempty"`

	// Relations
	SocialAccounts []SocialAccount `gorm:"foreignKey:UserID" json:"social_accounts,omitempty"`
	FCMDevices     []FCMDevice     `gorm:"foreignKey:UserID" json:"fcm_devices,omitempty"`
	Keywords       []Keyword       `gorm:"foreignKey:UserID" json:"keywords,omitempty"`
}

func (User) TableName() string {
	return "users"
}

// SocialAccount represents SNS account connections
type SocialAccount struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	UserID     uint      `gorm:"not null;uniqueIndex:idx_social_user_provider" json:"user_id"`
	Provider   string    `gorm:"size:20;not null;uniqueIndex:idx_social_user_provider" json:"provider"`
	ProviderID string    `gorm:"size:255;not null;uniqueIndex:idx_social_provider_id" json:"provider_id"`
	CreatedAt  time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt  time.Time `gorm:"autoUpdateTime" json:"updated_at"`

	// Relations
	User User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

func (SocialAccount) TableName() string {
	return "social_accounts"
}

// EmailVerification represents email verification records
type EmailVerification struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	Email      string    `gorm:"size:255;not null;index" json:"email"`
	Code       string    `gorm:"size:10;not null" json:"-"`
	IsVerified bool      `gorm:"default:false" json:"is_verified"`
	ExpiresAt  time.Time `gorm:"not null" json:"expires_at"`
	CreatedAt  time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (EmailVerification) TableName() string {
	return "email_verifications"
}

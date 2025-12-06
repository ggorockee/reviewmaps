package models

import (
	"time"
)

// User represents the users table
// Note: unique constraints are managed by existing Django migrations
// GORM tags avoid creating new constraints that conflict with Django schema
type User struct {
	ID           uint       `gorm:"primaryKey" json:"id"`
	Username     string     `gorm:"size:255;not null;->" json:"username"` // -> means read-only for migrations
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
// Note: Field names match Django model for DB compatibility
type SocialAccount struct {
	ID             uint      `gorm:"primaryKey" json:"id"`
	UserID         uint      `gorm:"not null;index:idx_user_provider" json:"user_id"`
	Provider       string    `gorm:"column:provider;size:20;not null;uniqueIndex:social_accounts_provider_provider_user_id_key,priority:1" json:"provider"`
	ProviderUserID string    `gorm:"column:provider_user_id;size:255;not null;uniqueIndex:social_accounts_provider_provider_user_id_key,priority:2" json:"provider_user_id"`
	Email          string    `gorm:"size:255" json:"email"`
	Name           string    `gorm:"size:100" json:"name"`
	ProfileImage   string    `gorm:"size:500" json:"profile_image"`
	AccessToken    string    `gorm:"type:text" json:"-"`
	RefreshToken   string    `gorm:"type:text" json:"-"`
	TokenExpiresAt *time.Time `json:"token_expires_at,omitempty"`
	CreatedAt      time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt      time.Time `gorm:"autoUpdateTime" json:"updated_at"`

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

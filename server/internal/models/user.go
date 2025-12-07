package models

import (
	"time"
)

// User represents the users table
// DB: users
type User struct {
	ID           uint       `gorm:"primaryKey" json:"id"`
	Username     string     `gorm:"column:username;size:255;not null;uniqueIndex:users_username_key" json:"username"`
	Email        string     `gorm:"column:email;size:255;not null" json:"email"`
	Password     string     `gorm:"column:password;size:255;not null" json:"-"`
	LoginMethod  string     `gorm:"column:login_method;size:20;not null" json:"login_method"`
	Name         string     `gorm:"column:name;size:100;not null" json:"name"`
	ProfileImage string     `gorm:"column:profile_image;size:500;not null" json:"profile_image"`
	IsActive     bool       `gorm:"column:is_active;not null" json:"is_active"`
	IsStaff      bool       `gorm:"column:is_staff;not null" json:"is_staff"`
	IsSuperuser  bool       `gorm:"column:is_superuser;not null" json:"is_superuser"`
	DateJoined   time.Time  `gorm:"column:date_joined;not null" json:"date_joined"`
	LastLogin    *time.Time `gorm:"column:last_login" json:"last_login,omitempty"`

	// Relations
	SocialAccounts []SocialAccount `gorm:"foreignKey:UserID" json:"social_accounts,omitempty"`
	FCMDevices     []FCMDevice     `gorm:"foreignKey:UserID" json:"fcm_devices,omitempty"`
	Keywords       []Keyword       `gorm:"foreignKey:UserID" json:"keywords,omitempty"`
}

func (User) TableName() string {
	return "users"
}

// SocialAccount represents SNS account connections
// DB: social_accounts
type SocialAccount struct {
	ID             uint       `gorm:"primaryKey" json:"id"`
	UserID         uint       `gorm:"column:user_id;not null;index:social_accounts_user_id_c09daa18" json:"user_id"`
	Provider       string     `gorm:"column:provider;size:20;not null;uniqueIndex:social_accounts_provider_provider_user_id_key,priority:1" json:"provider"`
	ProviderUserID string     `gorm:"column:provider_user_id;size:255;not null;uniqueIndex:social_accounts_provider_provider_user_id_key,priority:2" json:"provider_user_id"`
	Email          *string    `gorm:"column:email;size:255" json:"email,omitempty"`
	Name           *string    `gorm:"column:name;size:100" json:"name,omitempty"`
	ProfileImage   *string    `gorm:"column:profile_image;size:500" json:"profile_image,omitempty"`
	AccessToken    *string    `gorm:"column:access_token;type:text" json:"-"`
	RefreshToken   *string    `gorm:"column:refresh_token;type:text" json:"-"`
	TokenExpiresAt *time.Time `gorm:"column:token_expires_at" json:"token_expires_at,omitempty"`
	CreatedAt      time.Time  `gorm:"column:created_at;not null" json:"created_at"`
	UpdatedAt      time.Time  `gorm:"column:updated_at;not null" json:"updated_at"`

	// Relations
	User User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

func (SocialAccount) TableName() string {
	return "social_accounts"
}

// EmailVerification represents email verification records
// DB: email_verifications
type EmailVerification struct {
	ID                uint       `gorm:"primaryKey" json:"id"`
	Email             string     `gorm:"column:email;size:255;not null;index:email_verifications_email_c2d2b8ff" json:"email"`
	Code              string     `gorm:"column:code;size:10;not null" json:"-"`
	VerificationToken *string    `gorm:"column:verification_token;size:255;uniqueIndex:email_verifications_verification_token_key" json:"-"`
	IsVerified        bool       `gorm:"column:is_verified;not null" json:"is_verified"`
	ExpiresAt         time.Time  `gorm:"column:expires_at;not null" json:"expires_at"`
	SendCount         int        `gorm:"column:send_count;not null;default:1" json:"send_count"`
	LastSentAt        *time.Time `gorm:"column:last_sent_at" json:"last_sent_at,omitempty"`
	Attempts          int        `gorm:"column:attempts;not null;default:0" json:"attempts"`
	CreatedAt         time.Time  `gorm:"column:created_at;not null" json:"created_at"`
}

func (EmailVerification) TableName() string {
	return "email_verifications"
}

package models

import "time"

// AdminSession 관리자 콘솔 로그인 세션 (토큰 원문 대신 SHA-256만 저장)
// DB: admin_sessions (server/migrations/add_admin_tables.sql)
type AdminSession struct {
	TokenHash []byte    `gorm:"column:token_hash;primaryKey"`
	Email     string    `gorm:"column:email;not null"`
	ExpiresAt time.Time `gorm:"column:expires_at;not null;index:admin_sessions_expires"`
	CreatedAt time.Time `gorm:"column:created_at;not null"`
}

func (AdminSession) TableName() string {
	return "admin_sessions"
}

// AdminAuditLog 관리자 변경 기록
// DB: admin_audit_logs. Before/After는 JSON 문자열 (민감 필드는 넣지 않음)
type AdminAuditLog struct {
	ID         uint      `gorm:"column:id;primaryKey" json:"id"`
	AdminEmail string    `gorm:"column:admin_email;not null" json:"admin_email"`
	Action     string    `gorm:"column:action;not null" json:"action"`
	Entity     string    `gorm:"column:entity;not null" json:"entity"`
	EntityID   string    `gorm:"column:entity_id;not null;default:''" json:"entity_id"`
	Before     *string   `gorm:"column:before;type:jsonb" json:"before,omitempty"`
	After      *string   `gorm:"column:after;type:jsonb" json:"after,omitempty"`
	CreatedAt  time.Time `gorm:"column:created_at;not null" json:"created_at"`
}

func (AdminAuditLog) TableName() string {
	return "admin_audit_logs"
}

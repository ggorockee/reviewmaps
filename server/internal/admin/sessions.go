package admin

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"time"

	"github.com/ggorockee/reviewmaps/server/internal/models"
	"gorm.io/gorm"
)

// ErrNoSession 쿠키가 없거나, 모르는 값이거나, 만료됨.
var ErrNoSession = errors.New("no admin session")

// Sessions admin_sessions 테이블로 세션 쿠키를 발급·확인한다.
type Sessions struct {
	DB  *gorm.DB
	TTL time.Duration
	Now func() time.Time
}

// Create 이메일에 대한 새 무작위 세션 토큰을 만든다.
func (s *Sessions) Create(ctx context.Context, email string) (token string, expires time.Time, err error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", time.Time{}, err
	}
	token = base64.RawURLEncoding.EncodeToString(raw)
	now := s.now()
	expires = now.Add(s.TTL)
	row := models.AdminSession{TokenHash: Hash(token), Email: email, ExpiresAt: expires, CreatedAt: now}
	if err := s.DB.WithContext(ctx).Create(&row).Error; err != nil {
		return "", time.Time{}, err
	}
	// 만료된 세션은 로그인 때 함께 정리 (테이블이 계속 커지지 않게)
	s.DB.WithContext(ctx).Where("expires_at < ?", now).Delete(&models.AdminSession{})
	return token, expires, nil
}

// Lookup 유효한 세션의 이메일을 돌려준다.
func (s *Sessions) Lookup(ctx context.Context, token string) (string, error) {
	if token == "" {
		return "", ErrNoSession
	}
	var row models.AdminSession
	err := s.DB.WithContext(ctx).Where("token_hash = ?", Hash(token)).Take(&row).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return "", ErrNoSession
	}
	if err != nil {
		return "", err
	}
	if !s.now().Before(row.ExpiresAt) {
		s.DB.WithContext(ctx).Where("token_hash = ?", Hash(token)).Delete(&models.AdminSession{})
		return "", ErrNoSession
	}
	return row.Email, nil
}

// Delete 세션을 끝낸다.
func (s *Sessions) Delete(ctx context.Context, token string) error {
	return s.DB.WithContext(ctx).Where("token_hash = ?", Hash(token)).Delete(&models.AdminSession{}).Error
}

// Active 유효한 세션 수 (reviewmaps_admin_sessions_active 지표용).
func (s *Sessions) Active(ctx context.Context) (int64, error) {
	var n int64
	err := s.DB.WithContext(ctx).Model(&models.AdminSession{}).Where("expires_at > ?", s.now()).Count(&n).Error
	return n, err
}

func (s *Sessions) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// Hash 토큰 대신 DB에 저장하는 값.
func Hash(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}

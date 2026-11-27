// Package admin 관리자 화면(admin.review-maps.com) 사용자 인증.
//
// 로그인: 화면이 Google ID 토큰을 받아 서버에 한 번 보내면,
// 서버가 토큰을 검증하고 허용 목록(ADMIN_EMAILS)을 확인한 뒤
// 세션 쿠키를 발급한다. DB에는 세션 토큰의 SHA-256만 저장한다.
// 라익찍스 관리자 콘솔과 같은 구조.
package admin

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/MicahParks/keyfunc/v3"
	"github.com/golang-jwt/jwt/v5"
)

var (
	// ErrInvalidToken ID 토큰 형식 오류·만료·다른 클라이언트용·이메일 미확인.
	ErrInvalidToken = errors.New("invalid id token")
)

// GoogleCertsURL Google ID 토큰 서명 키(JWKS) 주소.
const GoogleCertsURL = "https://www.googleapis.com/oauth2/v3/certs"

// Verifier Google ID 토큰을 검증해 이메일을 돌려준다.
type Verifier interface {
	Verify(ctx context.Context, idToken string) (email string, err error)
}

// Allowlist 관리자 이메일 목록 (소문자).
type Allowlist map[string]bool

// ParseAllowlist 쉼표로 구분된 이메일 목록을 읽는다.
func ParseAllowlist(csv string) Allowlist {
	a := Allowlist{}
	for _, e := range strings.Split(csv, ",") {
		if e = strings.ToLower(strings.TrimSpace(e)); e != "" {
			a[e] = true
		}
	}
	return a
}

// Allowed 이 이메일이 관리자 화면을 쓸 수 있는지.
func (a Allowlist) Allowed(email string) bool { return a[strings.ToLower(strings.TrimSpace(email))] }

// GoogleVerifier Google이 공개한 서명 키(JWKS)로 ID 토큰을 검증한다.
type GoogleVerifier struct {
	clientID string
	keyfunc  jwt.Keyfunc
	now      func() time.Time
}

// NewGoogleVerifier Google 서명 키를 받아 온다 (백그라운드에서 갱신).
func NewGoogleVerifier(ctx context.Context, clientID string) (*GoogleVerifier, error) {
	if clientID == "" {
		return nil, errors.New("admin: ADMIN_GOOGLE_CLIENT_ID is empty")
	}
	k, err := keyfunc.NewDefaultCtx(ctx, []string{GoogleCertsURL})
	if err != nil {
		return nil, fmt.Errorf("admin: google jwks: %w", err)
	}
	return &GoogleVerifier{clientID: clientID, keyfunc: k.Keyfunc, now: time.Now}, nil
}

// NewGoogleVerifierWithKeyfunc 테스트용 (고정 서명 키).
func NewGoogleVerifierWithKeyfunc(clientID string, kf jwt.Keyfunc, now func() time.Time) *GoogleVerifier {
	return &GoogleVerifier{clientID: clientID, keyfunc: kf, now: now}
}

type googleClaims struct {
	Email         string `json:"email"`
	EmailVerified bool   `json:"email_verified"`
	jwt.RegisteredClaims
}

// Verify 서명(RS256), 대상(aud), 발급자(iss), 만료, email_verified를 확인한다.
func (v *GoogleVerifier) Verify(_ context.Context, idToken string) (string, error) {
	var c googleClaims
	_, err := jwt.ParseWithClaims(idToken, &c, v.keyfunc,
		jwt.WithValidMethods([]string{"RS256"}),
		jwt.WithAudience(v.clientID),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(v.now),
	)
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrInvalidToken, err)
	}
	if c.Issuer != "accounts.google.com" && c.Issuer != "https://accounts.google.com" {
		return "", fmt.Errorf("%w: issuer %q", ErrInvalidToken, c.Issuer)
	}
	if !c.EmailVerified || c.Email == "" {
		return "", fmt.Errorf("%w: email not verified", ErrInvalidToken)
	}
	return strings.ToLower(c.Email), nil
}

// Package admin authenticates admin console users (admin.review-maps.com).
//
// Login: the console obtains a Google ID token (Google Identity Services) and
// sends it once; the server verifies it, checks the allowlist (ADMIN_EMAILS) and
// issues an opaque session cookie. Only the SHA-256 of the session token is stored.
// Same design as the like-zzix admin console.
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
	// ErrInvalidToken means the ID token is malformed, expired, for another client or unverified.
	ErrInvalidToken = errors.New("invalid id token")
)

// GoogleCertsURL is Google's JWKS endpoint for ID tokens.
const GoogleCertsURL = "https://www.googleapis.com/oauth2/v3/certs"

// Verifier turns a Google ID token into a verified email.
type Verifier interface {
	Verify(ctx context.Context, idToken string) (email string, err error)
}

// Allowlist holds admin emails (lowercase).
type Allowlist map[string]bool

// ParseAllowlist parses a comma-separated email list.
func ParseAllowlist(csv string) Allowlist {
	a := Allowlist{}
	for _, e := range strings.Split(csv, ",") {
		if e = strings.ToLower(strings.TrimSpace(e)); e != "" {
			a[e] = true
		}
	}
	return a
}

// Allowed reports whether email may use the console.
func (a Allowlist) Allowed(email string) bool { return a[strings.ToLower(strings.TrimSpace(email))] }

// GoogleVerifier validates Google ID tokens against the published JWKS.
type GoogleVerifier struct {
	clientID string
	keyfunc  jwt.Keyfunc
	now      func() time.Time
}

// NewGoogleVerifier fetches Google's signing keys (refreshed in the background).
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

// NewGoogleVerifierWithKeyfunc is for tests (fixed signing key).
func NewGoogleVerifierWithKeyfunc(clientID string, kf jwt.Keyfunc, now func() time.Time) *GoogleVerifier {
	return &GoogleVerifier{clientID: clientID, keyfunc: kf, now: now}
}

type googleClaims struct {
	Email         string `json:"email"`
	EmailVerified bool   `json:"email_verified"`
	jwt.RegisteredClaims
}

// Verify checks signature (RS256), audience, issuer, expiry and email_verified.
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

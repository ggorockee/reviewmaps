package admin

import (
	"crypto/subtle"
	"errors"

	"golang.org/x/crypto/bcrypt"
)

// PasswordLogin is a single break-glass account (ID + bcrypt hash) for when Google login is unavailable.
type PasswordLogin struct {
	ID   string
	hash []byte
}

// NewPasswordLogin returns nil when id or hash is empty (password login disabled).
func NewPasswordLogin(id, hash string) (*PasswordLogin, error) {
	if id == "" || hash == "" {
		return nil, nil
	}
	if _, err := bcrypt.Cost([]byte(hash)); err != nil {
		return nil, errors.New("ADMIN_PASSWORD_HASH must be a bcrypt hash")
	}
	return &PasswordLogin{ID: id, hash: []byte(hash)}, nil
}

// Check reports whether id and password match. bcrypt always runs so a wrong ID takes the same time.
func (p *PasswordLogin) Check(id, password string) bool {
	pwOK := bcrypt.CompareHashAndPassword(p.hash, []byte(password)) == nil
	idOK := subtle.ConstantTimeCompare([]byte(id), []byte(p.ID)) == 1
	return pwOK && idOK
}

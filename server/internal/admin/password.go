package admin

import (
	"crypto/subtle"
	"errors"

	"golang.org/x/crypto/bcrypt"
)

// PasswordLogin Google 로그인을 쓸 수 없을 때를 위한 예비 계정 하나 (아이디 + bcrypt 해시).
type PasswordLogin struct {
	ID   string
	hash []byte
}

// NewPasswordLogin 아이디나 해시가 비어 있으면 nil (예비 로그인 꺼짐).
func NewPasswordLogin(id, hash string) (*PasswordLogin, error) {
	if id == "" || hash == "" {
		return nil, nil
	}
	if _, err := bcrypt.Cost([]byte(hash)); err != nil {
		return nil, errors.New("ADMIN_PASSWORD_HASH must be a bcrypt hash")
	}
	return &PasswordLogin{ID: id, hash: []byte(hash)}, nil
}

// Check 아이디·비밀번호가 맞는지 확인. 아이디가 틀려도 bcrypt를 항상 돌려 응답 시간이 같다.
func (p *PasswordLogin) Check(id, password string) bool {
	pwOK := bcrypt.CompareHashAndPassword(p.hash, []byte(password)) == nil
	idOK := subtle.ConstantTimeCompare([]byte(id), []byte(p.ID)) == 1
	return pwOK && idOK
}

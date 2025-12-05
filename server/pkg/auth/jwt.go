package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type TokenType string

const (
	AccessToken  TokenType = "access"
	RefreshToken TokenType = "refresh"
)

type Claims struct {
	UserID uint      `json:"user_id"`
	Type   TokenType `json:"type"`
	jwt.RegisteredClaims
}

func GenerateAccessToken(userID uint, secretKey string, expireMinutes int) (string, error) {
	claims := Claims{
		UserID: userID,
		Type:   AccessToken,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Duration(expireMinutes) * time.Minute)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secretKey))
}

func GenerateRefreshToken(userID uint, secretKey string, expireDays int) (string, error) {
	claims := Claims{
		UserID: userID,
		Type:   RefreshToken,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Duration(expireDays) * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secretKey))
}

func ValidateAccessToken(tokenString, secretKey string) (*Claims, error) {
	return validateToken(tokenString, secretKey, AccessToken)
}

func ValidateRefreshToken(tokenString, secretKey string) (*Claims, error) {
	return validateToken(tokenString, secretKey, RefreshToken)
}

func validateToken(tokenString, secretKey string, expectedType TokenType) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return []byte(secretKey), nil
	})

	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token")
	}

	if claims.Type != expectedType {
		return nil, errors.New("invalid token type")
	}

	return claims, nil
}

// GenerateTokenPair generates both access and refresh tokens
func GenerateTokenPair(userID uint, secretKey string, accessExpireMin, refreshExpireDays int) (accessToken, refreshToken string, err error) {
	accessToken, err = GenerateAccessToken(userID, secretKey, accessExpireMin)
	if err != nil {
		return "", "", err
	}

	refreshToken, err = GenerateRefreshToken(userID, secretKey, refreshExpireDays)
	if err != nil {
		return "", "", err
	}

	return accessToken, refreshToken, nil
}

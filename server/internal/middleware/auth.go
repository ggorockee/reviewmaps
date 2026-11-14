package middleware

import (
	"crypto/subtle"
	"strings"

	"github.com/ggorockee/reviewmaps/server/internal/config"
	"github.com/ggorockee/reviewmaps/server/pkg/auth"
	"github.com/gofiber/fiber/v2"
)

func AuthRequired(cfg *config.Config) fiber.Handler {
	return func(c *fiber.Ctx) error {
		authHeader := c.Get("Authorization")
		if authHeader == "" {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Authorization header required",
			})
		}

		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Invalid authorization header format",
			})
		}

		token := parts[1]
		claims, err := auth.ValidateAccessToken(token, cfg.JWTSecretKey)
		if err != nil {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Invalid or expired token",
			})
		}

		// Store user ID in context
		c.Locals("userID", claims.UserID)
		return c.Next()
	}
}

// OptionalAuth allows both authenticated and unauthenticated requests
func OptionalAuth(cfg *config.Config) fiber.Handler {
	return func(c *fiber.Ctx) error {
		authHeader := c.Get("Authorization")
		if authHeader == "" {
			return c.Next()
		}

		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			return c.Next()
		}

		token := parts[1]
		claims, err := auth.ValidateAccessToken(token, cfg.JWTSecretKey)
		if err != nil {
			return c.Next()
		}

		c.Locals("userID", claims.UserID)
		return c.Next()
	}
}

// InternalAPIKeyRequired 내부 API Key(X-API-Key) 인증
//
// 운영 설정 변경 등 서버 간/운영자 전용 엔드포인트에 사용합니다.
// 설정된 키가 비어 있으면 모든 요청을 거부합니다 (fail-closed).
func InternalAPIKeyRequired(cfg *config.Config) fiber.Handler {
	return func(c *fiber.Ctx) error {
		apiKey := c.Get("X-API-Key")
		expected := cfg.InternalAPIKey
		if apiKey == "" || expected == "" ||
			subtle.ConstantTimeCompare([]byte(apiKey), []byte(expected)) != 1 {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "Invalid or missing API key",
			})
		}
		return c.Next()
	}
}

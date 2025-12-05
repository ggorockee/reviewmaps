package middleware

import (
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

package handlers

import (
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/gofiber/fiber/v2"
)

// HealthCheck godoc
// @Summary Health check endpoint
// @Description Returns the health status of the API
// @Tags health
// @Accept json
// @Produce json
// @Success 200 {object} map[string]string
// @Router /healthz [get]
func HealthCheck(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"status": "healthy",
	})
}

// LivenessCheck godoc
// @Summary Liveness probe endpoint
// @Description Returns liveness status for k8s
// @Tags health
// @Accept json
// @Produce json
// @Success 200 {object} map[string]string
// @Router /v1/liveness [get]
func LivenessCheck(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"status": "alive",
	})
}

// ReadinessCheck godoc
// @Summary Readiness probe endpoint
// @Description Returns readiness status including DB connection for k8s
// @Tags health
// @Accept json
// @Produce json
// @Success 200 {object} map[string]string
// @Failure 503 {object} map[string]string
// @Router /v1/readiness [get]
func ReadinessCheck(db *database.DB) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// DB connection check
		sqlDB, err := db.DB.DB()
		if err != nil {
			return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
				"status": "not ready",
				"error":  "database connection error",
			})
		}

		if err := sqlDB.Ping(); err != nil {
			return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
				"status": "not ready",
				"error":  "database ping failed",
			})
		}

		return c.JSON(fiber.Map{
			"status":   "ready",
			"database": "connected",
		})
	}
}

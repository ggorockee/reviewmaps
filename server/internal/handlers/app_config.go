package handlers

import (
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/services"
	"github.com/gofiber/fiber/v2"
)

type AppConfigHandler struct {
	service *services.AppConfigService
}

func NewAppConfigHandler(db *database.DB) *AppConfigHandler {
	return &AppConfigHandler{
		service: services.NewAppConfigService(db),
	}
}

func SetupAppConfigRoutes(router fiber.Router, db *database.DB) {
	h := NewAppConfigHandler(db)

	router.Get("/ads", h.GetAdConfigs)
	router.Get("/version", h.GetVersion)
	router.Get("/settings", h.ListSettings)
	router.Get("/settings/:key", h.GetSetting)
	router.Get("/settings/keyword-limit", h.GetKeywordLimit)
	router.Put("/settings/keyword-limit", h.SetKeywordLimit)
	router.Get("/settings/alert-retention-days", h.GetAlertRetentionDays)
	router.Put("/settings/alert-retention-days", h.SetAlertRetentionDays)
}

// GetAdConfigs godoc
// @Summary Get ad configurations
// @Tags app-config
// @Accept json
// @Produce json
// @Param platform query string false "Platform (ios/android)"
// @Success 200 {array} models.AdConfig
// @Router /app-config/ads [get]
func (h *AppConfigHandler) GetAdConfigs(c *fiber.Ctx) error {
	platform := c.Query("platform")

	configs, err := h.service.GetAdConfigs(platform)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(configs)
}

// GetVersion godoc
// @Summary Get app version info
// @Tags app-config
// @Accept json
// @Produce json
// @Param platform query string true "Platform (ios/android)"
// @Param version query string false "Current app version (optional - client can compare locally)"
// @Success 200 {object} services.VersionCheckResponse
// @Router /app-config/version [get]
func (h *AppConfigHandler) GetVersion(c *fiber.Ctx) error {
	platform := c.Query("platform")
	version := c.Query("version") // 옵셔널 - 모바일 클라이언트는 자체 비교 수행

	if platform == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "platform is required"})
	}

	response, err := h.service.CheckVersion(platform, version)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(response)
}

// ListSettings godoc
// @Summary List app settings
// @Tags app-config
// @Accept json
// @Produce json
// @Success 200 {array} models.AppSetting
// @Router /app-config/settings [get]
func (h *AppConfigHandler) ListSettings(c *fiber.Ctx) error {
	settings, err := h.service.ListSettings()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(settings)
}

// GetSetting godoc
// @Summary Get app setting by key
// @Tags app-config
// @Accept json
// @Produce json
// @Param key path string true "Setting key"
// @Success 200 {object} models.AppSetting
// @Router /app-config/settings/{key} [get]
func (h *AppConfigHandler) GetSetting(c *fiber.Ctx) error {
	key := c.Params("key")

	setting, err := h.service.GetSetting(key)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(setting)
}

// GetKeywordLimit godoc
// @Summary Get keyword limit setting
// @Tags app-config
// @Accept json
// @Produce json
// @Success 200 {object} map[string]int
// @Router /app-config/settings/keyword-limit [get]
func (h *AppConfigHandler) GetKeywordLimit(c *fiber.Ctx) error {
	limit, err := h.service.GetKeywordLimit()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(fiber.Map{"limit": limit})
}

// SetKeywordLimit godoc
// @Summary Set keyword limit setting
// @Tags app-config
// @Accept json
// @Produce json
// @Param request body services.SetKeywordLimitRequest true "Limit value"
// @Success 200 {object} map[string]int
// @Router /app-config/settings/keyword-limit [put]
func (h *AppConfigHandler) SetKeywordLimit(c *fiber.Ctx) error {
	var req services.SetKeywordLimitRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	if err := h.service.SetKeywordLimit(req.Limit); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(fiber.Map{"limit": req.Limit})
}

// GetAlertRetentionDays godoc
// @Summary Get alert retention days setting
// @Tags app-config
// @Accept json
// @Produce json
// @Success 200 {object} map[string]int
// @Router /app-config/settings/alert-retention-days [get]
func (h *AppConfigHandler) GetAlertRetentionDays(c *fiber.Ctx) error {
	days, err := h.service.GetAlertRetentionDays()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(fiber.Map{"days": days})
}

// SetAlertRetentionDays godoc
// @Summary Set alert retention days setting
// @Tags app-config
// @Accept json
// @Produce json
// @Param request body map[string]int true "Days value"
// @Success 200 {object} map[string]int
// @Router /app-config/settings/alert-retention-days [put]
func (h *AppConfigHandler) SetAlertRetentionDays(c *fiber.Ctx) error {
	var req struct {
		Days int `json:"days"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	if err := h.service.SetAlertRetentionDays(req.Days); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(fiber.Map{"days": req.Days})
}

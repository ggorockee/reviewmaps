package handlers

import (
	"strconv"

	"github.com/ggorockee/reviewmaps/server/internal/config"
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/services"
	"github.com/gofiber/fiber/v2"
)

type KeywordAlertHandler struct {
	service *services.KeywordAlertService
}

func NewKeywordAlertHandler(db *database.DB, cfg *config.Config) *KeywordAlertHandler {
	return &KeywordAlertHandler{
		service: services.NewKeywordAlertService(db, cfg),
	}
}

func SetupKeywordAlertRoutes(router fiber.Router, db *database.DB, cfg *config.Config) {
	h := NewKeywordAlertHandler(db, cfg)

	// Keywords
	router.Post("/keywords", h.CreateKeyword)
	router.Get("/keywords", h.ListKeywords)
	router.Delete("/keywords/:id", h.DeleteKeyword)
	router.Patch("/keywords/:id/toggle", h.ToggleKeyword)

	// Alerts
	router.Get("/alerts", h.ListAlerts)
	router.Post("/alerts/read", h.MarkAlertsRead)
	router.Delete("/alerts/:id", h.DeleteAlert)

	// FCM
	router.Post("/fcm/register", h.RegisterFCM)
	router.Delete("/fcm/unregister", h.UnregisterFCM)
}

// CreateKeyword godoc
// @Summary Create keyword
// @Tags keyword-alerts
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param request body services.CreateKeywordRequest true "Keyword data"
// @Success 201 {object} models.Keyword
// @Router /keyword-alerts/keywords [post]
func (h *KeywordAlertHandler) CreateKeyword(c *fiber.Ctx) error {
	userID := c.Locals("userID").(uint)

	var req services.CreateKeywordRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	keyword, err := h.service.CreateKeyword(userID, &req)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusCreated).JSON(keyword)
}

// ListKeywords godoc
// @Summary List user keywords
// @Tags keyword-alerts
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {array} models.Keyword
// @Router /keyword-alerts/keywords [get]
func (h *KeywordAlertHandler) ListKeywords(c *fiber.Ctx) error {
	userID := c.Locals("userID").(uint)

	keywords, err := h.service.ListKeywords(userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(keywords)
}

// DeleteKeyword godoc
// @Summary Delete keyword
// @Tags keyword-alerts
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path int true "Keyword ID"
// @Success 204
// @Router /keyword-alerts/keywords/{id} [delete]
func (h *KeywordAlertHandler) DeleteKeyword(c *fiber.Ctx) error {
	userID := c.Locals("userID").(uint)
	id, _ := strconv.Atoi(c.Params("id"))

	if err := h.service.DeleteKeyword(userID, uint(id)); err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
	}

	return c.SendStatus(fiber.StatusNoContent)
}

// ToggleKeyword godoc
// @Summary Toggle keyword active status
// @Tags keyword-alerts
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path int true "Keyword ID"
// @Success 200 {object} models.Keyword
// @Router /keyword-alerts/keywords/{id}/toggle [patch]
func (h *KeywordAlertHandler) ToggleKeyword(c *fiber.Ctx) error {
	userID := c.Locals("userID").(uint)
	id, _ := strconv.Atoi(c.Params("id"))

	keyword, err := h.service.ToggleKeyword(userID, uint(id))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(keyword)
}

// ListAlerts godoc
// @Summary List user alerts
// @Tags keyword-alerts
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param page query int false "Page number"
// @Param limit query int false "Items per page"
// @Success 200 {object} services.AlertListResponse
// @Router /keyword-alerts/alerts [get]
func (h *KeywordAlertHandler) ListAlerts(c *fiber.Ctx) error {
	userID := c.Locals("userID").(uint)
	page, _ := strconv.Atoi(c.Query("page", "1"))
	limit, _ := strconv.Atoi(c.Query("limit", "20"))

	response, err := h.service.ListAlerts(userID, page, limit)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(response)
}

// MarkAlertsRead godoc
// @Summary Mark alerts as read
// @Tags keyword-alerts
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param request body services.MarkReadRequest true "Alert IDs"
// @Success 200 {object} map[string]int
// @Router /keyword-alerts/alerts/read [post]
func (h *KeywordAlertHandler) MarkAlertsRead(c *fiber.Ctx) error {
	userID := c.Locals("userID").(uint)

	var req services.MarkReadRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	count, err := h.service.MarkAlertsRead(userID, req.AlertIDs)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(fiber.Map{"updated": count})
}

// DeleteAlert godoc
// @Summary Delete alert
// @Tags keyword-alerts
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path int true "Alert ID"
// @Success 204
// @Router /keyword-alerts/alerts/{id} [delete]
func (h *KeywordAlertHandler) DeleteAlert(c *fiber.Ctx) error {
	userID := c.Locals("userID").(uint)
	id, _ := strconv.Atoi(c.Params("id"))

	if err := h.service.DeleteAlert(userID, uint(id)); err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
	}

	return c.SendStatus(fiber.StatusNoContent)
}

// RegisterFCM godoc
// @Summary Register FCM token
// @Tags keyword-alerts
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param request body services.FCMRegisterRequest true "FCM token"
// @Success 200 {object} models.FCMDevice
// @Router /keyword-alerts/fcm/register [post]
func (h *KeywordAlertHandler) RegisterFCM(c *fiber.Ctx) error {
	userID := c.Locals("userID").(uint)

	var req services.FCMRegisterRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	device, err := h.service.RegisterFCM(userID, &req)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(device)
}

// UnregisterFCM godoc
// @Summary Unregister FCM token
// @Tags keyword-alerts
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param request body services.FCMUnregisterRequest true "FCM token"
// @Success 204
// @Router /keyword-alerts/fcm/unregister [delete]
func (h *KeywordAlertHandler) UnregisterFCM(c *fiber.Ctx) error {
	userID := c.Locals("userID").(uint)

	var req services.FCMUnregisterRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	if err := h.service.UnregisterFCM(userID, req.Token); err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
	}

	return c.SendStatus(fiber.StatusNoContent)
}

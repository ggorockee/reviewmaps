package handlers

import (
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/services"
	"github.com/gofiber/fiber/v2"
)

type UserHandler struct {
	service *services.UserService
}

func NewUserHandler(db *database.DB) *UserHandler {
	return &UserHandler{
		service: services.NewUserService(db),
	}
}

func SetupUserRoutes(router fiber.Router, db *database.DB) {
	h := NewUserHandler(db)

	router.Get("/me", h.GetMe)
	router.Put("/me", h.UpdateMe)
	router.Delete("/me", h.DeleteMe)
}

// GetMe godoc
// @Summary Get current user info
// @Tags users
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} models.User
// @Router /users/me [get]
func (h *UserHandler) GetMe(c *fiber.Ctx) error {
	userID := c.Locals("userID").(uint)

	user, err := h.service.GetByID(userID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "User not found"})
	}

	return c.JSON(user)
}

// UpdateMe godoc
// @Summary Update current user info
// @Tags users
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param request body services.UpdateUserRequest true "Update data"
// @Success 200 {object} models.User
// @Router /users/me [put]
func (h *UserHandler) UpdateMe(c *fiber.Ctx) error {
	userID := c.Locals("userID").(uint)

	var req services.UpdateUserRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	user, err := h.service.Update(userID, &req)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(user)
}

// DeleteMe godoc
// @Summary Delete current user
// @Tags users
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 204
// @Router /users/me [delete]
func (h *UserHandler) DeleteMe(c *fiber.Ctx) error {
	userID := c.Locals("userID").(uint)

	if err := h.service.Delete(userID); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.SendStatus(fiber.StatusNoContent)
}

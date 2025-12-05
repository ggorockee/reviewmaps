package handlers

import (
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/services"
	"github.com/gofiber/fiber/v2"
)

type CategoryHandler struct {
	service *services.CategoryService
}

func NewCategoryHandler(db *database.DB) *CategoryHandler {
	return &CategoryHandler{
		service: services.NewCategoryService(db),
	}
}

func SetupCategoryRoutes(router fiber.Router, db *database.DB) {
	h := NewCategoryHandler(db)

	router.Get("/", h.List)
}

// List godoc
// @Summary List categories
// @Tags categories
// @Accept json
// @Produce json
// @Success 200 {array} models.Category
// @Router /categories [get]
func (h *CategoryHandler) List(c *fiber.Ctx) error {
	categories, err := h.service.List()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(categories)
}

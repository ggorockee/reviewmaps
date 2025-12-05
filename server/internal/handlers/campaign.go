package handlers

import (
	"strconv"

	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/services"
	"github.com/gofiber/fiber/v2"
)

type CampaignHandler struct {
	service *services.CampaignService
}

func NewCampaignHandler(db *database.DB) *CampaignHandler {
	return &CampaignHandler{
		service: services.NewCampaignService(db),
	}
}

func SetupCampaignRoutes(router fiber.Router, db *database.DB) {
	h := NewCampaignHandler(db)

	router.Get("/", h.List)
	router.Get("/:id", h.Get)
}

// List godoc
// @Summary List campaigns
// @Tags campaigns
// @Accept json
// @Produce json
// @Param page query int false "Page number"
// @Param limit query int false "Items per page"
// @Param category_id query int false "Filter by category"
// @Param platform query string false "Filter by platform"
// @Param region query string false "Filter by region"
// @Param lat query number false "User latitude"
// @Param lng query number false "User longitude"
// @Success 200 {object} services.CampaignListResponse
// @Router /campaigns [get]
func (h *CampaignHandler) List(c *fiber.Ctx) error {
	page, _ := strconv.Atoi(c.Query("page", "1"))
	limit, _ := strconv.Atoi(c.Query("limit", "20"))
	categoryID, _ := strconv.Atoi(c.Query("category_id", "0"))
	platform := c.Query("platform")
	region := c.Query("region")
	lat, _ := strconv.ParseFloat(c.Query("lat", "0"), 64)
	lng, _ := strconv.ParseFloat(c.Query("lng", "0"), 64)

	filter := services.CampaignFilter{
		Page:       page,
		Limit:      limit,
		CategoryID: uint(categoryID),
		Platform:   platform,
		Region:     region,
		Lat:        lat,
		Lng:        lng,
	}

	response, err := h.service.List(&filter)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(response)
}

// Get godoc
// @Summary Get campaign by ID
// @Tags campaigns
// @Accept json
// @Produce json
// @Param id path int true "Campaign ID"
// @Success 200 {object} models.Campaign
// @Router /campaigns/{id} [get]
func (h *CampaignHandler) Get(c *fiber.Ctx) error {
	id, err := strconv.Atoi(c.Params("id"))
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid campaign ID"})
	}

	campaign, err := h.service.GetByID(uint(id))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "Campaign not found"})
	}

	return c.JSON(campaign)
}

package handlers

import (
	"log"

	"github.com/ggorockee/reviewmaps/server/internal/config"
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/services"
	"github.com/gofiber/fiber/v2"
)

type InternalHandler struct {
	db           *database.DB
	cfg          *config.Config
	keywordMatch *services.KeywordMatchService
}

func NewInternalHandler(db *database.DB, cfg *config.Config) *InternalHandler {
	return &InternalHandler{
		db:           db,
		cfg:          cfg,
		keywordMatch: services.NewKeywordMatchService(db),
	}
}

func SetupInternalRoutes(router fiber.Router, db *database.DB, cfg *config.Config) {
	h := NewInternalHandler(db, cfg)

	// 내부 API (Scraper용) - API Key 인증 필요
	router.Post("/process-campaign-alerts", h.ProcessCampaignAlerts)
}

// ProcessCampaignAlertsRequest 캠페인 알림 처리 요청
type ProcessCampaignAlertsRequest struct {
	CampaignIDs []uint `json:"campaign_ids"`
}

// ProcessCampaignAlertsResponse 캠페인 알림 처리 응답
type ProcessCampaignAlertsResponse struct {
	ProcessedCount int      `json:"processed_count"`
	AlertsCreated  int      `json:"alerts_created"`
	Errors         []string `json:"errors,omitempty"`
}

// ProcessCampaignAlerts godoc
// @Summary Process keyword alerts for campaigns
// @Description Scraper에서 새로 저장한 캠페인들에 대해 키워드 매칭 및 알림 처리
// @Tags internal
// @Accept json
// @Produce json
// @Param X-API-Key header string true "Internal API Key"
// @Param request body ProcessCampaignAlertsRequest true "Campaign IDs to process"
// @Success 200 {object} ProcessCampaignAlertsResponse
// @Router /internal/process-campaign-alerts [post]
func (h *InternalHandler) ProcessCampaignAlerts(c *fiber.Ctx) error {
	// API Key 검증
	apiKey := c.Get("X-API-Key")
	if apiKey == "" || apiKey != h.cfg.InternalAPIKey {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Invalid or missing API key",
		})
	}

	var req ProcessCampaignAlertsRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	if len(req.CampaignIDs) == 0 {
		return c.JSON(ProcessCampaignAlertsResponse{
			ProcessedCount: 0,
			AlertsCreated:  0,
		})
	}

	log.Printf("[Internal] Processing %d campaigns for keyword alerts", len(req.CampaignIDs))

	// 캠페인별 키워드 매칭
	ctx := c.Context()
	alertsCreated := 0
	var errors []string

	for _, campaignID := range req.CampaignIDs {
		count := h.keywordMatch.ProcessCampaignKeywordMatchingByID(ctx, campaignID)
		alertsCreated += count
	}

	log.Printf("[Internal] Processed %d campaigns, created %d alerts", len(req.CampaignIDs), alertsCreated)

	return c.JSON(ProcessCampaignAlertsResponse{
		ProcessedCount: len(req.CampaignIDs),
		AlertsCreated:  alertsCreated,
		Errors:         errors,
	})
}

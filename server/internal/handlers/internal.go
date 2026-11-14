package handlers

import (
	"context"
	"log"
	"time"

	"github.com/ggorockee/reviewmaps/server/internal/config"
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/services"
	"github.com/gofiber/fiber/v2"
)

// pushTimeout 응답 후 백그라운드 푸시 발송 최대 시간
const pushTimeout = 5 * time.Minute

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

	// 전체 캠페인을 한 번에 키워드 매칭 (키워드/기존 알림 조회 및 알림 INSERT 일괄 처리)
	start := time.Now()
	var errors []string

	allAlertIDs, err := h.keywordMatch.ProcessCampaignsKeywordMatching(c.UserContext(), req.CampaignIDs)
	if err != nil {
		// 일부 청크가 처리된 뒤 실패할 수 있으므로, 이미 생성된 알림의 푸시는 계속 발송
		log.Printf("[Internal] Keyword matching error: %v", err)
		errors = append(errors, err.Error())
	}

	alertsCreated := len(allAlertIDs)
	log.Printf("[Internal] Processed %d campaigns, created %d alerts in %s",
		len(req.CampaignIDs), alertsCreated, time.Since(start).Round(time.Millisecond))

	// 푸시 알림 한 번에 발송 (사용자별 통합)
	// 응답 후에도 실행되므로 요청 컨텍스트(fasthttp RequestCtx는 응답 후 재사용됨) 대신 독립 컨텍스트 사용
	if alertsCreated > 0 {
		go func(alertIDs []uint) {
			pushCtx, cancel := context.WithTimeout(context.Background(), pushTimeout)
			defer cancel()
			h.keywordMatch.SendPushForRecentAlerts(pushCtx, alertIDs)
		}(allAlertIDs)
	}

	if err != nil && alertsCreated == 0 {
		return c.Status(fiber.StatusInternalServerError).JSON(ProcessCampaignAlertsResponse{
			ProcessedCount: 0,
			AlertsCreated:  0,
			Errors:         errors,
		})
	}

	return c.JSON(ProcessCampaignAlertsResponse{
		ProcessedCount: len(req.CampaignIDs),
		AlertsCreated:  alertsCreated,
		Errors:         errors,
	})
}

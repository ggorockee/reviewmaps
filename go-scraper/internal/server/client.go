package server

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/logger"
)

// Client Server API 클라이언트
type Client struct {
	baseURL    string
	apiKey     string
	enabled    bool
	httpClient *http.Client
}

// NewClient 새 클라이언트 생성
func NewClient(cfg *config.Config) *Client {
	return &Client{
		baseURL: cfg.ServerAPI.BaseURL,
		apiKey:  cfg.ServerAPI.APIKey,
		enabled: cfg.ServerAPI.Enabled,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
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

// ProcessCampaignAlerts 저장된 캠페인들에 대해 키워드 알림 처리 요청
func (c *Client) ProcessCampaignAlerts(ctx context.Context, campaignIDs []uint) (*ProcessCampaignAlertsResponse, error) {
	log := logger.GetLogger("server.client")

	if !c.enabled {
		log.Info("[ServerAPI] Server API 연동이 비활성화되어 있습니다")
		return nil, nil
	}

	if len(campaignIDs) == 0 {
		log.Info("[ServerAPI] 처리할 캠페인 ID가 없습니다")
		return nil, nil
	}

	if c.baseURL == "" {
		log.Warn("[ServerAPI] Server API Base URL이 설정되지 않았습니다")
		return nil, nil
	}

	log.Infof("[ServerAPI] %d개 캠페인 알림 처리 요청 시작", len(campaignIDs))

	// 요청 생성
	reqBody := ProcessCampaignAlertsRequest{
		CampaignIDs: campaignIDs,
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("요청 JSON 생성 실패: %w", err)
	}

	url := fmt.Sprintf("%s/v1/internal/process-campaign-alerts", c.baseURL)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("HTTP 요청 생성 실패: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", c.apiKey)

	// 요청 실행
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("HTTP 요청 실패: %w", err)
	}
	defer resp.Body.Close()

	// 응답 처리
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Server API 오류: status=%d", resp.StatusCode)
	}

	var result ProcessCampaignAlertsResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("응답 JSON 파싱 실패: %w", err)
	}

	log.Infof("[ServerAPI] 알림 처리 완료: processed=%d, alerts_created=%d",
		result.ProcessedCount, result.AlertsCreated)

	return &result, nil
}

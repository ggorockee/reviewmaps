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

// AlertBatchSize 키워드 알림 처리 요청 1회당 최대 캠페인 수
//
// 서버는 캠페인당 약 85ms가 소요되어(2026-11-14 운영 로그: 780개 66초),
// 한 번에 모두 보내면 클라이언트 타임아웃(30초)을 초과합니다.
// 100개 단위면 요청당 약 10초 내외로 타임아웃 여유가 충분합니다.
const AlertBatchSize = 100

// ProcessCampaignAlerts 저장된 캠페인들에 대해 키워드 알림 처리 요청
//
// campaignIDs를 AlertBatchSize 단위로 나누어 순차 요청합니다.
// 일부 배치가 실패해도 나머지 배치는 계속 처리하며,
// 성공한 배치의 집계 결과와 함께 실패 배치 수를 담은 에러를 반환합니다.
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

	totalBatches := (len(campaignIDs) + AlertBatchSize - 1) / AlertBatchSize
	log.Infof("[ServerAPI] %d개 캠페인 알림 처리 요청 시작 (%d개 배치)", len(campaignIDs), totalBatches)

	total := &ProcessCampaignAlertsResponse{}
	var failedBatches int
	var lastErr error

	for i := 0; i < len(campaignIDs); i += AlertBatchSize {
		if err := ctx.Err(); err != nil {
			return total, fmt.Errorf("알림 처리 중단: %w", err)
		}

		end := min(i+AlertBatchSize, len(campaignIDs))
		batchNo := i/AlertBatchSize + 1

		result, err := c.processBatch(ctx, campaignIDs[i:end])
		if err != nil {
			failedBatches++
			lastErr = err
			log.Warnf("[ServerAPI] 배치 %d/%d 실패 (%d개): %v", batchNo, totalBatches, end-i, err)
			continue
		}

		total.ProcessedCount += result.ProcessedCount
		total.AlertsCreated += result.AlertsCreated
		total.Errors = append(total.Errors, result.Errors...)
	}

	log.Infof("[ServerAPI] 알림 처리 완료: processed=%d, alerts_created=%d, failed_batches=%d/%d",
		total.ProcessedCount, total.AlertsCreated, failedBatches, totalBatches)

	if failedBatches > 0 {
		return total, fmt.Errorf("%d/%d개 배치 실패 (마지막 오류: %w)", failedBatches, totalBatches, lastErr)
	}
	return total, nil
}

// processBatch 캠페인 ID 배치 1건 요청
func (c *Client) processBatch(ctx context.Context, campaignIDs []uint) (*ProcessCampaignAlertsResponse, error) {
	jsonBody, err := json.Marshal(ProcessCampaignAlertsRequest{CampaignIDs: campaignIDs})
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

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("HTTP 요청 실패: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Server API 오류: status=%d", resp.StatusCode)
	}

	var result ProcessCampaignAlertsResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("응답 JSON 파싱 실패: %w", err)
	}
	return &result, nil
}

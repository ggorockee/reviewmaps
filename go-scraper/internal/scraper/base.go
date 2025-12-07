package scraper

import (
	"context"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/db"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/enricher"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/logger"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/server"
	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
)

// Scraper 스크레이퍼 인터페이스
type Scraper interface {
	// PlatformName 플랫폼 이름 반환
	PlatformName() string
	// BaseURL 기본 URL 반환
	BaseURL() string
	// Scrape 데이터 수집
	Scrape(ctx context.Context, keyword *string) ([]map[string]interface{}, error)
	// Parse 데이터 파싱
	Parse(ctx context.Context, rawData []map[string]interface{}) ([]models.Campaign, error)
	// Enrich 데이터 보강 (선택적)
	Enrich(ctx context.Context, parsedData []models.Campaign) ([]models.Campaign, error)
	// Run 전체 파이프라인 실행
	Run(ctx context.Context, keyword *string) error
}

// BaseScraper 기본 스크레이퍼 구현
type BaseScraper struct {
	Config       *config.Config
	DB           *db.DB
	Enricher     *enricher.Enricher
	ServerClient *server.Client
}

// NewBaseScraper 새로운 BaseScraper 생성
func NewBaseScraper(cfg *config.Config, database *db.DB) *BaseScraper {
	return &BaseScraper{
		Config:       cfg,
		DB:           database,
		Enricher:     enricher.New(cfg),
		ServerClient: server.NewClient(cfg),
	}
}

// Enrich 기본 Enrich 구현 (아무것도 안함)
func (b *BaseScraper) Enrich(ctx context.Context, parsedData []models.Campaign) ([]models.Campaign, error) {
	log := logger.GetLogger("scraper.base")
	log.Info("Enrich 단계는 구현되지 않아 건너뜁니다.")
	return parsedData, nil
}

// Save 데이터 저장 및 키워드 알림 처리 요청
func (b *BaseScraper) Save(ctx context.Context, data []models.Campaign) error {
	log := logger.GetLogger("scraper.base")

	// 1. DB에 저장하고 저장된 캠페인 ID 목록 받기
	campaignIDs, err := b.DB.UpsertCampaigns(ctx, data)
	if err != nil {
		return err
	}

	// 2. Server API로 키워드 알림 처리 요청
	if len(campaignIDs) > 0 && b.ServerClient != nil {
		result, err := b.ServerClient.ProcessCampaignAlerts(ctx, campaignIDs)
		if err != nil {
			log.Warnf("Server API 호출 실패 (알림 처리 계속 진행): %v", err)
		} else if result != nil {
			log.Infof("키워드 알림 처리 완료: %d개 캠페인, %d개 알림 생성",
				result.ProcessedCount, result.AlertsCreated)
		}
	}

	return nil
}

// GetAPIKeys API 키 목록 반환
func (b *BaseScraper) GetAPIKeys() []config.APIKeyPair {
	return b.Config.NaverAPI.GetSearchAPIKeys()
}

// LoadExistingCampaigns 기존 캠페인 맵 로딩
func (b *BaseScraper) LoadExistingCampaigns(ctx context.Context) (map[string]*models.CampaignKey, error) {
	return b.DB.LoadExistingCampaigns(ctx)
}

// RunPipeline 전체 파이프라인 실행 (공통 로직)
func RunPipeline(ctx context.Context, s Scraper, keyword *string) error {
	log := logger.GetLogger("scraper")

	keywordStr := "전체"
	if keyword != nil {
		keywordStr = *keyword
	}

	log.Infof("===== %s 스크레이핑 시작 (키워드: %s) =====", s.PlatformName(), keywordStr)

	// 1. Scrape
	rawData, err := s.Scrape(ctx, keyword)
	if err != nil {
		log.Errorf("scrape 단계에서 에러 발생: %v", err)
		return err
	}
	if len(rawData) == 0 {
		log.Warn("scrape 단계에서 데이터를 가져오지 못했습니다.")
		return nil
	}

	// 2. Parse
	parsedData, err := s.Parse(ctx, rawData)
	if err != nil {
		log.Errorf("parse 단계에서 에러 발생: %v", err)
		return err
	}
	if len(parsedData) == 0 {
		log.Warn("parse 단계에서 데이터가 파싱되지 않았습니다.")
		return nil
	}
	log.Infof("총 %d개의 아이템을 파싱했습니다.", len(parsedData))

	// 3. Enrich
	enrichedData, err := s.Enrich(ctx, parsedData)
	if err != nil {
		log.Errorf("enrich 단계에서 에러 발생: %v", err)
		return err
	}

	// 4. Run (Save는 각 스크레이퍼에서 처리)
	log.Infof("===== %s 스크레이핑 종료 =====", s.PlatformName())

	_ = enrichedData // 실제 저장은 구현체에서
	return nil
}

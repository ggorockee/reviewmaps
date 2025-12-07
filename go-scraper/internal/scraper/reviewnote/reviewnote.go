package reviewnote

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/db"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/logger"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/scraper"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/telemetry"
	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
)

const (
	platformName = "리뷰노트"
	baseURL      = "https://www.reviewnote.co.kr/api/v2/campaigns"
	imageBaseURL = "https://reviewnote.s3.ap-northeast-2.amazonaws.com/"
	pageLimit    = 100
)

// channelMap reviewnote channel을 내부 채널 형식으로 매핑
var channelMap = map[string]string{
	"BLOG":       "blog",
	"BLOG_CLIP":  "blog,clip",
	"INSTAGRAM":  "instagram",
	"REELS":      "reels",
	"YOUTUBE":    "youtube",
	"SHORTS":     "shorts",
	"TIKTOK":     "tiktok",
}

// sortToCampaignType sort 값을 campaign_type으로 매핑
var sortToCampaignType = map[string]string{
	"VISIT":    "방문형",
	"DELIVERY": "배송형",
	"PURCHASE": "구매형",
}

// APIResponse API 응답 구조체
type APIResponse struct {
	Page    int               `json:"page"`
	Objects []CampaignRawData `json:"objects"`
}

// CampaignRawData API에서 받아온 캠페인 원시 데이터
type CampaignRawData struct {
	ID                      int       `json:"id"`
	Title                   string    `json:"title"`
	Status                  string    `json:"status"`
	Sort                    string    `json:"sort"`
	Channel                 string    `json:"channel"`
	InfNum                  int       `json:"infNum"`
	InfPoint                int       `json:"infPoint"`
	Offer                   string    `json:"offer"`
	ImageKey                string    `json:"imageKey"`
	City                    string    `json:"city"`
	CurrentTurn             int       `json:"currentTurn"`
	ApplyEndAt              *string   `json:"applyEndAt"`
	ReviewEndAt             *string   `json:"reviewEndAt"`
	ExtendedReviewEndAt     *string   `json:"extendedReviewEndAt"`
	BeforeReviewEndAt       *string   `json:"beforeReviewEndAt"`
	ReviewlottoPosition     *int      `json:"reviewlottoPosition"`
	HotDealPosition         *int      `json:"hotDealPosition"`
	ProductPurchasePoint    *int      `json:"productPurchasePoint"`
	AdditionalRewardPoint   *int      `json:"additionalRewardPoint"`
	ApplicantCount          int       `json:"applicantCount"`
	IsPremium               bool      `json:"isPremium"`
	PremiumPosition         *int      `json:"premiumPosition"`
	Category                *Category `json:"category"`
	Sido                    *Sido     `json:"sido"`
}

// Category 카테고리 정보
type Category struct {
	Title string `json:"title"`
}

// Sido 지역 정보
type Sido struct {
	Name string `json:"name"`
}

// Scraper reviewnote 스크래퍼
type Scraper struct {
	*scraper.BaseScraper
	httpClient *http.Client
	telemetry  *telemetry.Telemetry
}

// New 새로운 reviewnote 스크래퍼 생성
func New(cfg *config.Config, database *db.DB, tel *telemetry.Telemetry) *Scraper {
	return &Scraper{
		BaseScraper: scraper.NewBaseScraper(cfg, database),
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		telemetry: tel,
	}
}

// PlatformName 플랫폼 이름 반환
func (s *Scraper) PlatformName() string {
	return platformName
}

// BaseURL 기본 URL 반환
func (s *Scraper) BaseURL() string {
	return baseURL
}

// Run 전체 파이프라인 실행
func (s *Scraper) Run(ctx context.Context, keyword *string) error {
	log := logger.GetLogger("scraper.reviewnote")

	keywordStr := "전체"
	if keyword != nil {
		keywordStr = *keyword
	}

	log.Infof("===== %s 스크레이핑 시작 (키워드: %s) =====", platformName, keywordStr)

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

	// 3. Enrich (선택적)
	enrichedData, err := s.Enrich(ctx, parsedData)
	if err != nil {
		log.Errorf("enrich 단계에서 에러 발생: %v", err)
		return err
	}

	// 4. Save
	if err := s.Save(ctx, enrichedData); err != nil {
		log.Errorf("save 단계에서 에러 발생: %v", err)
		return err
	}

	log.Infof("===== %s 스크레이핑 종료 =====", platformName)
	return nil
}

// Scrape 데이터 수집 - 모든 페이지를 순회하며 데이터 수집
func (s *Scraper) Scrape(ctx context.Context, keyword *string) ([]map[string]interface{}, error) {
	log := logger.GetLogger("scraper.reviewnote")

	var allData []map[string]interface{}
	page := 0
	maxItems := s.Config.Scrape.MaxItems

	if maxItems > 0 {
		log.Infof("MaxItems 제한 설정: %d개", maxItems)
	}

	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}

		// API URL 구성
		url := fmt.Sprintf("%s?limit=%d&page=%d", baseURL, pageLimit, page)
		log.Infof("Fetching page %d: %s", page, url)

		// HTTP 요청
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			return nil, fmt.Errorf("failed to create request: %w", err)
		}

		req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
		req.Header.Set("Accept", "application/json")

		resp, err := s.httpClient.Do(req)
		if err != nil {
			return nil, fmt.Errorf("failed to fetch page %d: %w", page, err)
		}

		if resp.StatusCode != http.StatusOK {
			resp.Body.Close()
			return nil, fmt.Errorf("unexpected status code %d for page %d", resp.StatusCode, page)
		}

		var apiResp APIResponse
		if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
			resp.Body.Close()
			return nil, fmt.Errorf("failed to decode response for page %d: %w", page, err)
		}
		resp.Body.Close()

		// 데이터가 없으면 종료
		if len(apiResp.Objects) == 0 {
			log.Infof("No more data at page %d, stopping", page)
			break
		}

		// 원시 데이터를 map으로 변환하여 저장
		for _, obj := range apiResp.Objects {
			// MaxItems 제한 체크
			if maxItems > 0 && len(allData) >= maxItems {
				log.Infof("MaxItems 제한(%d)에 도달, 수집 중단", maxItems)
				break
			}

			rawMap := make(map[string]interface{})
			rawMap["id"] = obj.ID
			rawMap["title"] = obj.Title
			rawMap["status"] = obj.Status
			rawMap["sort"] = obj.Sort
			rawMap["channel"] = obj.Channel
			rawMap["infNum"] = obj.InfNum
			rawMap["infPoint"] = obj.InfPoint
			rawMap["offer"] = obj.Offer
			rawMap["imageKey"] = obj.ImageKey
			rawMap["city"] = obj.City
			if obj.ApplyEndAt != nil {
				rawMap["applyEndAt"] = *obj.ApplyEndAt
			}
			if obj.ReviewEndAt != nil {
				rawMap["reviewEndAt"] = *obj.ReviewEndAt
			}
			rawMap["applicantCount"] = obj.ApplicantCount
			rawMap["isPremium"] = obj.IsPremium

			if obj.Category != nil {
				rawMap["categoryTitle"] = obj.Category.Title
			}
			if obj.Sido != nil {
				rawMap["sidoName"] = obj.Sido.Name
			}

			allData = append(allData, rawMap)
		}

		log.Infof("Page %d: fetched %d items (total: %d)", page, len(apiResp.Objects), len(allData))

		// MaxItems 제한에 도달하면 종료
		if maxItems > 0 && len(allData) >= maxItems {
			break
		}

		// 받은 데이터가 limit보다 적으면 마지막 페이지
		if len(apiResp.Objects) < pageLimit {
			break
		}

		page++

		// Rate limiting
		time.Sleep(100 * time.Millisecond)
	}

	log.Infof("Scrape 완료: 총 %d개 캠페인 수집", len(allData))
	return allData, nil
}

// Parse 데이터 파싱 - 원시 데이터를 Campaign 모델로 변환
func (s *Scraper) Parse(ctx context.Context, rawData []map[string]interface{}) ([]models.Campaign, error) {
	log := logger.GetLogger("scraper.reviewnote")

	var campaigns []models.Campaign
	seen := make(map[string]bool)

	for _, raw := range rawData {
		campaign := models.Campaign{
			Platform: platformName,
			Source:   platformName,
		}

		// Title
		if title, ok := raw["title"].(string); ok {
			campaign.Title = strings.TrimSpace(title)
			campaign.Company = campaign.Title // 회사명은 타이틀과 동일
		}

		// Offer
		if offer, ok := raw["offer"].(string); ok {
			campaign.Offer = strings.TrimSpace(offer)
		}

		// Channel 매핑
		if channel, ok := raw["channel"].(string); ok {
			if mapped, exists := channelMap[channel]; exists {
				campaign.CampaignChannel = mapped
			} else {
				campaign.CampaignChannel = strings.ToLower(channel)
			}
		}

		// Campaign Type (sort → campaign_type)
		if sort, ok := raw["sort"].(string); ok {
			if mapped, exists := sortToCampaignType[sort]; exists {
				campaign.CampaignType = &mapped
			}
		}

		// Region (city + sidoName)
		if city, ok := raw["city"].(string); ok {
			region := city
			if sidoName, ok := raw["sidoName"].(string); ok && sidoName != "" && sidoName != city {
				region = fmt.Sprintf("%s %s", city, sidoName)
			}
			campaign.Region = &region
		}

		// Content Link
		if id, ok := raw["id"].(int); ok {
			contentLink := fmt.Sprintf("https://www.reviewnote.co.kr/campaigns/%d", id)
			campaign.ContentLink = &contentLink
			campaign.CompanyLink = &contentLink
		}

		// Image URL
		if imageKey, ok := raw["imageKey"].(string); ok && imageKey != "" {
			imgURL := imageBaseURL + imageKey
			campaign.ImgURL = &imgURL
		}

		// Apply Deadline
		if applyEndAt := raw["applyEndAt"]; applyEndAt != nil {
			if str, ok := applyEndAt.(string); ok && str != "" {
				if t, err := time.Parse(time.RFC3339, str); err == nil {
					campaign.ApplyDeadline = &t
				}
			}
		}

		// Review Deadline
		if reviewEndAt := raw["reviewEndAt"]; reviewEndAt != nil {
			if str, ok := reviewEndAt.(string); ok && str != "" {
				if t, err := time.Parse(time.RFC3339, str); err == nil {
					campaign.ReviewDeadline = &t
				}
			}
		}

		// Search Text (키워드 검색용)
		campaign.SearchText = campaign.Title

		// 중복 체크 (platform + title + offer + campaign_channel)
		dedupKey := fmt.Sprintf("%s|%s|%s|%s",
			campaign.Platform, campaign.Title, campaign.Offer, campaign.CampaignChannel)
		if seen[dedupKey] {
			continue
		}
		seen[dedupKey] = true

		campaigns = append(campaigns, campaign)
	}

	log.Infof("Parse 완료: %d개 중 %d개 캠페인 파싱 (중복 제거)", len(rawData), len(campaigns))

	// 메트릭 기록
	if s.telemetry != nil {
		s.telemetry.AddCampaignsScraped(ctx, int64(len(campaigns)), platformName)
	}

	return campaigns, nil
}

// scrapePage 단일 페이지 데이터 수집 (테스트용 헬퍼)
func (s *Scraper) scrapePage(ctx context.Context, page, limit int) ([]map[string]interface{}, error) {
	url := fmt.Sprintf("%s?limit=%d&page=%d", baseURL, limit, page)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
	req.Header.Set("Accept", "application/json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch page %d: %w", page, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code %d for page %d", resp.StatusCode, page)
	}

	var apiResp APIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("failed to decode response for page %d: %w", page, err)
	}

	var result []map[string]interface{}
	for _, obj := range apiResp.Objects {
		rawMap := make(map[string]interface{})
		rawMap["id"] = obj.ID
		rawMap["title"] = obj.Title
		rawMap["status"] = obj.Status
		rawMap["sort"] = obj.Sort
		rawMap["channel"] = obj.Channel
		rawMap["infNum"] = obj.InfNum
		rawMap["infPoint"] = obj.InfPoint
		rawMap["offer"] = obj.Offer
		rawMap["imageKey"] = obj.ImageKey
		rawMap["city"] = obj.City
		if obj.ApplyEndAt != nil {
			rawMap["applyEndAt"] = *obj.ApplyEndAt
		}
		if obj.ReviewEndAt != nil {
			rawMap["reviewEndAt"] = *obj.ReviewEndAt
		}
		rawMap["applicantCount"] = obj.ApplicantCount
		rawMap["isPremium"] = obj.IsPremium

		if obj.Category != nil {
			rawMap["categoryTitle"] = obj.Category.Title
		}
		if obj.Sido != nil {
			rawMap["sidoName"] = obj.Sido.Name
		}

		result = append(result, rawMap)
	}

	return result, nil
}

// Enrich 데이터 보강 - 주소/좌표 정보 추가 (방문형만)
func (s *Scraper) Enrich(ctx context.Context, parsedData []models.Campaign) ([]models.Campaign, error) {
	log := logger.GetLogger("scraper.reviewnote")

	log.Info("Enrich 단계: 방문형 캠페인 주소/좌표 보강 시작")

	// Worker Pool 패턴으로 병렬 처리
	// - MaxWorkers: 3 (네이버 API 키 개수와 맞춤)
	// - APIDelay: 200ms (Rate limiting)
	config := DefaultEnrichConfig()

	enrichedData, stats := s.enrichVisitCampaigns(ctx, parsedData, config)

	log.Infof("Enrich 완료: %d건 처리 (CacheHit: %d, API: %d, Geocode: %d)",
		stats.Total, stats.CacheHit, stats.APICalled, stats.Geocoded)

	return enrichedData, nil
}

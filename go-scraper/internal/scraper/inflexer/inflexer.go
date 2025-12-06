package inflexer

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
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
	platformName   = "inflexer"
	searchURL      = "https://inflexer.net:5000/search"
	mapURL         = "https://inflexer.net:5000/map"
	requestTimeout = 30 * time.Second
)

// MEDIA_MAP 미디어 타입 매핑
var mediaMap = map[string]string{
	"BP_":       "blog",
	"IP_":       "instagram",
	"IR_":       "reels",
	"BC_":       "clip",
	"BP_BC_":    "blog,clip",
	"IP_IR_":    "instagram,reels",
	"BP_IP_":    "blog,instagram",
	"IP_IP_":    "instagram",
	"YP_":       "youtube",
	"YS_":       "shorts",
	"YP_YS_":    "youtube,shorts",
	"SR_":       "shorts",
	"":          "etc",
}

// TYPE_MAP 타입 매핑
var typeMap = map[string]string{
	"PRS":          "기자단",
	"VST":          "방문형",
	"SHP":          "배송형",
	"서울오빠_기타": "구매평",
}

// SearchAPIResponse 검색 API 응답
type SearchAPIResponse struct {
	IsValid bool             `json:"is_valid"`
	Result  []CampaignRawData `json:"result"`
}

// MapAPIResponse 맵 API 응답
type MapAPIResponse struct {
	Result []MapData `json:"result"`
}

// CampaignRawData API에서 받아온 캠페인 원시 데이터
type CampaignRawData struct {
	Domain    string  `json:"domain"`
	Title     string  `json:"title"`
	Offer     string  `json:"offer"`
	URL       string  `json:"url"`
	Media     string  `json:"media"`
	Type      string  `json:"type"`
	AplDueDt  *string `json:"apl_due_dt"`
	PubDueDt  *string `json:"pub_due_dt"`
	AplSttDt  *string `json:"apl_stt_dt"`
}

// MapData 맵 API 데이터
type MapData struct {
	Title     string   `json:"title"`
	Latitude  *float64 `json:"latitude"`
	Longitude *float64 `json:"longitude"`
}

// Scraper inflexer 스크래퍼
type Scraper struct {
	*scraper.BaseScraper
	httpClient *http.Client
	telemetry  *telemetry.Telemetry
}

// New 새로운 inflexer 스크래퍼 생성
func New(cfg *config.Config, database *db.DB, tel *telemetry.Telemetry) *Scraper {
	return &Scraper{
		BaseScraper: scraper.NewBaseScraper(cfg, database),
		httpClient: &http.Client{
			Timeout: requestTimeout,
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
	return searchURL
}

// Run 전체 파이프라인 실행
func (s *Scraper) Run(ctx context.Context, keyword *string) error {
	log := logger.GetLogger("scraper.inflexer")

	keywordStr := "전체"
	if keyword != nil {
		keywordStr = *keyword
	}

	log.Infof("===== %s 스크레이핑 시작 (키워드: %s) =====", platformName, keywordStr)

	// 1. Scrape (Search + Map API 병렬 호출)
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

// Scrape 데이터 수집 - Search API와 Map API 병렬 호출
func (s *Scraper) Scrape(ctx context.Context, keyword *string) ([]map[string]interface{}, error) {
	log := logger.GetLogger("scraper.inflexer")

	if keyword == nil || *keyword == "" {
		return nil, fmt.Errorf("inflexer는 keyword가 필수입니다")
	}

	// 병렬로 Search와 Map API 호출
	type searchResult struct {
		data []CampaignRawData
		err  error
	}
	type mapResult struct {
		data []MapData
		err  error
	}

	searchCh := make(chan searchResult, 1)
	mapCh := make(chan mapResult, 1)

	// Search API 호출 (goroutine)
	go func() {
		data, err := s.fetchSearchAPI(ctx, *keyword)
		searchCh <- searchResult{data: data, err: err}
	}()

	// Map API 호출 (goroutine)
	go func() {
		data, err := s.fetchMapAPI(ctx, *keyword)
		mapCh <- mapResult{data: data, err: err}
	}()

	// 결과 수집
	searchRes := <-searchCh
	mapRes := <-mapCh

	if searchRes.err != nil {
		return nil, fmt.Errorf("search API 실패: %w", searchRes.err)
	}

	if len(searchRes.data) == 0 {
		log.Info("Search API에서 데이터가 없습니다.")
		return nil, nil
	}

	// Map 데이터를 title 기준으로 매핑
	mapByTitle := make(map[string]*MapData)
	if mapRes.err == nil && len(mapRes.data) > 0 {
		for i := range mapRes.data {
			mapByTitle[mapRes.data[i].Title] = &mapRes.data[i]
		}
		log.Infof("Map API에서 %d개 좌표 데이터 수집", len(mapRes.data))
	} else if mapRes.err != nil {
		log.Warnf("Map API 호출 실패 (계속 진행): %v", mapRes.err)
	}

	// 결과 병합
	var allData []map[string]interface{}
	for _, raw := range searchRes.data {
		rawMap := make(map[string]interface{})
		rawMap["domain"] = raw.Domain
		rawMap["title"] = raw.Title
		rawMap["offer"] = raw.Offer
		rawMap["url"] = raw.URL
		rawMap["media"] = raw.Media
		rawMap["type"] = raw.Type
		rawMap["keyword"] = *keyword

		if raw.AplDueDt != nil {
			rawMap["apl_due_dt"] = *raw.AplDueDt
		}
		if raw.PubDueDt != nil {
			rawMap["pub_due_dt"] = *raw.PubDueDt
		}
		if raw.AplSttDt != nil {
			rawMap["apl_stt_dt"] = *raw.AplSttDt
		}

		// Map 데이터 병합
		if mapData, ok := mapByTitle[raw.Title]; ok {
			if mapData.Latitude != nil {
				rawMap["lat"] = *mapData.Latitude
			}
			if mapData.Longitude != nil {
				rawMap["lng"] = *mapData.Longitude
			}
		}

		allData = append(allData, rawMap)
	}

	log.Infof("Scrape 완료: 총 %d개 캠페인 수집", len(allData))
	return allData, nil
}

// fetchSearchAPI Search API 호출
func (s *Scraper) fetchSearchAPI(ctx context.Context, keyword string) ([]CampaignRawData, error) {
	log := logger.GetLogger("scraper.inflexer")

	reqURL := fmt.Sprintf("%s?query=%s", searchURL, url.QueryEscape(keyword))
	log.Infof("Search API 호출: %s", reqURL)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
	req.Header.Set("Accept", "application/json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code %d", resp.StatusCode)
	}

	var apiResp SearchAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if !apiResp.IsValid {
		log.Warn("API 응답 비정상: is_valid=false")
		return nil, nil
	}

	return apiResp.Result, nil
}

// fetchMapAPI Map API 호출
func (s *Scraper) fetchMapAPI(ctx context.Context, keyword string) ([]MapData, error) {
	log := logger.GetLogger("scraper.inflexer")

	reqURL := fmt.Sprintf("%s?query=%s&type=VST", mapURL, url.QueryEscape(keyword))
	log.Infof("Map API 호출: %s", reqURL)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
	req.Header.Set("Accept", "application/json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code %d", resp.StatusCode)
	}

	var apiResp MapAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return apiResp.Result, nil
}

// Parse 데이터 파싱 - 원시 데이터를 Campaign 모델로 변환
func (s *Scraper) Parse(ctx context.Context, rawData []map[string]interface{}) ([]models.Campaign, error) {
	log := logger.GetLogger("scraper.inflexer")

	var campaigns []models.Campaign
	seen := make(map[string]bool)

	for _, raw := range rawData {
		campaign := models.Campaign{
			Source: platformName,
		}

		// Platform (domain)
		if domain, ok := raw["domain"].(string); ok {
			campaign.Platform = strings.TrimSpace(domain)
		}

		// Title
		if title, ok := raw["title"].(string); ok {
			campaign.Title = strings.TrimSpace(title)
			campaign.Company = campaign.Title
		}

		// Offer
		if offer, ok := raw["offer"].(string); ok {
			campaign.Offer = strings.TrimSpace(offer)
		}

		// URL
		if contentURL, ok := raw["url"].(string); ok {
			campaign.ContentLink = &contentURL
			campaign.CompanyLink = &contentURL
		}

		// Channel 매핑 (media)
		if media, ok := raw["media"].(string); ok {
			media = strings.TrimSpace(media)
			if mapped, exists := mediaMap[media]; exists {
				campaign.CampaignChannel = mapped
			} else {
				campaign.CampaignChannel = "etc"
			}
		}

		// Campaign Type 매핑 (type)
		if typeStr, ok := raw["type"].(string); ok {
			typeStr = strings.TrimSpace(typeStr)
			if mapped, exists := typeMap[typeStr]; exists {
				campaign.CampaignType = &mapped
			}
		}

		// Region & SearchText (keyword)
		if keyword, ok := raw["keyword"].(string); ok {
			campaign.Region = &keyword
			campaign.SearchText = keyword
		}

		// Apply Deadline
		if aplDueDt, ok := raw["apl_due_dt"].(string); ok && aplDueDt != "" {
			if t, err := time.Parse("2006-01-02T15:04:05", aplDueDt); err == nil {
				campaign.ApplyDeadline = &t
			} else if t, err := time.Parse("2006-01-02", aplDueDt); err == nil {
				campaign.ApplyDeadline = &t
			}
		}

		// Review Deadline
		if pubDueDt, ok := raw["pub_due_dt"].(string); ok && pubDueDt != "" {
			if t, err := time.Parse("2006-01-02T15:04:05", pubDueDt); err == nil {
				campaign.ReviewDeadline = &t
			} else if t, err := time.Parse("2006-01-02", pubDueDt); err == nil {
				campaign.ReviewDeadline = &t
			}
		}

		// Apply From
		if aplSttDt, ok := raw["apl_stt_dt"].(string); ok && aplSttDt != "" {
			if t, err := time.Parse("2006-01-02T15:04:05", aplSttDt); err == nil {
				campaign.ApplyFrom = &t
			} else if t, err := time.Parse("2006-01-02", aplSttDt); err == nil {
				campaign.ApplyFrom = &t
			}
		}

		// Map 데이터에서 lat/lng
		if lat, ok := raw["lat"].(float64); ok {
			campaign.Lat = &lat
		}
		if lng, ok := raw["lng"].(float64); ok {
			campaign.Lng = &lng
		}

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

// Enrich 데이터 보강 - 주소/좌표 정보 추가 (방문형만)
func (s *Scraper) Enrich(ctx context.Context, parsedData []models.Campaign) ([]models.Campaign, error) {
	log := logger.GetLogger("scraper.inflexer")

	log.Info("Enrich 단계: 방문형 캠페인 주소/좌표 보강 시작")

	// Worker Pool 패턴으로 병렬 처리
	config := DefaultEnrichConfig()

	enrichedData, stats := s.enrichVisitCampaigns(ctx, parsedData, config)

	log.Infof("Enrich 완료: %d건 처리 (CacheHit: %d, API: %d, Geocode: %d)",
		stats.Total, stats.CacheHit, stats.APICalled, stats.Geocoded)

	return enrichedData, nil
}

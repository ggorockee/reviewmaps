package reviewnote

import (
	"github.com/ggorockee/reviewmaps/go-scraper/internal/runstats"
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	neturl "net/url"
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
	// 이미지는 Firebase Storage에 있다 (사이트가 쓰는 주소, 2026-11-27 확인).
	// 예전 S3 주소(reviewnote.s3.ap-northeast-2.amazonaws.com/<키>)는 전부 404.
	imageURLFormat = "https://firebasestorage.googleapis.com/v0/b/reviewnote-e92d9.appspot.com/o/%s?alt=media"
	pageLimit    = 100
	// 목록 API는 limit 값과 상관없이 한 쪽에 16건을 주고, 한 조건당 100쪽(1,600건)까지만 준다 (2026-11-28 확인).
	// 카테고리별로 나눠 받아야 그 뒤의 공고가 빠지지 않는다.
	listPageCap = 100
	// 카테고리별 목록 요청 간격 (reviewnote 02:00)
	categoryPageDelay = time.Second
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
	httpClient  *http.Client
	telemetry   *telemetry.Telemetry
	stays       stayStore       // 보관된 상세 값 읽기 (DB)
	details     detailStore     // 상세 값 저장 (DB, reviewnote-detail)
	fetchDetail detailFetcher   // 상세 API 호출
	listPage    listPageFetcher // 목록 API 한 페이지
	sleep       func(ctx context.Context, d time.Duration) bool
	rnd         *rand.Rand
}

// New 새로운 reviewnote 스크래퍼 생성
func New(cfg *config.Config, database *db.DB, tel *telemetry.Telemetry) *Scraper {
	s := &Scraper{
		BaseScraper: scraper.NewBaseScraper(cfg, database),
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		telemetry: tel,
	}
	if database != nil {
		s.stays = database
		s.details = database
	}
	s.fetchDetail = s.fetchDetailHTTP
	s.listPage = s.scrapePage
	s.sleep = sleepCtx
	s.rnd = rand.New(rand.NewSource(time.Now().UnixNano()))
	return s
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
	runstats.SetItems(runstats.StageScraped, len(rawData))
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
	// 3. 보관된 상세 이용 조건(요일 등) 붙이기 (상세 API 호출은 reviewnote-detail 이 새벽에 따로 함)
	parsedData = s.ApplyStoredStayDetails(ctx, parsedData)

	// 4. 중복 공고는 하나만 남김 (요일 정보가 있는 것을 고르려고 상세 값을 붙인 뒤에 함)
	unique := dedupeCampaigns(parsedData)
	log.Infof("중복 제거: %d개 중 %d개를 남겼습니다", len(parsedData), len(unique))
	runstats.SetItems(runstats.StageParsed, len(unique))
	if s.telemetry != nil {
		s.telemetry.AddCampaignsScraped(ctx, int64(len(unique)), platformName)
	}

	// 5. Enrich (선택적)
	enrichedData, err := s.Enrich(ctx, unique)
	if err != nil {
		log.Errorf("enrich 단계에서 에러 발생: %v", err)
		return err
	}

	// 6. Save
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
	maxPages := s.Config.Scrape.MaxPages

	if maxItems > 0 {
		log.Infof("MaxItems 제한 설정: %d개", maxItems)
	}
	if maxPages > 0 {
		log.Infof("MaxPages 안전장치 설정: %d페이지", maxPages)
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

		req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
		req.Header.Set("Accept", "application/json")
		req.Header.Set("Referer", "https://www.reviewnote.co.kr/")

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

		// MaxPages 안전장치: API가 빈 페이지를 반환하지 않는 경우 무한루프 방지
		if maxPages > 0 && page >= maxPages-1 {
			log.Warnf("MaxPages 안전장치(%d페이지)에 도달, 수집 중단 (total: %d)", maxPages, len(allData))
			break
		}

		page++

		// Rate limiting
		time.Sleep(100 * time.Millisecond)
	}

	allData, err := s.appendCategoryPages(ctx, allData, s.Config.Reviewnote.ListCategoryIDs)
	if err != nil {
		return nil, err
	}

	log.Infof("Scrape 완료: 총 %d개 캠페인 수집", len(allData))
	return allData, nil
}

// appendCategoryPages 카테고리별 목록을 더 받아 아직 없는 공고만 붙인다.
// 필터 없는 목록은 앞의 1,600건만 주므로, 빠지면 안 되는 카테고리(여행: 이용 요일 상세 대상)는 따로 받는다.
func (s *Scraper) appendCategoryPages(ctx context.Context, data []map[string]interface{}, categoryIDs []string) ([]map[string]interface{}, error) {
	if len(categoryIDs) == 0 {
		return data, nil
	}
	log := logger.GetLogger("scraper.reviewnote")
	maxItems := s.Config.Scrape.MaxItems
	seen := make(map[int]bool, len(data))
	for _, raw := range data {
		if id, ok := raw["id"].(int); ok {
			seen[id] = true
		}
	}
	for _, categoryID := range categoryIDs {
		added := 0
		for page := 0; page < listPageCap; page++ {
			if maxItems > 0 && len(data) >= maxItems {
				return data, nil
			}
			if !s.sleep(ctx, categoryPageDelay) {
				return nil, ctx.Err()
			}
			items, err := s.listPage(ctx, categoryID, page, pageLimit)
			if err != nil {
				return nil, fmt.Errorf("카테고리 %s 목록 %d쪽: %w", categoryID, page, err)
			}
			if len(items) == 0 {
				break
			}
			for _, raw := range items {
				id, _ := raw["id"].(int)
				if id == 0 || seen[id] || (maxItems > 0 && len(data) >= maxItems) {
					continue
				}
				seen[id] = true
				data = append(data, raw)
				added++
			}
			if page == listPageCap-1 {
				log.Warnf("카테고리 %s 목록이 상한(%d쪽)까지 참, 뒤의 공고는 빠졌을 수 있음", categoryID, listPageCap)
			}
		}
		log.Infof("카테고리 %s 목록에서 %d건 추가", categoryID, added)
	}
	return data, nil
}

// Parse 데이터 파싱 - 원시 데이터를 Campaign 모델로 변환
func (s *Scraper) Parse(ctx context.Context, rawData []map[string]interface{}) ([]models.Campaign, error) {
	log := logger.GetLogger("scraper.reviewnote")

	var campaigns []models.Campaign

	for _, raw := range rawData {
		// Status 필터링: SELECT 상태 캠페인만 수집
		if status, ok := raw["status"].(string); ok {
			if status != "SELECT" {
				log.Debugf("Skip non-active campaign: %s (status: %s)",
					raw["title"], status)
				continue
			}
		}

		campaign := models.Campaign{
			Platform: platformName,
			Source:   platformName,
		}

		// Status 저장
		if status, ok := raw["status"].(string); ok && status != "" {
			campaign.Status = &status
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

		if categoryTitle, ok := raw["categoryTitle"].(string); ok {
			campaign.SourceCategory = categoryTitle
		}

		// Content Link
		if id, ok := raw["id"].(int); ok {
			campaign.SourceID = id
			contentLink := fmt.Sprintf("https://www.reviewnote.co.kr/campaigns/%d", id)
			campaign.ContentLink = &contentLink
			campaign.CompanyLink = &contentLink
		}

		// Image URL
		if imageKey, ok := raw["imageKey"].(string); ok && imageKey != "" {
			imgURL := imageURL(imageKey)
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

		campaigns = append(campaigns, campaign)
	}

	log.Infof("Parse 완료: %d개 중 %d개 캠페인 파싱 (모집 중)", len(rawData), len(campaigns))

	return campaigns, nil
}

// dedupeCampaigns 저장 키(platform + title + offer + campaign_channel)가 같은 공고는 하나만 남긴다.
// 같은 업체가 회차를 나눠 올린 공고라, 앱에 보여줄 정보가 가장 많은 것을 고른다 (순서는 처음 나온 자리 유지).
func dedupeCampaigns(campaigns []models.Campaign) []models.Campaign {
	index := make(map[string]int, len(campaigns))
	out := make([]models.Campaign, 0, len(campaigns))
	for _, c := range campaigns {
		key := fmt.Sprintf("%s|%s|%s|%s", c.Platform, c.Title, c.Offer, c.CampaignChannel)
		i, seen := index[key]
		if !seen {
			index[key] = len(out)
			out = append(out, c)
			continue
		}
		if richerCampaign(c, out[i]) {
			out[i] = c
		}
	}
	return out
}

// richerCampaign a가 b보다 보여줄 것이 많은지: 이용 요일 있음 > 상세 받음 > 모집 마감이 늦음(더 오래 신청 가능)
func richerCampaign(a, b models.Campaign) bool {
	hasDays := func(c models.Campaign) bool { return c.PossibleDays != nil || c.ImpossibleDays != nil }
	if hasDays(a) != hasDays(b) {
		return hasDays(a)
	}
	if (a.DetailFetchedAt != nil) != (b.DetailFetchedAt != nil) {
		return a.DetailFetchedAt != nil
	}
	return a.ApplyDeadline != nil && (b.ApplyDeadline == nil || a.ApplyDeadline.After(*b.ApplyDeadline))
}

// scrapePage 목록 API 한 쪽. categoryID가 있으면 그 카테고리만 받는다.
func (s *Scraper) scrapePage(ctx context.Context, categoryID string, page, limit int) ([]map[string]interface{}, error) {
	url := fmt.Sprintf("%s?limit=%d&page=%d", baseURL, limit, page)
	if categoryID != "" {
		url += "&s=default&categoryId=" + neturl.QueryEscape(categoryID)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Referer", "https://www.reviewnote.co.kr/")

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

// imageURL 이미지 키(예: "campaigns/<uuid>")를 Firebase Storage 주소로 바꾼다. 키의 "/"는 %2F로 인코딩해야 한다.
func imageURL(key string) string {
	return fmt.Sprintf(imageURLFormat, strings.ReplaceAll(neturl.PathEscape(key), "/", "%2F"))
}

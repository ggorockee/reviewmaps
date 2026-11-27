// Package pickly 피클리(picklykorea.kr) 네이버 블로그 체험단 수집기.
//
// 피클리 운영자가 2026-11-27 메일로 리뷰맵 목록 추가를 요청했다. 사이트가 쓰는 공개 JSON API를 쓴다
// (로그인 불필요). robots.txt 가 일반 수집기의 /api/ 를 막고 있어 요청을 최소화한다:
//   - 하루 1번, 목록 1~2번(100건씩) + 처음 보는 공고만 상세(좌표) 조회, 요청 사이 PICKLY_REQUEST_DELAY_MS
//   - User-Agent 에 리뷰맵 수집기임을 밝힘
//   - 끄기 스위치 PICKLY_ENABLED (피클리가 중단을 요청하면 false)
//
// 조사·매핑 규칙: claudedocs/planning/2026-11-pickly-integration.md
package pickly

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/db"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/logger"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/runstats"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/scraper"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/telemetry"
	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
)

const (
	platformName = "피클리"
	siteURL      = "https://picklykorea.kr"
	listLimit    = 100
	maxListPages = 10
	userAgent    = "Mozilla/5.0 (compatible; ReviewMapsBot/1.0; +https://review-maps.com)"
	// 원본 카테고리 이름 앞에 붙여 다른 출처(네이버 지도 카테고리)와 구분 → 관리자 화면 카테고리 매핑
	rawCategoryPrefix = "피클리>"
)

var kst = time.FixedZone("KST", 9*3600)

// Business 목록·상세 API 공고 (쓰는 필드만)
type Business struct {
	ID                   string   `json:"id"`
	Name                 string   `json:"name"`
	Location             string   `json:"location"`
	Address              string   `json:"address"`
	ImageURL             string   `json:"imageUrl"`
	ApplicationStartDate string   `json:"applicationStartDate"`
	ApplicationEndDate   string   `json:"applicationEndDate"`
	ExperienceEndDate    string   `json:"experienceEndDate"`
	Status               string   `json:"status"`
	BusinessType         string   `json:"businessType"`
	Channel              string   `json:"channel"`
	City                 string   `json:"city"`
	District             string   `json:"district"`
	ProductInfoOne       *string  `json:"productInfoOne"`
	BenefitsOne          *string  `json:"benefitsOne"`
	VisitDays            []string `json:"visitDays"`
	AllowTodayVisit      *bool    `json:"allowTodayVisit"`
	WeekdaySchedule      map[string]struct {
		Enabled   bool   `json:"enabled"`
		StartTime string `json:"startTime"`
		EndTime   string `json:"endTime"`
	} `json:"weekdaySchedule"`
	Category *struct {
		Name string `json:"name"`
	} `json:"category"`
	Latitude  *float64 `json:"latitude"`
	Longitude *float64 `json:"longitude"`
}

// locationStore 저장된 주소·좌표·카테고리 조회 (테스트에서 바꿔 끼움)
type locationStore interface {
	LoadLocationsByLinks(ctx context.Context, platform string, links []string) (map[string]models.CampaignKey, error)
}

// Scraper 피클리 수집기
type Scraper struct {
	*scraper.BaseScraper
	httpClient *http.Client
	telemetry  *telemetry.Telemetry
	locations  locationStore
	fetchList  func(ctx context.Context, offset int) ([]Business, error)
	fetchOne   func(ctx context.Context, id string) (*Business, error)
	category   func(ctx context.Context, raw string) *int64
	sleep      func(ctx context.Context, d time.Duration) bool
}

// New 피클리 수집기 생성
func New(cfg *config.Config, database *db.DB, tel *telemetry.Telemetry) *Scraper {
	s := &Scraper{
		BaseScraper: scraper.NewBaseScraper(cfg, database),
		httpClient:  &http.Client{Timeout: 30 * time.Second},
		telemetry:   tel,
		sleep:       sleepCtx,
	}
	if database != nil {
		s.locations = database
	}
	s.fetchList = s.fetchListHTTP
	s.fetchOne = s.fetchDetailHTTP
	s.category = s.mappedCategory
	return s
}

// Run 목록 → 변환 → 새 공고만 상세(좌표) → 저장
func (s *Scraper) Run(ctx context.Context, _ *string) error {
	log := logger.GetLogger("scraper.pickly")
	if !s.Config.Pickly.Enabled {
		log.Warn("PICKLY_ENABLED=false 라 수집하지 않습니다")
		return nil
	}
	log.Infof("===== %s 수집 시작 =====", platformName)

	items, err := s.Scrape(ctx)
	if err != nil {
		return err
	}
	runstats.SetItems(runstats.StageScraped, len(items))

	campaigns := Parse(items, time.Now())
	runstats.SetItems(runstats.StageParsed, len(campaigns))
	if len(campaigns) == 0 {
		log.Warn("저장할 공고가 없습니다")
		return nil
	}
	if s.telemetry != nil {
		s.telemetry.AddCampaignsScraped(ctx, int64(len(campaigns)), platformName)
	}

	campaigns = s.enrichLocations(ctx, campaigns)
	raws := rawCategories(items)
	for i := range campaigns {
		if raw := raws[*campaigns[i].ContentLink]; raw != "" && s.category != nil {
			campaigns[i].CategoryID = s.category(ctx, raw)
		}
	}

	if err := s.Save(ctx, campaigns); err != nil {
		return err
	}
	log.Infof("===== %s 수집 끝: %d건 =====", platformName, len(campaigns))
	return nil
}

// Scrape 목록 API를 끝까지 (100건씩, 요청 사이 대기)
func (s *Scraper) Scrape(ctx context.Context) ([]Business, error) {
	var all []Business
	for page := 0; page < maxListPages; page++ {
		if page > 0 && !s.sleep(ctx, s.Config.Pickly.RequestDelay) {
			return nil, ctx.Err()
		}
		items, err := s.fetchList(ctx, page*listLimit)
		if err != nil {
			return nil, err
		}
		all = append(all, items...)
		if len(items) < listLimit {
			break
		}
	}
	return all, nil
}

func (s *Scraper) get(ctx context.Context, url string, out interface{}) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Accept", "application/json")
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("피클리 API %s 응답 %d", url, resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func (s *Scraper) fetchListHTTP(ctx context.Context, offset int) ([]Business, error) {
	var items []Business
	url := fmt.Sprintf("%s/api/businesses?limit=%d&offset=%d&channel=naver_blog", siteURL, listLimit, offset)
	if err := s.get(ctx, url, &items); err != nil {
		return nil, fmt.Errorf("목록 조회 실패: %w", err)
	}
	return items, nil
}

func (s *Scraper) fetchDetailHTTP(ctx context.Context, id string) (*Business, error) {
	var b Business
	if err := s.get(ctx, fmt.Sprintf("%s/api/businesses/%s", siteURL, id), &b); err != nil {
		return nil, fmt.Errorf("상세 조회 실패: %w", err)
	}
	return &b, nil
}

// enrichLocations 방문형 좌표: DB에 이미 있으면 그대로, 없으면 상세 조회 (최대 MaxDetailFetch건)
// UpsertCampaigns 가 DELETE 후 INSERT 하므로 매번 좌표를 채워야 지도에서 빠지지 않는다.
func (s *Scraper) enrichLocations(ctx context.Context, campaigns []models.Campaign) []models.Campaign {
	log := logger.GetLogger("scraper.pickly")
	var links []string
	for _, c := range campaigns {
		links = append(links, *c.ContentLink)
	}
	stored := map[string]models.CampaignKey{}
	if s.locations != nil {
		if got, err := s.locations.LoadLocationsByLinks(ctx, platformName, links); err != nil {
			log.Warnf("저장된 좌표 조회 실패 (새로 조회): %v", err)
		} else {
			stored = got
		}
	}

	reused, fetched, failed := 0, 0, 0
	for i := range campaigns {
		c := &campaigns[i]
		if c.CampaignType == nil || *c.CampaignType != "방문형" {
			continue
		}
		if prev, ok := stored[*c.ContentLink]; ok && prev.Lat != nil && prev.Lng != nil {
			c.Lat, c.Lng = prev.Lat, prev.Lng
			if c.Address == nil {
				c.Address = prev.Address
			}
			reused++
			continue
		}
		if fetched+failed >= s.Config.Pickly.MaxDetailFetch {
			continue
		}
		if fetched+failed > 0 && !s.sleep(ctx, s.Config.Pickly.RequestDelay) {
			break
		}
		d, err := s.fetchOne(ctx, strings.TrimPrefix(*c.ContentLink, siteURL+"/business/"))
		if err != nil {
			failed++
			log.Warnf("%v", err)
			continue
		}
		fetched++
		if d.Latitude != nil && d.Longitude != nil {
			c.Lat, c.Lng = d.Latitude, d.Longitude
		}
		if addr := strings.TrimSpace(firstNonEmpty(d.Address, d.Location)); addr != "" {
			c.Address = &addr
		}
	}
	log.Infof("좌표: 재사용 %d, 상세 조회 %d, 실패 %d", reused, fetched, failed)
	runstats.SetEnrich(runstats.EnrichStats{Total: int64(reused + fetched + failed), CacheHit: int64(reused), APICalled: int64(fetched + failed), Errors: int64(failed)})
	return campaigns
}

func (s *Scraper) mappedCategory(ctx context.Context, raw string) *int64 {
	if s.DB == nil {
		return nil
	}
	rawID, err := s.DB.GetOrCreateRawCategory(ctx, raw)
	if err != nil || rawID == nil {
		return nil
	}
	mapped, err := s.DB.FindMappedCategoryID(ctx, *rawID)
	if err != nil {
		return nil
	}
	return mapped
}

// rawCategories 공고 링크 → 원본 카테고리 ("피클리>맛집"). 관리자 화면에서 리뷰맵 카테고리로 매핑
func rawCategories(items []Business) map[string]string {
	out := map[string]string{}
	for _, b := range items {
		if b.Category != nil && strings.TrimSpace(b.Category.Name) != "" {
			out[contentLink(b.ID)] = rawCategoryPrefix + strings.TrimSpace(b.Category.Name)
		}
	}
	return out
}

func contentLink(id string) string { return siteURL + "/business/" + id }

// Parse 공고 → 리뷰맵 캠페인 (모집 중·네이버 블로그만, 중복 제거)
func Parse(items []Business, now time.Time) []models.Campaign {
	var out []models.Campaign
	seen := map[string]bool{}
	for _, b := range items {
		if b.Status != "active" || (b.Channel != "" && b.Channel != "naver_blog") || strings.TrimSpace(b.Name) == "" {
			continue
		}
		c := toCampaign(b)
		if c.ApplyDeadline != nil && c.ApplyDeadline.Before(now) {
			continue
		}
		key := c.Platform + "|" + c.Title + "|" + c.Offer + "|" + c.CampaignChannel
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, c)
	}
	return out
}

func toCampaign(b Business) models.Campaign {
	title := strings.TrimSpace(b.Name)
	link := contentLink(b.ID)
	status := "active"
	c := models.Campaign{
		Platform:        platformName,
		Source:          platformName,
		Title:           title,
		Company:         title,
		Offer:           offerText(b),
		CampaignChannel: "blog",
		ContentLink:     &link,
		CompanyLink:     &link,
		SearchText:      title,
		Status:          &status,
		SameDayVisit:    b.AllowTodayVisit,
	}
	switch b.BusinessType {
	case "delivery":
		t := "배송형"
		c.CampaignType = &t
	default:
		t := "방문형"
		c.CampaignType = &t
		if addr := strings.TrimSpace(firstNonEmpty(b.Address, b.Location)); addr != "" {
			c.Address = &addr
		}
		if b.Latitude != nil && b.Longitude != nil {
			c.Lat, c.Lng = b.Latitude, b.Longitude
		}
	}
	if region := regionText(b.City, b.District); region != "" {
		c.Region = &region
	}
	if img := strings.TrimSpace(b.ImageURL); img != "" {
		if strings.HasPrefix(img, "/") {
			img = siteURL + img
		}
		c.ImgURL = &img
	}
	c.ApplyFrom = parseDate(b.ApplicationStartDate, false)
	c.ApplyDeadline = parseDate(b.ApplicationEndDate, true)
	c.ReviewDeadline = parseDate(b.ExperienceEndDate, true)
	c.PossibleDays = visitDaysText(b.VisitDays)
	c.PossibleTime = scheduleTime(b)
	return c
}

func offerText(b Business) string {
	if b.ProductInfoOne != nil && strings.TrimSpace(*b.ProductInfoOne) != "" {
		return strings.TrimSpace(*b.ProductInfoOne)
	}
	if b.BenefitsOne != nil {
		if won, err := strconv.Atoi(strings.TrimSpace(*b.BenefitsOne)); err == nil && won > 0 {
			if won%10000 == 0 {
				return fmt.Sprintf("%d만원 상당", won/10000)
			}
			return fmt.Sprintf("%s원 상당", commas(won))
		}
	}
	return ""
}

func commas(n int) string {
	s := strconv.Itoa(n)
	var b strings.Builder
	for i, ch := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteRune(ch)
	}
	return b.String()
}

func regionText(city, district string) string {
	city, district = strings.TrimSpace(city), strings.TrimSpace(district)
	switch {
	case city == "":
		return district
	case district == "" || district == city:
		return city
	default:
		return city + " " + district
	}
}

// parseDate "2026-12-09" → KST 그날 00:00 (endOfDay 면 23:59:59)
func parseDate(v string, endOfDay bool) *time.Time {
	t, err := time.ParseInLocation("2006-01-02", strings.TrimSpace(v), kst)
	if err != nil {
		return nil
	}
	if endOfDay {
		t = t.Add(24*time.Hour - time.Second)
	}
	return &t
}

var dayOrder = map[string]int{"월": 1, "화": 2, "수": 3, "목": 4, "금": 5, "토": 6, "일": 7}

// visitDaysText ["금","월","일"] → "월 / 금 / 일" (리뷰노트 possible_days 와 같은 형식, 앱 요일 배지가 읽음)
func visitDaysText(days []string) *string {
	var ds []string
	seen := map[string]bool{}
	for _, d := range days {
		d = strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(d), "요일"))
		if _, ok := dayOrder[d]; ok && !seen[d] {
			seen[d] = true
			ds = append(ds, d)
		}
	}
	if len(ds) == 0 {
		return nil
	}
	sort.Slice(ds, func(i, j int) bool { return dayOrder[ds[i]] < dayOrder[ds[j]] })
	s := strings.Join(ds, " / ")
	return &s
}

// scheduleTime 운영하는 요일의 시작·끝 시각이 모두 같을 때만 "10:30 ~ 17:00"
func scheduleTime(b Business) *string {
	var start, end string
	for _, d := range b.WeekdaySchedule {
		if !d.Enabled {
			continue
		}
		if start == "" {
			start, end = d.StartTime, d.EndTime
		} else if d.StartTime != start || d.EndTime != end {
			return nil
		}
	}
	if start == "" || end == "" {
		return nil
	}
	s := start + " ~ " + end
	return &s
}

func firstNonEmpty(vs ...string) string {
	for _, v := range vs {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

func sleepCtx(ctx context.Context, d time.Duration) bool {
	if d <= 0 {
		return ctx.Err() == nil
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}

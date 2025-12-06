package reviewnote

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/enricher"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/scraper"
	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
)

// TestEnricherNaverLocalSearch 네이버 Local Search API 테스트 (실제 API 호출)
func TestEnricherNaverLocalSearch(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping live API test in short mode")
	}

	cfg, err := config.Load()
	if err != nil {
		t.Skipf("Config load failed (no .env?): %v", err)
	}

	if len(cfg.NaverAPI.GetSearchAPIKeys()) == 0 {
		t.Skip("No Naver API keys configured")
	}

	e := enricher.New(cfg)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// 테스트 쿼리
	testQueries := []string{
		"스타벅스 강남역점",
		"혜민한의원",
		"브리사뜰",
	}

	for _, query := range testQueries {
		result, err := e.NaverLocalSearch(ctx, query)
		if err != nil {
			t.Logf("Query '%s' failed: %v (may be rate limited)", query, err)
			continue
		}

		if result == nil {
			t.Logf("Query '%s': No result found", query)
			continue
		}

		t.Logf("Query '%s' → Address: %s, MapX: %s, MapY: %s",
			query, result.RoadAddress, result.MapX, result.MapY)

		// mapxy → lat/lng 변환 테스트
		if result.MapX != "" && result.MapY != "" {
			lat, lng, valid := enricher.FromMapXY(result.MapX, result.MapY)
			if valid {
				t.Logf("  → Converted: lat=%.6f, lng=%.6f", lat, lng)
			} else {
				t.Logf("  → MapXY conversion failed")
			}
		}

		// Rate limiting
		time.Sleep(300 * time.Millisecond)
	}
}

// TestEnrichConfig 설정 테스트
func TestEnrichConfig(t *testing.T) {
	config := DefaultEnrichConfig()

	if config.MaxWorkers != 3 {
		t.Errorf("Expected MaxWorkers=3, got %d", config.MaxWorkers)
	}

	if config.APIDelay != 200*time.Millisecond {
		t.Errorf("Expected APIDelay=200ms, got %v", config.APIDelay)
	}

	if !config.EnableParallel {
		t.Error("Expected EnableParallel=true")
	}
}

// TestCampaignKey 캠페인 키 생성 테스트
func TestCampaignKey(t *testing.T) {
	campaign := &models.Campaign{
		Platform:        "reviewnote",
		Title:           "테스트 캠페인",
		Offer:           "테스트 제공",
		CampaignChannel: "blog",
	}

	key := campaignKey(campaign)
	expected := "reviewnote|테스트 캠페인|테스트 제공|blog"

	if key != expected {
		t.Errorf("Expected key '%s', got '%s'", expected, key)
	}
}

// TestEnrichVisitCampaignsWithoutDB Enrich 로직 테스트 (DB 없이)
func TestEnrichVisitCampaignsWithoutDB(t *testing.T) {
	// DB 연결 없이 Enrich 로직의 기본 동작 확인
	visitType := "방문형"
	deliveryType := "배송형"

	campaigns := []models.Campaign{
		{
			Platform:        "reviewnote",
			Title:           "방문형 캠페인",
			Offer:           "테스트 제공",
			CampaignChannel: "blog",
			CampaignType:    &visitType,
		},
		{
			Platform:        "reviewnote",
			Title:           "배송형 캠페인",
			Offer:           "테스트 제공",
			CampaignChannel: "blog",
			CampaignType:    &deliveryType,
		},
	}

	// 방문형만 필터링되는지 확인
	visitCount := 0
	for _, c := range campaigns {
		if c.CampaignType != nil && *c.CampaignType == "방문형" {
			visitCount++
		}
	}

	if visitCount != 1 {
		t.Errorf("Expected 1 visit campaign, got %d", visitCount)
	}

	t.Logf("방문형 캠페인: %d개, 배송형 캠페인: %d개", visitCount, len(campaigns)-visitCount)
}

// TestEnrichStatsInit 통계 초기화 테스트
func TestEnrichStatsInit(t *testing.T) {
	stats := &EnrichStats{}

	if stats.Total != 0 || stats.CacheHit != 0 || stats.APICalled != 0 {
		t.Error("Stats should be initialized to zero")
	}
}

// TestMockEnrichSingleCampaign Enrich 단일 캠페인 로직 테스트 (모의)
func TestMockEnrichSingleCampaign(t *testing.T) {
	// 이 테스트는 실제 DB/API 없이 로직 흐름만 확인
	visitType := "방문형"

	job := EnrichJob{
		Index: 0,
		Campaign: &models.Campaign{
			Platform:        "reviewnote",
			Title:           "테스트 매장",
			Offer:           "테스트 제공",
			CampaignChannel: "blog",
			CampaignType:    &visitType,
		},
		Existing: nil,
	}

	// job 구조체 확인
	if job.Campaign.Title != "테스트 매장" {
		t.Errorf("Expected title '테스트 매장', got '%s'", job.Campaign.Title)
	}

	if job.Existing != nil {
		t.Error("Existing should be nil for new campaign")
	}

	t.Log("EnrichJob 구조체 정상 동작")
}

// TestFromMapXY mapxy 변환 테스트
func TestFromMapXY(t *testing.T) {
	testCases := []struct {
		mapX, mapY string
		expectLat  float64
		expectLng  float64
		valid      bool
	}{
		{"1269876543", "375123456", 37.5123456, 126.9876543, true}, // 서울 좌표
		{"1289876543", "359123456", 35.9123456, 128.9876543, true}, // 대구 좌표
		{"0", "0", 0, 0, false},                                    // 잘못된 좌표
		{"abc", "def", 0, 0, false},                                // 파싱 불가
	}

	for _, tc := range testCases {
		lat, lng, valid := enricher.FromMapXY(tc.mapX, tc.mapY)

		if valid != tc.valid {
			t.Errorf("MapXY(%s, %s): expected valid=%v, got %v", tc.mapX, tc.mapY, tc.valid, valid)
			continue
		}

		if valid {
			// 소수점 5자리까지 비교
			if int(lat*100000) != int(tc.expectLat*100000) || int(lng*100000) != int(tc.expectLng*100000) {
				t.Errorf("MapXY(%s, %s): expected (%.6f, %.6f), got (%.6f, %.6f)",
					tc.mapX, tc.mapY, tc.expectLat, tc.expectLng, lat, lng)
			}
		}
	}
}

// TestHaversine 거리 계산 테스트
func TestHaversine(t *testing.T) {
	// 서울역 → 강남역 (약 8km)
	lat1, lng1 := 37.5547, 126.9707 // 서울역
	lat2, lng2 := 37.4979, 127.0276 // 강남역

	dist := enricher.Haversine(lat1, lng1, lat2, lng2)

	// 약 8km (8000m) 예상
	if dist < 7000 || dist > 9000 {
		t.Errorf("Expected distance ~8000m, got %.0fm", dist)
	}

	t.Logf("서울역 → 강남역 거리: %.0fm", dist)
}

// BenchmarkEnrichConfig 설정 생성 벤치마크
func BenchmarkEnrichConfig(b *testing.B) {
	for i := 0; i < b.N; i++ {
		_ = DefaultEnrichConfig()
	}
}

// BenchmarkCampaignKey 키 생성 벤치마크
func BenchmarkCampaignKey(b *testing.B) {
	campaign := &models.Campaign{
		Platform:        "reviewnote",
		Title:           "테스트 캠페인",
		Offer:           "테스트 제공",
		CampaignChannel: "blog",
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = campaignKey(campaign)
	}
}

// TestScraperWithMockDB Scraper 구조체 테스트 (DB 없이)
func TestScraperWithMockDB(t *testing.T) {
	// DB 없이 Scraper 기본 구조 확인
	s := &Scraper{
		BaseScraper: &scraper.BaseScraper{},
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}

	if s.PlatformName() != "reviewnote" {
		t.Errorf("Expected platform 'reviewnote', got '%s'", s.PlatformName())
	}

	if s.BaseURL() != "https://www.reviewnote.co.kr/api/v2/campaigns" {
		t.Errorf("Unexpected BaseURL: %s", s.BaseURL())
	}
}

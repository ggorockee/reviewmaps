package reviewnote

import (
	"context"
	"net/http"
	"testing"
	"time"
)

func TestScrapeAndParse(t *testing.T) {
	s := &Scraper{}

	// 샘플 raw data (API 응답 형식)
	rawData := []map[string]interface{}{
		{
			"id":             985180,
			"title":          "필립스 전자동 에스프레소 커피머신",
			"status":         "SELECT",
			"sort":           "DELIVERY",
			"channel":        "BLOG",
			"infNum":         1,
			"infPoint":       0,
			"offer":          "필립스 전자동 에스프레소 커피머신 (색상랜덤) (정가 599,000원)",
			"imageKey":       "campaigns/3cf3fdad-e3cd-4abf-9f68-efacf784c07f",
			"city":           "재택",
			"applyEndAt":     "2025-12-31T14:59:59.999Z",
			"reviewEndAt":    "2026-01-14T14:59:59.999Z",
			"applicantCount": 3733,
			"isPremium":      false,
			"categoryTitle":  "기타",
			"sidoName":       "재택",
		},
		{
			"id":             992390,
			"title":          "혜민한의원",
			"status":         "SELECT",
			"sort":           "VISIT",
			"channel":        "BLOG_CLIP",
			"infNum":         10,
			"infPoint":       5000,
			"offer":          "한방좌욕제 (3만원 상당)+5,000 포인트",
			"imageKey":       "campaigns/949001e1-170e-42f9-bd63-8411c047dbc4",
			"city":           "서울",
			"applyEndAt":     "2025-12-17T14:59:59.999Z",
			"reviewEndAt":    "2025-12-31T14:59:59.999Z",
			"applicantCount": 50,
			"isPremium":      false,
			"categoryTitle":  "뷰티",
			"sidoName":       "강남구",
		},
	}

	ctx := context.Background()
	campaigns, err := s.Parse(ctx, rawData)
	if err != nil {
		t.Fatalf("Parse failed: %v", err)
	}

	if len(campaigns) != 2 {
		t.Errorf("Expected 2 campaigns, got %d", len(campaigns))
	}

	// 첫 번째 캠페인 검증
	c1 := campaigns[0]
	if c1.Platform != "리뷰노트" {
		t.Errorf("Expected platform '리뷰노트', got '%s'", c1.Platform)
	}
	if c1.Title != "필립스 전자동 에스프레소 커피머신" {
		t.Errorf("Unexpected title: %s", c1.Title)
	}
	if c1.CampaignChannel != "blog" {
		t.Errorf("Expected channel 'blog', got '%s'", c1.CampaignChannel)
	}
	if c1.CampaignType == nil || *c1.CampaignType != "배송형" {
		t.Errorf("Expected campaign type '배송형', got %v", c1.CampaignType)
	}
	if c1.ApplyDeadline == nil {
		t.Error("ApplyDeadline should not be nil")
	}

	// 두 번째 캠페인 검증
	c2 := campaigns[1]
	if c2.CampaignChannel != "blog,clip" {
		t.Errorf("Expected channel 'blog,clip', got '%s'", c2.CampaignChannel)
	}
	if c2.CampaignType == nil || *c2.CampaignType != "방문형" {
		t.Errorf("Expected campaign type '방문형', got %v", c2.CampaignType)
	}
	if c2.Region == nil || *c2.Region != "서울 강남구" {
		t.Errorf("Expected region '서울 강남구', got %v", c2.Region)
	}

	t.Logf("Parse test passed! Parsed %d campaigns", len(campaigns))
	for i, c := range campaigns {
		t.Logf("Campaign %d: %s (%s) - %s", i+1, c.Title, c.CampaignChannel, *c.CampaignType)
	}
}

// TestLiveAPI 실제 API 호출 테스트 (네트워크 필요)
func TestLiveAPI(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping live API test in short mode")
	}

	s := &Scraper{
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// 첫 페이지만 가져오기 (샘플링)
	rawData, err := s.scrapePage(ctx, 0, 5)
	if err != nil {
		t.Fatalf("Failed to fetch from API: %v", err)
	}

	t.Logf("Fetched %d campaigns from live API", len(rawData))

	if len(rawData) == 0 {
		t.Error("Expected at least 1 campaign from live API")
		return
	}

	// Parse 테스트
	campaigns, err := s.Parse(ctx, rawData)
	if err != nil {
		t.Fatalf("Parse failed: %v", err)
	}

	t.Logf("Parsed %d campaigns", len(campaigns))
	for i, c := range campaigns {
		t.Logf("Campaign %d: %s (%s)", i+1, c.Title, c.CampaignChannel)
		if c.ContentLink != nil {
			t.Logf("  Link: %s", *c.ContentLink)
		}
		if c.ImgURL != nil {
			t.Logf("  Image: %s", *c.ImgURL)
		}
	}
}

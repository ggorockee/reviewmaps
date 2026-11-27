package pickly

import (
	"context"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/scraper"
)

// 실제 사이트 확인용 (평소에는 건너뜀): PICKLY_LIVE_TEST=1 go test -run Live ./internal/scraper/pickly/
func TestListLive(t *testing.T) {
	if os.Getenv("PICKLY_LIVE_TEST") == "" {
		t.Skip("PICKLY_LIVE_TEST 없음")
	}
	s := &Scraper{
		BaseScraper: &scraper.BaseScraper{Config: &config.Config{Pickly: config.PicklyConfig{Enabled: true, RequestDelay: 2 * time.Second}}},
		httpClient:  &http.Client{Timeout: 30 * time.Second},
		sleep:       sleepCtx,
	}
	s.fetchList = s.fetchListHTTP
	items, err := s.Scrape(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	got := Parse(items, time.Now())
	withDays := 0
	for _, c := range got {
		if c.PossibleDays != nil {
			withDays++
		}
	}
	t.Logf("목록 %d건 → 저장 대상 %d건, 요일 있음 %d건, 예: %s / %s / %v", len(items), len(got), withDays, got[0].Title, got[0].Offer, *got[0].Region)
	if len(got) == 0 {
		t.Fatal("0건")
	}
}

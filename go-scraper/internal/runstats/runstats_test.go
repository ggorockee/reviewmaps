package runstats

import (
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

func TestRegistryDetailMetrics(t *testing.T) {
	Start("reviewnote", "")
	exp := time.Date(2026, 12, 12, 17, 5, 0, 0, time.UTC)
	SetDetail(DetailStats{Targets: 10, Reused: 6, Fetched: 3, Errors: 1, WithDays: 9, SessionOK: true, SessionExpiresAt: exp})

	reg := Registry(true, time.Now())
	families, err := reg.Gather()
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]bool{}
	for _, f := range families {
		got[f.GetName()] = true
	}
	for _, name := range []string{
		"reviewmaps_scraper_last_run_detail",
		"reviewmaps_scraper_detail_session_ok",
		"reviewmaps_scraper_detail_session_expiry_timestamp_seconds",
	} {
		if !got[name] {
			t.Errorf("%s 없음", name)
		}
	}
	if n := count(t, reg, "reviewmaps_scraper_last_run_detail"); n != 6 {
		t.Errorf("detail type 6개 기대, got %d", n)
	}
}

func TestRegistryWithoutDetailHasNoDetailMetrics(t *testing.T) {
	Start("inflexer", "서울 강남")
	if n := count(t, Registry(true, time.Now()), "reviewmaps_scraper_detail_session_ok"); n != 0 {
		t.Errorf("상세 보강을 안 한 스크레이퍼는 세션 지표가 없어야 함 (알림 오탐 방지)")
	}
}

func count(t *testing.T, reg *prometheus.Registry, name string) int {
	t.Helper()
	families, err := reg.Gather()
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range families {
		if f.GetName() == name {
			return len(f.GetMetric())
		}
	}
	return 0
}

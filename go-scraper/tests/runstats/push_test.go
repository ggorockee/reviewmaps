package runstats_test

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/runstats"
)

type captured struct {
	method, path, body string
}

func fakePushgateway(t *testing.T) (*httptest.Server, *[]captured) {
	t.Helper()
	var reqs []captured
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		reqs = append(reqs, captured{r.Method, r.URL.Path, string(b)})
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(srv.Close)
	return srv, &reqs
}

// 성공 실행: (scraper, keyword) 그룹으로 POST(Add)되고 단계별 건수·보강 통계·성공 시각이 포함되어야 한다.
func TestPushSuccess(t *testing.T) {
	srv, reqs := fakePushgateway(t)
	t.Setenv("PUSHGATEWAY_URL", srv.URL)

	runstats.Start("inflexer", "서울 강남")
	runstats.SetItems(runstats.StageScraped, 122)
	runstats.SetItems(runstats.StageParsed, 120)
	runstats.SetItems(runstats.StageSaved, 120)
	runstats.SetItems(runstats.StageUpdated, 116)
	runstats.SetItems(runstats.StageNew, 4)
	runstats.SetEnrich(runstats.EnrichStats{Total: 14, CacheHit: 7, APICalled: 7, Errors: 1})
	runstats.SetAlertsCreated(2)

	if err := runstats.Push(true); err != nil {
		t.Fatalf("Push 에러: %v", err)
	}
	if len(*reqs) != 1 {
		t.Fatalf("요청 수 = %d, want 1", len(*reqs))
	}
	r := (*reqs)[0]
	if r.method != http.MethodPost {
		t.Errorf("method = %s, want POST (Add: 같은 이름 메트릭만 교체)", r.method)
	}
	// 한글·공백 키워드는 base64 grouping key로 전달 (공백이 "+"로 바뀌지 않도록)
	if r.path != runstats.GroupPath("inflexer", "서울 강남") {
		t.Errorf("path = %s, want %s", r.path, runstats.GroupPath("inflexer", "서울 강남"))
	}
	if !strings.HasPrefix(r.path, "/metrics/job/reviewmaps_scraper/scraper@base64/") || !strings.Contains(r.path, "/keyword@base64/") {
		t.Errorf("base64 grouping 경로 아님: %s", r.path)
	}
	for _, want := range []string{
		"reviewmaps_scraper_last_success_timestamp_seconds",
		"reviewmaps_scraper_last_run_success",
		"reviewmaps_scraper_last_run_duration_seconds",
		"reviewmaps_scraper_last_run_items",
		"reviewmaps_scraper_last_run_enrich",
		"reviewmaps_scraper_last_run_alerts_created",
	} {
		if !strings.Contains(r.body, want) {
			t.Errorf("body에 %s 없음", want)
		}
	}
}

// 실패 실행: last_success_timestamp를 보내지 않아야 Pushgateway에 이전 성공 시각이 유지된다.
func TestPushFailureKeepsLastSuccess(t *testing.T) {
	srv, reqs := fakePushgateway(t)
	t.Setenv("PUSHGATEWAY_URL", srv.URL)

	runstats.Start("reviewnote", "")
	if err := runstats.Push(false); err != nil {
		t.Fatalf("Push 에러: %v", err)
	}
	r := (*reqs)[0]
	if strings.Contains(r.body, "reviewmaps_scraper_last_success_timestamp_seconds") {
		t.Error("실패 실행에 last_success_timestamp가 포함됨")
	}
	if !strings.Contains(r.body, "reviewmaps_scraper_last_run_timestamp_seconds") {
		t.Error("last_run_timestamp 누락")
	}
	if r.path != runstats.GroupPath("reviewnote", "전체") {
		t.Errorf("키워드 미지정 시 '전체'로 그룹핑되어야 함: path = %s", r.path)
	}
}

// PUSHGATEWAY_URL이 없으면 아무 것도 하지 않는다 (로컬 실행 호환).
func TestPushSkippedWithoutURL(t *testing.T) {
	t.Setenv("PUSHGATEWAY_URL", "")
	runstats.Start("cleanup", "")
	if err := runstats.Push(true); err != nil {
		t.Fatalf("URL 없을 때 에러 반환: %v", err)
	}
}

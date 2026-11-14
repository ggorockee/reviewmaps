package server_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/server"
)

// fakeServer 요청별 배치 크기를 기록하고, failOn 번째 요청(1부터)은 500으로 응답
func fakeServer(t *testing.T, failOn int) (*httptest.Server, *[]int) {
	t.Helper()
	var mu sync.Mutex
	sizes := []int{}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-API-Key") != "k" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		var req server.ProcessCampaignAlertsRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		mu.Lock()
		sizes = append(sizes, len(req.CampaignIDs))
		n := len(sizes)
		mu.Unlock()

		if n == failOn {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		// 캠페인 10개당 알림 1건 생성한 것으로 응답
		_ = json.NewEncoder(w).Encode(server.ProcessCampaignAlertsResponse{
			ProcessedCount: len(req.CampaignIDs),
			AlertsCreated:  len(req.CampaignIDs) / 10,
		})
	}))
	t.Cleanup(srv.Close)
	return srv, &sizes
}

func newClient(baseURL string) *server.Client {
	cfg := &config.Config{}
	cfg.ServerAPI.BaseURL = baseURL
	cfg.ServerAPI.APIKey = "k"
	cfg.ServerAPI.Enabled = true
	return server.NewClient(cfg)
}

func ids(n int) []uint {
	out := make([]uint, n)
	for i := range out {
		out[i] = uint(i + 1)
	}
	return out
}

// 780개(2026-11-14 운영 장애 규모)는 100개 단위 8개 배치로 나뉘어야 함
func TestProcessCampaignAlerts_SplitsIntoBatches(t *testing.T) {
	srv, sizes := fakeServer(t, 0)

	res, err := newClient(srv.URL).ProcessCampaignAlerts(context.Background(), ids(780))
	if err != nil {
		t.Fatalf("예상치 못한 오류: %v", err)
	}

	want := []int{100, 100, 100, 100, 100, 100, 100, 80}
	if len(*sizes) != len(want) {
		t.Fatalf("배치 수: 기대 %d, 실제 %d (%v)", len(want), len(*sizes), *sizes)
	}
	for i, w := range want {
		if (*sizes)[i] != w {
			t.Errorf("배치 %d 크기: 기대 %d, 실제 %d", i+1, w, (*sizes)[i])
		}
		if (*sizes)[i] > server.AlertBatchSize {
			t.Errorf("배치 %d가 최대 크기 초과: %d", i+1, (*sizes)[i])
		}
	}
	if res.ProcessedCount != 780 || res.AlertsCreated != 78 {
		t.Errorf("집계: processed=%d alerts=%d (기대 780/78)", res.ProcessedCount, res.AlertsCreated)
	}
}

// 일부 배치가 실패해도 나머지는 처리하고, 성공분 집계와 에러를 함께 반환
func TestProcessCampaignAlerts_PartialFailureContinues(t *testing.T) {
	srv, sizes := fakeServer(t, 2)

	res, err := newClient(srv.URL).ProcessCampaignAlerts(context.Background(), ids(250))
	if err == nil {
		t.Fatal("실패 배치가 있으면 에러를 반환해야 함")
	}
	if len(*sizes) != 3 {
		t.Fatalf("실패 후에도 모든 배치를 요청해야 함: 실제 %d회", len(*sizes))
	}
	if res == nil || res.ProcessedCount != 150 || res.AlertsCreated != 15 {
		t.Errorf("성공 배치(100+50)만 집계되어야 함: %+v", res)
	}
}

// 배치 크기 이하는 단일 요청
func TestProcessCampaignAlerts_SmallSingleRequest(t *testing.T) {
	srv, sizes := fakeServer(t, 0)

	if _, err := newClient(srv.URL).ProcessCampaignAlerts(context.Background(), ids(3)); err != nil {
		t.Fatalf("예상치 못한 오류: %v", err)
	}
	if len(*sizes) != 1 || (*sizes)[0] != 3 {
		t.Errorf("단일 요청이어야 함: %v", *sizes)
	}
}

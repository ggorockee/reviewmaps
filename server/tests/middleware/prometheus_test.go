package middleware_test

import (
	"io"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ggorockee/reviewmaps/server/internal/middleware"
	"github.com/gofiber/fiber/v2"
	"github.com/prometheus/client_golang/prometheus"
)

// newApp 메트릭 미들웨어와 테스트 라우트를 가진 앱 생성
func newApp() *fiber.App {
	app := fiber.New()
	app.Use(middleware.PrometheusMiddleware())
	app.Get("/metrics", middleware.PrometheusHandler())
	app.Get("/v1/campaigns/:id", func(c *fiber.Ctx) error { return c.SendString("ok") })
	app.Post("/v1/keyword-alerts/keywords", func(c *fiber.Ctx) error { return c.Status(fiber.StatusCreated).SendString("created") })
	return app
}

func doRequest(t *testing.T, app *fiber.App, method, path, body string) *httpResult {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	resp, err := app.Test(req, -1)
	if err != nil {
		t.Fatalf("%s %s 요청 실패: %v", method, path, err)
	}
	b, _ := io.ReadAll(resp.Body)
	return &httpResult{status: resp.StatusCode, body: string(b)}
}

type httpResult struct {
	status int
	body   string
}

// 서로 다른 메서드/경로 요청이 섞여도 라벨이 깨지지 않고 /metrics가 200을 반환해야 한다.
// (수정 전: fasthttp 버퍼 재사용으로 "GET"이 "GETT"로 덮어써져 중복 시리즈 → 500)
func TestMetricsLabelsNotCorruptedAcrossRequests(t *testing.T) {
	app := newApp()

	for i := 0; i < 50; i++ {
		doRequest(t, app, "POST", "/v1/keyword-alerts/keywords", `{"keyword":"테스트키워드"}`)
		doRequest(t, app, "GET", "/v1/campaigns/123", "")
		doRequest(t, app, "GET", "/does-not-exist-"+strings.Repeat("x", i%5), "")
	}

	res := doRequest(t, app, "GET", "/metrics", "")
	if res.status != fiber.StatusOK {
		t.Fatalf("/metrics 상태 코드 = %d, want 200\n%s", res.status, res.body[:min(len(res.body), 500)])
	}

	families, err := prometheus.DefaultGatherer.Gather()
	if err != nil {
		t.Fatalf("Gather 에러: %v", err)
	}

	allowedMethods := map[string]bool{"GET": true, "POST": true}
	allowedPaths := map[string]bool{"/v1/campaigns/:id": true, "/v1/keyword-alerts/keywords": true, "unmatched": true}
	found := 0
	for _, mf := range families {
		if mf.GetName() != "reviewmaps_http_requests_total" {
			continue
		}
		for _, m := range mf.GetMetric() {
			labels := map[string]string{}
			for _, lp := range m.GetLabel() {
				labels[lp.GetName()] = lp.GetValue()
			}
			if !allowedMethods[labels["method"]] {
				t.Errorf("잘못된 method 라벨: %q", labels["method"])
			}
			if !allowedPaths[labels["path"]] {
				t.Errorf("잘못된 path 라벨: %q", labels["path"])
			}
			found++
		}
	}
	if found != 3 {
		t.Errorf("reviewmaps_http_requests_total 시리즈 수 = %d, want 3 (GET 캠페인, POST 키워드, unmatched 404)", found)
	}
}

package handlers_test

import (
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ggorockee/reviewmaps/server/internal/config"
	"github.com/ggorockee/reviewmaps/server/internal/handlers"
	"github.com/gofiber/fiber/v2"
)

const testInternalKey = "test-internal-key"

// newAppConfigApp 실제 SetupAppConfigRoutes로 라우트를 등록한 앱 생성
// DB는 nil: 인증 실패 경로와 라우트 등록 순서만 검증 (핸들러 본문은 실행되지 않음)
func newAppConfigApp(internalKey string) *fiber.App {
	app := fiber.New()
	cfg := &config.Config{InternalAPIKey: internalKey}
	handlers.SetupAppConfigRoutes(app.Group("/v1/app-config"), nil, cfg)
	return app
}

// 고정 경로 GET이 /settings/:key 보다 먼저 등록되어야 함 (Fiber는 등록 순서대로 매칭)
func TestAppConfigRoutes_FixedSettingRoutesBeforeParamRoute(t *testing.T) {
	app := newAppConfigApp(testInternalKey)

	index := map[string]int{}
	for i, r := range app.GetRoutes(true) {
		if r.Method == fiber.MethodGet {
			index[r.Path] = i
		}
	}

	paramIdx, ok := index["/v1/app-config/settings/:key"]
	if !ok {
		t.Fatal("/settings/:key 라우트가 등록되지 않음")
	}
	for _, p := range []string{
		"/v1/app-config/settings/keyword-limit",
		"/v1/app-config/settings/alert-retention-days",
	} {
		idx, ok := index[p]
		if !ok {
			t.Fatalf("%s 라우트가 등록되지 않음", p)
		}
		if idx > paramIdx {
			t.Errorf("%s 가 /settings/:key 보다 뒤에 등록됨 (%d > %d)", p, idx, paramIdx)
		}
	}
}

// 설정 변경 PUT은 올바른 X-API-Key 없이는 401
func TestAppConfigRoutes_PutRequiresInternalAPIKey(t *testing.T) {
	paths := []string{
		"/v1/app-config/settings/keyword-limit",
		"/v1/app-config/settings/alert-retention-days",
	}
	cases := []struct {
		name        string
		internalKey string
		header      string
	}{
		{"헤더 없음", testInternalKey, ""},
		{"잘못된 키", testInternalKey, "wrong-key"},
		{"서버 키 미설정 (fail-closed)", "", ""},
		{"서버 키 미설정 + 임의 헤더", "", "anything"},
	}

	for _, tc := range cases {
		app := newAppConfigApp(tc.internalKey)
		for _, p := range paths {
			req := httptest.NewRequest(fiber.MethodPut, p, strings.NewReader(`{"limit":0,"days":0}`))
			req.Header.Set("Content-Type", "application/json")
			if tc.header != "" {
				req.Header.Set("X-API-Key", tc.header)
			}
			resp, err := app.Test(req)
			if err != nil {
				t.Fatalf("%s %s: 요청 실패: %v", tc.name, p, err)
			}
			if resp.StatusCode != fiber.StatusUnauthorized {
				t.Errorf("%s %s: 기대 401, 실제 %d", tc.name, p, resp.StatusCode)
			}
		}
	}
}

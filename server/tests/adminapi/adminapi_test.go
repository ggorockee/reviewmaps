package adminapi_test

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/glebarez/sqlite"
	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/ggorockee/reviewmaps/server/internal/admin"
	"github.com/ggorockee/reviewmaps/server/internal/adminapi"
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
	"github.com/ggorockee/reviewmaps/server/internal/services"
)

const origin = "https://admin.review-maps.com"

var dbSeq atomic.Int64

// newDB: 테스트마다 별도 메모리 DB, 외래 키 검사 켬 (운영 DB처럼 연결 행이 있으면 삭제 실패)
func newDB(t *testing.T) *database.DB {
	t.Helper()
	dsn := fmt.Sprintf("file:admintest%d?mode=memory&cache=shared&_pragma=foreign_keys(1)", dbSeq.Add(1))
	g, err := gorm.Open(sqlite.Open(dsn), &gorm.Config{Logger: logger.Default.LogMode(logger.Silent)})
	if err != nil {
		t.Fatal(err)
	}
	err = g.AutoMigrate(&models.User{}, &models.SocialAccount{}, &models.EmailVerification{}, &models.FCMDevice{},
		&models.Category{}, &models.Campaign{}, &models.Keyword{}, &models.KeywordAlert{}, &models.RawCategory{},
		&models.CategoryMapping{}, &models.AppSetting{}, &models.AppVersion{}, &models.AdConfig{},
		&models.RateLimitConfig{}, &models.AdminSession{}, &models.AdminAuditLog{})
	if err != nil {
		t.Fatal(err)
	}
	// go-scraper 소유 테이블 (서버 모델과 실제 구조가 달라 직접 생성)
	if err := g.Exec(`CREATE TABLE local_search_cache (title_hash text primary key, title text, category text)`).Error; err != nil {
		t.Fatal(err)
	}
	return &database.DB{DB: g}
}

type fakeVerifier map[string]string

func (f fakeVerifier) Verify(_ context.Context, tok string) (string, error) {
	if e, ok := f[tok]; ok {
		return e, nil
	}
	return "", admin.ErrInvalidToken
}

type env struct {
	app *fiber.App
	db  *database.DB
}

func newEnv(t *testing.T) *env {
	t.Helper()
	db := newDB(t)
	hash, _ := bcrypt.GenerateFromPassword([]byte("pw-1234"), bcrypt.MinCost)
	pw, err := admin.NewPasswordLogin("breakglass@review-maps.com", string(hash))
	if err != nil {
		t.Fatal(err)
	}
	app := fiber.New()
	adminapi.Mount(app, &adminapi.Options{
		DB:        db,
		Verifier:  fakeVerifier{"good": "Admin@Example.com", "outsider": "someone@example.com"},
		Allowlist: admin.ParseAllowlist("admin@example.com, breakglass@review-maps.com"),
		Sessions:  &admin.Sessions{DB: db.DB, TTL: time.Hour},
		Origin:    origin,
		Password:  pw,
	})
	return &env{app: app, db: db}
}

func (e *env) do(t *testing.T, method, path string, body any, cookie string) (int, string, *http.Response) {
	t.Helper()
	var r io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		r = bytes.NewReader(b)
	}
	req := httptest.NewRequest(method, path, r)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Origin", origin)
	if cookie != "" {
		req.Header.Set("Cookie", adminapi.SessionCookie+"="+cookie)
	}
	resp, err := e.app.Test(req, -1)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b), resp
}

func (e *env) login(t *testing.T) string {
	t.Helper()
	code, body, resp := e.do(t, "POST", "/admin/v1/auth/google", map[string]string{"credential": "good"}, "")
	if code != 200 {
		t.Fatalf("login: %d %s", code, body)
	}
	for _, c := range resp.Cookies() {
		if c.Name == adminapi.SessionCookie {
			if !c.HttpOnly || c.SameSite != http.SameSiteStrictMode || c.Path != adminapi.Prefix {
				t.Fatalf("cookie flags: %+v", c)
			}
			return c.Value
		}
	}
	t.Fatal("no session cookie")
	return ""
}

func TestAuth(t *testing.T) {
	e := newEnv(t)
	if code, _, _ := e.do(t, "GET", "/admin/v1/users", nil, ""); code != 401 {
		t.Fatalf("no cookie: want 401, got %d", code)
	}
	if code, _, _ := e.do(t, "POST", "/admin/v1/auth/google", map[string]string{"credential": "bad"}, ""); code != 401 {
		t.Fatalf("invalid token: want 401, got %d", code)
	}
	if code, _, _ := e.do(t, "POST", "/admin/v1/auth/google", map[string]string{"credential": "outsider"}, ""); code != 403 {
		t.Fatalf("not allowed: want 403, got %d", code)
	}
	if code, _, _ := e.do(t, "POST", "/admin/v1/auth/password", map[string]string{"id": "breakglass@review-maps.com", "password": "wrong"}, ""); code != 401 {
		t.Fatalf("wrong password: want 401, got %d", code)
	}
	if code, body, _ := e.do(t, "POST", "/admin/v1/auth/password", map[string]string{"id": "breakglass@review-maps.com", "password": "pw-1234"}, ""); code != 200 {
		t.Fatalf("password login: %d %s", code, body)
	}
	tok := e.login(t)
	code, body, _ := e.do(t, "GET", "/admin/v1/me", nil, tok)
	if code != 200 || !strings.Contains(body, "admin@example.com") {
		t.Fatalf("me: %d %s", code, body)
	}
	// 세션 DB에는 토큰 원문이 없어야 함
	var n int64
	e.db.Model(&models.AdminSession{}).Where("token_hash = ?", []byte(tok)).Count(&n)
	if n != 0 {
		t.Fatal("raw token stored")
	}
	if code, _, _ := e.do(t, "POST", "/admin/v1/auth/logout", nil, tok); code != 204 {
		t.Fatalf("logout: %d", code)
	}
	if code, _, _ := e.do(t, "GET", "/admin/v1/me", nil, tok); code != 401 {
		t.Fatalf("after logout: want 401, got %d", code)
	}
}

func TestOriginGuard(t *testing.T) {
	e := newEnv(t)
	tok := e.login(t)
	req := httptest.NewRequest("PUT", "/admin/v1/settings/keyword_limit", strings.NewReader(`{"value":5}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Origin", "https://evil.example.com")
	req.Header.Set("Cookie", adminapi.SessionCookie+"="+tok)
	resp, _ := e.app.Test(req, -1)
	if resp.StatusCode != 403 {
		t.Fatalf("foreign origin: want 403, got %d", resp.StatusCode)
	}
}

func TestSessionExpiry(t *testing.T) {
	db := newDB(t)
	now := time.Now()
	s := &admin.Sessions{DB: db.DB, TTL: time.Hour, Now: func() time.Time { return now }}
	tok, _, err := s.Create(context.Background(), "a@b.c")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.Lookup(context.Background(), tok); err != nil {
		t.Fatal(err)
	}
	now = now.Add(2 * time.Hour)
	if _, err := s.Lookup(context.Background(), tok); !errors.Is(err, admin.ErrNoSession) {
		t.Fatalf("expired: want ErrNoSession, got %v", err)
	}
}

func seedUser(t *testing.T, db *database.DB, email string) models.User {
	t.Helper()
	now := time.Now()
	u := models.User{Username: email, Email: email, Password: "x", LoginMethod: "google", Name: "n", IsActive: true, DateJoined: now}
	if err := db.Create(&u).Error; err != nil {
		t.Fatal(err)
	}
	at, rt, mail := "secret-access-token", "secret-refresh-token", email
	if err := db.Create(&models.SocialAccount{UserID: u.ID, Provider: "google", ProviderUserID: "g-" + email, Email: &mail,
		AccessToken: &at, RefreshToken: &rt, CreatedAt: now, UpdatedAt: now}).Error; err != nil {
		t.Fatal(err)
	}
	cat := models.Campaign{Platform: "리뷰노트", Company: "가게", Offer: "식사권", CreatedAt: now, UpdatedAt: now}
	db.Create(&cat)
	kw := models.Keyword{UserID: &u.ID, Keyword: "강남", IsActive: true, CreatedAt: now, UpdatedAt: now}
	if err := db.Create(&kw).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.KeywordAlert{KeywordID: kw.ID, CampaignID: &cat.ID, MatchedField: "title", CreatedAt: now, UpdatedAt: now}).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&models.FCMDevice{UserID: &u.ID, FCMToken: "fcm-token-abcdefghijklmnop", DeviceType: "ios", IsActive: true, CreatedAt: now, UpdatedAt: now}).Error; err != nil {
		t.Fatal(err)
	}
	return u
}

// 운영 DB처럼 외래 키가 NO ACTION이면 사용자 행만 지우는 예전 방식은 실패해야 함
func TestUserDelete_NeedsRelatedRowsFirst(t *testing.T) {
	db := newDB(t)
	u := seedUser(t, db, "old@example.com")
	if err := db.Delete(&models.User{}, u.ID).Error; err == nil {
		t.Fatal("expected FK violation when deleting only the users row")
	}
	if err := services.NewUserService(db).Delete(u.ID); err != nil {
		t.Fatalf("UserService.Delete: %v", err)
	}
	for _, m := range []any{&models.User{}, &models.SocialAccount{}, &models.Keyword{}, &models.FCMDevice{}} {
		var n int64
		db.Model(m).Count(&n)
		if n != 0 {
			t.Fatalf("%T left: %d", m, n)
		}
	}
	var alerts int64
	db.Unscoped().Model(&models.KeywordAlert{}).Count(&alerts)
	if alerts != 0 {
		t.Fatalf("alerts left: %d", alerts)
	}
}

func TestUserDetailHidesSecretsAndDelete(t *testing.T) {
	e := newEnv(t)
	tok := e.login(t)
	u := seedUser(t, e.db, "user@example.com")
	code, body, _ := e.do(t, "GET", fmt.Sprintf("/admin/v1/users/%d", u.ID), nil, tok)
	if code != 200 {
		t.Fatalf("detail: %d %s", code, body)
	}
	for _, secret := range []string{"secret-access-token", "secret-refresh-token", "fcm-token-abcdefghijklmnop", `"password"`} {
		if strings.Contains(body, secret) {
			t.Fatalf("detail leaks %q: %s", secret, body)
		}
	}
	if !strings.Contains(body, "fcm-toke…") {
		t.Fatalf("token hint missing: %s", body)
	}
	if code, _, _ := e.do(t, "DELETE", fmt.Sprintf("/admin/v1/users/%d", u.ID), map[string]string{"confirm_email": "wrong@example.com"}, tok); code != 400 {
		t.Fatalf("wrong confirm: want 400, got %d", code)
	}
	if code, body, _ := e.do(t, "DELETE", fmt.Sprintf("/admin/v1/users/%d", u.ID), map[string]string{"confirm_email": "USER@example.com"}, tok); code != 204 {
		t.Fatalf("delete: %d %s", code, body)
	}
	var audit models.AdminAuditLog
	if err := e.db.Where("entity = ? AND action = ?", "user", "delete").Take(&audit).Error; err != nil {
		t.Fatalf("audit: %v", err)
	}
	if audit.AdminEmail != "admin@example.com" || audit.Before == nil || strings.Contains(*audit.Before, "secret") {
		t.Fatalf("audit row: %+v", audit)
	}
}

func TestAlertsBulkDeleteIsSoft(t *testing.T) {
	e := newEnv(t)
	tok := e.login(t)
	seedUser(t, e.db, "a@example.com")
	if code, _, _ := e.do(t, "POST", "/admin/v1/alerts/bulk-delete", map[string]any{}, tok); code != 400 {
		t.Fatalf("missing before: want 400, got %d", code)
	}
	tomorrow := time.Now().Add(48 * time.Hour).Format("2006-01-02")
	code, body, _ := e.do(t, "POST", "/admin/v1/alerts/bulk-delete", map[string]any{"before": tomorrow, "dry_run": true}, tok)
	if code != 200 || !strings.Contains(body, `"matched":1`) || !strings.Contains(body, `"deleted":0`) {
		t.Fatalf("dry run: %d %s", code, body)
	}
	code, body, _ = e.do(t, "POST", "/admin/v1/alerts/bulk-delete", map[string]any{"before": tomorrow}, tok)
	if code != 200 || !strings.Contains(body, `"deleted":1`) {
		t.Fatalf("delete: %d %s", code, body)
	}
	var live, all int64
	e.db.Model(&models.KeywordAlert{}).Count(&live)
	e.db.Unscoped().Model(&models.KeywordAlert{}).Count(&all)
	if live != 0 || all != 1 {
		t.Fatalf("soft delete: live=%d all=%d", live, all)
	}
}

func TestCampaignSoftDeleteRestore(t *testing.T) {
	e := newEnv(t)
	tok := e.login(t)
	now := time.Now()
	c := models.Campaign{Platform: "리뷰노트", Company: "카페", Offer: "음료", CreatedAt: now, UpdatedAt: now}
	e.db.Create(&c)
	id := fmt.Sprint(c.ID)
	if code, _, _ := e.do(t, "DELETE", "/admin/v1/campaigns/"+id, nil, tok); code != 204 {
		t.Fatalf("delete: %d", code)
	}
	_, body, _ := e.do(t, "GET", "/admin/v1/campaigns", nil, tok)
	if !strings.Contains(body, `"total":0`) {
		t.Fatalf("deleted still listed: %s", body)
	}
	_, body, _ = e.do(t, "GET", "/admin/v1/campaigns?deleted=only", nil, tok)
	if !strings.Contains(body, `"total":1`) {
		t.Fatalf("deleted=only: %s", body)
	}
	if code, _, _ := e.do(t, "POST", "/admin/v1/campaigns/"+id+"/restore", nil, tok); code != 204 {
		t.Fatalf("restore: %d", code)
	}
	if code, _, _ := e.do(t, "PATCH", "/admin/v1/campaigns/"+id, map[string]int{"promotion_level": 11}, tok); code != 400 {
		t.Fatalf("promotion range: want 400, got %d", code)
	}
	if code, _, _ := e.do(t, "PATCH", "/admin/v1/campaigns/"+id, map[string]int{"promotion_level": 3}, tok); code != 200 {
		t.Fatalf("promotion: %d", code)
	}
}

func TestRawCategorySuggestionsAndBulkMapping(t *testing.T) {
	e := newEnv(t)
	tok := e.login(t)
	now := time.Now()
	food := models.Category{Name: "맛집", DisplayOrder: 1, CreatedAt: now}
	shop := models.Category{Name: "쇼핑", DisplayOrder: 2, CreatedAt: now}
	e.db.Create(&food)
	e.db.Create(&shop)
	mk := func(text string) models.RawCategory {
		r := models.RawCategory{RawText: text, CreatedAt: now}
		e.db.Create(&r)
		return r
	}
	for _, s := range []string{"음식점>한식>국밥", "음식점>한식>냉면", "음식점>중식"} {
		r := mk(s)
		e.db.Create(&models.CategoryMapping{RawCategoryID: r.ID, StandardCategoryID: food.ID})
	}
	numeric := mk(fmt.Sprint(food.ID))
	prefix := mk("음식점>한식>순대국")
	unknown := mk("농업>곡물재배")
	e.db.Exec(`INSERT INTO local_search_cache (title_hash, title, category) VALUES ('h1','t1',?),('h2','t2',?),('h3','t3',?)`,
		numeric.RawText, numeric.RawText, prefix.RawText)

	code, body, _ := e.do(t, "GET", "/admin/v1/raw-categories?unmapped=1", nil, tok)
	if code != 200 {
		t.Fatalf("list: %d %s", code, body)
	}
	var res struct {
		Items []struct {
			ID         uint  `json:"id"`
			Usage      int64 `json:"usage"`
			Suggestion *struct {
				CategoryID uint    `json:"category_id"`
				Confidence float64 `json:"confidence"`
			} `json:"suggestion"`
		} `json:"items"`
		Total int64 `json:"total"`
	}
	json.Unmarshal([]byte(body), &res)
	if res.Total != 3 || len(res.Items) != 3 {
		t.Fatalf("unmapped: %s", body)
	}
	// 사용량 순: 숫자 원본(2) → 접두어(1) → 미사용(0)
	if res.Items[0].ID != numeric.ID || res.Items[0].Usage != 2 || res.Items[0].Suggestion == nil ||
		res.Items[0].Suggestion.CategoryID != food.ID || res.Items[0].Suggestion.Confidence != 1 {
		t.Fatalf("numeric suggestion: %+v", res.Items[0])
	}
	if res.Items[1].ID != prefix.ID || res.Items[1].Suggestion == nil || res.Items[1].Suggestion.CategoryID != food.ID {
		t.Fatalf("prefix suggestion: %+v", res.Items[1])
	}
	if res.Items[2].ID != unknown.ID || res.Items[2].Suggestion != nil {
		t.Fatalf("no suggestion expected: %+v", res.Items[2])
	}
	code, body, _ = e.do(t, "POST", "/admin/v1/raw-categories/bulk-mapping", map[string]any{"items": []map[string]any{
		{"raw_category_id": numeric.ID, "category_id": food.ID},
		{"raw_category_id": unknown.ID, "category_id": shop.ID},
	}}, tok)
	if code != 200 || !strings.Contains(body, `"updated":2`) {
		t.Fatalf("bulk: %d %s", code, body)
	}
	_, body, _ = e.do(t, "GET", "/admin/v1/categories/coverage", nil, tok)
	if !strings.Contains(body, `"raw_categories_unmapped":1`) {
		t.Fatalf("coverage: %s", body)
	}
	var audits int64
	e.db.Model(&models.AdminAuditLog{}).Where("entity = ?", "category_mapping").Count(&audits)
	if audits != 2 {
		t.Fatalf("audits: %d", audits)
	}
	// 없는 카테고리면 전체 롤백
	code, _, _ = e.do(t, "POST", "/admin/v1/raw-categories/bulk-mapping", map[string]any{"items": []map[string]any{
		{"raw_category_id": prefix.ID, "category_id": food.ID},
		{"raw_category_id": prefix.ID, "category_id": 999},
	}}, tok)
	if code != 400 {
		t.Fatalf("bad category: want 400, got %d", code)
	}
	var m int64
	e.db.Model(&models.CategoryMapping{}).Where("raw_category_id = ?", prefix.ID).Count(&m)
	if m != 0 {
		t.Fatal("partial mapping committed")
	}
}

func TestSettingsValidation(t *testing.T) {
	e := newEnv(t)
	tok := e.login(t)
	if code, _, _ := e.do(t, "PUT", "/admin/v1/settings/keyword_limit", map[string]int{"value": 0}, tok); code != 400 {
		t.Fatalf("range: want 400, got %d", code)
	}
	if code, _, _ := e.do(t, "PUT", "/admin/v1/settings/unknown", map[string]int{"value": 1}, tok); code != 400 {
		t.Fatalf("unknown key: want 400, got %d", code)
	}
	if code, body, _ := e.do(t, "PUT", "/admin/v1/settings/keyword_limit", map[string]int{"value": 15}, tok); code != 200 {
		t.Fatalf("update: %d %s", code, body)
	}
	_, body, _ := e.do(t, "GET", "/admin/v1/settings", nil, tok)
	// 저장 안 된 설정은 서버 기본값(알림 보관 3일)으로 보여야 함 (null이면 화면이 1로 채워 잘못 저장될 수 있음)
	if !strings.Contains(body, `"key":"alert_retention_days","value":3`) || !strings.Contains(body, `"stored":false`) {
		t.Fatalf("default setting: %s", body)
	}
	if !strings.Contains(body, `"key":"keyword_limit","value":15`) {
		t.Fatalf("settings: %s", body)
	}
}

func TestGoogleVerifier(t *testing.T) {
	key, _ := rsa.GenerateKey(rand.Reader, 2048)
	now := time.Now()
	v := admin.NewGoogleVerifierWithKeyfunc("client-123", func(*jwt.Token) (any, error) { return &key.PublicKey, nil },
		func() time.Time { return now })
	sign := func(claims jwt.MapClaims) string {
		s, _ := jwt.NewWithClaims(jwt.SigningMethodRS256, claims).SignedString(key)
		return s
	}
	base := func() jwt.MapClaims {
		return jwt.MapClaims{"iss": "https://accounts.google.com", "aud": "client-123", "exp": now.Add(time.Hour).Unix(),
			"email": "Admin@Example.com", "email_verified": true}
	}
	if email, err := v.Verify(context.Background(), sign(base())); err != nil || email != "admin@example.com" {
		t.Fatalf("valid: %q %v", email, err)
	}
	for name, mut := range map[string]func(jwt.MapClaims){
		"aud":      func(c jwt.MapClaims) { c["aud"] = "other" },
		"iss":      func(c jwt.MapClaims) { c["iss"] = "evil" },
		"expired":  func(c jwt.MapClaims) { c["exp"] = now.Add(-time.Minute).Unix() },
		"verified": func(c jwt.MapClaims) { c["email_verified"] = false },
	} {
		c := base()
		mut(c)
		if _, err := v.Verify(context.Background(), sign(c)); !errors.Is(err, admin.ErrInvalidToken) {
			t.Fatalf("%s: want ErrInvalidToken, got %v", name, err)
		}
	}
}

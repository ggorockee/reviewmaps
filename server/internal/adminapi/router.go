// Package adminapi serves the admin console API under /admin/v1 (admin.review-maps.com).
//
// 인증: Google ID 토큰 또는 예비 아이디/비밀번호 → 허용 목록(ADMIN_EMAILS) → 세션 쿠키.
// 앱 API(/v1)와 같은 서버·DB를 쓰지만, CORS·쿠키·Origin 검사는 이 그룹에만 적용한다.
// 모든 변경은 admin_audit_logs와 reviewmaps_admin_changes_total에 남긴다.
package adminapi

import (
	"errors"
	"log"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/limiter"

	"github.com/ggorockee/reviewmaps/server/internal/admin"
	"github.com/ggorockee/reviewmaps/server/internal/database"
)

// Options configures /admin/v1.
type Options struct {
	DB        *database.DB
	Verifier  admin.Verifier
	Allowlist admin.Allowlist
	Sessions  *admin.Sessions
	// Origin is the admin console origin (https://admin.review-maps.com).
	Origin string
	// GoogleClientID is handed to the console's login button.
	GoogleClientID string
	// CookieSecure must be true in production (HTTPS).
	CookieSecure bool
	// Password enables POST /auth/password (break-glass account); nil disables it.
	Password *admin.PasswordLogin
	// DevEmail enables POST /auth/dev for local development only. Never set in production.
	DevEmail string
	// LoginLimit is login attempts per minute per IP (default 5).
	LoginLimit int
}

const (
	// SessionCookie is the admin session cookie name.
	SessionCookie = "rm_admin"
	// Prefix is where the admin API is mounted.
	Prefix = "/admin/v1"
)

// Mount registers /admin/v1 on app.
func Mount(app *fiber.App, opt *Options) {
	if opt.LoginLimit == 0 {
		opt.LoginLimit = 5
	}
	g := app.Group(Prefix, cors.New(cors.Config{
		AllowOrigins:     opt.Origin,
		AllowCredentials: true,
		AllowMethods:     "GET,POST,PUT,PATCH,DELETE",
		AllowHeaders:     "Content-Type",
		MaxAge:           600,
	}), originGuard(opt.Origin))

	// 로그인 화면이 쓰는 공개 설정
	g.Get("/config", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"google_client_id": opt.GoogleClientID,
			"dev_login":        opt.DevEmail != "",
			"password_login":   opt.Password != nil,
		})
	})

	loginLimiter := func(method string) fiber.Handler {
		return limiter.New(limiter.Config{
			Max:        opt.LoginLimit,
			Expiration: time.Minute,
			LimitReached: func(c *fiber.Ctx) error {
				admin.RecordLogin(method, "rate_limited")
				return fiber.NewError(fiber.StatusTooManyRequests, "too many login attempts")
			},
		})
	}
	if opt.Verifier != nil {
		g.Post("/auth/google", loginLimiter("google"), func(c *fiber.Ctx) error {
			var req struct {
				Credential string `json:"credential"`
			}
			if err := c.BodyParser(&req); err != nil || req.Credential == "" {
				admin.RecordLogin("google", "invalid_token")
				return fiber.NewError(fiber.StatusBadRequest, "credential is required")
			}
			email, err := opt.Verifier.Verify(c.UserContext(), req.Credential)
			if err != nil {
				admin.RecordLogin("google", "invalid_token")
				log.Printf("[admin] login rejected: invalid_token: %v", err)
				return fiber.NewError(fiber.StatusUnauthorized, "invalid google credential")
			}
			return startSession(c, opt, "google", email)
		})
	}
	if opt.Password != nil {
		g.Post("/auth/password", loginLimiter("password"), func(c *fiber.Ctx) error {
			var req struct {
				ID       string `json:"id"`
				Password string `json:"password"`
			}
			if err := c.BodyParser(&req); err != nil || req.ID == "" || req.Password == "" {
				admin.RecordLogin("password", "invalid_password")
				return fiber.NewError(fiber.StatusBadRequest, "id and password are required")
			}
			if !opt.Password.Check(strings.TrimSpace(req.ID), req.Password) {
				admin.RecordLogin("password", "invalid_password")
				log.Printf("[admin] login rejected: invalid_password")
				return fiber.NewError(fiber.StatusUnauthorized, "invalid id or password")
			}
			return startSession(c, opt, "password", opt.Password.ID)
		})
	}
	if opt.DevEmail != "" {
		g.Post("/auth/dev", func(c *fiber.Ctx) error {
			return startSession(c, opt, "dev", opt.DevEmail)
		})
	}

	auth := requireSession(opt)
	g.Post("/auth/logout", auth, func(c *fiber.Ctx) error {
		_ = opt.Sessions.Delete(c.UserContext(), c.Cookies(SessionCookie))
		c.Cookie(sessionCookieFor(opt, "", time.Unix(0, 0)))
		return c.SendStatus(fiber.StatusNoContent)
	})
	g.Get("/me", auth, func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"email": adminEmail(c)})
	})

	h := &handlers{db: opt.DB}
	g.Get("/summary", auth, h.summary)
	g.Get("/audit-logs", auth, h.listAuditLogs)

	g.Get("/users", auth, h.listUsers)
	g.Get("/users/:id", auth, h.getUser)
	g.Patch("/users/:id", auth, h.updateUser)
	g.Delete("/users/:id", auth, h.deleteUser)
	g.Get("/fcm-devices", auth, h.listFCMDevices)
	g.Get("/email-verifications", auth, h.listEmailVerifications)

	g.Get("/keywords", auth, h.listKeywords)
	g.Patch("/keywords/:id", auth, h.updateKeyword)
	g.Delete("/keywords/:id", auth, h.deleteKeyword)
	g.Get("/alerts", auth, h.listAlerts)
	g.Post("/alerts/bulk-delete", auth, h.bulkDeleteAlerts)

	g.Get("/campaigns", auth, h.listCampaigns)
	g.Get("/campaigns/:id", auth, h.getCampaign)
	g.Patch("/campaigns/:id", auth, h.updateCampaign)
	g.Delete("/campaigns/:id", auth, h.deleteCampaign)
	g.Post("/campaigns/:id/restore", auth, h.restoreCampaign)

	// 고정 경로를 /:id 보다 먼저 등록 (Fiber는 등록 순서대로 매칭)
	g.Get("/categories/coverage", auth, h.categoryCoverage)
	g.Put("/categories/order", auth, h.reorderCategories)
	g.Get("/categories", auth, h.listCategories)
	g.Post("/categories", auth, h.createCategory)
	g.Patch("/categories/:id", auth, h.updateCategory)
	g.Delete("/categories/:id", auth, h.deleteCategory)
	g.Get("/raw-categories", auth, h.listRawCategories)
	g.Post("/raw-categories/bulk-mapping", auth, h.bulkMapRawCategories)
	g.Put("/raw-categories/:id/mapping", auth, h.mapRawCategory)

	g.Get("/settings", auth, h.listSettings)
	g.Put("/settings/:key", auth, h.updateSetting)
	g.Get("/app-versions", auth, h.listAppVersions)
	g.Get("/ad-configs", auth, h.listAdConfigs)
	g.Get("/rate-limits", auth, h.listRateLimits)
}

// originGuard rejects state-changing requests that do not come from the console (CSRF 방어).
// 쿠키는 SameSite=Strict이지만, 같은 사이트의 다른 주소에서 오는 요청까지 막기 위해 Origin을 확인한다.
func originGuard(origin string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		switch c.Method() {
		case fiber.MethodGet, fiber.MethodHead, fiber.MethodOptions:
			return c.Next()
		}
		if c.Get(fiber.HeaderOrigin) != origin {
			return fiber.NewError(fiber.StatusForbidden, "origin not allowed")
		}
		return c.Next()
	}
}

func startSession(c *fiber.Ctx, opt *Options, method, email string) error {
	// 대소문자·공백이 달라도 같은 계정으로 취급 (세션·변경 기록·허용 목록 일치)
	email = strings.ToLower(strings.TrimSpace(email))
	if !opt.Allowlist.Allowed(email) {
		admin.RecordLogin(method, "not_allowed")
		log.Printf("[admin] login rejected: not_allowed: %s", email)
		return fiber.NewError(fiber.StatusForbidden, "this account is not an admin")
	}
	token, expires, err := opt.Sessions.Create(c.UserContext(), email)
	if err != nil {
		log.Printf("[admin] create session: %v", err)
		return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
	}
	admin.RecordLogin(method, "success")
	log.Printf("[admin] login: %s (%s)", email, method)
	c.Cookie(sessionCookieFor(opt, token, expires))
	return c.JSON(fiber.Map{"email": email, "expires_at": expires})
}

func sessionCookieFor(opt *Options, token string, expires time.Time) *fiber.Cookie {
	return &fiber.Cookie{
		Name:     SessionCookie,
		Value:    token,
		Path:     Prefix,
		Expires:  expires,
		HTTPOnly: true,
		Secure:   opt.CookieSecure,
		// 콘솔(admin.review-maps.com)과 API(api.review-maps.com)는 같은 사이트라 Strict로 충분
		SameSite: fiber.CookieSameSiteStrictMode,
	}
}

func requireSession(opt *Options) fiber.Handler {
	return func(c *fiber.Ctx) error {
		email, err := opt.Sessions.Lookup(c.UserContext(), c.Cookies(SessionCookie))
		if errors.Is(err, admin.ErrNoSession) {
			return fiber.NewError(fiber.StatusUnauthorized, "login required")
		}
		if err != nil {
			return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
		}
		// 세션이 남아 있어도 허용 목록에서 빠진 계정은 차단
		if !opt.Allowlist.Allowed(email) {
			return fiber.NewError(fiber.StatusForbidden, "this account is not an admin")
		}
		c.Locals("admin_email", email)
		return c.Next()
	}
}

func adminEmail(c *fiber.Ctx) string { s, _ := c.Locals("admin_email").(string); return s }

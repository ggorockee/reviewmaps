package handlers

import (
	"strings"

	"github.com/ggorockee/reviewmaps/server/internal/config"
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/services"
	"github.com/ggorockee/reviewmaps/server/pkg/auth"
	"github.com/gofiber/fiber/v2"
)

type AuthHandler struct {
	service     *services.AuthService
	userService *services.UserService
	cfg         *config.Config
}

func NewAuthHandler(db *database.DB, cfg *config.Config) *AuthHandler {
	return &AuthHandler{
		service:     services.NewAuthService(db, cfg),
		userService: services.NewUserService(db),
		cfg:         cfg,
	}
}

func SetupAuthRoutes(router fiber.Router, db *database.DB, cfg *config.Config) {
	h := NewAuthHandler(db, cfg)

	router.Post("/email/send-code", h.SendEmailCode)
	router.Post("/email/verify-code", h.VerifyEmailCode)
	router.Post("/signup", h.Signup)
	router.Post("/login", h.Login)
	router.Post("/refresh", h.RefreshToken)
	router.Post("/anonymous", h.AnonymousSession)
	router.Post("/kakao", h.KakaoLogin)
	router.Post("/google", h.GoogleLogin)
	router.Post("/apple", h.AppleLogin)

	// /auth/me endpoints (mobile app compatibility)
	router.Get("/me", h.GetMe)
	router.Delete("/me", h.DeleteMe)
}

// SendEmailCode godoc
// @Summary Send email verification code
// @Tags auth
// @Accept json
// @Produce json
// @Param request body services.SendEmailCodeRequest true "Email"
// @Success 200 {object} services.EmailCodeSentResponse
// @Router /auth/email/send-code [post]
func (h *AuthHandler) SendEmailCode(c *fiber.Ctx) error {
	var req services.SendEmailCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	if err := h.service.SendEmailCode(req.Email); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(services.EmailCodeSentResponse{
		Message:   "Verification code sent",
		ExpiresIn: 600, // 10 minutes in seconds
	})
}

// VerifyEmailCode godoc
// @Summary Verify email code
// @Tags auth
// @Accept json
// @Produce json
// @Param request body services.VerifyEmailCodeRequest true "Email and code"
// @Success 200 {object} services.EmailVerifyCodeResponse
// @Router /auth/email/verify-code [post]
func (h *AuthHandler) VerifyEmailCode(c *fiber.Ctx) error {
	var req services.VerifyEmailCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	verificationToken, err := h.service.VerifyEmailCode(req.Email, req.Code)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(services.EmailVerifyCodeResponse{
		Verified:          true,
		VerificationToken: verificationToken,
	})
}

// Signup godoc
// @Summary User signup
// @Tags auth
// @Accept json
// @Produce json
// @Param request body services.SignupRequest true "Signup data"
// @Success 201 {object} services.AuthResponse
// @Router /auth/signup [post]
func (h *AuthHandler) Signup(c *fiber.Ctx) error {
	var req services.SignupRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	response, err := h.service.Signup(&req)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(fiber.StatusCreated).JSON(response)
}

// Login godoc
// @Summary User login
// @Tags auth
// @Accept json
// @Produce json
// @Param request body services.LoginRequest true "Login credentials"
// @Success 200 {object} services.AuthResponse
// @Router /auth/login [post]
func (h *AuthHandler) Login(c *fiber.Ctx) error {
	var req services.LoginRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	response, err := h.service.Login(&req)
	if err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(response)
}

// RefreshToken godoc
// @Summary Refresh access token
// @Tags auth
// @Accept json
// @Produce json
// @Param request body services.RefreshTokenRequest true "Refresh token"
// @Success 200 {object} services.AuthResponse
// @Router /auth/refresh [post]
func (h *AuthHandler) RefreshToken(c *fiber.Ctx) error {
	var req services.RefreshTokenRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	response, err := h.service.RefreshToken(req.RefreshToken)
	if err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(response)
}

// AnonymousSession godoc
// @Summary Create anonymous session
// @Tags auth
// @Accept json
// @Produce json
// @Success 200 {object} services.AuthResponse
// @Router /auth/anonymous [post]
func (h *AuthHandler) AnonymousSession(c *fiber.Ctx) error {
	response, err := h.service.CreateAnonymousSession()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(response)
}

// KakaoLogin godoc
// @Summary Kakao OAuth login
// @Tags auth
// @Accept json
// @Produce json
// @Param request body services.SNSLoginRequest true "Kakao access token"
// @Success 200 {object} services.AuthResponse
// @Router /auth/kakao [post]
func (h *AuthHandler) KakaoLogin(c *fiber.Ctx) error {
	var req services.SNSLoginRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
			"detail": err.Error(),
		})
	}

	response, err := h.service.KakaoLogin(req.AccessToken)
	if err != nil {
		// Log detailed error to console
		c.Context().Logger().Printf("[KakaoLogin] Error: %v, Token (first 20 chars): %s", err, truncateString(req.AccessToken, 20))

		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Kakao login failed",
			"detail": err.Error(),
		})
	}

	return c.JSON(response)
}

// GoogleLogin godoc
// @Summary Google OAuth login
// @Tags auth
// @Accept json
// @Produce json
// @Param request body services.SNSLoginRequest true "Google ID token"
// @Success 200 {object} services.AuthResponse
// @Router /auth/google [post]
func (h *AuthHandler) GoogleLogin(c *fiber.Ctx) error {
	var req services.SNSLoginRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
			"detail": err.Error(),
		})
	}

	response, err := h.service.GoogleLogin(req.AccessToken)
	if err != nil {
		// Log detailed error to console
		c.Context().Logger().Printf("[GoogleLogin] Error: %v, Token (first 20 chars): %s", err, truncateString(req.AccessToken, 20))

		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Google login failed",
			"detail": err.Error(),
		})
	}

	return c.JSON(response)
}

// truncateString safely truncates a string to maxLen characters
func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}

// AppleLogin godoc
// @Summary Apple OAuth login
// @Tags auth
// @Accept json
// @Produce json
// @Param request body services.SNSLoginRequest true "Apple ID token"
// @Success 200 {object} services.AuthResponse
// @Router /auth/apple [post]
func (h *AuthHandler) AppleLogin(c *fiber.Ctx) error {
	var req services.SNSLoginRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
			"detail": err.Error(),
		})
	}

	response, err := h.service.AppleLogin(req.AccessToken)
	if err != nil {
		// Log detailed error to console
		c.Context().Logger().Printf("[AppleLogin] Error: %v, Token (first 20 chars): %s", err, truncateString(req.AccessToken, 20))

		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Apple login failed",
			"detail": err.Error(),
		})
	}

	return c.JSON(response)
}

// GetMe godoc
// @Summary Get current user info (auth/me compatibility)
// @Tags auth
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} models.User
// @Router /auth/me [get]
func (h *AuthHandler) GetMe(c *fiber.Ctx) error {
	// Extract token from Authorization header
	authHeader := c.Get("Authorization")
	if authHeader == "" {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"detail": "로그인이 필요합니다.",
		})
	}

	parts := strings.Split(authHeader, " ")
	if len(parts) != 2 || parts[0] != "Bearer" {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"detail": "잘못된 인증 형식입니다.",
		})
	}

	token := parts[1]
	claims, err := auth.ValidateAccessToken(token, h.cfg.JWTSecretKey)
	if err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"detail": "로그인이 만료되었습니다. 다시 로그인해 주세요.",
		})
	}

	user, err := h.userService.GetByID(claims.UserID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"detail": "사용자를 찾을 수 없습니다.",
		})
	}

	return c.JSON(user)
}

// DeleteMe godoc
// @Summary Delete current user (auth/me compatibility)
// @Tags auth
// @Accept json
// @Produce json
// @Security BearerAuth
// @Success 200 {object} map[string]string
// @Router /auth/me [delete]
func (h *AuthHandler) DeleteMe(c *fiber.Ctx) error {
	// Extract token from Authorization header
	authHeader := c.Get("Authorization")
	if authHeader == "" {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"detail": "로그인이 필요합니다.",
		})
	}

	parts := strings.Split(authHeader, " ")
	if len(parts) != 2 || parts[0] != "Bearer" {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"detail": "잘못된 인증 형식입니다.",
		})
	}

	token := parts[1]
	claims, err := auth.ValidateAccessToken(token, h.cfg.JWTSecretKey)
	if err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"detail": "로그인이 만료되었습니다. 다시 로그인해 주세요.",
		})
	}

	if err := h.userService.Delete(claims.UserID); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"detail": "회원 탈퇴 처리 중 오류가 발생했습니다.",
		})
	}

	return c.JSON(fiber.Map{
		"message": "회원 탈퇴가 완료되었습니다.",
	})
}

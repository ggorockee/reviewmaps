package handlers

import (
	"github.com/ggorockee/reviewmaps/server/internal/config"
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/services"
	"github.com/gofiber/fiber/v2"
)

type AuthHandler struct {
	service *services.AuthService
}

func NewAuthHandler(db *database.DB, cfg *config.Config) *AuthHandler {
	return &AuthHandler{
		service: services.NewAuthService(db, cfg),
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
}

// SendEmailCode godoc
// @Summary Send email verification code
// @Tags auth
// @Accept json
// @Produce json
// @Param request body services.SendEmailCodeRequest true "Email"
// @Success 200 {object} map[string]string
// @Router /auth/email/send-code [post]
func (h *AuthHandler) SendEmailCode(c *fiber.Ctx) error {
	var req services.SendEmailCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	if err := h.service.SendEmailCode(req.Email); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(fiber.Map{"message": "Verification code sent"})
}

// VerifyEmailCode godoc
// @Summary Verify email code
// @Tags auth
// @Accept json
// @Produce json
// @Param request body services.VerifyEmailCodeRequest true "Email and code"
// @Success 200 {object} map[string]bool
// @Router /auth/email/verify-code [post]
func (h *AuthHandler) VerifyEmailCode(c *fiber.Ctx) error {
	var req services.VerifyEmailCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	valid, err := h.service.VerifyEmailCode(req.Email, req.Code)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(fiber.Map{"verified": valid})
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
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	response, err := h.service.KakaoLogin(req.AccessToken)
	if err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": err.Error()})
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
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	response, err := h.service.GoogleLogin(req.AccessToken)
	if err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(response)
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
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	response, err := h.service.AppleLogin(req.AccessToken)
	if err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(response)
}

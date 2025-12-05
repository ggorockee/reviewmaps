package services

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"time"

	"github.com/ggorockee/reviewmaps/server/internal/config"
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
	"github.com/ggorockee/reviewmaps/server/pkg/auth"
	"github.com/ggorockee/reviewmaps/server/pkg/sns"
	"github.com/google/uuid"
)

type AuthService struct {
	db  *database.DB
	cfg *config.Config
}

func NewAuthService(db *database.DB, cfg *config.Config) *AuthService {
	return &AuthService{db: db, cfg: cfg}
}

// Request/Response types
type SendEmailCodeRequest struct {
	Email string `json:"email"`
}

type VerifyEmailCodeRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

type SignupRequest struct {
	Email    string  `json:"email"`
	Password string  `json:"password"`
	Name     *string `json:"name,omitempty"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type SNSLoginRequest struct {
	AccessToken string `json:"access_token"`
}

type AuthResponse struct {
	AccessToken  string       `json:"access_token"`
	RefreshToken string       `json:"refresh_token"`
	User         *models.User `json:"user"`
}

// SendEmailCode sends verification code to email
func (s *AuthService) SendEmailCode(email string) error {
	// Generate 6-digit code
	code := fmt.Sprintf("%06d", rand.Intn(1000000))

	// Delete existing codes for this email
	s.db.Where("email = ?", email).Delete(&models.EmailVerification{})

	// Create new verification record
	verification := models.EmailVerification{
		Email:     email,
		Code:      code,
		ExpiresAt: time.Now().Add(10 * time.Minute),
	}

	if err := s.db.Create(&verification).Error; err != nil {
		return err
	}

	// TODO: Send email with code (implement email service)
	fmt.Printf("Verification code for %s: %s\n", email, code)

	return nil
}

// VerifyEmailCode verifies the email code
func (s *AuthService) VerifyEmailCode(email, code string) (bool, error) {
	var verification models.EmailVerification
	err := s.db.Where("email = ? AND code = ? AND expires_at > ?", email, code, time.Now()).First(&verification).Error
	if err != nil {
		return false, errors.New("invalid or expired code")
	}

	verification.IsVerified = true
	s.db.Save(&verification)

	return true, nil
}

// Signup creates a new user
func (s *AuthService) Signup(req *SignupRequest) (*AuthResponse, error) {
	// Check if email is verified
	var verification models.EmailVerification
	err := s.db.Where("email = ? AND is_verified = ?", req.Email, true).First(&verification).Error
	if err != nil {
		return nil, errors.New("email not verified")
	}

	// Check if user already exists
	var existingUser models.User
	if err := s.db.Where("email = ? AND login_method = ?", req.Email, "email").First(&existingUser).Error; err == nil {
		return nil, errors.New("user already exists")
	}

	// Hash password
	hashedPassword, err := auth.HashPassword(req.Password)
	if err != nil {
		return nil, err
	}

	// Create user
	user := models.User{
		Username:    uuid.New().String(),
		Email:       req.Email,
		Password:    hashedPassword,
		LoginMethod: "email",
		Name:        req.Name,
	}

	if err := s.db.Create(&user).Error; err != nil {
		return nil, err
	}

	// Generate tokens
	accessToken, refreshToken, err := auth.GenerateTokenPair(
		user.ID,
		s.cfg.JWTSecretKey,
		s.cfg.JWTAccessTokenExpireMin,
		s.cfg.JWTRefreshTokenExpireDays,
	)
	if err != nil {
		return nil, err
	}

	return &AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		User:         &user,
	}, nil
}

// Login authenticates a user
func (s *AuthService) Login(req *LoginRequest) (*AuthResponse, error) {
	var user models.User
	if err := s.db.Where("email = ? AND login_method = ?", req.Email, "email").First(&user).Error; err != nil {
		return nil, errors.New("invalid credentials")
	}

	if !auth.CheckPassword(req.Password, user.Password) {
		return nil, errors.New("invalid credentials")
	}

	// Update last login
	now := time.Now()
	user.LastLogin = &now
	s.db.Save(&user)

	// Generate tokens
	accessToken, refreshToken, err := auth.GenerateTokenPair(
		user.ID,
		s.cfg.JWTSecretKey,
		s.cfg.JWTAccessTokenExpireMin,
		s.cfg.JWTRefreshTokenExpireDays,
	)
	if err != nil {
		return nil, err
	}

	return &AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		User:         &user,
	}, nil
}

// RefreshToken generates new tokens from refresh token
func (s *AuthService) RefreshToken(refreshToken string) (*AuthResponse, error) {
	claims, err := auth.ValidateRefreshToken(refreshToken, s.cfg.JWTSecretKey)
	if err != nil {
		return nil, errors.New("invalid refresh token")
	}

	var user models.User
	if err := s.db.First(&user, claims.UserID).Error; err != nil {
		return nil, errors.New("user not found")
	}

	// Generate new tokens
	accessToken, newRefreshToken, err := auth.GenerateTokenPair(
		user.ID,
		s.cfg.JWTSecretKey,
		s.cfg.JWTAccessTokenExpireMin,
		s.cfg.JWTRefreshTokenExpireDays,
	)
	if err != nil {
		return nil, err
	}

	return &AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: newRefreshToken,
		User:         &user,
	}, nil
}

// CreateAnonymousSession creates an anonymous user session
func (s *AuthService) CreateAnonymousSession() (*AuthResponse, error) {
	user := models.User{
		Username:    uuid.New().String(),
		Email:       fmt.Sprintf("anonymous_%s@reviewmaps.local", uuid.New().String()),
		LoginMethod: "anonymous",
	}

	if err := s.db.Create(&user).Error; err != nil {
		return nil, err
	}

	accessToken, refreshToken, err := auth.GenerateTokenPair(
		user.ID,
		s.cfg.JWTSecretKey,
		s.cfg.JWTAccessTokenExpireMin,
		s.cfg.JWTRefreshTokenExpireDays,
	)
	if err != nil {
		return nil, err
	}

	return &AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		User:         &user,
	}, nil
}

// KakaoLogin handles Kakao OAuth login
func (s *AuthService) KakaoLogin(accessToken string) (*AuthResponse, error) {
	ctx := context.Background()

	// Verify Kakao token
	kakaoUser, err := sns.VerifyKakaoToken(ctx, accessToken)
	if err != nil {
		return nil, fmt.Errorf("kakao verification failed: %w", err)
	}

	return s.handleSNSLogin("kakao", kakaoUser.ID, kakaoUser.Email, kakaoUser.Name, kakaoUser.ProfileImage)
}

// GoogleLogin handles Google OAuth login
func (s *AuthService) GoogleLogin(accessToken string) (*AuthResponse, error) {
	ctx := context.Background()

	// Verify Google token
	googleUser, err := sns.VerifyGoogleToken(ctx, accessToken)
	if err != nil {
		return nil, fmt.Errorf("google verification failed: %w", err)
	}

	return s.handleSNSLogin("google", googleUser.ID, googleUser.Email, googleUser.Name, googleUser.ProfileImage)
}

// AppleLogin handles Apple OAuth login
func (s *AuthService) AppleLogin(identityToken string) (*AuthResponse, error) {
	ctx := context.Background()

	// Verify Apple token
	appleUser, err := sns.VerifyAppleToken(ctx, identityToken, s.cfg.AppleBundleID)
	if err != nil {
		return nil, fmt.Errorf("apple verification failed: %w", err)
	}

	return s.handleSNSLogin("apple", appleUser.ID, appleUser.Email, appleUser.Name, appleUser.ProfileImage)
}

// handleSNSLogin handles common SNS login logic
func (s *AuthService) handleSNSLogin(provider, providerID, email, name, profileImage string) (*AuthResponse, error) {
	// Check if social account exists
	var socialAccount models.SocialAccount
	err := s.db.Where("provider = ? AND provider_id = ?", provider, providerID).
		Preload("User").
		First(&socialAccount).Error

	var user *models.User

	if err == nil {
		// Existing user
		user = &socialAccount.User

		// Update last login
		now := time.Now()
		user.LastLogin = &now
		s.db.Save(user)
	} else {
		// Create new user
		var namePtr *string
		if name != "" {
			namePtr = &name
		}
		var profileImagePtr *string
		if profileImage != "" {
			profileImagePtr = &profileImage
		}

		// Generate email if not provided
		if email == "" {
			email = fmt.Sprintf("%s_%s@reviewmaps.local", provider, providerID)
		}

		user = &models.User{
			Username:     uuid.New().String(),
			Email:        email,
			LoginMethod:  provider,
			Name:         namePtr,
			ProfileImage: profileImagePtr,
		}

		if err := s.db.Create(user).Error; err != nil {
			return nil, fmt.Errorf("failed to create user: %w", err)
		}

		// Create social account
		socialAccount = models.SocialAccount{
			UserID:     user.ID,
			Provider:   provider,
			ProviderID: providerID,
		}

		if err := s.db.Create(&socialAccount).Error; err != nil {
			return nil, fmt.Errorf("failed to create social account: %w", err)
		}
	}

	// Generate tokens
	accessToken, refreshToken, err := auth.GenerateTokenPair(
		user.ID,
		s.cfg.JWTSecretKey,
		s.cfg.JWTAccessTokenExpireMin,
		s.cfg.JWTRefreshTokenExpireDays,
	)
	if err != nil {
		return nil, err
	}

	return &AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		User:         user,
	}, nil
}

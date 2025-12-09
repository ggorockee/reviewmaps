package services

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"strings"
	"sync"
	"time"

	"github.com/ggorockee/reviewmaps/server/internal/config"
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
	"github.com/ggorockee/reviewmaps/server/pkg/auth"
	"github.com/ggorockee/reviewmaps/server/pkg/sns"
	"github.com/google/uuid"
	"gorm.io/gorm"
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

type EmailCodeSentResponse struct {
	Message   string `json:"message"`
	ExpiresIn int    `json:"expires_in"` // seconds
}

type EmailVerifyCodeResponse struct {
	Verified          bool   `json:"verified"`
	VerificationToken string `json:"verification_token"`
}

// AppleLoginRequest for Apple Sign In (identity_token + optional authorization_code)
type AppleLoginRequest struct {
	IdentityToken     string `json:"identity_token"`
	AuthorizationCode string `json:"authorization_code,omitempty"`
}

type AuthResponse struct {
	AccessToken  string       `json:"access_token"`
	RefreshToken string       `json:"refresh_token"`
	TokenType    string       `json:"token_type"`
	User         *UserResponse `json:"user"`
}

// UserResponse matches Django SNSLoginResponse.user structure
type UserResponse struct {
	ID          uint      `json:"id"`
	Email       string    `json:"email"`
	IsActive    bool      `json:"is_active"`
	DateJoined  time.Time `json:"date_joined"`
	LoginMethod string    `json:"login_method"`
}

// SendEmailCode sends verification code to email
func (s *AuthService) SendEmailCode(email string) error {
	// Generate 6-digit code
	code := fmt.Sprintf("%06d", rand.Intn(1000000))

	// Delete existing codes for this email
	s.db.Where("email = ?", email).Delete(&models.EmailVerification{})

	// Create new verification record
	expiresAt := time.Now().Add(10 * time.Minute)
	verification := models.EmailVerification{
		Email:     email,
		Code:      code,
		ExpiresAt: expiresAt,
	}

	if err := s.db.Create(&verification).Error; err != nil {
		return err
	}

	// TODO: Send email with code (implement email service)
	// For now, print to console for testing
	fmt.Printf("\n========================================\n")
	fmt.Printf("📧 EMAIL VERIFICATION CODE\n")
	fmt.Printf("========================================\n")
	fmt.Printf("Email: %s\n", email)
	fmt.Printf("Code: %s\n", code)
	fmt.Printf("Expires at: %s (in 10 minutes)\n", expiresAt.Format("2006-01-02 15:04:05"))
	fmt.Printf("========================================\n\n")

	return nil
}

// VerifyEmailCode verifies the email code and returns verification token
func (s *AuthService) VerifyEmailCode(email, code string) (string, error) {
	fmt.Printf("[VerifyEmailCode] Attempting to verify - Email: %s, Code: %s\n", email, code)

	var verification models.EmailVerification
	now := time.Now()
	err := s.db.Where("email = ? AND code = ? AND expires_at > ?", email, code, now).First(&verification).Error

	if err != nil {
		// Check if code exists but expired
		var expiredCheck models.EmailVerification
		if err2 := s.db.Where("email = ? AND code = ?", email, code).First(&expiredCheck).Error; err2 == nil {
			fmt.Printf("[VerifyEmailCode] Code found but expired - Expires at: %s, Current time: %s\n",
				expiredCheck.ExpiresAt.Format("2006-01-02 15:04:05"),
				now.Format("2006-01-02 15:04:05"))
			return "", errors.New("verification code has expired")
		}

		// Check if email exists with different code
		var emailCheck models.EmailVerification
		if err2 := s.db.Where("email = ?", email).Order("created_at DESC").First(&emailCheck).Error; err2 == nil {
			fmt.Printf("[VerifyEmailCode] Email found with different code - Expected: %s, Got: %s\n", emailCheck.Code, code)
			return "", errors.New("invalid verification code")
		}

		fmt.Printf("[VerifyEmailCode] No verification record found for email: %s\n", email)
		return "", errors.New("invalid or expired code")
	}

	// Generate verification token
	verificationToken := uuid.New().String()

	fmt.Printf("[VerifyEmailCode] Code verified successfully for: %s, Token: %s\n", email, verificationToken)
	verification.IsVerified = true
	verification.VerificationToken = &verificationToken
	s.db.Save(&verification)

	return verificationToken, nil
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

	// Create user with username as email_loginmethod (Django pattern)
	username := fmt.Sprintf("%s_email", req.Email)
	name := ""
	if req.Name != nil {
		name = *req.Name
	}
	user := models.User{
		Username:     username,
		Email:        req.Email,
		Password:     hashedPassword,
		LoginMethod:  "email",
		Name:         name,
		ProfileImage: "",
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
		TokenType:    "bearer",
		User: &UserResponse{
			ID:          user.ID,
			Email:       user.Email,
			IsActive:    user.IsActive,
			DateJoined:  user.DateJoined,
			LoginMethod: user.LoginMethod,
		},
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
		TokenType:    "bearer",
		User: &UserResponse{
			ID:          user.ID,
			Email:       user.Email,
			IsActive:    user.IsActive,
			DateJoined:  user.DateJoined,
			LoginMethod: user.LoginMethod,
		},
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
		TokenType:    "bearer",
		User: &UserResponse{
			ID:          user.ID,
			Email:       user.Email,
			IsActive:    user.IsActive,
			DateJoined:  user.DateJoined,
			LoginMethod: user.LoginMethod,
		},
	}, nil
}

// CreateAnonymousSession creates an anonymous user session
func (s *AuthService) CreateAnonymousSession() (*AuthResponse, error) {
	anonymousID := uuid.New().String()
	user := models.User{
		Username:    anonymousID,
		Email:       fmt.Sprintf("anonymous_%s@reviewmaps.local", anonymousID),
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
		TokenType:    "bearer",
		User: &UserResponse{
			ID:          user.ID,
			Email:       user.Email,
			IsActive:    user.IsActive,
			DateJoined:  user.DateJoined,
			LoginMethod: user.LoginMethod,
		},
	}, nil
}

// KakaoLogin handles Kakao OAuth login
// Django original: server_backup/users/api_social.py - kakao_login()
func (s *AuthService) KakaoLogin(accessToken string) (*AuthResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Verify Kakao token (async via goroutine with channel)
	type verifyResult struct {
		user *sns.KakaoUserInfo
		err  error
	}
	resultCh := make(chan verifyResult, 1)

	go func() {
		user, err := sns.VerifyKakaoToken(ctx, accessToken)
		resultCh <- verifyResult{user, err}
	}()

	// Wait for verification result
	result := <-resultCh
	if result.err != nil {
		return nil, fmt.Errorf("kakao 토큰 검증에 실패했습니다: %w", result.err)
	}

	kakaoUser := result.user
	if kakaoUser.Email == "" {
		return nil, errors.New("kakao 계정에 이메일이 없습니다. 이메일 제공 동의가 필요합니다")
	}

	return s.handleSNSLogin(
		"kakao",
		kakaoUser.ID,
		kakaoUser.Email,
		kakaoUser.Name,
		kakaoUser.ProfileImage,
		accessToken,
	)
}

// GoogleLogin handles Google OAuth login
// Django original: server_backup/users/api_social.py - google_login()
func (s *AuthService) GoogleLogin(accessToken string) (*AuthResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Verify Google token (async via goroutine with channel)
	type verifyResult struct {
		user *sns.GoogleUserInfo
		err  error
	}
	resultCh := make(chan verifyResult, 1)

	go func() {
		user, err := sns.VerifyGoogleToken(ctx, accessToken)
		resultCh <- verifyResult{user, err}
	}()

	// Wait for verification result
	result := <-resultCh
	if result.err != nil {
		return nil, fmt.Errorf("google 토큰 검증에 실패했습니다: %w", result.err)
	}

	googleUser := result.user
	if googleUser.Email == "" {
		return nil, errors.New("google 계정에 이메일이 없습니다")
	}

	return s.handleSNSLogin(
		"google",
		googleUser.ID,
		googleUser.Email,
		googleUser.Name,
		googleUser.ProfileImage,
		accessToken,
	)
}

// AppleLogin handles Apple OAuth login
// Django original: server_backup/users/api_social.py - apple_login()
func (s *AuthService) AppleLogin(identityToken string) (*AuthResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Verify Apple token (async via goroutine with channel)
	type verifyResult struct {
		user *sns.AppleUserInfo
		err  error
	}
	resultCh := make(chan verifyResult, 1)

	go func() {
		user, err := sns.VerifyAppleToken(ctx, identityToken, s.cfg.AppleClientID)
		resultCh <- verifyResult{user, err}
	}()

	// Wait for verification result
	result := <-resultCh
	if result.err != nil {
		return nil, fmt.Errorf("apple 토큰 검증에 실패했습니다: %w", result.err)
	}

	appleUser := result.user
	if appleUser.Email == "" {
		return nil, errors.New("apple 계정에 이메일이 없습니다")
	}

	// Apple doesn't provide access token in the same way, pass empty
	return s.handleSNSLogin(
		"apple",
		appleUser.ID,
		appleUser.Email,
		appleUser.Name,
		appleUser.ProfileImage,
		"",
	)
}

// handleSNSLogin handles common SNS login logic
// Django original: server_backup/users/api_social.py - create_or_update_user() inner function
// This implements the exact same logic as Django's @transaction.atomic decorated function
func (s *AuthService) handleSNSLogin(provider, providerUserID, email, name, profileImage, accessToken string) (*AuthResponse, error) {
	// Normalize email (Django: BaseUserManager.normalize_email)
	email = normalizeEmail(email)

	var user *models.User

	// Use transaction for atomic operations (Django: @transaction.atomic)
	txErr := s.db.Transaction(func(tx *gorm.DB) error {
		// 1. Try to find existing SocialAccount by provider + provider_user_id
		// Django: SocialAccount.objects.select_related('user').get(provider='xxx', provider_user_id=xxx)
		// Note: Do NOT use Preload("User") to avoid association issues with legacy NULL username data
		var socialAccount models.SocialAccount
		findErr := tx.Where("provider = ? AND provider_user_id = ?", provider, providerUserID).
			First(&socialAccount).Error

		if findErr == nil {
			// Existing social account found - fetch user separately
			var existingUser models.User
			if err := tx.First(&existingUser, socialAccount.UserID).Error; err != nil {
				return fmt.Errorf("failed to find user: %w", err)
			}
			user = &existingUser

			// Update social account info (Django: social_account.save())
			// Use raw SQL update to completely avoid GORM association handling
			if err := tx.Model(&models.SocialAccount{}).
				Where("id = ?", socialAccount.ID).
				Updates(map[string]interface{}{
					"email":         email,
					"name":          name,
					"profile_image": profileImage,
					"access_token":  accessToken,
				}).Error; err != nil {
				return fmt.Errorf("failed to update social account: %w", err)
			}

			// Update User model profile info (Django: user.save(update_fields=['name', 'profile_image']))
			// Use raw SQL update to avoid touching username field
			updateFields := map[string]interface{}{
				"last_login": time.Now(),
			}
			if name != "" {
				updateFields["name"] = name
			}
			if profileImage != "" {
				updateFields["profile_image"] = profileImage
			}

			if err := tx.Model(&models.User{}).
				Where("id = ?", user.ID).
				Updates(updateFields).Error; err != nil {
				return fmt.Errorf("failed to update user: %w", err)
			}

			return nil
		}

		// 2. No SocialAccount found - check if User exists by email + login_method
		// Django: User.objects.get_or_create(email=email, login_method='xxx', defaults={...})
		var existingUser models.User
		userErr := tx.Where("email = ? AND login_method = ?", email, provider).First(&existingUser).Error

		if userErr == nil {
			// User exists - update profile if needed
			user = &existingUser

			updateFields := make(map[string]interface{})
			if name != "" && user.Name == "" {
				updateFields["name"] = name
			}
			if profileImage != "" && user.ProfileImage == "" {
				updateFields["profile_image"] = profileImage
			}
			now := time.Now()
			updateFields["last_login"] = now

			if len(updateFields) > 0 {
				if err := tx.Model(user).Updates(updateFields).Error; err != nil {
					return fmt.Errorf("failed to update user: %w", err)
				}
			}
		} else {
			// Create new user (Django: User.objects.get_or_create with defaults)
			// Generate username as email_provider (Django: f"{email}_{login_method}")
			username := fmt.Sprintf("%s_%s", email, provider)

			user = &models.User{
				Username:     username,
				Email:        email,
				LoginMethod:  provider,
				Name:         name,
				ProfileImage: profileImage,
			}

			if err := tx.Create(user).Error; err != nil {
				return fmt.Errorf("failed to create user: %w", err)
			}
		}

		// 3. Create SocialAccount (Django: SocialAccount.objects.create(...))
		// SocialAccount fields are nullable (*string)
		var emailPtr, namePtr, profileImagePtr, accessTokenPtr *string
		if email != "" {
			emailPtr = &email
		}
		if name != "" {
			namePtr = &name
		}
		if profileImage != "" {
			profileImagePtr = &profileImage
		}
		if accessToken != "" {
			accessTokenPtr = &accessToken
		}
		socialAccount = models.SocialAccount{
			UserID:         user.ID,
			Provider:       provider,
			ProviderUserID: providerUserID,
			Email:          emailPtr,
			Name:           namePtr,
			ProfileImage:   profileImagePtr,
			AccessToken:    accessTokenPtr,
		}

		if err := tx.Create(&socialAccount).Error; err != nil {
			return fmt.Errorf("failed to create social account: %w", err)
		}

		return nil
	})

	if txErr != nil {
		return nil, txErr
	}

	// Generate JWT tokens (Django: create_access_token, create_refresh_token)
	// Use goroutine for parallel token generation
	var jwtAccessToken, jwtRefreshToken string
	var tokenErr error

	var wg sync.WaitGroup
	wg.Add(1)

	go func() {
		defer wg.Done()
		jwtAccessToken, jwtRefreshToken, tokenErr = auth.GenerateTokenPair(
			user.ID,
			s.cfg.JWTSecretKey,
			s.cfg.JWTAccessTokenExpireMin,
			s.cfg.JWTRefreshTokenExpireDays,
		)
	}()

	wg.Wait()

	if tokenErr != nil {
		return nil, tokenErr
	}

	// Return response matching Django SNSLoginResponse structure
	return &AuthResponse{
		AccessToken:  jwtAccessToken,
		RefreshToken: jwtRefreshToken,
		TokenType:    "bearer",
		User: &UserResponse{
			ID:          user.ID,
			Email:       user.Email,
			IsActive:    user.IsActive,
			DateJoined:  user.DateJoined,
			LoginMethod: user.LoginMethod,
		},
	}, nil
}

// normalizeEmail normalizes email address (Django: BaseUserManager.normalize_email)
// Lowercases the domain portion of the email address
func normalizeEmail(email string) string {
	if email == "" {
		return ""
	}
	parts := strings.SplitN(email, "@", 2)
	if len(parts) == 2 {
		return parts[0] + "@" + strings.ToLower(parts[1])
	}
	return email
}

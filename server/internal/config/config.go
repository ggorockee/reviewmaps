package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	// Server
	ServerPort string
	ServerEnv  string
	ServerHost string // Swagger host 설정용

	// Database
	DatabaseURL string

	// JWT
	JWTSecretKey              string
	JWTAccessTokenExpireMin   int
	JWTRefreshTokenExpireDays int

	// Firebase
	FirebaseCredentialsPath string

	// Kakao
	KakaoRESTAPIKey string

	// Google
	GoogleClientIDIOS     string
	GoogleClientIDAndroid string
	GoogleClientIDWeb     string

	// Apple
	AppleTeamID   string
	AppleKeyID    string
	AppleClientID string // Bundle ID for Apple Sign In (APPLE_CLIENT_ID or APPLE_BUNDLE_ID)

	// SigNoz
	SigNozEndpoint string
}

func Load() *Config {
	return &Config{
		// Server
		ServerPort: getEnv("SERVER_PORT", "3000"),
		ServerEnv:  getEnv("SERVER_ENV", "development"),
		ServerHost: getEnv("SERVER_HOST", "localhost:3000"),

		// Database - DATABASE_URL 우선, 없으면 개별 환경변수로 구성
		DatabaseURL: getDatabaseURL(),

		// JWT
		JWTSecretKey:              getEnv("JWT_SECRET_KEY", ""),
		JWTAccessTokenExpireMin:   getEnvAsInt("JWT_ACCESS_TOKEN_EXPIRE_MINUTES", 15),
		JWTRefreshTokenExpireDays: getEnvAsInt("JWT_REFRESH_TOKEN_EXPIRE_DAYS", 7),

		// Firebase
		FirebaseCredentialsPath: getEnv("FIREBASE_CREDENTIALS_PATH", ""),

		// Kakao
		KakaoRESTAPIKey: getEnv("KAKAO_REST_API_KEY", ""),

		// Google
		GoogleClientIDIOS:     getEnv("GOOGLE_CLIENT_ID_IOS", ""),
		GoogleClientIDAndroid: getEnv("GOOGLE_CLIENT_ID_ANDROID", ""),
		GoogleClientIDWeb:     getEnv("GOOGLE_CLIENT_ID_WEB", ""),

		// Apple (APPLE_CLIENT_ID 우선, APPLE_BUNDLE_ID fallback - k8s secret 호환)
		AppleTeamID:   getEnv("APPLE_TEAM_ID", ""),
		AppleKeyID:    getEnv("APPLE_KEY_ID", ""),
		AppleClientID: getEnvWithFallback("APPLE_CLIENT_ID", "APPLE_BUNDLE_ID", ""),

		// SigNoz
		SigNozEndpoint: getEnv("SIGNOZ_ENDPOINT", ""),
	}
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}

// getEnvWithFallback tries primary key first, then fallback key
func getEnvWithFallback(primary, fallback, defaultValue string) string {
	if value, exists := os.LookupEnv(primary); exists && value != "" {
		return value
	}
	if value, exists := os.LookupEnv(fallback); exists && value != "" {
		return value
	}
	return defaultValue
}

func getEnvAsInt(key string, defaultValue int) int {
	if value, exists := os.LookupEnv(key); exists {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

// getDatabaseURL returns DATABASE_URL or builds it from individual env vars
func getDatabaseURL() string {
	// 1. DATABASE_URL이 있으면 그대로 사용
	if url := os.Getenv("DATABASE_URL"); url != "" {
		return url
	}

	// 2. 개별 환경변수로 구성 (k8s secret 키 이름과 일치)
	host := getEnv("POSTGRES_HOST", "localhost")
	port := getEnv("POSTGRES_PORT", "5432")
	user := getEnv("POSTGRES_USER", "postgres")
	password := getEnv("POSTGRES_PASSWORD", "")
	dbname := getEnv("POSTGRES_DB", "reviewmaps")
	sslmode := getEnv("POSTGRES_SSLMODE", "disable")

	return fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=%s",
		user, password, host, port, dbname, sslmode)
}

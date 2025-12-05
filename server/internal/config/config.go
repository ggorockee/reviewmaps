package config

import (
	"os"
	"strconv"
)

type Config struct {
	// Server
	ServerPort string
	ServerEnv  string

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
	AppleBundleID string

	// SigNoz
	SigNozEndpoint string
}

func Load() *Config {
	return &Config{
		// Server
		ServerPort: getEnv("SERVER_PORT", "8000"),
		ServerEnv:  getEnv("SERVER_ENV", "development"),

		// Database
		DatabaseURL: getEnv("DATABASE_URL", ""),

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

		// Apple
		AppleTeamID:   getEnv("APPLE_TEAM_ID", ""),
		AppleKeyID:    getEnv("APPLE_KEY_ID", ""),
		AppleBundleID: getEnv("APPLE_BUNDLE_ID", ""),

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

func getEnvAsInt(key string, defaultValue int) int {
	if value, exists := os.LookupEnv(key); exists {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

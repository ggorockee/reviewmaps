package config

import (
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/joho/godotenv"
)

// DatabaseConfig 데이터베이스 관련 설정
type DatabaseConfig struct {
	User     string
	Password string
	Host     string
	Port     string
	DBName   string
}

// URL SQLAlchemy 스타일의 데이터베이스 URL 생성
func (d *DatabaseConfig) URL() string {
	return fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable",
		d.User, d.Password, d.Host, d.Port, d.DBName)
}

// DSN pgx용 DSN 생성
func (d *DatabaseConfig) DSN() string {
	return fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		d.Host, d.Port, d.User, d.Password, d.DBName)
}

// NaverAPIConfig 네이버 API 관련 클라이언트 ID 및 시크릿 설정
type NaverAPIConfig struct {
	MapClientID       string
	MapClientSecret   string
	SearchClientID    string
	SearchClientSecret string
	SearchClientID2   string
	SearchClientSecret2 string
	SearchClientID3   string
	SearchClientSecret3 string
}

// GetSearchAPIKeys 검색 API 키 목록 반환
func (n *NaverAPIConfig) GetSearchAPIKeys() []APIKeyPair {
	var keys []APIKeyPair
	if n.SearchClientID != "" && n.SearchClientSecret != "" {
		keys = append(keys, APIKeyPair{ClientID: n.SearchClientID, ClientSecret: n.SearchClientSecret})
	}
	if n.SearchClientID2 != "" && n.SearchClientSecret2 != "" {
		keys = append(keys, APIKeyPair{ClientID: n.SearchClientID2, ClientSecret: n.SearchClientSecret2})
	}
	if n.SearchClientID3 != "" && n.SearchClientSecret3 != "" {
		keys = append(keys, APIKeyPair{ClientID: n.SearchClientID3, ClientSecret: n.SearchClientSecret3})
	}
	return keys
}

// APIKeyPair API 키 쌍
type APIKeyPair struct {
	ClientID     string
	ClientSecret string
}

// BatchConfig 배치(Batch) 작업 실행 관련 설정
type BatchConfig struct {
	Mode            string        // daily | interval | once
	TimeHHMM        string        // daily 모드일 때 실행 시각 (HH:MM)
	IntervalSeconds int           // interval 모드일 때 주기 (초)
	Timezone        string        // 타임존
	RunAtStart      bool          // 프로세스 시작 직후 한 번 즉시 실행할지 여부
	WaitTimeout     time.Duration // 대기 타임아웃
}

// Location 설정된 타임존을 *time.Location으로 반환
func (b *BatchConfig) Location() *time.Location {
	loc, err := time.LoadLocation(b.Timezone)
	if err != nil {
		loc, _ = time.LoadLocation("Asia/Seoul")
	}
	return loc
}

// ScrapeConfig 스크래핑 관련 설정
type ScrapeConfig struct {
	MaxItems int // 최대 수집 개수 (0 = 무제한)
}

// Config 애플리케이션의 모든 설정을 통합 관리하는 메인 구조체
type Config struct {
	BaseURL   string
	Headless  bool
	TableName string
	DB        DatabaseConfig
	NaverAPI  NaverAPIConfig
	Batch     BatchConfig
	Scrape    ScrapeConfig
}

// Load 환경변수에서 설정을 로드
func Load() (*Config, error) {
	// .env 파일 로드 (없어도 에러 무시)
	_ = godotenv.Load()

	cfg := &Config{
		BaseURL:   getEnv("BASE_URL", "https://mymilky.co.kr/"),
		Headless:  getEnvBool("HEADLESS", true),
		TableName: getEnv("TABLE_NAME", "campaign"),
		DB: DatabaseConfig{
			User:     getEnv("POSTGRES_USER", ""),
			Password: getEnv("POSTGRES_PASSWORD", ""),
			Host:     getEnv("POSTGRES_HOST", "localhost"),
			Port:     getEnv("POSTGRES_PORT", "5432"),
			DBName:   getEnv("POSTGRES_DB", ""),
		},
		NaverAPI: NaverAPIConfig{
			MapClientID:       getEnv("NAVER_MAP_CLIENT_ID", ""),
			MapClientSecret:   getEnv("NAVER_MAP_CLIENT_SECRET", ""),
			SearchClientID:    getEnv("NAVER_SEARCH_CLIENT_ID", ""),
			SearchClientSecret: getEnv("NAVER_SEARCH_CLIENT_SECRET", ""),
			SearchClientID2:   getEnv("NAVER_SEARCH_CLIENT_ID_2", ""),
			SearchClientSecret2: getEnv("NAVER_SEARCH_CLIENT_SECRET_2", ""),
			SearchClientID3:   getEnv("NAVER_SEARCH_CLIENT_ID_3", ""),
			SearchClientSecret3: getEnv("NAVER_SEARCH_CLIENT_SECRET_3", ""),
		},
		Batch: BatchConfig{
			Mode:            getEnv("BATCH_MODE", "daily"),
			TimeHHMM:        getEnv("BATCH_TIME", "01:00"),
			IntervalSeconds: getEnvInt("BATCH_INTERVAL_SECONDS", 300),
			Timezone:        getEnv("TIMEZONE", "Asia/Seoul"),
			RunAtStart:      getEnvBool("RUN_AT_START", false),
			WaitTimeout:     time.Duration(getEnvInt("WAIT_TIMEOUT", 15)) * time.Second,
		},
		Scrape: ScrapeConfig{
			MaxItems: getEnvInt("SCRAPE_MAX_ITEMS", 100),
		},
	}

	return cfg, nil
}

// getEnv 환경변수 가져오기 (기본값 지원)
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvBool 환경변수를 bool로 가져오기
func getEnvBool(key string, defaultValue bool) bool {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value == "true" || value == "1" || value == "yes"
}

// getEnvInt 환경변수를 int로 가져오기
func getEnvInt(key string, defaultValue int) int {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	intVal, err := strconv.Atoi(value)
	if err != nil {
		return defaultValue
	}
	return intVal
}

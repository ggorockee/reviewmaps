package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
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
	MaxPages int // 최대 페이지 수 (0 = 무제한, 기본 500 - 무한루프 방지)
}

// ServerAPIConfig Server API 연동 설정
type ServerAPIConfig struct {
	BaseURL    string // Server API Base URL (예: http://localhost:3000)
	APIKey     string // Internal API Key
	Enabled    bool   // API 호출 활성화 여부
}

// ReviewnoteConfig 리뷰노트 상세 보강 설정 (여행 카테고리 이용 요일 등)
type ReviewnoteConfig struct {
	Session           string        // 로그인 세션 쿠키(reviewNoteSession) 값. 비어 있으면 상세 API를 부르지 않음
	SessionExpiresAt  time.Time     // 세션 쿠키 만료 시각 (갱신할 때 함께 저장, 만료 전 알림용). 모르면 0
	DetailCategories  []string      // 상세를 받을 원본 카테고리 이름 (목록 응답 category.title)
	DetailCategoryIDs []string      // 목록 API categoryId (사이트 카테고리 선택 상자 값, 2026-11-27 여행)
	DetailRefreshDays int           // 이 기간 안에 받은 상세는 다시 받지 않음
	DetailMaxFetch    int           // 한 번 실행에서 상세 API 최대 호출 수 (0 = 상한 없음)
	ListCategoryIDs   []string      // 02:00 목록 수집에서 따로 더 받을 categoryId (전체 목록은 1,600건까지만 줌)
	DetailMinDelay    time.Duration // 상세 API 호출 최소 간격
	DetailWindowEnd   string        // 이 시각(HH:MM, TIMEZONE 기준)까지 끝냄
	DetailEndMargin   time.Duration // 마감 시각보다 이만큼 먼저 멈춤
	DetailStartJitter time.Duration // 시작 전 무작위 대기 최대값 (매일 같은 시각에 요청하지 않도록)
	DetailManualRun   time.Duration // 마감 시각 이후 수동 실행 시 쓸 시간
}

// PicklyConfig 피클리(picklykorea.kr) 수집 설정
type PicklyConfig struct {
	Enabled        bool          // 끄기 스위치 (피클리가 중단을 요청하면 false). 기본 false
	MaxDetailFetch int           // 한 번 실행에서 상세(좌표) 조회 최대 수 (새 공고만 조회)
	RequestDelay   time.Duration // 요청 간격
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
	ServerAPI ServerAPIConfig
	Reviewnote ReviewnoteConfig
	Pickly     PicklyConfig
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
			MaxItems: getEnvInt("SCRAPE_MAX_ITEMS", 0),
			MaxPages: getEnvInt("SCRAPE_MAX_PAGES", 500),
		},
		ServerAPI: ServerAPIConfig{
			BaseURL: getEnv("SERVER_API_BASE_URL", ""),
			APIKey:  getEnvWithFallback("SERVER_API_KEY", "API_SECRET_KEY", ""),
			Enabled: getEnvBool("SERVER_API_ENABLED", false),
		},
		Pickly: PicklyConfig{
			Enabled:        getEnvBool("PICKLY_ENABLED", false),
			MaxDetailFetch: getEnvInt("PICKLY_MAX_DETAIL_FETCH", 60),
			RequestDelay:   time.Duration(getEnvInt("PICKLY_REQUEST_DELAY_MS", 2000)) * time.Millisecond,
		},
		Reviewnote: ReviewnoteConfig{
			Session:           strings.TrimSpace(getEnv("REVIEWNOTE_SESSION", "")),
			SessionExpiresAt:  parseTime(getEnv("REVIEWNOTE_SESSION_EXPIRES_AT", "")),
			DetailCategories:  splitCSV(getEnv("REVIEWNOTE_DETAIL_CATEGORIES", "여행")),
			DetailRefreshDays: getEnvInt("REVIEWNOTE_DETAIL_REFRESH_DAYS", 14),
			DetailCategoryIDs: splitCSV(getEnv("REVIEWNOTE_DETAIL_CATEGORY_IDS", "d1910206-2676-433b-958f-6cb6e7385d1c")),
			DetailMaxFetch:    getEnvInt("REVIEWNOTE_DETAIL_MAX_FETCH", 0),
			ListCategoryIDs:   splitCSV(getEnv("REVIEWNOTE_LIST_CATEGORY_IDS", "d1910206-2676-433b-958f-6cb6e7385d1c")),
			DetailMinDelay:    time.Duration(getEnvInt("REVIEWNOTE_DETAIL_MIN_DELAY_SECONDS", 30)) * time.Second,
			DetailWindowEnd:   getEnv("REVIEWNOTE_DETAIL_WINDOW_END", "08:00"),
			DetailEndMargin:   time.Duration(getEnvInt("REVIEWNOTE_DETAIL_END_MARGIN_MINUTES", 10)) * time.Minute,
			DetailStartJitter: time.Duration(getEnvInt("REVIEWNOTE_DETAIL_START_JITTER_MINUTES", 30)) * time.Minute,
			DetailManualRun:   time.Duration(getEnvInt("REVIEWNOTE_DETAIL_MANUAL_RUN_MINUTES", 60)) * time.Minute,
		},
	}

	return cfg, nil
}

// parseTime RFC3339 시각을 읽는다 (비었거나 형식이 틀리면 0)
func parseTime(v string) time.Time {
	t, err := time.Parse(time.RFC3339, strings.TrimSpace(v))
	if err != nil {
		return time.Time{}
	}
	return t
}

// splitCSV 쉼표로 구분된 값을 공백 제거 후 목록으로 (빈 값 제외)
func splitCSV(v string) []string {
	var out []string
	for _, part := range strings.Split(v, ",") {
		if p := strings.TrimSpace(part); p != "" {
			out = append(out, p)
		}
	}
	return out
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

// getEnvWithFallback 주 키가 없으면 대체 키 사용
func getEnvWithFallback(primary, fallback, defaultValue string) string {
	if value := os.Getenv(primary); value != "" {
		return value
	}
	if value := os.Getenv(fallback); value != "" {
		return value
	}
	return defaultValue
}

package enricher

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"math/rand"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/logger"
	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
)

const (
	// STRIKE_LIMIT 동일 키에서 429가 이 횟수 이상 발생하면 소진 판단
	STRIKE_LIMIT = 3
	// INITIAL_SLEEP 첫 백오프(초)
	INITIAL_SLEEP = 0.4
	// BACKOFF_FACTOR 지수 백오프 계수
	BACKOFF_FACTOR = 1.7
	// MAX_BACKOFF 같은 키에서 한 번 시도 시 최대 대기
	MAX_BACKOFF = 6.0
	// DRIFT_METERS 좌표 드리프트 허용 거리(미터)
	DRIFT_METERS = 50.0
)

// Enricher 데이터 보강 서비스
type Enricher struct {
	cfg        *config.Config
	httpClient *http.Client
	apiKeys    []config.APIKeyPair
	workerID   int // Worker별 전용 키 인덱스 (-1이면 공유 풀 사용)
}

// New 새로운 Enricher 생성 (공유 풀 모드)
func New(cfg *config.Config) *Enricher {
	return &Enricher{
		cfg: cfg,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
		apiKeys:  cfg.NaverAPI.GetSearchAPIKeys(),
		workerID: -1, // 공유 풀 모드
	}
}

// NewForWorker Worker 전용 Enricher 생성
// workerID: 0, 1, 2, ... (시작 키 인덱스 결정에 사용)
// 모든 키를 공유하되, 시작 인덱스만 다르게 하여 부하 분산
func NewForWorker(cfg *config.Config, workerID int) *Enricher {
	allKeys := cfg.NaverAPI.GetSearchAPIKeys()

	// Worker별로 시작 키를 다르게 하여 부하 분산
	// 모든 키를 순환하며 사용 (키 소진 시 다음 키로 이동)
	var rotatedKeys []config.APIKeyPair
	if len(allKeys) > 0 {
		startIndex := workerID % len(allKeys)
		// 시작 인덱스부터 순환하여 모든 키 포함
		for i := 0; i < len(allKeys); i++ {
			idx := (startIndex + i) % len(allKeys)
			rotatedKeys = append(rotatedKeys, allKeys[idx])
		}
	}

	return &Enricher{
		cfg: cfg,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
		apiKeys:  rotatedKeys,
		workerID: workerID,
	}
}

// NaverLocalSearch 네이버 Local API 검색
func (e *Enricher) NaverLocalSearch(ctx context.Context, query string) (*models.NaverLocalSearchResult, error) {
	log := logger.GetLogger("enricher")

	// 쿼리 정리
	cleanQuery := strings.TrimSpace(query)
	cleanQuery = strings.ReplaceAll(cleanQuery, "[", "")
	cleanQuery = strings.ReplaceAll(cleanQuery, "]", "")
	cleanQuery = strings.ReplaceAll(cleanQuery, "/", " ")

	if len(e.apiKeys) == 0 {
		if e.workerID >= 0 {
			log.Errorf("[Worker-%d] Local API 키 없음", e.workerID)
		} else {
			log.Error("Local API 키 없음")
		}
		return nil, fmt.Errorf("no API keys available")
	}

	apiURL := "https://openapi.naver.com/v1/search/local.json"

	// 키를 순차적으로 시도 (단일 키 모드에서는 1개만 있음)
	for len(e.apiKeys) > 0 {
		key := e.apiKeys[0]
		strikes := 0
		backoff := INITIAL_SLEEP

		for {
			workerPrefix := ""
			if e.workerID >= 0 {
				workerPrefix = fmt.Sprintf("[Worker-%d] ", e.workerID)
			}
			log.Infof("%sNaver Local API 호출 (키: ...%s, 잔여키수: %d, Query='%s')",
				workerPrefix, key.ClientID[len(key.ClientID)-4:], len(e.apiKeys), cleanQuery)

			req, err := http.NewRequestWithContext(ctx, "GET", apiURL, nil)
			if err != nil {
				return nil, fmt.Errorf("failed to create request: %w", err)
			}

			q := req.URL.Query()
			q.Add("query", cleanQuery)
			q.Add("display", "1")
			req.URL.RawQuery = q.Encode()

			req.Header.Set("X-Naver-Client-Id", key.ClientID)
			req.Header.Set("X-Naver-Client-Secret", key.ClientSecret)

			resp, err := e.httpClient.Do(req)
			if err != nil {
				log.Warnf("Naver Local API 실패: %v. 같은 키로 1회 재시도.", err)
				time.Sleep(500*time.Millisecond + time.Duration(rand.Float64()*300)*time.Millisecond)

				// 재시도
				resp, err = e.httpClient.Do(req)
				if err != nil {
					log.Warnf("재시도 실패: %v. 키 소진으로 판단하고 제거.", err)
					e.apiKeys = e.apiKeys[1:]
					break
				}
			}

			if resp.StatusCode == http.StatusTooManyRequests {
				resp.Body.Close()
				strikes++
				if strikes >= STRIKE_LIMIT {
					log.Warnf("Key ...%s 429 %d회 → 소진 판단, 키 제거 후 다음 키로 이동.",
						key.ClientID[len(key.ClientID)-4:], strikes)
					e.apiKeys = e.apiKeys[1:]
					break
				}
				sleepFor := math.Min(MAX_BACKOFF, backoff) + rand.Float64()*0.3
				log.Warnf("429(Too Many Requests): 같은 키 재시도까지 %.2fs 대기 (strike %d/%d, key ...%s)",
					sleepFor, strikes, STRIKE_LIMIT, key.ClientID[len(key.ClientID)-4:])
				time.Sleep(time.Duration(sleepFor * float64(time.Second)))
				backoff *= BACKOFF_FACTOR
				continue
			}

			if resp.StatusCode != http.StatusOK {
				resp.Body.Close()
				log.Warnf("Naver Local API 실패(status=%d). 키 소진으로 판단하고 제거.", resp.StatusCode)
				e.apiKeys = e.apiKeys[1:]
				break
			}

			var result models.NaverLocalSearchResponse
			if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
				resp.Body.Close()
				return nil, fmt.Errorf("failed to decode response: %w", err)
			}
			resp.Body.Close()

			if len(result.Items) == 0 {
				return nil, nil
			}

			return &result.Items[0], nil
		}
	}

	log.Errorf("Naver Local API 모든 키 소진(또는 실패): %s", cleanQuery)
	return nil, fmt.Errorf("all API keys exhausted")
}

// NaverGeocode 네이버 Geocode API 호출
func (e *Enricher) NaverGeocode(ctx context.Context, address string) (lat, lng float64, found bool) {
	log := logger.GetLogger("enricher")

	apiURL := "https://maps.apigw.ntruss.com/map-geocode/v2/geocode"
	maxRetries := 3
	backoffFactor := 1.0

	for attempt := 0; attempt < maxRetries; attempt++ {
		req, err := http.NewRequestWithContext(ctx, "GET", apiURL, nil)
		if err != nil {
			log.Warnf("Geocode 요청 생성 실패: %v", err)
			return 0, 0, false
		}

		q := req.URL.Query()
		q.Add("query", address)
		req.URL.RawQuery = q.Encode()

		req.Header.Set("x-ncp-apigw-api-key-id", e.cfg.NaverAPI.MapClientID)
		req.Header.Set("x-ncp-apigw-api-key", e.cfg.NaverAPI.MapClientSecret)

		resp, err := e.httpClient.Do(req)
		if err != nil {
			log.Warnf("Geocode 실패 (%s): %v", address, err)
			return 0, 0, false
		}

		if resp.StatusCode == http.StatusTooManyRequests {
			resp.Body.Close()
			waitTime := backoffFactor * math.Pow(2, float64(attempt))
			log.Warnf("Geocode API 쿼터 초과 (%s). %.0f초 후 재시도... (%d/%d)",
				address, waitTime, attempt+1, maxRetries)
			time.Sleep(time.Duration(waitTime) * time.Second)
			continue
		}

		if resp.StatusCode != http.StatusOK {
			resp.Body.Close()
			log.Warnf("Geocode 실패 (%s): status=%d", address, resp.StatusCode)
			return 0, 0, false
		}

		var result models.NaverGeocodeResponse
		if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
			resp.Body.Close()
			log.Warnf("Geocode 응답 파싱 실패: %v", err)
			return 0, 0, false
		}
		resp.Body.Close()

		if len(result.Addresses) == 0 {
			return 0, 0, false
		}

		lat, err = strconv.ParseFloat(result.Addresses[0].Y, 64)
		if err != nil {
			return 0, 0, false
		}
		lng, err = strconv.ParseFloat(result.Addresses[0].X, 64)
		if err != nil {
			return 0, 0, false
		}

		return lat, lng, true
	}

	log.Errorf("Geocode API 모든 재시도 실패 (%s)", address)
	return 0, 0, false
}

// FromMapXY 네이버 Local API 응답에서 mapx/mapy를 위경도로 변환
func FromMapXY(mapx, mapy string) (lat, lng float64, valid bool) {
	mx, err := strconv.ParseFloat(mapx, 64)
	if err != nil {
		return 0, 0, false
	}
	my, err := strconv.ParseFloat(mapy, 64)
	if err != nil {
		return 0, 0, false
	}

	lon := mx / 1e7
	lat = my / 1e7

	// 한국 좌표 대략 범위 체크
	if lat < 33.0 || lat > 39.5 || lon < 124.0 || lon > 132.0 {
		return 0, 0, false
	}

	return lat, lon, true
}

// Haversine 두 좌표 사이 거리(meter)
func Haversine(lat1, lng1, lat2, lng2 float64) float64 {
	const R = 6371000.0 // 지구 반지름 (미터)

	dLat := toRadians(lat2 - lat1)
	dLng := toRadians(lng2 - lng1)

	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(toRadians(lat1))*math.Cos(toRadians(lat2))*
			math.Sin(dLng/2)*math.Sin(dLng/2)

	c := 2 * math.Asin(math.Sqrt(a))

	return R * c
}

// toRadians 각도를 라디안으로 변환
func toRadians(deg float64) float64 {
	return deg * math.Pi / 180
}

// CleanTitle 제목 정리 (특수문자 제거)
func CleanTitle(title string) string {
	result := strings.TrimSpace(title)
	result = strings.ReplaceAll(result, "[", "")
	result = strings.ReplaceAll(result, "]", " ")
	return strings.TrimSpace(result)
}

// URLEncode URL 인코딩
func URLEncode(s string) string {
	return url.QueryEscape(s)
}

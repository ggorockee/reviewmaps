package reviewnote

import (
	"context"
	"sync"
	"sync/atomic"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/enricher"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/logger"
	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
)

// EnrichConfig Enrich 설정
type EnrichConfig struct {
	MaxWorkers     int           // 동시 API 호출 Worker 수 (기본: 3)
	APIDelay       time.Duration // API 호출 간 딜레이 (기본: 200ms)
	EnableParallel bool          // 병렬 처리 활성화
}

// DefaultEnrichConfig 기본 설정
func DefaultEnrichConfig() *EnrichConfig {
	return &EnrichConfig{
		MaxWorkers:     3,             // 네이버 API 키 개수와 맞춤
		APIDelay:       200 * time.Millisecond,
		EnableParallel: true,
	}
}

// EnrichJob Worker에 전달되는 작업
type EnrichJob struct {
	Index    int
	Campaign *models.Campaign
	Existing *models.CampaignKey // 기존 DB 데이터 (있으면)
}

// EnrichResult 보강 결과
type EnrichResult struct {
	Index      int
	Address    *string
	Lat        *float64
	Lng        *float64
	CategoryID *int64
	Error      error
}

// EnrichStats 보강 통계
type EnrichStats struct {
	Total       int32
	CacheHit    int32
	APICalled   int32
	Geocoded    int32
	DriftFixed  int32
	Skipped     int32
	Errors      int32
}

// enrichVisitCampaigns 방문형 캠페인만 보강 (Worker Pool 패턴)
func (s *Scraper) enrichVisitCampaigns(ctx context.Context, campaigns []models.Campaign, config *EnrichConfig) ([]models.Campaign, *EnrichStats) {
	log := logger.GetLogger("scraper.reviewnote.enrich")

	if config == nil {
		config = DefaultEnrichConfig()
	}

	stats := &EnrichStats{}

	// 1. 기존 DB 캠페인 로드
	existing, err := s.DB.LoadExistingCampaigns(ctx)
	if err != nil {
		log.Warnf("기존 캠페인 로드 실패: %v", err)
		existing = make(map[string]*models.CampaignKey)
	}
	log.Infof("기존 DB에서 %d개 캠페인 로드", len(existing))

	// 2. 방문형 캠페인만 필터링
	var visitCampaigns []int // 인덱스만 저장
	for i := range campaigns {
		if campaigns[i].CampaignType != nil && *campaigns[i].CampaignType == "방문형" {
			visitCampaigns = append(visitCampaigns, i)
		} else {
			atomic.AddInt32(&stats.Skipped, 1)
		}
	}

	log.Infof("방문형 캠페인 %d개 보강 시작 (총 %d개 중)", len(visitCampaigns), len(campaigns))

	if len(visitCampaigns) == 0 {
		return campaigns, stats
	}

	atomic.StoreInt32(&stats.Total, int32(len(visitCampaigns)))

	// 3. Worker Pool 설정
	if !config.EnableParallel {
		config.MaxWorkers = 1
	}

	jobs := make(chan EnrichJob, len(visitCampaigns))
	results := make(chan EnrichResult, len(visitCampaigns))

	// 4. Workers 시작
	var wg sync.WaitGroup
	for w := 0; w < config.MaxWorkers; w++ {
		wg.Add(1)
		go s.enrichWorker(ctx, w, jobs, results, &wg, config, stats)
	}

	// 5. 작업 분배
	for _, idx := range visitCampaigns {
		campaign := &campaigns[idx]
		key := campaignKey(campaign)
		var existingData *models.CampaignKey
		if ex, ok := existing[key]; ok {
			existingData = ex
		}

		jobs <- EnrichJob{
			Index:    idx,
			Campaign: campaign,
			Existing: existingData,
		}
	}
	close(jobs)

	// 6. Workers 완료 대기
	go func() {
		wg.Wait()
		close(results)
	}()

	// 7. 결과 수집 및 적용
	for result := range results {
		if result.Error != nil {
			atomic.AddInt32(&stats.Errors, 1)
			continue
		}

		// 결과 적용
		if result.Address != nil {
			campaigns[result.Index].Address = result.Address
		}
		if result.Lat != nil {
			campaigns[result.Index].Lat = result.Lat
		}
		if result.Lng != nil {
			campaigns[result.Index].Lng = result.Lng
		}
		if result.CategoryID != nil {
			campaigns[result.Index].CategoryID = result.CategoryID
		}
	}

	log.Infof("[Enrich 통계] Total:%d, CacheHit:%d, APICalled:%d, Geocoded:%d, DriftFixed:%d, Skipped:%d, Errors:%d",
		stats.Total, stats.CacheHit, stats.APICalled, stats.Geocoded, stats.DriftFixed, stats.Skipped, stats.Errors)

	// 메트릭 기록
	if s.telemetry != nil {
		s.telemetry.RecordEnrichStats(ctx, platformName,
			int64(stats.Total),
			int64(stats.CacheHit),
			int64(stats.APICalled),
			int64(stats.Geocoded),
		)
	}

	return campaigns, stats
}

// enrichWorker 개별 Worker (각 Worker별 전용 API 키 할당)
func (s *Scraper) enrichWorker(ctx context.Context, id int, jobs <-chan EnrichJob, results chan<- EnrichResult, wg *sync.WaitGroup, config *EnrichConfig, stats *EnrichStats) {
	defer wg.Done()
	log := logger.GetLogger("scraper.reviewnote.enrich")

	// Worker별 전용 Enricher 생성 (각 Worker는 자신만의 API 키 사용)
	workerEnricher := enricher.NewForWorker(s.Config, id)
	log.Infof("[Worker-%d] 시작 (전용 API 키 할당)", id)

	for job := range jobs {
		select {
		case <-ctx.Done():
			results <- EnrichResult{Index: job.Index, Error: ctx.Err()}
			continue
		default:
		}

		result := s.enrichSingleCampaignWithEnricher(ctx, job, stats, workerEnricher)
		results <- result

		// Rate limiting: API 호출 간 딜레이
		time.Sleep(config.APIDelay)
	}

	log.Infof("[Worker-%d] 종료", id)
}

// enrichSingleCampaign 단일 캠페인 보강 (BaseScraper의 공유 Enricher 사용)
func (s *Scraper) enrichSingleCampaign(ctx context.Context, job EnrichJob, stats *EnrichStats) EnrichResult {
	return s.enrichSingleCampaignWithEnricher(ctx, job, stats, s.Enricher)
}

// enrichSingleCampaignWithEnricher 단일 캠페인 보강 (지정된 Enricher 사용)
func (s *Scraper) enrichSingleCampaignWithEnricher(ctx context.Context, job EnrichJob, stats *EnrichStats, workerEnricher *enricher.Enricher) EnrichResult {
	log := logger.GetLogger("scraper.reviewnote.enrich")
	campaign := job.Campaign

	result := EnrichResult{Index: job.Index}

	// 1. Local Cache 확인
	cacheEntry, found := s.DB.GetLocalCache(ctx, campaign.Title)
	if found && cacheEntry != nil {
		atomic.AddInt32(&stats.CacheHit, 1)
		log.Debugf("[Cache HIT] %s", campaign.Title)

		result.Address = cacheEntry.Address
		result.Lat = cacheEntry.Lat
		result.Lng = cacheEntry.Lng

		// 카테고리 매핑 (캐시에 저장된 원본 텍스트 → raw_categories → category_mappings)
		if cacheEntry.CategoryText != nil && *cacheEntry.CategoryText != "" {
			rawID, err := s.DB.GetOrCreateRawCategory(ctx, *cacheEntry.CategoryText)
			if err == nil && rawID != nil {
				mappedID, err := s.DB.FindMappedCategoryID(ctx, *rawID)
				if err == nil && mappedID != nil {
					result.CategoryID = mappedID
				}
			}
		}

		return result
	}

	// 2. Cache MISS → 네이버 Local Search API 호출
	atomic.AddInt32(&stats.APICalled, 1)
	log.Debugf("[Cache MISS] %s → API 호출", campaign.Title)

	place, err := workerEnricher.NaverLocalSearch(ctx, campaign.Title)
	if err != nil {
		log.Warnf("Local Search 실패 (%s): %v", campaign.Title, err)
		return result
	}

	if place == nil {
		log.Debugf("Local Search 결과 없음: %s", campaign.Title)
		return result
	}

	// 3. 주소 추출
	address := place.RoadAddress
	if address == "" {
		address = place.Address
	}
	if address != "" {
		result.Address = &address
	}

	// 4. mapx/mapy → lat/lng 변환
	if place.MapX != "" && place.MapY != "" {
		lat, lng, valid := enricher.FromMapXY(place.MapX, place.MapY)
		if valid {
			result.Lat = &lat
			result.Lng = &lng
		}
	}

	// 5. 카테고리 처리
	var categoryTextForCache *string
	if place.Category != "" {
		categoryTextForCache = &place.Category
		rawID, err := s.DB.GetOrCreateRawCategory(ctx, place.Category)
		if err == nil && rawID != nil {
			mappedID, err := s.DB.FindMappedCategoryID(ctx, *rawID)
			if err == nil && mappedID != nil {
				result.CategoryID = mappedID
			}
		}
	}

	// 6. 주소는 있는데 좌표가 없으면 Geocode
	if result.Address != nil && (result.Lat == nil || result.Lng == nil) {
		// Geocode Cache 확인
		lat, lng, found := s.DB.GetGeocodeCache(ctx, *result.Address)
		if found {
			result.Lat = &lat
			result.Lng = &lng
		} else {
			// Geocode API 호출
			lat, lng, ok := workerEnricher.NaverGeocode(ctx, *result.Address)
			if ok {
				result.Lat = &lat
				result.Lng = &lng
				atomic.AddInt32(&stats.Geocoded, 1)

				// Geocode Cache 저장
				_ = s.DB.PutGeocodeCache(ctx, *result.Address, lat, lng)
			}
		}
	}

	// 7. 드리프트 체크 (기존 DB 좌표와 50m 이상 차이나면)
	if job.Existing != nil && result.Lat != nil && result.Lng != nil && result.Address != nil {
		if job.Existing.Lat != nil && job.Existing.Lng != nil {
			dist := enricher.Haversine(*job.Existing.Lat, *job.Existing.Lng, *result.Lat, *result.Lng)
			if dist > enricher.DRIFT_METERS {
				log.Warnf("[Drift] %s: %.0fm 드리프트 감지, Geocode로 재보정", campaign.Title, dist)

				// Geocode로 재보정
				lat, lng, ok := workerEnricher.NaverGeocode(ctx, *result.Address)
				if ok {
					result.Lat = &lat
					result.Lng = &lng
					atomic.AddInt32(&stats.DriftFixed, 1)
					atomic.AddInt32(&stats.Geocoded, 1)

					// Geocode Cache 업데이트
					_ = s.DB.PutGeocodeCache(ctx, *result.Address, lat, lng)
				}
			}
		}
	}

	// 8. Local Cache 저장 (원본 카테고리 텍스트 저장)
	if result.Address != nil && result.Lat != nil && result.Lng != nil {
		_ = s.DB.PutLocalCache(ctx, campaign.Title, *result.Address, *result.Lat, *result.Lng, categoryTextForCache)
	}

	return result
}

// campaignKey 캠페인 고유 키 생성
func campaignKey(c *models.Campaign) string {
	return c.Platform + "|" + c.Title + "|" + c.Offer + "|" + c.CampaignChannel
}

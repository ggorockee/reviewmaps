package services

import (
	"fmt"
	"time"

	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
)

type CampaignService struct {
	db *database.DB
}

func NewCampaignService(db *database.DB) *CampaignService {
	return &CampaignService{db: db}
}

type CampaignFilter struct {
	Page       int
	Limit      int
	Offset     int    // 모바일 앱 호환성
	CategoryID uint
	Platform   string
	Region     string
	Lat        float64
	Lng        float64
	Sort       string // 정렬 기준: -created_at, distance 등
	Query      string // 검색어 (q 파라미터)
	// Bounding box 파라미터 (지도 뷰포트)
	SwLat float64
	SwLng float64
	NeLat float64
	NeLng float64
}

type CampaignListResponse struct {
	Items      []models.Campaign `json:"items"`
	Total      int64             `json:"total"`
	Page       int               `json:"page"`
	Limit      int               `json:"limit"`
	TotalPages int               `json:"total_pages"`
}

// List retrieves campaigns with filtering and pagination
func (s *CampaignService) List(filter *CampaignFilter) (*CampaignListResponse, error) {
	var campaigns []models.Campaign
	var total int64

	query := s.db.Model(&models.Campaign{}).
		Preload("Category").
		Where("apply_deadline > ?", time.Now())

	// Apply filters
	if filter.CategoryID > 0 {
		query = query.Where("category_id = ?", filter.CategoryID)
	}
	if filter.Platform != "" {
		query = query.Where("platform = ?", filter.Platform)
	}
	if filter.Region != "" {
		query = query.Where("region = ?", filter.Region)
	}

	// 검색어 필터 (q 파라미터)
	if filter.Query != "" {
		searchTerm := "%" + filter.Query + "%"
		query = query.Where("title ILIKE ? OR company ILIKE ? OR search_text ILIKE ?",
			searchTerm, searchTerm, searchTerm)
	}

	// Bounding box 필터 (지도 뷰포트)
	if filter.SwLat != 0 && filter.SwLng != 0 && filter.NeLat != 0 && filter.NeLng != 0 {
		query = query.Where("lat >= ? AND lat <= ? AND lng >= ? AND lng <= ?",
			filter.SwLat, filter.NeLat, filter.SwLng, filter.NeLng)
	}

	// Count total
	query.Count(&total)

	// 정렬 처리 (원본 Django 로직과 동일)
	// 1순위: promotion_level 내림차순 (NULL은 0으로 처리)
	// 2순위: pseudo_random (id % 1000) - 동일 레벨 내 균형 분포
	// 3순위: 사용자 지정 정렬 또는 created_at

	switch filter.Sort {
	case "distance":
		// 거리순 정렬 (Haversine 공식 사용)
		if filter.Lat != 0 && filter.Lng != 0 {
			// Haversine 공식: 2 * 6371 * asin(sqrt(sin^2((lat2-lat1)/2) + cos(lat1)*cos(lat2)*sin^2((lng2-lng1)/2)))
			haversineExpr := fmt.Sprintf(`
				CASE WHEN lat IS NULL OR lng IS NULL THEN 999999
				ELSE 2 * 6371 * asin(sqrt(
					power(sin(radians(lat - %f) / 2), 2) +
					cos(radians(%f)) * cos(radians(lat)) * power(sin(radians(lng - %f) / 2), 2)
				))
				END`,
				filter.Lat, filter.Lat, filter.Lng)

			// 1순위: promotion_level, 2순위: distance, 3순위: pseudo_random, 4순위: created_at
			query = query.Order("COALESCE(promotion_level, 0) DESC").
				Order(haversineExpr + " ASC").
				Order("id % 1000").
				Order("created_at DESC")
		} else {
			// lat, lng 없으면 기본 정렬
			query = query.Order("COALESCE(promotion_level, 0) DESC").
				Order("id % 1000").
				Order("created_at DESC")
		}
	case "created_at":
		// 1순위: promotion_level, 2순위: pseudo_random, 3순위: created_at ASC
		query = query.Order("COALESCE(promotion_level, 0) DESC").
			Order("id % 1000").
			Order("created_at ASC")
	case "-created_at":
		// 1순위: promotion_level, 2순위: pseudo_random, 3순위: created_at DESC
		query = query.Order("COALESCE(promotion_level, 0) DESC").
			Order("id % 1000").
			Order("created_at DESC")
	default:
		// 기본: 1순위 promotion_level, 2순위 pseudo_random, 3순위 created_at DESC
		query = query.Order("COALESCE(promotion_level, 0) DESC").
			Order("id % 1000").
			Order("created_at DESC")
	}

	// Pagination - offset 우선, 없으면 page 기반
	var offset int
	if filter.Offset > 0 {
		offset = filter.Offset
	} else {
		offset = (filter.Page - 1) * filter.Limit
	}
	query = query.Offset(offset).Limit(filter.Limit)

	if err := query.Find(&campaigns).Error; err != nil {
		return nil, err
	}

	totalPages := int(total) / filter.Limit
	if int(total)%filter.Limit > 0 {
		totalPages++
	}

	return &CampaignListResponse{
		Items:      campaigns,
		Total:      total,
		Page:       filter.Page,
		Limit:      filter.Limit,
		TotalPages: totalPages,
	}, nil
}

// GetByID retrieves a campaign by ID with relations
func (s *CampaignService) GetByID(id uint) (*models.Campaign, error) {
	var campaign models.Campaign
	err := s.db.Preload("Category").First(&campaign, id).Error
	if err != nil {
		return nil, err
	}
	return &campaign, nil
}

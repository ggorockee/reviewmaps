package services

import (
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
	CategoryID uint
	Platform   string
	Region     string
	Lat        float64
	Lng        float64
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

	// Count total
	query.Count(&total)

	// Order by promotion_level DESC, created_at DESC
	query = query.Order("promotion_level DESC, created_at DESC")

	// Pagination
	offset := (filter.Page - 1) * filter.Limit
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

package services

import (
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
)

type CategoryService struct {
	db *database.DB
}

func NewCategoryService(db *database.DB) *CategoryService {
	return &CategoryService{db: db}
}

// List retrieves all categories ordered by display_order
// Note: Django model doesn't have is_active field
func (s *CategoryService) List() ([]models.Category, error) {
	var categories []models.Category
	err := s.db.Order("display_order ASC, id ASC").Find(&categories).Error
	if err != nil {
		return nil, err
	}
	return categories, nil
}

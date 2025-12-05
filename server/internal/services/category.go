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

// List retrieves all active categories
func (s *CategoryService) List() ([]models.Category, error) {
	var categories []models.Category
	err := s.db.Where("is_active = ?", true).Order("sort_order ASC").Find(&categories).Error
	if err != nil {
		return nil, err
	}
	return categories, nil
}

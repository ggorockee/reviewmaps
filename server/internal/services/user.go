package services

import (
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
)

type UserService struct {
	db *database.DB
}

func NewUserService(db *database.DB) *UserService {
	return &UserService{db: db}
}

type UpdateUserRequest struct {
	Name         *string `json:"name,omitempty"`
	ProfileImage *string `json:"profile_image,omitempty"`
}

// GetByID retrieves a user by ID with relations
func (s *UserService) GetByID(id uint) (*models.User, error) {
	var user models.User
	err := s.db.Preload("SocialAccounts").Preload("FCMDevices").First(&user, id).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

// Update updates user information
func (s *UserService) Update(id uint, req *UpdateUserRequest) (*models.User, error) {
	var user models.User
	if err := s.db.First(&user, id).Error; err != nil {
		return nil, err
	}

	if req.Name != nil {
		user.Name = req.Name
	}
	if req.ProfileImage != nil {
		user.ProfileImage = req.ProfileImage
	}

	if err := s.db.Save(&user).Error; err != nil {
		return nil, err
	}

	return &user, nil
}

// Delete soft deletes a user
func (s *UserService) Delete(id uint) error {
	return s.db.Delete(&models.User{}, id).Error
}

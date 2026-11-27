package services

import (
	"gorm.io/gorm"

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
		user.Name = *req.Name
	}
	if req.ProfileImage != nil {
		user.ProfileImage = *req.ProfileImage
	}

	if err := s.db.Save(&user).Error; err != nil {
		return nil, err
	}

	return &user, nil
}

// Delete soft deletes a user
// Delete 회원 탈퇴 (앱 탈퇴와 관리자 삭제가 같이 사용)
//
// 운영 DB의 users 외래 키는 모두 ON DELETE NO ACTION(Django 시절 생성)이라
// 연결된 행을 먼저 지우지 않으면 users 삭제가 실패한다. 한 트랜잭션에서
// 키워드 알림 → 키워드 → FCM 기기 → SNS 계정 → (Django 권한 연결) → 사용자 순으로 지운다.
func (s *UserService) Delete(id uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var user models.User
		if err := tx.Select("id").Take(&user, id).Error; err != nil {
			return err
		}
		keywordIDs := tx.Model(&models.Keyword{}).Select("id").Where("user_id = ?", id)
		if err := tx.Unscoped().Where("keyword_id IN (?)", keywordIDs).Delete(&models.KeywordAlert{}).Error; err != nil {
			return err
		}
		for _, m := range []interface{}{&models.Keyword{}, &models.FCMDevice{}, &models.SocialAccount{}} {
			if err := tx.Where("user_id = ?", id).Delete(m).Error; err != nil {
				return err
			}
		}
		// Django 관리자 시절 테이블 (Phase 7에서 삭제 예정). 없으면 건너뜀
		for _, t := range []string{"users_groups", "users_user_permissions"} {
			if tx.Migrator().HasTable(t) {
				if err := tx.Exec("DELETE FROM "+t+" WHERE user_id = ?", id).Error; err != nil {
					return err
				}
			}
		}
		return tx.Delete(&models.User{}, id).Error
	})
}

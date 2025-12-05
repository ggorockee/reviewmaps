package database

import (
	"github.com/ggorockee/reviewmaps/server/internal/config"
	"github.com/ggorockee/reviewmaps/server/internal/models"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

type DB struct {
	*gorm.DB
}

func Connect(cfg *config.Config) (*DB, error) {
	logLevel := logger.Silent
	if cfg.ServerEnv == "development" {
		logLevel = logger.Info
	}

	db, err := gorm.Open(postgres.Open(cfg.DatabaseURL), &gorm.Config{
		Logger: logger.Default.LogMode(logLevel),
	})
	if err != nil {
		return nil, err
	}

	return &DB{db}, nil
}

func Migrate(db *DB) error {
	return db.AutoMigrate(
		// User domain
		&models.User{},
		&models.SocialAccount{},
		&models.EmailVerification{},

		// Campaign domain
		&models.Category{},
		&models.Campaign{},
		&models.RawCategory{},
		&models.CategoryMapping{},

		// Keyword alert domain
		&models.FCMDevice{},
		&models.Keyword{},
		&models.KeywordAlert{},

		// App config domain
		&models.AdConfig{},
		&models.AppVersion{},
		&models.AppSetting{},
		&models.RateLimitConfig{},

		// Cache
		&models.GeocodeCache{},
		&models.LocalSearchCache{},
	)
}

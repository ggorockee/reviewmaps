package models

import (
	"time"
)

// GeocodeCache represents geocoding cache
type GeocodeCache struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Address   string    `gorm:"size:500;not null;uniqueIndex" json:"address"`
	Lat       float64   `gorm:"type:decimal(9,6);not null" json:"lat"`
	Lng       float64   `gorm:"type:decimal(9,6);not null" json:"lng"`
	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	ExpiresAt time.Time `gorm:"not null" json:"expires_at"`
}

func (GeocodeCache) TableName() string {
	return "geocode_cache"
}

// LocalSearchCache represents local search cache
type LocalSearchCache struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Query     string    `gorm:"size:500;not null;index" json:"query"`
	Result    string    `gorm:"type:text;not null" json:"result"`
	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
	ExpiresAt time.Time `gorm:"not null" json:"expires_at"`
}

func (LocalSearchCache) TableName() string {
	return "local_search_cache"
}

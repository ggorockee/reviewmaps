package models

import (
	"time"
)

// GeocodeCache represents geocoding cache
// DB: geocode_cache (hash is PK, not id)
type GeocodeCache struct {
	Hash      string    `gorm:"column:hash;size:64;primaryKey" json:"hash"`
	Address   string    `gorm:"column:address;size:500;not null" json:"address"`
	Lat       float64   `gorm:"column:lat;type:double precision;not null" json:"lat"`
	Lng       float64   `gorm:"column:lng;type:double precision;not null" json:"lng"`
	CreatedAt time.Time `gorm:"column:created_at;not null" json:"created_at"`
	ExpiresAt time.Time `gorm:"column:expires_at;not null" json:"expires_at"`
}

func (GeocodeCache) TableName() string {
	return "geocode_cache"
}

// LocalSearchCache represents local search cache
// DB: local_search_cache (hash is PK, not id)
type LocalSearchCache struct {
	Hash      string    `gorm:"column:hash;size:64;primaryKey" json:"hash"`
	Query     string    `gorm:"column:query;size:500;not null" json:"query"`
	Result    string    `gorm:"column:result;type:text;not null" json:"result"`
	CreatedAt time.Time `gorm:"column:created_at;not null" json:"created_at"`
	ExpiresAt time.Time `gorm:"column:expires_at;not null" json:"expires_at"`
}

func (LocalSearchCache) TableName() string {
	return "local_search_cache"
}

package models

import (
	"time"
)

// Category represents campaign categories
// Note: Field names match Django model for DB compatibility
type Category struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Name         string    `gorm:"size:100;not null;uniqueIndex" json:"name"`
	DisplayOrder int       `gorm:"column:display_order;default:99" json:"display_order"`
	CreatedAt    time.Time `gorm:"autoCreateTime" json:"created_at"`

	// Relations
	Campaigns []Campaign `gorm:"foreignKey:CategoryID" json:"campaigns,omitempty"`
}

func (Category) TableName() string {
	return "categories"
}

// Campaign represents campaign data
type Campaign struct {
	ID              uint       `gorm:"primaryKey" json:"id"`
	CategoryID      *uint      `gorm:"index:idx_cpg_category" json:"category_id,omitempty"`
	Platform        string     `gorm:"size:20;not null" json:"platform"`
	Company         string     `gorm:"size:255;not null" json:"company"`
	CompanyLink     *string    `gorm:"type:text" json:"company_link,omitempty"`
	Offer           string     `gorm:"type:text;not null" json:"offer"`
	ApplyDeadline   *time.Time `gorm:"index:idx_cpg_deadline" json:"apply_deadline,omitempty"`
	ReviewDeadline  *time.Time `json:"review_deadline,omitempty"`
	ApplyFrom       *time.Time `json:"apply_from,omitempty"`
	Address         *string    `gorm:"type:text" json:"address,omitempty"`
	Lat             *float64   `gorm:"type:decimal(9,6)" json:"lat,omitempty"`
	Lng             *float64   `gorm:"type:decimal(9,6)" json:"lng,omitempty"`
	ImgURL          *string    `gorm:"type:text" json:"img_url,omitempty"`
	ContentLink     *string    `gorm:"type:text" json:"content_link,omitempty"`
	SearchText      *string    `gorm:"size:20" json:"search_text,omitempty"`
	Source          *string    `gorm:"size:100" json:"source,omitempty"`
	Title           *string    `gorm:"type:text" json:"title,omitempty"`
	CampaignType    *string    `gorm:"size:50;index:idx_cpg_type" json:"campaign_type,omitempty"`
	Region          *string    `gorm:"size:100;index:idx_cpg_region" json:"region,omitempty"`
	CampaignChannel *string    `gorm:"size:255" json:"campaign_channel,omitempty"`
	PromotionLevel  int        `gorm:"default:0" json:"promotion_level"`
	CreatedAt       time.Time  `gorm:"autoCreateTime;index:idx_cpg_created,sort:desc" json:"created_at"`
	UpdatedAt       time.Time  `gorm:"autoUpdateTime" json:"updated_at"`

	// Relations
	Category *Category `gorm:"foreignKey:CategoryID" json:"category,omitempty"`
}

func (Campaign) TableName() string {
	return "campaign"
}

// RawCategory represents original categories from sources
type RawCategory struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Name      string    `gorm:"size:255;not null" json:"name"`
	Source    string    `gorm:"size:100;not null" json:"source"`
	CreatedAt time.Time `gorm:"autoCreateTime" json:"created_at"`
}

func (RawCategory) TableName() string {
	return "raw_categories"
}

// CategoryMapping maps raw categories to standard categories
type CategoryMapping struct {
	ID            uint      `gorm:"primaryKey" json:"id"`
	RawCategoryID uint      `gorm:"not null;uniqueIndex:idx_catmap_raw_cat" json:"raw_category_id"`
	CategoryID    uint      `gorm:"not null;uniqueIndex:idx_catmap_raw_cat" json:"category_id"`
	CreatedAt     time.Time `gorm:"autoCreateTime" json:"created_at"`

	// Relations
	RawCategory RawCategory `gorm:"foreignKey:RawCategoryID" json:"raw_category,omitempty"`
	Category    Category    `gorm:"foreignKey:CategoryID" json:"category,omitempty"`
}

func (CategoryMapping) TableName() string {
	return "category_mappings"
}

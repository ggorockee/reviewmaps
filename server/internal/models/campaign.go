package models

import (
	"time"

	"gorm.io/gorm"
)

// Category represents campaign categories
// DB: categories
type Category struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Name         string    `gorm:"column:name;size:100;not null;uniqueIndex:categories_name_key" json:"name"`
	DisplayOrder int       `gorm:"column:display_order;not null;default:99" json:"display_order"`
	CreatedAt    time.Time `gorm:"column:created_at;not null" json:"created_at"`

	// Relations
	Campaigns []Campaign `gorm:"foreignKey:CategoryID" json:"campaigns,omitempty"`
}

func (Category) TableName() string {
	return "categories"
}

// Campaign represents campaign data
// DB: campaign
type Campaign struct {
	ID              uint       `gorm:"primaryKey" json:"id"`
	CategoryID      *uint      `gorm:"column:category_id;index:idx_cpg_category" json:"category_id,omitempty"`
	Platform        string     `gorm:"column:platform;size:20;not null" json:"platform"`
	Company         string     `gorm:"column:company;size:255;not null" json:"company"`
	CompanyLink     *string    `gorm:"column:company_link;type:text" json:"company_link,omitempty"`
	Offer           string     `gorm:"column:offer;type:text;not null" json:"offer"`
	ApplyDeadline   *time.Time `gorm:"column:apply_deadline;index:idx_cpg_deadline" json:"apply_deadline,omitempty"`
	ReviewDeadline  *time.Time `gorm:"column:review_deadline" json:"review_deadline,omitempty"`
	ApplyFrom       *time.Time `gorm:"column:apply_from" json:"apply_from,omitempty"`
	Address         *string    `gorm:"column:address;type:text" json:"address,omitempty"`
	Lat             *float64   `gorm:"column:lat;type:double precision" json:"lat,omitempty"`
	Lng             *float64   `gorm:"column:lng;type:double precision" json:"lng,omitempty"`
	ImgURL          *string    `gorm:"column:img_url;type:text" json:"img_url,omitempty"`
	ContentLink     *string    `gorm:"column:content_link;type:text" json:"content_link,omitempty"`
	SearchText      *string    `gorm:"column:search_text;size:20" json:"search_text,omitempty"`
	Source          *string    `gorm:"column:source;size:100" json:"source,omitempty"`
	Title           *string    `gorm:"column:title;type:text" json:"title,omitempty"`
	CampaignType    *string    `gorm:"column:campaign_type;size:50;index:idx_cpg_type" json:"campaign_type,omitempty"`
	Region          *string    `gorm:"column:region;size:100;index:idx_cpg_region" json:"region,omitempty"`
	CampaignChannel *string    `gorm:"column:campaign_channel;size:255" json:"campaign_channel,omitempty"`
	Status          *string    `gorm:"column:status;size:20;index:idx_campaign_status" json:"status,omitempty"`
	PromotionLevel  int            `gorm:"column:promotion_level;not null;default:0" json:"promotion_level"`
	CreatedAt       time.Time      `gorm:"column:created_at;not null;index:idx_cpg_created,sort:desc" json:"created_at"`
	UpdatedAt       time.Time      `gorm:"column:updated_at;not null" json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"column:deleted_at;index:idx_cpg_deleted" json:"deleted_at,omitempty"`

	// Relations
	Category *Category `gorm:"foreignKey:CategoryID" json:"category,omitempty"`
}

func (Campaign) TableName() string {
	return "campaign"
}

// RawCategory represents original categories from sources
// DB: raw_categories
type RawCategory struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	RawText   string    `gorm:"column:raw_text;type:text;not null;uniqueIndex:raw_categories_raw_text_key" json:"raw_text"`
	CreatedAt time.Time `gorm:"column:created_at;not null" json:"created_at"`
}

func (RawCategory) TableName() string {
	return "raw_categories"
}

// CategoryMapping maps raw categories to standard categories
// DB: category_mappings
type CategoryMapping struct {
	ID                 uint `gorm:"primaryKey" json:"id"`
	RawCategoryID      uint `gorm:"column:raw_category_id;not null;uniqueIndex:category_mappings_raw_category_id_key" json:"raw_category_id"`
	StandardCategoryID uint `gorm:"column:standard_category_id;not null" json:"standard_category_id"`

	// Relations
	RawCategory      RawCategory `gorm:"foreignKey:RawCategoryID" json:"raw_category,omitempty"`
	StandardCategory Category    `gorm:"foreignKey:StandardCategoryID" json:"standard_category,omitempty"`
}

func (CategoryMapping) TableName() string {
	return "category_mappings"
}

package models

import (
	"fmt"
	"time"
)

// Campaign 캠페인 데이터 모델
type Campaign struct {
	Platform        string     `json:"platform"`
	Title           string     `json:"title"`
	Offer           string     `json:"offer"`
	CampaignChannel string     `json:"campaign_channel"`
	Source          string     `json:"source"`
	Company         string     `json:"company"`
	CompanyLink     *string    `json:"company_link"`
	CategoryID      *int64     `json:"category_id"`
	ApplyFrom       *time.Time `json:"apply_from"`
	ApplyDeadline   *time.Time `json:"apply_deadline"`
	ReviewDeadline  *time.Time `json:"review_deadline"`
	SearchText      string     `json:"search_text"`
	Address         *string    `json:"address"`
	Lat             *float64   `json:"lat"`
	Lng             *float64   `json:"lng"`
	ImgURL          *string    `json:"img_url"`
	ContentLink     *string    `json:"content_link"`
	CampaignType    *string    `json:"campaign_type"`
	Region          *string    `json:"region"`
	Status          *string    `json:"status"`
}

// CampaignKey 캠페인 고유 키 (중복 체크용)
type CampaignKey struct {
	Platform        string
	Title           string
	Offer           string
	CampaignChannel string
	Address         *string
	Lat             *float64
	Lng             *float64
	CategoryID      *int64
}

// Key 캠페인 키 문자열 생성
func (c *CampaignKey) Key() string {
	return fmt.Sprintf("%s|%s|%s|%s", c.Platform, c.Title, c.Offer, c.CampaignChannel)
}

// LocalCacheEntry local_search_cache 테이블 엔트리
// Note: category는 DB에서 text 타입이지만, 내부적으로는 raw_category_id로 변환하여 사용
type LocalCacheEntry struct {
	Address      *string
	Lat          *float64
	Lng          *float64
	CategoryText *string // DB의 category 컬럼 (text 타입)
	Category     *int64  // 변환된 raw_category_id (코드 내부용)
	UpdatedAt    time.Time
}

// NaverLocalSearchResult 네이버 Local API 검색 결과
type NaverLocalSearchResult struct {
	Title       string `json:"title"`
	Link        string `json:"link"`
	Category    string `json:"category"`
	Description string `json:"description"`
	Telephone   string `json:"telephone"`
	Address     string `json:"address"`
	RoadAddress string `json:"roadAddress"`
	MapX        string `json:"mapx"`
	MapY        string `json:"mapy"`
}

// NaverLocalSearchResponse 네이버 Local API 응답
type NaverLocalSearchResponse struct {
	LastBuildDate string                   `json:"lastBuildDate"`
	Total         int                      `json:"total"`
	Start         int                      `json:"start"`
	Display       int                      `json:"display"`
	Items         []NaverLocalSearchResult `json:"items"`
}

// NaverGeocodeAddress 네이버 Geocode API 주소 결과
type NaverGeocodeAddress struct {
	RoadAddress   string `json:"roadAddress"`
	JibunAddress  string `json:"jibunAddress"`
	EnglishAddress string `json:"englishAddress"`
	X             string `json:"x"` // longitude
	Y             string `json:"y"` // latitude
}

// NaverGeocodeResponse 네이버 Geocode API 응답
type NaverGeocodeResponse struct {
	Status     string                `json:"status"`
	ErrorMessage string              `json:"errorMessage"`
	Addresses  []NaverGeocodeAddress `json:"addresses"`
}

// BaseDataTypes 기본 데이터 타입 정의 (Python과 동일)
var BaseDataTypes = map[string]string{
	"source":           "string",
	"platform":         "string",
	"company":          "string",
	"title":            "string",
	"offer":            "string",
	"campaign_channel": "string",
	"content_link":     "string",
	"company_link":     "string",
	"campaign_type":    "string",
	"region":           "string",
	"address":          "string",
	"apply_deadline":   "datetime",
	"review_deadline":  "datetime",
	"img_url":          "string",
	"apply_from":       "datetime",
	"search_text":      "string",
	"status":           "string",
}

// ResultTableColumns 최종 DB 스키마 컬럼 (Python과 동일)
var ResultTableColumns = []string{
	"platform",
	"title",
	"offer",
	"campaign_channel",
	"source",
	"company",
	"company_link",
	"category_id",
	"apply_from",
	"apply_deadline",
	"review_deadline",
	"search_text",
	"address",
	"lat",
	"lng",
	"img_url",
	"content_link",
	"campaign_type",
	"region",
	"status",
}

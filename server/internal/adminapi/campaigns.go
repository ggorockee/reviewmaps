package adminapi

import (
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"github.com/ggorockee/reviewmaps/server/internal/models"
)

// 캠페인은 go-scraper가 매일 다시 저장(DELETE 후 INSERT)하므로 내용 수정은 다음 수집 때 덮어써진다.
// 관리자는 조회, soft delete(deleted_at)·복구, 프로모션 단계만 바꾼다 (결정 D5).

type campaignDTO struct {
	ID             uint       `json:"id"`
	Platform       string     `json:"platform"`
	Source         *string    `json:"source,omitempty"`
	Company        string     `json:"company"`
	Title          *string    `json:"title,omitempty"`
	Offer          string     `json:"offer"`
	CategoryID     *uint      `json:"category_id,omitempty"`
	CategoryName   string     `json:"category_name,omitempty"`
	CampaignType   *string    `json:"campaign_type,omitempty"`
	Channel        *string    `json:"campaign_channel,omitempty"`
	Region         *string    `json:"region,omitempty"`
	Address        *string    `json:"address,omitempty"`
	ApplyDeadline  *time.Time `json:"apply_deadline,omitempty"`
	ContentLink    *string    `json:"content_link,omitempty"`
	ImgURL         *string    `json:"img_url,omitempty"`
	Status         *string    `json:"status,omitempty"`
	PromotionLevel int        `json:"promotion_level"`
	CreatedAt      time.Time  `json:"created_at"`
	DeletedAt      *time.Time `json:"deleted_at,omitempty"`
}

func toCampaignDTO(m models.Campaign) campaignDTO {
	d := campaignDTO{ID: m.ID, Platform: m.Platform, Source: m.Source, Company: m.Company, Title: m.Title,
		Offer: m.Offer, CategoryID: m.CategoryID, CampaignType: m.CampaignType, Channel: m.CampaignChannel,
		Region: m.Region, Address: m.Address, ApplyDeadline: m.ApplyDeadline, ContentLink: m.ContentLink,
		ImgURL: m.ImgURL, Status: m.Status, PromotionLevel: m.PromotionLevel, CreatedAt: m.CreatedAt}
	if m.Category != nil {
		d.CategoryName = m.Category.Name
	}
	if m.DeletedAt.Valid {
		t := m.DeletedAt.Time
		d.DeletedAt = &t
	}
	return d
}

// listCampaigns ?q=&platform=&source=&category_id=(0이면 카테고리 없음)&deleted=only|include
func (h *handlers) listCampaigns(c *fiber.Ctx) error {
	pageNo, size, offset := paging(c)
	q := h.db.Model(&models.Campaign{})
	switch c.Query("deleted") {
	case "include":
		q = q.Unscoped()
	case "only":
		q = q.Unscoped().Where("deleted_at IS NOT NULL")
	}
	if s := c.Query("q"); s != "" {
		p := like(s)
		q = q.Where(ilike("company")+" OR "+ilike("COALESCE(title, '')")+" OR "+ilike("offer"), p, p, p)
	}
	if p := c.Query("platform"); p != "" {
		q = q.Where("platform = ?", p)
	}
	if s := c.Query("source"); s != "" {
		q = q.Where("source = ?", s)
	}
	if v := c.Query("category_id"); v != "" {
		if v == "0" {
			q = q.Where("category_id IS NULL")
		} else {
			q = q.Where("category_id = ?", v)
		}
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return notFoundOr(err, "campaigns")
	}
	var rows []models.Campaign
	if err := q.Preload("Category").Order("created_at DESC, id DESC").Limit(size).Offset(offset).Find(&rows).Error; err != nil {
		return notFoundOr(err, "campaigns")
	}
	items := make([]campaignDTO, len(rows))
	for i, m := range rows {
		items[i] = toCampaignDTO(m)
	}
	return c.JSON(page[campaignDTO]{Items: items, Total: total, Page: pageNo, Size: size})
}

func (h *handlers) getCampaign(c *fiber.Ctx) error {
	id, err := idParam(c)
	if err != nil {
		return err
	}
	var m models.Campaign
	if err := h.db.Unscoped().Preload("Category").Take(&m, id).Error; err != nil {
		return notFoundOr(err, "campaign")
	}
	return c.JSON(toCampaignDTO(m))
}

func (h *handlers) updateCampaign(c *fiber.Ctx) error {
	id, err := idParam(c)
	if err != nil {
		return err
	}
	var req struct {
		PromotionLevel *int `json:"promotion_level"`
	}
	if err := c.BodyParser(&req); err != nil || req.PromotionLevel == nil {
		return fiber.NewError(fiber.StatusBadRequest, "promotion_level is required")
	}
	if *req.PromotionLevel < 0 || *req.PromotionLevel > 10 {
		return fiber.NewError(fiber.StatusBadRequest, "promotion_level must be 0..10")
	}
	err = h.db.Transaction(func(tx *gorm.DB) error {
		var m models.Campaign
		if err := tx.Unscoped().Take(&m, id).Error; err != nil {
			return err
		}
		if err := tx.Unscoped().Model(&models.Campaign{}).Where("id = ?", id).
			Update("promotion_level", *req.PromotionLevel).Error; err != nil {
			return err
		}
		return h.audit(tx, c, "campaign", "update", strconv.Itoa(int(id)),
			fiber.Map{"company": m.Company, "promotion_level": m.PromotionLevel},
			fiber.Map{"company": m.Company, "promotion_level": *req.PromotionLevel})
	})
	if err != nil {
		return notFoundOr(err, "campaign")
	}
	return c.JSON(fiber.Map{"id": id, "promotion_level": *req.PromotionLevel})
}

// deleteCampaign soft delete (앱·키워드 알림 매칭에서 빠짐)
func (h *handlers) deleteCampaign(c *fiber.Ctx) error {
	return h.setCampaignDeleted(c, true)
}

func (h *handlers) restoreCampaign(c *fiber.Ctx) error {
	return h.setCampaignDeleted(c, false)
}

func (h *handlers) setCampaignDeleted(c *fiber.Ctx, deleted bool) error {
	id, err := idParam(c)
	if err != nil {
		return err
	}
	action := "restore"
	var value any
	if deleted {
		action = "delete"
		value = time.Now()
	}
	err = h.db.Transaction(func(tx *gorm.DB) error {
		var m models.Campaign
		if err := tx.Unscoped().Take(&m, id).Error; err != nil {
			return err
		}
		if err := tx.Unscoped().Model(&models.Campaign{}).Where("id = ?", id).Update("deleted_at", value).Error; err != nil {
			return err
		}
		return h.audit(tx, c, "campaign", action, strconv.Itoa(int(id)),
			fiber.Map{"company": m.Company, "platform": m.Platform, "deleted": m.DeletedAt.Valid},
			fiber.Map{"company": m.Company, "platform": m.Platform, "deleted": deleted})
	})
	if err != nil {
		return notFoundOr(err, "campaign")
	}
	return c.SendStatus(fiber.StatusNoContent)
}

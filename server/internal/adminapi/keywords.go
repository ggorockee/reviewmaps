package adminapi

import (
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"github.com/ggorockee/reviewmaps/server/internal/models"
)

type keywordDTO struct {
	ID         uint      `json:"id"`
	Keyword    string    `json:"keyword"`
	UserID     *uint     `json:"user_id,omitempty"`
	UserEmail  string    `json:"user_email,omitempty"`
	Anonymous  bool      `json:"anonymous"`
	IsActive   bool      `json:"is_active"`
	AlertCount int64     `json:"alert_count"`
	CreatedAt  time.Time `json:"created_at"`
}

func (h *handlers) listKeywords(c *fiber.Ctx) error {
	pageNo, size, offset := paging(c)
	q := h.db.Model(&models.Keyword{})
	if s := c.Query("q"); s != "" {
		q = q.Where(ilike("keyword"), like(s))
	}
	if uid := c.QueryInt("user_id", 0); uid > 0 {
		q = q.Where("user_id = ?", uid)
	}
	if a := c.Query("is_active"); a != "" {
		q = q.Where("is_active = ?", a == "true")
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return notFoundOr(err, "keywords")
	}
	var rows []models.Keyword
	if err := q.Order("created_at DESC, id DESC").Limit(size).Offset(offset).Find(&rows).Error; err != nil {
		return notFoundOr(err, "keywords")
	}
	items, err := h.keywordDTOs(rows)
	if err != nil {
		return notFoundOr(err, "keywords")
	}
	return c.JSON(page[keywordDTO]{Items: items, Total: total, Page: pageNo, Size: size})
}

func (h *handlers) keywordDTOs(rows []models.Keyword) ([]keywordDTO, error) {
	userIDs, kwIDs := []uint{}, []uint{}
	for _, k := range rows {
		kwIDs = append(kwIDs, k.ID)
		if k.UserID != nil {
			userIDs = append(userIDs, *k.UserID)
		}
	}
	emails := map[uint]string{}
	if len(userIDs) > 0 {
		var users []models.User
		if err := h.db.Select("id", "email").Where("id IN ?", userIDs).Find(&users).Error; err != nil {
			return nil, err
		}
		for _, u := range users {
			emails[u.ID] = u.Email
		}
	}
	counts := map[uint]int64{}
	if len(kwIDs) > 0 {
		var cs []struct {
			KeywordID uint
			N         int64
		}
		if err := h.db.Model(&models.KeywordAlert{}).Select("keyword_id, COUNT(*) AS n").
			Where("keyword_id IN ?", kwIDs).Group("keyword_id").Scan(&cs).Error; err != nil {
			return nil, err
		}
		for _, x := range cs {
			counts[x.KeywordID] = x.N
		}
	}
	items := make([]keywordDTO, len(rows))
	for i, k := range rows {
		d := keywordDTO{ID: k.ID, Keyword: k.Keyword, UserID: k.UserID, Anonymous: k.UserID == nil,
			IsActive: k.IsActive, AlertCount: counts[k.ID], CreatedAt: k.CreatedAt}
		if k.UserID != nil {
			d.UserEmail = emails[*k.UserID]
		}
		items[i] = d
	}
	return items, nil
}

func (h *handlers) updateKeyword(c *fiber.Ctx) error {
	id, err := idParam(c)
	if err != nil {
		return err
	}
	var req struct {
		IsActive *bool `json:"is_active"`
	}
	if err := c.BodyParser(&req); err != nil || req.IsActive == nil {
		return fiber.NewError(fiber.StatusBadRequest, "is_active is required")
	}
	err = h.db.Transaction(func(tx *gorm.DB) error {
		var k models.Keyword
		if err := tx.Take(&k, id).Error; err != nil {
			return err
		}
		before := fiber.Map{"keyword": k.Keyword, "is_active": k.IsActive}
		if err := tx.Model(&models.Keyword{}).Where("id = ?", id).Update("is_active", *req.IsActive).Error; err != nil {
			return err
		}
		return h.audit(tx, c, "keyword", "update", strconv.Itoa(int(id)), before,
			fiber.Map{"keyword": k.Keyword, "is_active": *req.IsActive})
	})
	if err != nil {
		return notFoundOr(err, "keyword")
	}
	return c.JSON(fiber.Map{"id": id, "is_active": *req.IsActive})
}

// deleteKeyword 앱의 키워드 삭제와 같은 규칙: 알림을 완전히 지운 뒤 키워드 삭제
func (h *handlers) deleteKeyword(c *fiber.Ctx) error {
	id, err := idParam(c)
	if err != nil {
		return err
	}
	err = h.db.Transaction(func(tx *gorm.DB) error {
		var k models.Keyword
		if err := tx.Take(&k, id).Error; err != nil {
			return err
		}
		if err := tx.Unscoped().Where("keyword_id = ?", id).Delete(&models.KeywordAlert{}).Error; err != nil {
			return err
		}
		if err := tx.Delete(&models.Keyword{}, id).Error; err != nil {
			return err
		}
		return h.audit(tx, c, "keyword", "delete", strconv.Itoa(int(id)),
			fiber.Map{"keyword": k.Keyword, "user_id": k.UserID, "is_active": k.IsActive}, nil)
	})
	if err != nil {
		return notFoundOr(err, "keyword")
	}
	return c.SendStatus(fiber.StatusNoContent)
}

type alertDTO struct {
	ID            uint      `json:"id"`
	KeywordID     uint      `json:"keyword_id"`
	Keyword       string    `json:"keyword"`
	CampaignID    *uint     `json:"campaign_id,omitempty"`
	CampaignTitle string    `json:"campaign_title,omitempty"`
	MatchedField  string    `json:"matched_field"`
	IsRead        bool      `json:"is_read"`
	CreatedAt     time.Time `json:"created_at"`
}

// alertFilter: keyword_id, is_read, before(YYYY-MM-DD, KST 0시 이전), after
func alertFilter(c *fiber.Ctx, q *gorm.DB) (*gorm.DB, error) {
	if kid := c.QueryInt("keyword_id", 0); kid > 0 {
		q = q.Where("keyword_id = ?", kid)
	}
	if r := c.Query("is_read"); r != "" {
		q = q.Where("is_read = ?", r == "true")
	}
	for param, op := range map[string]string{"before": "<", "after": ">="} {
		if v := c.Query(param); v != "" {
			t, err := parseKSTDate(v)
			if err != nil {
				return nil, fiber.NewError(fiber.StatusBadRequest, param+" must be YYYY-MM-DD")
			}
			q = q.Where("created_at "+op+" ?", t)
		}
	}
	return q, nil
}

func parseKSTDate(v string) (time.Time, error) {
	return time.ParseInLocation("2006-01-02", v, time.FixedZone("KST", 9*60*60))
}

func (h *handlers) listAlerts(c *fiber.Ctx) error {
	pageNo, size, offset := paging(c)
	q, err := alertFilter(c, h.db.Model(&models.KeywordAlert{}))
	if err != nil {
		return err
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return notFoundOr(err, "alerts")
	}
	var rows []models.KeywordAlert
	if err := q.Preload("Keyword").Preload("Campaign", func(db *gorm.DB) *gorm.DB { return db.Unscoped() }).
		Order("created_at DESC, id DESC").Limit(size).Offset(offset).Find(&rows).Error; err != nil {
		return notFoundOr(err, "alerts")
	}
	items := make([]alertDTO, len(rows))
	for i, a := range rows {
		d := alertDTO{ID: a.ID, KeywordID: a.KeywordID, Keyword: a.Keyword.Keyword, CampaignID: a.CampaignID,
			MatchedField: a.MatchedField, IsRead: a.IsRead, CreatedAt: a.CreatedAt}
		if a.Campaign != nil {
			d.CampaignTitle = a.Campaign.Company
			if a.Campaign.Title != nil && *a.Campaign.Title != "" {
				d.CampaignTitle = *a.Campaign.Title
			}
		}
		items[i] = d
	}
	return c.JSON(page[alertDTO]{Items: items, Total: total, Page: pageNo, Size: size})
}

// bulkDeleteAlerts 키워드 알림 일괄 정리 (soft delete: 스크래퍼가 같은 알림을 다시 만들지 않도록 deleted_at만 채움)
// before(날짜)는 필수. dry_run=true면 지울 건수만 돌려준다.
func (h *handlers) bulkDeleteAlerts(c *fiber.Ctx) error {
	var req struct {
		Before    string `json:"before"`
		IsRead    *bool  `json:"is_read"`
		KeywordID uint   `json:"keyword_id"`
		DryRun    bool   `json:"dry_run"`
	}
	if err := c.BodyParser(&req); err != nil || req.Before == "" {
		return fiber.NewError(fiber.StatusBadRequest, "before (YYYY-MM-DD) is required")
	}
	before, err := parseKSTDate(req.Before)
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "before must be YYYY-MM-DD")
	}
	scope := func(db *gorm.DB) *gorm.DB {
		q := db.Model(&models.KeywordAlert{}).Where("created_at < ?", before)
		if req.IsRead != nil {
			q = q.Where("is_read = ?", *req.IsRead)
		}
		if req.KeywordID > 0 {
			q = q.Where("keyword_id = ?", req.KeywordID)
		}
		return q
	}
	var n int64
	if err := scope(h.db.DB).Count(&n).Error; err != nil {
		return notFoundOr(err, "alerts")
	}
	if req.DryRun || n == 0 {
		return c.JSON(fiber.Map{"matched": n, "deleted": 0, "dry_run": req.DryRun})
	}
	var deleted int64
	err = h.db.Transaction(func(tx *gorm.DB) error {
		res := scope(tx).Delete(&models.KeywordAlert{})
		if res.Error != nil {
			return res.Error
		}
		deleted = res.RowsAffected
		cond := fiber.Map{"before": req.Before, "is_read": req.IsRead, "keyword_id": req.KeywordID, "deleted": deleted}
		return h.audit(tx, c, "keyword_alert", "bulk_delete", "", nil, cond)
	})
	if err != nil {
		return notFoundOr(err, "alerts")
	}
	return c.JSON(fiber.Map{"matched": n, "deleted": deleted, "dry_run": false})
}

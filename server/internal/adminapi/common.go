package adminapi

import (
	"encoding/json"
	"errors"
	"log"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"github.com/ggorockee/reviewmaps/server/internal/admin"
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/models"
)

type handlers struct {
	db *database.DB
}

// page is the common list response.
type page[T any] struct {
	Items []T   `json:"items"`
	Total int64 `json:"total"`
	Page  int   `json:"page"`
	Size  int   `json:"size"`
}

const (
	defaultSize = 50
	maxSize     = 200
)

// paging reads ?page=&size= (page from 1, size 1..200, default 50).
func paging(c *fiber.Ctx) (pageNo, size, offset int) {
	pageNo = c.QueryInt("page", 1)
	if pageNo < 1 {
		pageNo = 1
	}
	size = c.QueryInt("size", defaultSize)
	if size < 1 || size > maxSize {
		size = defaultSize
	}
	return pageNo, size, (pageNo - 1) * size
}

// like builds a case-insensitive contains pattern (PostgreSQL·SQLite 모두 동작하도록 LOWER 사용).
func like(q string) string {
	q = strings.ToLower(strings.TrimSpace(q))
	q = strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(q)
	return "%" + q + "%"
}

func idParam(c *fiber.Ctx) (uint, error) {
	n, err := strconv.ParseUint(c.Params("id"), 10, 64)
	if err != nil || n == 0 {
		return 0, fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	return uint(n), nil
}

func notFoundOr(err error, what string) error {
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return fiber.NewError(fiber.StatusNotFound, what+" not found")
	}
	log.Printf("[admin] %s: %v", what, err)
	return fiber.NewError(fiber.StatusServiceUnavailable, "database error")
}

// audit stores who changed what (before/after JSON) and counts the change.
// before/after에는 DTO만 넘긴다 (토큰·비밀번호·인증 코드가 들어가지 않도록).
func (h *handlers) audit(tx *gorm.DB, c *fiber.Ctx, entity, action, entityID string, before, after any) error {
	row := models.AdminAuditLog{
		AdminEmail: adminEmail(c),
		Action:     action,
		Entity:     entity,
		EntityID:   entityID,
		Before:     jsonOrNil(before),
		After:      jsonOrNil(after),
		CreatedAt:  time.Now(),
	}
	if err := tx.Create(&row).Error; err != nil {
		return err
	}
	admin.RecordChange(entity, action)
	return nil
}

func jsonOrNil(v any) *string {
	if v == nil {
		return nil
	}
	b, err := json.Marshal(v)
	if err != nil {
		return nil
	}
	s := string(b)
	return &s
}

// kstToday returns today's midnight in Asia/Seoul (운영 기준 시간대).
func kstToday(now time.Time) time.Time {
	kst := time.FixedZone("KST", 9*60*60)
	t := now.In(kst)
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, kst)
}

func (h *handlers) listAuditLogs(c *fiber.Ctx) error {
	pageNo, size, offset := paging(c)
	q := h.db.Model(&models.AdminAuditLog{})
	if e := c.Query("entity"); e != "" {
		q = q.Where("entity = ?", e)
	}
	if id := c.Query("entity_id"); id != "" {
		q = q.Where("entity_id = ?", id)
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return notFoundOr(err, "audit logs")
	}
	var rows []models.AdminAuditLog
	if err := q.Order("created_at DESC, id DESC").Limit(size).Offset(offset).Find(&rows).Error; err != nil {
		return notFoundOr(err, "audit logs")
	}
	return c.JSON(page[models.AdminAuditLog]{Items: rows, Total: total, Page: pageNo, Size: size})
}

type summary struct {
	UsersTotal          int64                  `json:"users_total"`
	UsersToday          int64                  `json:"users_today"`
	KeywordsActive      int64                  `json:"keywords_active"`
	AlertsLast7Days     int64                  `json:"alerts_last_7_days"`
	CampaignsActive     int64                  `json:"campaigns_active"`
	CampaignsDeleted    int64                  `json:"campaigns_deleted"`
	CampaignsNoCategory int64                  `json:"campaigns_no_category"`
	RawUnmapped         int64                  `json:"raw_categories_unmapped"`
	RecentChanges       []models.AdminAuditLog `json:"recent_changes"`
}

func (h *handlers) summary(c *fiber.Ctx) error {
	var s summary
	now := time.Now()
	db := h.db.DB
	steps := []error{
		db.Model(&models.User{}).Count(&s.UsersTotal).Error,
		db.Model(&models.User{}).Where("date_joined >= ?", kstToday(now)).Count(&s.UsersToday).Error,
		db.Model(&models.Keyword{}).Where("is_active = ?", true).Count(&s.KeywordsActive).Error,
		db.Model(&models.KeywordAlert{}).Where("created_at >= ?", now.AddDate(0, 0, -7)).Count(&s.AlertsLast7Days).Error,
		db.Model(&models.Campaign{}).Count(&s.CampaignsActive).Error,
		db.Unscoped().Model(&models.Campaign{}).Where("deleted_at IS NOT NULL").Count(&s.CampaignsDeleted).Error,
		db.Model(&models.Campaign{}).Where("category_id IS NULL").Count(&s.CampaignsNoCategory).Error,
		db.Model(&models.RawCategory{}).Where("id NOT IN (?)", db.Model(&models.CategoryMapping{}).Select("raw_category_id")).Count(&s.RawUnmapped).Error,
		db.Order("created_at DESC, id DESC").Limit(10).Find(&s.RecentChanges).Error,
	}
	for _, err := range steps {
		if err != nil {
			return notFoundOr(err, "summary")
		}
	}
	return c.JSON(s)
}

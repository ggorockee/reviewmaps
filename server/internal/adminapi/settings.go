package adminapi

import (
	"encoding/json"
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"github.com/ggorockee/reviewmaps/server/internal/models"
)

// settingRules: 관리자 화면에서 바꿀 수 있는 앱 설정과 허용 범위
var settingRules = map[string]struct {
	Min, Max    int
	Description string
}{
	"keyword_limit":        {1, 100, "사용자당 키워드 최대 개수"},
	"alert_retention_days": {1, 365, "키워드 알림 보관 일수"},
}

func (h *handlers) listSettings(c *fiber.Ctx) error {
	var rows []models.AppSetting
	if err := h.db.Order("key").Find(&rows).Error; err != nil {
		return notFoundOr(err, "settings")
	}
	type item struct {
		models.AppSetting
		Editable bool `json:"editable"`
		Min      int  `json:"min,omitempty"`
		Max      int  `json:"max,omitempty"`
	}
	seen := map[string]bool{}
	items := []item{}
	for _, r := range rows {
		rule, ok := settingRules[r.Key]
		items = append(items, item{AppSetting: r, Editable: ok, Min: rule.Min, Max: rule.Max})
		seen[r.Key] = true
	}
	// 아직 DB에 없는 편집 가능 설정도 보여 준다 (저장하면 생성)
	for key, rule := range settingRules {
		if !seen[key] {
			d := rule.Description
			items = append(items, item{AppSetting: models.AppSetting{Key: key, Value: json.RawMessage("null"), Description: &d, IsActive: true},
				Editable: true, Min: rule.Min, Max: rule.Max})
		}
	}
	return c.JSON(items)
}

// updateSetting PUT /settings/:key {"value": 10}
func (h *handlers) updateSetting(c *fiber.Ctx) error {
	key := c.Params("key")
	rule, ok := settingRules[key]
	if !ok {
		return fiber.NewError(fiber.StatusBadRequest, "this setting is not editable")
	}
	var req struct {
		Value *int `json:"value"`
	}
	if err := c.BodyParser(&req); err != nil || req.Value == nil {
		return fiber.NewError(fiber.StatusBadRequest, "value (integer) is required")
	}
	if *req.Value < rule.Min || *req.Value > rule.Max {
		return fiber.NewError(fiber.StatusBadRequest, key+" must be "+strconv.Itoa(rule.Min)+".."+strconv.Itoa(rule.Max))
	}
	value := json.RawMessage(strconv.Itoa(*req.Value))
	err := h.db.Transaction(func(tx *gorm.DB) error {
		var s models.AppSetting
		now := time.Now()
		var before any
		if err := tx.Where("key = ?", key).Take(&s).Error; err == nil {
			before = fiber.Map{"value": json.RawMessage(s.Value)}
			if err := tx.Model(&models.AppSetting{}).Where("id = ?", s.ID).
				Updates(map[string]any{"value": value, "updated_at": now}).Error; err != nil {
				return err
			}
		} else {
			d := rule.Description
			s = models.AppSetting{Key: key, Value: value, Description: &d, IsActive: true, CreatedAt: now, UpdatedAt: now}
			if err := tx.Create(&s).Error; err != nil {
				return err
			}
		}
		return h.audit(tx, c, "app_setting", "update", key, before, fiber.Map{"value": *req.Value})
	})
	if err != nil {
		return notFoundOr(err, "setting")
	}
	return c.JSON(fiber.Map{"key": key, "value": *req.Value})
}

// listAppVersions 읽기 전용 (결정 D4): 2.2.0부터 앱은 Firebase Remote Config로 업데이트를 안내하고,
// 이 표는 2.1.x 이하 앱의 /v1/app-config/version 응답에만 쓰인다.
func (h *handlers) listAppVersions(c *fiber.Ctx) error {
	var rows []models.AppVersion
	if err := h.db.Order("platform, updated_at DESC").Find(&rows).Error; err != nil {
		return notFoundOr(err, "app versions")
	}
	return c.JSON(fiber.Map{
		"items": rows,
		"note":  "앱 2.2.0부터 업데이트 안내는 Firebase Remote Config(reviewmap-c03f1)의 ios_/android_latest_version·min_version으로 관리합니다. 이 표는 2.1.x 이하 앱만 읽습니다.",
	})
}

// listAdConfigs 읽기 전용: 앱이 2026-11 기준 /v1/app-config/ads를 호출하지 않음 (광고 설정은 Remote Config)
func (h *handlers) listAdConfigs(c *fiber.Ctx) error {
	var rows []models.AdConfig
	if err := h.db.Order("platform, priority").Find(&rows).Error; err != nil {
		return notFoundOr(err, "ad configs")
	}
	return c.JSON(rows)
}

func (h *handlers) listRateLimits(c *fiber.Ctx) error {
	var rows []models.RateLimitConfig
	if err := h.db.Order("priority, endpoint").Find(&rows).Error; err != nil {
		return notFoundOr(err, "rate limits")
	}
	return c.JSON(rows)
}

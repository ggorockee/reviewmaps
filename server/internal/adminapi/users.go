package adminapi

import (
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"github.com/ggorockee/reviewmaps/server/internal/models"
	"github.com/ggorockee/reviewmaps/server/internal/services"
)

// ilike 대소문자 구분 없는 LIKE (PostgreSQL·SQLite 공용, 패턴은 like()로 만든다).
func ilike(col string) string { return "LOWER(" + col + ") LIKE ? ESCAPE '\\'" }

// userDTO 비밀번호 해시는 절대 넣지 않는다.
type userDTO struct {
	ID          uint       `json:"id"`
	Email       string     `json:"email"`
	Name        string     `json:"name"`
	LoginMethod string     `json:"login_method"`
	IsActive    bool       `json:"is_active"`
	IsStaff     bool       `json:"is_staff"`
	DateJoined  time.Time  `json:"date_joined"`
	LastLogin   *time.Time `json:"last_login,omitempty"`
}

func toUserDTO(u models.User) userDTO {
	return userDTO{ID: u.ID, Email: u.Email, Name: u.Name, LoginMethod: u.LoginMethod, IsActive: u.IsActive,
		IsStaff: u.IsStaff, DateJoined: u.DateJoined, LastLogin: u.LastLogin}
}

// socialDTO 접근·갱신 토큰은 절대 넣지 않는다.
type socialDTO struct {
	Provider  string    `json:"provider"`
	Email     *string   `json:"email,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

// deviceDTO FCM 토큰은 앞 8자만 보여 준다.
type deviceDTO struct {
	ID         uint      `json:"id"`
	UserID     *uint     `json:"user_id,omitempty"`
	DeviceType string    `json:"device_type"`
	TokenHint  string    `json:"token_hint"`
	IsActive   bool      `json:"is_active"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

func toDeviceDTO(d models.FCMDevice) deviceDTO {
	hint := d.FCMToken
	if len(hint) > 8 {
		hint = hint[:8] + "…"
	}
	return deviceDTO{ID: d.ID, UserID: d.UserID, DeviceType: d.DeviceType, TokenHint: hint, IsActive: d.IsActive,
		CreatedAt: d.CreatedAt, UpdatedAt: d.UpdatedAt}
}

type keywordBrief struct {
	ID        uint      `json:"id"`
	Keyword   string    `json:"keyword"`
	IsActive  bool      `json:"is_active"`
	CreatedAt time.Time `json:"created_at"`
}

type userDetail struct {
	userDTO
	SocialAccounts []socialDTO    `json:"social_accounts"`
	Keywords       []keywordBrief `json:"keywords"`
	Devices        []deviceDTO    `json:"devices"`
}

func (h *handlers) listUsers(c *fiber.Ctx) error {
	pageNo, size, offset := paging(c)
	q := h.db.Model(&models.User{})
	if s := c.Query("q"); s != "" {
		p := like(s)
		q = q.Where(ilike("email")+" OR "+ilike("name"), p, p)
	}
	if m := c.Query("login_method"); m != "" {
		q = q.Where("login_method = ?", m)
	}
	if a := c.Query("is_active"); a != "" {
		q = q.Where("is_active = ?", a == "true")
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return notFoundOr(err, "users")
	}
	var rows []models.User
	if err := q.Order("date_joined DESC, id DESC").Limit(size).Offset(offset).Find(&rows).Error; err != nil {
		return notFoundOr(err, "users")
	}
	items := make([]userDTO, len(rows))
	for i, u := range rows {
		items[i] = toUserDTO(u)
	}
	return c.JSON(page[userDTO]{Items: items, Total: total, Page: pageNo, Size: size})
}

func (h *handlers) getUser(c *fiber.Ctx) error {
	id, err := idParam(c)
	if err != nil {
		return err
	}
	var u models.User
	if err := h.db.Take(&u, id).Error; err != nil {
		return notFoundOr(err, "user")
	}
	d := userDetail{userDTO: toUserDTO(u), SocialAccounts: []socialDTO{}, Keywords: []keywordBrief{}, Devices: []deviceDTO{}}
	var socials []models.SocialAccount
	h.db.Where("user_id = ?", id).Order("created_at").Find(&socials)
	for _, s := range socials {
		d.SocialAccounts = append(d.SocialAccounts, socialDTO{Provider: s.Provider, Email: s.Email, CreatedAt: s.CreatedAt})
	}
	var kws []models.Keyword
	h.db.Where("user_id = ?", id).Order("created_at DESC").Find(&kws)
	for _, k := range kws {
		d.Keywords = append(d.Keywords, keywordBrief{ID: k.ID, Keyword: k.Keyword, IsActive: k.IsActive, CreatedAt: k.CreatedAt})
	}
	var devs []models.FCMDevice
	h.db.Where("user_id = ?", id).Order("updated_at DESC").Find(&devs)
	for _, dv := range devs {
		d.Devices = append(d.Devices, toDeviceDTO(dv))
	}
	return c.JSON(d)
}

func (h *handlers) updateUser(c *fiber.Ctx) error {
	id, err := idParam(c)
	if err != nil {
		return err
	}
	var req struct {
		IsActive *bool   `json:"is_active"`
		Name     *string `json:"name"`
	}
	if err := c.BodyParser(&req); err != nil || (req.IsActive == nil && req.Name == nil) {
		return fiber.NewError(fiber.StatusBadRequest, "is_active or name is required")
	}
	var after userDTO
	err = h.db.Transaction(func(tx *gorm.DB) error {
		var u models.User
		if err := tx.Take(&u, id).Error; err != nil {
			return err
		}
		before := toUserDTO(u)
		updates := map[string]any{}
		if req.IsActive != nil {
			updates["is_active"] = *req.IsActive
			u.IsActive = *req.IsActive
		}
		if req.Name != nil {
			name := strings.TrimSpace(*req.Name)
			updates["name"] = name
			u.Name = name
		}
		if err := tx.Model(&models.User{}).Where("id = ?", id).Updates(updates).Error; err != nil {
			return err
		}
		after = toUserDTO(u)
		return h.audit(tx, c, "user", "update", strconv.Itoa(int(id)), before, after)
	})
	if err != nil {
		return notFoundOr(err, "user")
	}
	return c.JSON(after)
}

// deleteUser 회원 삭제 (앱 탈퇴와 같은 UserService.Delete: 연관 데이터를 한 트랜잭션에서 함께 삭제)
// 실수 방지를 위해 body의 confirm_email이 대상 이메일과 같아야 한다.
func (h *handlers) deleteUser(c *fiber.Ctx) error {
	id, err := idParam(c)
	if err != nil {
		return err
	}
	var req struct {
		ConfirmEmail string `json:"confirm_email"`
	}
	_ = c.BodyParser(&req)
	var u models.User
	if err := h.db.Take(&u, id).Error; err != nil {
		return notFoundOr(err, "user")
	}
	if !strings.EqualFold(strings.TrimSpace(req.ConfirmEmail), strings.TrimSpace(u.Email)) {
		return fiber.NewError(fiber.StatusBadRequest, "confirm_email does not match")
	}
	before := toUserDTO(u)
	if err := services.NewUserService(h.db).Delete(id); err != nil {
		return notFoundOr(err, "user")
	}
	if err := h.audit(h.db.DB, c, "user", "delete", strconv.Itoa(int(id)), before, nil); err != nil {
		return notFoundOr(err, "audit")
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *handlers) listFCMDevices(c *fiber.Ctx) error {
	pageNo, size, offset := paging(c)
	q := h.db.Model(&models.FCMDevice{})
	if uid := c.QueryInt("user_id", 0); uid > 0 {
		q = q.Where("user_id = ?", uid)
	}
	if t := c.Query("device_type"); t != "" {
		q = q.Where("device_type = ?", t)
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return notFoundOr(err, "devices")
	}
	var rows []models.FCMDevice
	if err := q.Order("updated_at DESC, id DESC").Limit(size).Offset(offset).Find(&rows).Error; err != nil {
		return notFoundOr(err, "devices")
	}
	items := make([]deviceDTO, len(rows))
	for i, d := range rows {
		items[i] = toDeviceDTO(d)
	}
	return c.JSON(page[deviceDTO]{Items: items, Total: total, Page: pageNo, Size: size})
}

// emailVerificationDTO 인증 코드·토큰은 절대 넣지 않는다.
type emailVerificationDTO struct {
	ID         uint       `json:"id"`
	Email      string     `json:"email"`
	IsVerified bool       `json:"is_verified"`
	ExpiresAt  time.Time  `json:"expires_at"`
	SendCount  int        `json:"send_count"`
	Attempts   int        `json:"attempts"`
	LastSentAt *time.Time `json:"last_sent_at,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`
}

func (h *handlers) listEmailVerifications(c *fiber.Ctx) error {
	pageNo, size, offset := paging(c)
	q := h.db.Model(&models.EmailVerification{})
	if s := c.Query("q"); s != "" {
		q = q.Where(ilike("email"), like(s))
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return notFoundOr(err, "email verifications")
	}
	var rows []models.EmailVerification
	if err := q.Order("created_at DESC, id DESC").Limit(size).Offset(offset).Find(&rows).Error; err != nil {
		return notFoundOr(err, "email verifications")
	}
	items := make([]emailVerificationDTO, len(rows))
	for i, e := range rows {
		items[i] = emailVerificationDTO{ID: e.ID, Email: e.Email, IsVerified: e.IsVerified, ExpiresAt: e.ExpiresAt,
			SendCount: e.SendCount, Attempts: e.Attempts, LastSentAt: e.LastSentAt, CreatedAt: e.CreatedAt}
	}
	return c.JSON(page[emailVerificationDTO]{Items: items, Total: total, Page: pageNo, Size: size})
}

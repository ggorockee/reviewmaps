package adminapi

import (
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"github.com/ggorockee/reviewmaps/server/internal/models"
)

type categoryDTO struct {
	ID            uint      `json:"id"`
	Name          string    `json:"name"`
	DisplayOrder  int       `json:"display_order"`
	MappingCount  int64     `json:"mapping_count"`
	CampaignCount int64     `json:"campaign_count"`
	CreatedAt     time.Time `json:"created_at"`
}

func (h *handlers) listCategories(c *fiber.Ctx) error {
	var cats []models.Category
	if err := h.db.Order("display_order, id").Find(&cats).Error; err != nil {
		return notFoundOr(err, "categories")
	}
	type cnt struct {
		ID uint
		N  int64
	}
	var maps, camps []cnt
	h.db.Model(&models.CategoryMapping{}).Select("standard_category_id AS id, COUNT(*) AS n").Group("standard_category_id").Scan(&maps)
	h.db.Model(&models.Campaign{}).Select("category_id AS id, COUNT(*) AS n").Where("category_id IS NOT NULL").Group("category_id").Scan(&camps)
	mc, cc := map[uint]int64{}, map[uint]int64{}
	for _, x := range maps {
		mc[x.ID] = x.N
	}
	for _, x := range camps {
		cc[x.ID] = x.N
	}
	items := make([]categoryDTO, len(cats))
	for i, k := range cats {
		items[i] = categoryDTO{ID: k.ID, Name: k.Name, DisplayOrder: k.DisplayOrder, MappingCount: mc[k.ID], CampaignCount: cc[k.ID], CreatedAt: k.CreatedAt}
	}
	return c.JSON(items)
}

func (h *handlers) createCategory(c *fiber.Ctx) error {
	var req struct {
		Name         string `json:"name"`
		DisplayOrder *int   `json:"display_order"`
	}
	if err := c.BodyParser(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		return fiber.NewError(fiber.StatusBadRequest, "name is required")
	}
	cat := models.Category{Name: strings.TrimSpace(req.Name), DisplayOrder: 99, CreatedAt: time.Now()}
	if req.DisplayOrder != nil {
		cat.DisplayOrder = *req.DisplayOrder
	}
	err := h.db.Transaction(func(tx *gorm.DB) error {
		var n int64
		tx.Model(&models.Category{}).Where("name = ?", cat.Name).Count(&n)
		if n > 0 {
			return fiber.NewError(fiber.StatusConflict, "category name already exists")
		}
		if err := tx.Create(&cat).Error; err != nil {
			return err
		}
		return h.audit(tx, c, "category", "create", strconv.Itoa(int(cat.ID)), nil, fiber.Map{"name": cat.Name, "display_order": cat.DisplayOrder})
	})
	if fe, ok := err.(*fiber.Error); ok {
		return fe
	}
	if err != nil {
		return notFoundOr(err, "category")
	}
	return c.Status(fiber.StatusCreated).JSON(categoryDTO{ID: cat.ID, Name: cat.Name, DisplayOrder: cat.DisplayOrder, CreatedAt: cat.CreatedAt})
}

func (h *handlers) updateCategory(c *fiber.Ctx) error {
	id, err := idParam(c)
	if err != nil {
		return err
	}
	var req struct {
		Name         *string `json:"name"`
		DisplayOrder *int    `json:"display_order"`
	}
	if err := c.BodyParser(&req); err != nil || (req.Name == nil && req.DisplayOrder == nil) {
		return fiber.NewError(fiber.StatusBadRequest, "name or display_order is required")
	}
	err = h.db.Transaction(func(tx *gorm.DB) error {
		var cat models.Category
		if err := tx.Take(&cat, id).Error; err != nil {
			return err
		}
		before := fiber.Map{"name": cat.Name, "display_order": cat.DisplayOrder}
		updates := map[string]any{}
		if req.Name != nil && strings.TrimSpace(*req.Name) != "" {
			cat.Name = strings.TrimSpace(*req.Name)
			updates["name"] = cat.Name
		}
		if req.DisplayOrder != nil {
			cat.DisplayOrder = *req.DisplayOrder
			updates["display_order"] = cat.DisplayOrder
		}
		if err := tx.Model(&models.Category{}).Where("id = ?", id).Updates(updates).Error; err != nil {
			return err
		}
		return h.audit(tx, c, "category", "update", strconv.Itoa(int(id)), before, fiber.Map{"name": cat.Name, "display_order": cat.DisplayOrder})
	})
	if err != nil {
		return notFoundOr(err, "category")
	}
	return c.JSON(fiber.Map{"id": id})
}

// deleteCategory 캠페인·매핑이 하나도 없을 때만 삭제
func (h *handlers) deleteCategory(c *fiber.Ctx) error {
	id, err := idParam(c)
	if err != nil {
		return err
	}
	err = h.db.Transaction(func(tx *gorm.DB) error {
		var cat models.Category
		if err := tx.Take(&cat, id).Error; err != nil {
			return err
		}
		var used int64
		tx.Unscoped().Model(&models.Campaign{}).Where("category_id = ?", id).Count(&used)
		var mapped int64
		tx.Model(&models.CategoryMapping{}).Where("standard_category_id = ?", id).Count(&mapped)
		if used > 0 || mapped > 0 {
			return fiber.NewError(fiber.StatusConflict, "category is used by campaigns or mappings")
		}
		if err := tx.Delete(&models.Category{}, id).Error; err != nil {
			return err
		}
		return h.audit(tx, c, "category", "delete", strconv.Itoa(int(id)), fiber.Map{"name": cat.Name}, nil)
	})
	if fe, ok := err.(*fiber.Error); ok {
		return fe
	}
	if err != nil {
		return notFoundOr(err, "category")
	}
	return c.SendStatus(fiber.StatusNoContent)
}

// reorderCategories {"ids":[...]} 순서대로 display_order 1, 2, 3...
func (h *handlers) reorderCategories(c *fiber.Ctx) error {
	var req struct {
		IDs []uint `json:"ids"`
	}
	if err := c.BodyParser(&req); err != nil || len(req.IDs) == 0 {
		return fiber.NewError(fiber.StatusBadRequest, "ids is required")
	}
	err := h.db.Transaction(func(tx *gorm.DB) error {
		for i, id := range req.IDs {
			if err := tx.Model(&models.Category{}).Where("id = ?", id).Update("display_order", i+1).Error; err != nil {
				return err
			}
		}
		return h.audit(tx, c, "category", "reorder", "", nil, fiber.Map{"ids": req.IDs})
	})
	if err != nil {
		return notFoundOr(err, "categories")
	}
	return c.SendStatus(fiber.StatusNoContent)
}

type coverageRow struct {
	Source        string  `json:"source"`
	Total         int64   `json:"total"`
	NoCategory    int64   `json:"no_category"`
	NoCategoryPct float64 `json:"no_category_ratio"`
}

// categoryCoverage 카테고리 없는 활성 캠페인 비율 (출처별 + 전체)
func (h *handlers) categoryCoverage(c *fiber.Ctx) error {
	rows, err := coverage(h.db.DB)
	if err != nil {
		return notFoundOr(err, "coverage")
	}
	var unmapped int64
	if err := unmappedQuery(h.db.DB).Count(&unmapped).Error; err != nil {
		return notFoundOr(err, "coverage")
	}
	return c.JSON(fiber.Map{"by_source": rows, "raw_categories_unmapped": unmapped})
}

func coverage(db *gorm.DB) ([]coverageRow, error) {
	var raw []struct {
		Source     *string
		Total      int64
		NoCategory int64
	}
	err := db.Model(&models.Campaign{}).
		Select("source, COUNT(*) AS total, SUM(CASE WHEN category_id IS NULL THEN 1 ELSE 0 END) AS no_category").
		Group("source").Scan(&raw).Error
	if err != nil {
		return nil, err
	}
	out := []coverageRow{}
	all := coverageRow{Source: "전체"}
	for _, r := range raw {
		src := "(없음)"
		if r.Source != nil && *r.Source != "" {
			src = *r.Source
		}
		out = append(out, coverageRow{Source: src, Total: r.Total, NoCategory: r.NoCategory, NoCategoryPct: ratio(r.NoCategory, r.Total)})
		all.Total += r.Total
		all.NoCategory += r.NoCategory
	}
	all.NoCategoryPct = ratio(all.NoCategory, all.Total)
	sort.Slice(out, func(i, j int) bool { return out[i].Total > out[j].Total })
	return append([]coverageRow{all}, out...), nil
}

func ratio(a, b int64) float64 {
	if b == 0 {
		return 0
	}
	return float64(a) / float64(b)
}

func unmappedQuery(db *gorm.DB) *gorm.DB {
	return db.Model(&models.RawCategory{}).Where("id NOT IN (?)", db.Model(&models.CategoryMapping{}).Select("raw_category_id"))
}

// suggestion 원본 카테고리 문구에 대한 추천 카테고리.
type suggestion struct {
	CategoryID   uint    `json:"category_id"`
	CategoryName string  `json:"category_name"`
	Confidence   float64 `json:"confidence"`
	Basis        string  `json:"basis"`
}

// suggester recommends categories from existing mappings (계획 C-2).
//  1. 원문이 숫자이고 categories.id와 같으면 그 카테고리 (예전 Python 수집기가 캐시에 ID를 넣은 경우), 신뢰도 1
//  2. 원문의 대분류 경로("쇼핑,유통>식료품>반찬가게" → "쇼핑,유통>식료품", "쇼핑,유통")를 긴 것부터 찾아
//     기존 매핑에서 가장 많은 카테고리, 신뢰도 = 그 비율
type suggester struct {
	names    map[uint]string
	byPrefix map[string]map[uint]int
}

func newSuggester(db *gorm.DB) (*suggester, error) {
	s := &suggester{names: map[uint]string{}, byPrefix: map[string]map[uint]int{}}
	var cats []models.Category
	if err := db.Find(&cats).Error; err != nil {
		return nil, err
	}
	for _, k := range cats {
		s.names[k.ID] = k.Name
	}
	var mapped []struct {
		RawText    string
		CategoryID uint
	}
	err := db.Table("category_mappings m").Select("r.raw_text AS raw_text, m.standard_category_id AS category_id").
		Joins("JOIN raw_categories r ON r.id = m.raw_category_id").Scan(&mapped).Error
	if err != nil {
		return nil, err
	}
	for _, m := range mapped {
		for _, p := range prefixes(m.RawText) {
			if s.byPrefix[p] == nil {
				s.byPrefix[p] = map[uint]int{}
			}
			s.byPrefix[p][m.CategoryID]++
		}
	}
	return s, nil
}

// prefixes 원본 문구의 상위 경로를 긴 것부터 돌려준다 ("a>b>c" → "a>b", "a").
func prefixes(raw string) []string {
	parts := strings.Split(raw, ">")
	for i := range parts {
		parts[i] = strings.TrimSpace(parts[i])
	}
	var out []string
	for n := len(parts) - 1; n >= 1; n-- {
		out = append(out, strings.Join(parts[:n], ">"))
	}
	return out
}

func (s *suggester) suggest(raw string) *suggestion {
	raw = strings.TrimSpace(raw)
	if id, err := strconv.ParseUint(raw, 10, 64); err == nil {
		if name, ok := s.names[uint(id)]; ok {
			return &suggestion{CategoryID: uint(id), CategoryName: name, Confidence: 1, Basis: "번호가 카테고리 ID와 같음 (예전 수집기 저장값)"}
		}
		return nil
	}
	for _, p := range prefixes(raw) {
		counts := s.byPrefix[p]
		if len(counts) == 0 {
			continue
		}
		var best uint
		var bestN, total int
		for id, n := range counts {
			total += n
			if n > bestN || (n == bestN && id < best) {
				best, bestN = id, n
			}
		}
		return &suggestion{CategoryID: best, CategoryName: s.names[best], Confidence: float64(bestN) / float64(total),
			Basis: "'" + p + "' 기존 매핑 " + strconv.Itoa(bestN) + "/" + strconv.Itoa(total)}
	}
	return nil
}

type rawCategoryDTO struct {
	ID           uint        `json:"id"`
	RawText      string      `json:"raw_text"`
	Usage        int64       `json:"usage"`
	CategoryID   *uint       `json:"category_id,omitempty"`
	CategoryName string      `json:"category_name,omitempty"`
	Suggestion   *suggestion `json:"suggestion,omitempty"`
	CreatedAt    time.Time   `json:"created_at"`
}

// listRawCategories ?unmapped=1&q=&sort=usage|recent
// usage: 지역 검색 캐시(local_search_cache, go-scraper 소유)에서 이 원문을 쓰는 장소 수 = 매핑했을 때 바로 영향받는 규모
func (h *handlers) listRawCategories(c *fiber.Ctx) error {
	pageNo, size, offset := paging(c)
	q := h.db.Model(&models.RawCategory{})
	if c.Query("unmapped") == "1" {
		q = unmappedQuery(h.db.DB)
	}
	if s := c.Query("q"); s != "" {
		q = q.Where(ilike("raw_text"), like(s))
	}
	var total int64
	if err := q.Count(&total).Error; err != nil {
		return notFoundOr(err, "raw categories")
	}
	usage := map[string]int64{}
	hasCache := h.db.Migrator().HasTable("local_search_cache")
	if hasCache {
		var us []struct {
			Category string
			N        int64
		}
		h.db.Table("local_search_cache").Select("category, COUNT(*) AS n").Where("category IS NOT NULL").Group("category").Scan(&us)
		for _, u := range us {
			usage[u.Category] = u.N
		}
	}
	var rows []models.RawCategory
	if c.Query("sort") == "recent" || !hasCache {
		if err := q.Order("created_at DESC, id DESC").Limit(size).Offset(offset).Find(&rows).Error; err != nil {
			return notFoundOr(err, "raw categories")
		}
	} else {
		// 사용량 순: 미매핑 원본은 수백 개라 전부 읽어 정렬한 뒤 잘라낸다
		var all []models.RawCategory
		if err := q.Find(&all).Error; err != nil {
			return notFoundOr(err, "raw categories")
		}
		sort.SliceStable(all, func(i, j int) bool {
			ui, uj := usage[all[i].RawText], usage[all[j].RawText]
			if ui != uj {
				return ui > uj
			}
			return all[i].CreatedAt.After(all[j].CreatedAt)
		})
		end := offset + size
		if offset > len(all) {
			offset = len(all)
		}
		if end > len(all) {
			end = len(all)
		}
		rows = all[offset:end]
	}
	sg, err := newSuggester(h.db.DB)
	if err != nil {
		return notFoundOr(err, "raw categories")
	}
	ids := make([]uint, len(rows))
	for i, r := range rows {
		ids[i] = r.ID
	}
	current := map[uint]uint{}
	if len(ids) > 0 {
		var ms []models.CategoryMapping
		h.db.Where("raw_category_id IN ?", ids).Find(&ms)
		for _, m := range ms {
			current[m.RawCategoryID] = m.StandardCategoryID
		}
	}
	items := make([]rawCategoryDTO, len(rows))
	for i, r := range rows {
		d := rawCategoryDTO{ID: r.ID, RawText: r.RawText, Usage: usage[r.RawText], CreatedAt: r.CreatedAt}
		if cid, ok := current[r.ID]; ok {
			cid := cid
			d.CategoryID = &cid
			d.CategoryName = sg.names[cid]
		} else {
			d.Suggestion = sg.suggest(r.RawText)
		}
		items[i] = d
	}
	return c.JSON(page[rawCategoryDTO]{Items: items, Total: total, Page: pageNo, Size: size})
}

type mappingItem struct {
	RawCategoryID uint  `json:"raw_category_id"`
	CategoryID    *uint `json:"category_id"` // null이면 매핑 해제
}

// mapRawCategory PUT /raw-categories/:id/mapping {"category_id": 3 | null}
func (h *handlers) mapRawCategory(c *fiber.Ctx) error {
	id, err := idParam(c)
	if err != nil {
		return err
	}
	var req struct {
		CategoryID *uint `json:"category_id"`
	}
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "category_id is required (null to unmap)")
	}
	n, err := h.applyMappings(c, []mappingItem{{RawCategoryID: id, CategoryID: req.CategoryID}})
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"updated": n})
}

// bulkMapRawCategories POST /raw-categories/bulk-mapping {"items":[{"raw_category_id":1,"category_id":2}, ...]}
// 예전 Django Ninja의 POST /category-mappings를 대신한다 (여러 개를 한 트랜잭션으로).
func (h *handlers) bulkMapRawCategories(c *fiber.Ctx) error {
	var req struct {
		Items []mappingItem `json:"items"`
	}
	if err := c.BodyParser(&req); err != nil || len(req.Items) == 0 {
		return fiber.NewError(fiber.StatusBadRequest, "items is required")
	}
	if len(req.Items) > 1000 {
		return fiber.NewError(fiber.StatusBadRequest, "at most 1000 items")
	}
	n, err := h.applyMappings(c, req.Items)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"updated": n})
}

func (h *handlers) applyMappings(c *fiber.Ctx, items []mappingItem) (int, error) {
	updated := 0
	err := h.db.Transaction(func(tx *gorm.DB) error {
		for _, it := range items {
			var raw models.RawCategory
			if err := tx.Take(&raw, it.RawCategoryID).Error; err != nil {
				return fiber.NewError(fiber.StatusNotFound, "raw category "+strconv.Itoa(int(it.RawCategoryID))+" not found")
			}
			if it.CategoryID != nil {
				var n int64
				tx.Model(&models.Category{}).Where("id = ?", *it.CategoryID).Count(&n)
				if n == 0 {
					return fiber.NewError(fiber.StatusBadRequest, "category "+strconv.Itoa(int(*it.CategoryID))+" not found")
				}
			}
			var cur models.CategoryMapping
			found := tx.Where("raw_category_id = ?", raw.ID).Take(&cur).Error == nil
			var before any
			if found {
				before = fiber.Map{"raw_text": raw.RawText, "category_id": cur.StandardCategoryID}
			}
			switch {
			case it.CategoryID == nil && found:
				if err := tx.Delete(&models.CategoryMapping{}, cur.ID).Error; err != nil {
					return err
				}
			case it.CategoryID == nil:
				continue
			case found && cur.StandardCategoryID == *it.CategoryID:
				continue
			case found:
				if err := tx.Model(&models.CategoryMapping{}).Where("id = ?", cur.ID).Update("standard_category_id", *it.CategoryID).Error; err != nil {
					return err
				}
			default:
				if err := tx.Create(&models.CategoryMapping{RawCategoryID: raw.ID, StandardCategoryID: *it.CategoryID}).Error; err != nil {
					return err
				}
			}
			var after any
			action := "unmap"
			if it.CategoryID != nil {
				after = fiber.Map{"raw_text": raw.RawText, "category_id": *it.CategoryID}
				action = "map"
			}
			if err := h.audit(tx, c, "category_mapping", action, strconv.Itoa(int(raw.ID)), before, after); err != nil {
				return err
			}
			updated++
		}
		return nil
	})
	if fe, ok := err.(*fiber.Error); ok {
		return 0, fe
	}
	if err != nil {
		return 0, notFoundOr(err, "category mapping")
	}
	return updated, nil
}

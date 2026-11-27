package adminapi

import (
	"context"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"gorm.io/gorm"
)

// CategoryCollector exposes category mapping health (계획 C-4, 원칙 2: 매핑이 다시 조용히 밀리지 않게).
//
//	reviewmaps_raw_categories_unmapped                  미매핑 원본 카테고리 수
//	reviewmaps_campaigns_uncategorized_ratio{source}    카테고리 없는 활성 캠페인 비율 (source="전체" 포함)
//	reviewmaps_campaigns_active{source}                 활성 캠페인 수
//
// DB 조회는 최대 5분에 한 번만 하고 그 사이 수집 요청에는 마지막 값을 돌려준다.
type CategoryCollector struct {
	db       *gorm.DB
	unmapped *prometheus.Desc
	ratio    *prometheus.Desc
	active   *prometheus.Desc

	mu      sync.Mutex
	at      time.Time
	lastUn  int64
	lastCov []coverageRow
	ok      bool
}

// NewCategoryCollector main에서 한 번만 등록할 수집기.
func NewCategoryCollector(db *gorm.DB) *CategoryCollector {
	return &CategoryCollector{
		db:       db,
		unmapped: prometheus.NewDesc("reviewmaps_raw_categories_unmapped", "Raw categories without a category mapping", nil, nil),
		ratio:    prometheus.NewDesc("reviewmaps_campaigns_uncategorized_ratio", "Share of active campaigns without a category", []string{"source"}, nil),
		active:   prometheus.NewDesc("reviewmaps_campaigns_active", "Active (not soft-deleted) campaigns", []string{"source"}, nil),
	}
}

func (c *CategoryCollector) Describe(ch chan<- *prometheus.Desc) {
	ch <- c.unmapped
	ch <- c.ratio
	ch <- c.active
}

func (c *CategoryCollector) Collect(ch chan<- prometheus.Metric) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if time.Since(c.at) > 5*time.Minute || !c.ok {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		db := c.db.WithContext(ctx)
		var un int64
		err := unmappedQuery(db).Count(&un).Error
		cov, err2 := coverage(db)
		if err == nil && err2 == nil {
			c.lastUn, c.lastCov, c.ok, c.at = un, cov, true, time.Now()
		}
	}
	if !c.ok {
		return
	}
	ch <- prometheus.MustNewConstMetric(c.unmapped, prometheus.GaugeValue, float64(c.lastUn))
	for _, r := range c.lastCov {
		ch <- prometheus.MustNewConstMetric(c.ratio, prometheus.GaugeValue, r.NoCategoryPct, r.Source)
		ch <- prometheus.MustNewConstMetric(c.active, prometheus.GaugeValue, float64(r.Total), r.Source)
	}
}

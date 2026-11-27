package admin

import (
	"context"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	loginsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "reviewmaps_admin_logins_total",
		Help: "Admin console login attempts by method (google, password, dev) and result (success, invalid_token, invalid_password, not_allowed, rate_limited)",
	}, []string{"method", "result"})

	changesTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "reviewmaps_admin_changes_total",
		Help: "Admin console changes by entity and action",
	}, []string{"entity", "action"})
)

// RecordLogin counts a login attempt.
func RecordLogin(method, result string) { loginsTotal.WithLabelValues(method, result).Inc() }

// RecordChange counts an admin change.
func RecordChange(entity, action string) { changesTotal.WithLabelValues(entity, action).Inc() }

// RegisterActiveSessionsGauge exposes reviewmaps_admin_sessions_active (counted on scrape).
func RegisterActiveSessionsGauge(s *Sessions) {
	promauto.NewGaugeFunc(prometheus.GaugeOpts{
		Name: "reviewmaps_admin_sessions_active",
		Help: "Live admin console sessions",
	}, func() float64 {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		n, err := s.Active(ctx)
		if err != nil {
			return -1
		}
		return float64(n)
	})
}

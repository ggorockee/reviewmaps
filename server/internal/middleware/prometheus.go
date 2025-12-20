package middleware

import (
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/adaptor/v2"
	"github.com/gofiber/fiber/v2"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	// HTTP 요청 수
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "reviewmaps_http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "path", "status"},
	)

	// HTTP 요청 지연시간 (히스토그램)
	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "reviewmaps_http_request_duration_seconds",
			Help:    "HTTP request latency in seconds",
			Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
		},
		[]string{"method", "path"},
	)

	// 활성 연결 수
	httpActiveConnections = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "reviewmaps_http_active_connections",
			Help: "Number of active HTTP connections",
		},
	)

	// 요청 크기 (Summary)
	httpRequestSize = promauto.NewSummaryVec(
		prometheus.SummaryOpts{
			Name:       "reviewmaps_http_request_size_bytes",
			Help:       "HTTP request size in bytes",
			Objectives: map[float64]float64{0.5: 0.05, 0.9: 0.01, 0.99: 0.001},
		},
		[]string{"method", "path"},
	)

	// 응답 크기 (Summary)
	httpResponseSize = promauto.NewSummaryVec(
		prometheus.SummaryOpts{
			Name:       "reviewmaps_http_response_size_bytes",
			Help:       "HTTP response size in bytes",
			Objectives: map[float64]float64{0.5: 0.05, 0.9: 0.01, 0.99: 0.001},
		},
		[]string{"method", "path"},
	)
)

// PrometheusMiddleware Prometheus 메트릭 수집 미들웨어
func PrometheusMiddleware() fiber.Handler {
	return func(c *fiber.Ctx) error {
		// /docs, /metrics 경로는 제외
		path := c.Path()
		if strings.Contains(path, "/docs") || strings.Contains(path, "/metrics") {
			return c.Next()
		}

		start := time.Now()

		httpActiveConnections.Inc()
		defer httpActiveConnections.Dec()

		// 요청 크기 기록
		reqSize := float64(len(c.Body()))

		// 다음 핸들러 실행
		err := c.Next()

		// 메트릭 기록
		duration := time.Since(start).Seconds()
		status := strconv.Itoa(c.Response().StatusCode())
		method := c.Method()
		routePath := c.Route().Path
		if routePath == "" {
			routePath = path
		}

		// 응답 크기
		respSize := float64(len(c.Response().Body()))

		httpRequestsTotal.WithLabelValues(method, routePath, status).Inc()
		httpRequestDuration.WithLabelValues(method, routePath).Observe(duration)
		httpRequestSize.WithLabelValues(method, routePath).Observe(reqSize)
		httpResponseSize.WithLabelValues(method, routePath).Observe(respSize)

		return err
	}
}

// PrometheusHandler Prometheus 메트릭 엔드포인트 핸들러
// Prometheus가 이 엔드포인트를 scrape하여 메트릭 수집
func PrometheusHandler() fiber.Handler {
	return adaptor.HTTPHandler(promhttp.Handler())
}

// InternalOnly 내부망 접근 제한 미들웨어 (사용하지 않음)
// 보안을 위해 /metrics 경로는 내부망에서만 접근 가능
func InternalOnly() fiber.Handler {
	// 허용된 내부 IP 대역
	allowedCIDRs := []string{
		"127.0.0.0/8",     // localhost
		"10.0.0.0/8",      // Private Class A
		"172.16.0.0/12",   // Private Class B
		"192.168.0.0/16",  // Private Class C
		"::1/128",         // IPv6 localhost
		"fc00::/7",        // IPv6 private
	}

	var allowedNets []*net.IPNet
	for _, cidr := range allowedCIDRs {
		_, ipNet, err := net.ParseCIDR(cidr)
		if err == nil {
			allowedNets = append(allowedNets, ipNet)
		}
	}

	return func(c *fiber.Ctx) error {
		// X-Forwarded-For 헤더 또는 직접 IP 확인
		clientIP := c.IP()

		// X-Real-IP 헤더 확인 (프록시 뒤에 있는 경우)
		if realIP := c.Get("X-Real-IP"); realIP != "" {
			clientIP = realIP
		}

		ip := net.ParseIP(clientIP)
		if ip == nil {
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
				"success": false,
				"error": fiber.Map{
					"code":    "FORBIDDEN",
					"message": "Invalid IP address",
				},
			})
		}

		// 내부망 IP 체크
		for _, ipNet := range allowedNets {
			if ipNet.Contains(ip) {
				return c.Next()
			}
		}

		// 개발 환경에서는 모든 접근 허용 (환경변수로 제어)
		// APP_ENV가 development인 경우 허용
		// 프로덕션에서는 내부망만 허용
		return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
			"success": false,
			"error": fiber.Map{
				"code":    "FORBIDDEN",
				"message": "Access denied. Internal network only.",
			},
		})
	}
}

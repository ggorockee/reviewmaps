package database

import (
	"context"
	"fmt"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"gorm.io/gorm"
)

var (
	// DB 쿼리 실행 시간
	dbQueryDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "reviewmaps_db_query_duration_seconds",
			Help:    "Database query execution time in seconds",
			Buckets: []float64{.001, .005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5},
		},
		[]string{"operation", "table", "status"},
	)

	// DB 쿼리 실행 횟수
	dbQueryTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "reviewmaps_db_query_total",
			Help: "Total number of database queries",
		},
		[]string{"operation", "table", "status"},
	)

	// DB 에러 횟수
	dbErrorsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "reviewmaps_db_errors_total",
			Help: "Total number of database errors",
		},
		[]string{"operation", "table", "error_type"},
	)

	// 느린 쿼리 횟수 (>1초)
	dbSlowQueriesTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "reviewmaps_db_slow_queries_total",
			Help: "Total number of slow queries (>1 second)",
		},
		[]string{"operation", "table"},
	)

	// Connection Pool 크기
	dbConnectionPoolSize = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "reviewmaps_db_connection_pool_size",
			Help: "Maximum number of database connections in the pool",
		},
	)

	// Connection Pool 유휴 연결 수
	dbConnectionPoolIdle = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "reviewmaps_db_connection_pool_idle",
			Help: "Number of idle database connections in the pool",
		},
	)

	// Connection Pool 사용 중 연결 수
	dbConnectionPoolInUse = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "reviewmaps_db_connection_pool_in_use",
			Help: "Number of database connections currently in use",
		},
	)
)

// MetricsPlugin GORM metrics plugin
type MetricsPlugin struct{}

// Name plugin name
func (p *MetricsPlugin) Name() string {
	return "metricsPlugin"
}

// Initialize plugin initialization
func (p *MetricsPlugin) Initialize(db *gorm.DB) error {
	// Register callbacks for all operations
	_ = db.Callback().Create().Before("gorm:create").Register("metrics:before_create", beforeCallback)
	_ = db.Callback().Create().After("gorm:create").Register("metrics:after_create", afterCallback)

	_ = db.Callback().Query().Before("gorm:query").Register("metrics:before_query", beforeCallback)
	_ = db.Callback().Query().After("gorm:query").Register("metrics:after_query", afterCallback)

	_ = db.Callback().Update().Before("gorm:update").Register("metrics:before_update", beforeCallback)
	_ = db.Callback().Update().After("gorm:update").Register("metrics:after_update", afterCallback)

	_ = db.Callback().Delete().Before("gorm:delete").Register("metrics:before_delete", beforeCallback)
	_ = db.Callback().Delete().After("gorm:delete").Register("metrics:after_delete", afterCallback)

	_ = db.Callback().Row().Before("gorm:row").Register("metrics:before_row", beforeCallback)
	_ = db.Callback().Row().After("gorm:row").Register("metrics:after_row", afterCallback)

	_ = db.Callback().Raw().Before("gorm:raw").Register("metrics:before_raw", beforeCallback)
	_ = db.Callback().Raw().After("gorm:raw").Register("metrics:after_raw", afterCallback)

	return nil
}

// beforeCallback 쿼리 실행 전 콜백
func beforeCallback(db *gorm.DB) {
	db.InstanceSet("metrics:start_time", time.Now())
}

// afterCallback 쿼리 실행 후 콜백
func afterCallback(db *gorm.DB) {
	startTime, ok := db.InstanceGet("metrics:start_time")
	if !ok {
		return
	}

	duration := time.Since(startTime.(time.Time)).Seconds()
	operation := getOperation(db)
	table := db.Statement.Table
	if table == "" {
		table = "unknown"
	}

	// 성공/실패 상태
	status := "success"
	if db.Error != nil && db.Error != gorm.ErrRecordNotFound {
		status = "error"
	}

	// 쿼리 실행 시간 기록
	dbQueryDuration.WithLabelValues(operation, table, status).Observe(duration)

	// 쿼리 실행 횟수 기록
	dbQueryTotal.WithLabelValues(operation, table, status).Inc()

	// 에러 기록
	if db.Error != nil && db.Error != gorm.ErrRecordNotFound {
		errorType := "unknown"
		if db.Error != nil {
			errorType = fmt.Sprintf("%T", db.Error)
		}
		dbErrorsTotal.WithLabelValues(operation, table, errorType).Inc()
	}

	// 느린 쿼리 기록 (>1초)
	if duration > 1.0 {
		dbSlowQueriesTotal.WithLabelValues(operation, table).Inc()
	}
}

// getOperation 쿼리 operation 타입 추출
func getOperation(db *gorm.DB) string {
	switch db.Statement.ReflectValue.Kind() {
	case 0:
		// Raw query
		if db.Statement.SQL.String() != "" {
			sql := db.Statement.SQL.String()
			if len(sql) > 6 {
				switch sql[:6] {
				case "SELECT", "select":
					return "SELECT"
				case "INSERT", "insert":
					return "INSERT"
				case "UPDATE", "update":
					return "UPDATE"
				case "DELETE", "delete":
					return "DELETE"
				}
			}
		}
		return "RAW"
	default:
		// Use callback name to determine operation
		if db.Statement.Context != nil {
			if op := db.Statement.Context.Value("operation"); op != nil {
				return op.(string)
			}
		}
	}

	// Fallback: parse from SQL
	if db.Statement.SQL.String() != "" {
		sql := db.Statement.SQL.String()
		if len(sql) > 0 {
			switch {
			case len(sql) >= 6 && (sql[:6] == "SELECT" || sql[:6] == "select"):
				return "SELECT"
			case len(sql) >= 6 && (sql[:6] == "INSERT" || sql[:6] == "insert"):
				return "INSERT"
			case len(sql) >= 6 && (sql[:6] == "UPDATE" || sql[:6] == "update"):
				return "UPDATE"
			case len(sql) >= 6 && (sql[:6] == "DELETE" || sql[:6] == "delete"):
				return "DELETE"
			}
		}
	}

	return "UNKNOWN"
}

// UpdateConnectionPoolMetrics connection pool 메트릭 업데이트 (주기적 호출)
func UpdateConnectionPoolMetrics(db *gorm.DB) {
	sqlDB, err := db.DB()
	if err != nil {
		return
	}

	stats := sqlDB.Stats()
	dbConnectionPoolSize.Set(float64(stats.MaxOpenConnections))
	dbConnectionPoolIdle.Set(float64(stats.Idle))
	dbConnectionPoolInUse.Set(float64(stats.InUse))
}

// StartConnectionPoolMetricsCollector connection pool 메트릭 수집 시작 (백그라운드)
func StartConnectionPoolMetricsCollector(ctx context.Context, db *gorm.DB, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			UpdateConnectionPoolMetrics(db)
		}
	}
}

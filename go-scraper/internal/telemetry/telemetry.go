package telemetry

import (
	"context"
	"os"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/metric"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
	"go.opentelemetry.io/otel/trace"
)

const (
	serviceName    = "go-scraper"
	serviceVersion = "1.0.0"
)

// Telemetry OpenTelemetry 인스턴스
type Telemetry struct {
	tracerProvider *sdktrace.TracerProvider
	meterProvider  *sdkmetric.MeterProvider
	tracer         trace.Tracer
	meter          metric.Meter

	// Metrics
	ScrapeDuration   metric.Float64Histogram
	ScrapeTotal      metric.Int64Counter
	ScrapeErrors     metric.Int64Counter
	CampaignsScraped metric.Int64Counter
	EnrichTotal      metric.Int64Counter
	EnrichCacheHits  metric.Int64Counter
	EnrichAPICalls   metric.Int64Counter
	EnrichGeocodes   metric.Int64Counter

	// Cleanup Metrics
	CleanupTotal    metric.Int64Counter
	CleanupDeleted  metric.Int64Counter
	CleanupDuration metric.Float64Histogram
	CleanupErrors   metric.Int64Counter
}

// New 새로운 Telemetry 인스턴스 생성
func New(ctx context.Context) (*Telemetry, error) {
	endpoint := os.Getenv("SIGNOZ_ENDPOINT")
	if endpoint == "" {
		endpoint = os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	}

	// 엔드포인트가 없으면 빈 Telemetry 반환 (no-op)
	if endpoint == "" {
		return newNoOpTelemetry()
	}

	// Resource 생성
	res, err := resource.Merge(
		resource.Default(),
		resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion(serviceVersion),
			attribute.String("environment", getEnv("ENVIRONMENT", "production")),
		),
	)
	if err != nil {
		return nil, err
	}

	// Trace Exporter 생성
	traceExporter, err := otlptracehttp.New(ctx,
		otlptracehttp.WithEndpoint(endpoint),
		otlptracehttp.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	// Metric Exporter 생성
	metricExporter, err := otlpmetrichttp.New(ctx,
		otlpmetrichttp.WithEndpoint(endpoint),
		otlpmetrichttp.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	// Tracer Provider 설정
	tracerProvider := sdktrace.NewTracerProvider(
		sdktrace.WithResource(res),
		sdktrace.WithBatcher(traceExporter),
	)
	otel.SetTracerProvider(tracerProvider)

	// Meter Provider 설정
	meterProvider := sdkmetric.NewMeterProvider(
		sdkmetric.WithResource(res),
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter, sdkmetric.WithInterval(30*time.Second))),
	)
	otel.SetMeterProvider(meterProvider)

	tracer := tracerProvider.Tracer(serviceName)
	meter := meterProvider.Meter(serviceName)

	t := &Telemetry{
		tracerProvider: tracerProvider,
		meterProvider:  meterProvider,
		tracer:         tracer,
		meter:          meter,
	}

	// Metrics 등록
	if err := t.registerMetrics(); err != nil {
		return nil, err
	}

	return t, nil
}

// registerMetrics 메트릭 등록
func (t *Telemetry) registerMetrics() error {
	var err error

	// Scrape duration histogram
	t.ScrapeDuration, err = t.meter.Float64Histogram(
		"scraper.scrape.duration",
		metric.WithDescription("Duration of scrape operations in seconds"),
		metric.WithUnit("s"),
	)
	if err != nil {
		return err
	}

	// Scrape total counter
	t.ScrapeTotal, err = t.meter.Int64Counter(
		"scraper.scrape.total",
		metric.WithDescription("Total number of scrape operations"),
	)
	if err != nil {
		return err
	}

	// Scrape errors counter
	t.ScrapeErrors, err = t.meter.Int64Counter(
		"scraper.scrape.errors",
		metric.WithDescription("Total number of scrape errors"),
	)
	if err != nil {
		return err
	}

	// Campaigns scraped counter
	t.CampaignsScraped, err = t.meter.Int64Counter(
		"scraper.campaigns.scraped",
		metric.WithDescription("Total number of campaigns scraped"),
	)
	if err != nil {
		return err
	}

	// Enrich total counter
	t.EnrichTotal, err = t.meter.Int64Counter(
		"scraper.enrich.total",
		metric.WithDescription("Total number of enrich operations"),
	)
	if err != nil {
		return err
	}

	// Enrich cache hits counter
	t.EnrichCacheHits, err = t.meter.Int64Counter(
		"scraper.enrich.cache_hits",
		metric.WithDescription("Total number of enrich cache hits"),
	)
	if err != nil {
		return err
	}

	// Enrich API calls counter
	t.EnrichAPICalls, err = t.meter.Int64Counter(
		"scraper.enrich.api_calls",
		metric.WithDescription("Total number of enrich API calls"),
	)
	if err != nil {
		return err
	}

	// Enrich geocodes counter
	t.EnrichGeocodes, err = t.meter.Int64Counter(
		"scraper.enrich.geocodes",
		metric.WithDescription("Total number of geocode operations"),
	)
	if err != nil {
		return err
	}

	// Cleanup total counter
	t.CleanupTotal, err = t.meter.Int64Counter(
		"scraper.cleanup.total",
		metric.WithDescription("Total number of cleanup operations"),
	)
	if err != nil {
		return err
	}

	// Cleanup deleted counter
	t.CleanupDeleted, err = t.meter.Int64Counter(
		"scraper.cleanup.deleted",
		metric.WithDescription("Total number of campaigns deleted by cleanup"),
	)
	if err != nil {
		return err
	}

	// Cleanup duration histogram
	t.CleanupDuration, err = t.meter.Float64Histogram(
		"scraper.cleanup.duration",
		metric.WithDescription("Duration of cleanup operations in seconds"),
		metric.WithUnit("s"),
	)
	if err != nil {
		return err
	}

	// Cleanup errors counter
	t.CleanupErrors, err = t.meter.Int64Counter(
		"scraper.cleanup.errors",
		metric.WithDescription("Total number of cleanup errors"),
	)
	if err != nil {
		return err
	}

	return nil
}

// Tracer returns the tracer
func (t *Telemetry) Tracer() trace.Tracer {
	return t.tracer
}

// StartSpan 새로운 span 시작
func (t *Telemetry) StartSpan(ctx context.Context, name string, opts ...trace.SpanStartOption) (context.Context, trace.Span) {
	return t.tracer.Start(ctx, name, opts...)
}

// RecordScrapeDuration scrape duration 기록
func (t *Telemetry) RecordScrapeDuration(ctx context.Context, duration time.Duration, scraper string) {
	t.ScrapeDuration.Record(ctx, duration.Seconds(),
		metric.WithAttributes(attribute.String("scraper", scraper)),
	)
}

// IncrementScrapeTotal scrape total 증가
func (t *Telemetry) IncrementScrapeTotal(ctx context.Context, scraper string) {
	t.ScrapeTotal.Add(ctx, 1,
		metric.WithAttributes(attribute.String("scraper", scraper)),
	)
}

// IncrementScrapeErrors scrape errors 증가
func (t *Telemetry) IncrementScrapeErrors(ctx context.Context, scraper string) {
	t.ScrapeErrors.Add(ctx, 1,
		metric.WithAttributes(attribute.String("scraper", scraper)),
	)
}

// AddCampaignsScraped campaigns scraped 추가
func (t *Telemetry) AddCampaignsScraped(ctx context.Context, count int64, scraper string) {
	t.CampaignsScraped.Add(ctx, count,
		metric.WithAttributes(attribute.String("scraper", scraper)),
	)
}

// RecordEnrichStats enrich 통계 기록
func (t *Telemetry) RecordEnrichStats(ctx context.Context, scraper string, total, cacheHits, apiCalls, geocodes int64) {
	attrs := metric.WithAttributes(attribute.String("scraper", scraper))
	t.EnrichTotal.Add(ctx, total, attrs)
	t.EnrichCacheHits.Add(ctx, cacheHits, attrs)
	t.EnrichAPICalls.Add(ctx, apiCalls, attrs)
	t.EnrichGeocodes.Add(ctx, geocodes, attrs)
}

// IncrementCleanupTotal cleanup total 증가
func (t *Telemetry) IncrementCleanupTotal(ctx context.Context) {
	t.CleanupTotal.Add(ctx, 1)
}

// AddCleanupDeleted cleanup deleted 추가
func (t *Telemetry) AddCleanupDeleted(ctx context.Context, count int64) {
	t.CleanupDeleted.Add(ctx, count)
}

// RecordCleanupDuration cleanup duration 기록
func (t *Telemetry) RecordCleanupDuration(ctx context.Context, duration time.Duration) {
	t.CleanupDuration.Record(ctx, duration.Seconds())
}

// IncrementCleanupErrors cleanup errors 증가
func (t *Telemetry) IncrementCleanupErrors(ctx context.Context) {
	t.CleanupErrors.Add(ctx, 1)
}

// Shutdown 텔레메트리 종료
func (t *Telemetry) Shutdown(ctx context.Context) error {
	if t.tracerProvider != nil {
		if err := t.tracerProvider.Shutdown(ctx); err != nil {
			return err
		}
	}
	if t.meterProvider != nil {
		if err := t.meterProvider.Shutdown(ctx); err != nil {
			return err
		}
	}
	return nil
}

// newNoOpTelemetry no-op 텔레메트리 생성
func newNoOpTelemetry() (*Telemetry, error) {
	meter := otel.Meter(serviceName)
	tracer := otel.Tracer(serviceName)

	t := &Telemetry{
		tracer: tracer,
		meter:  meter,
	}

	// No-op metrics 등록
	_ = t.registerMetrics()

	return t, nil
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

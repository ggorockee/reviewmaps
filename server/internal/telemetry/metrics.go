package telemetry

import (
	"context"
	"log"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/metric"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
)

var meter metric.Meter

// HTTP metrics
var (
	HTTPRequestsTotal   metric.Int64Counter
	HTTPRequestDuration metric.Float64Histogram
	HTTPActiveRequests  metric.Int64UpDownCounter
)

// InitMeter initializes OpenTelemetry meter with OTLP HTTP exporter
func InitMeter(ctx context.Context, serviceName, endpoint string) (func(context.Context) error, error) {
	if endpoint == "" {
		log.Println("SIGNOZ_ENDPOINT not set, metrics disabled")
		return func(context.Context) error { return nil }, nil
	}

	// Create OTLP HTTP metric exporter
	exporter, err := otlpmetrichttp.New(ctx,
		otlpmetrichttp.WithEndpoint(endpoint),
		otlpmetrichttp.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	// Create resource with service info
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceNameKey.String(serviceName),
			semconv.ServiceVersionKey.String("1.0.0"),
		),
		resource.WithHost(),
		resource.WithOS(),
	)
	if err != nil {
		return nil, err
	}

	// Create meter provider with periodic reader
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithResource(res),
		sdkmetric.WithReader(
			sdkmetric.NewPeriodicReader(exporter,
				sdkmetric.WithInterval(15*time.Second),
			),
		),
	)

	// Set global meter provider
	otel.SetMeterProvider(mp)

	// Create meter
	meter = mp.Meter(serviceName)

	// Initialize HTTP metrics
	if err := initHTTPMetrics(); err != nil {
		return nil, err
	}

	log.Printf("OpenTelemetry metrics initialized with endpoint: %s", endpoint)

	return mp.Shutdown, nil
}

// initHTTPMetrics creates HTTP-related metrics instruments
func initHTTPMetrics() error {
	var err error

	HTTPRequestsTotal, err = meter.Int64Counter(
		"http_requests_total",
		metric.WithDescription("Total number of HTTP requests"),
		metric.WithUnit("{request}"),
	)
	if err != nil {
		return err
	}

	HTTPRequestDuration, err = meter.Float64Histogram(
		"http_request_duration_seconds",
		metric.WithDescription("HTTP request duration in seconds"),
		metric.WithUnit("s"),
		metric.WithExplicitBucketBoundaries(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
	)
	if err != nil {
		return err
	}

	HTTPActiveRequests, err = meter.Int64UpDownCounter(
		"http_active_requests",
		metric.WithDescription("Number of active HTTP requests"),
		metric.WithUnit("{request}"),
	)
	if err != nil {
		return err
	}

	return nil
}

// Meter returns the global meter
func Meter() metric.Meter {
	return meter
}

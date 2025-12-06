package telemetry

import (
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
	"go.opentelemetry.io/otel/trace"
)

// Config holds the configuration for the tracing middleware
type Config struct {
	ServiceName string
	Skip        func(*fiber.Ctx) bool
}

// DefaultConfig returns the default configuration
func DefaultConfig() Config {
	return Config{
		ServiceName: "reviewmaps-api",
		Skip: func(c *fiber.Ctx) bool {
			return c.Path() == "/v1/healthz"
		},
	}
}

// New returns a tracing middleware for Fiber
func New(config ...Config) fiber.Handler {
	cfg := DefaultConfig()
	if len(config) > 0 {
		cfg = config[0]
	}

	return func(c *fiber.Ctx) error {
		// Skip if configured
		if cfg.Skip != nil && cfg.Skip(c) {
			return c.Next()
		}

		// Record start time for metrics
		start := time.Now()

		// Increment active requests (metrics)
		method := c.Method()
		path := c.Path()
		if HTTPActiveRequests != nil {
			HTTPActiveRequests.Add(c.Context(), 1,
				metric.WithAttributes(
					attribute.String("method", method),
					attribute.String("path", path),
				),
			)
		}

		// Get tracer
		tr := otel.GetTracerProvider().Tracer(cfg.ServiceName)
		if tr == nil {
			return c.Next()
		}

		// Extract context from incoming request headers
		ctx := otel.GetTextMapPropagator().Extract(c.Context(), propagation.HeaderCarrier(c.GetReqHeaders()))

		// Start span
		spanName := method + " " + path
		ctx, span := tr.Start(ctx, spanName,
			trace.WithSpanKind(trace.SpanKindServer),
			trace.WithAttributes(
				semconv.HTTPMethodKey.String(method),
				semconv.HTTPURLKey.String(c.OriginalURL()),
				semconv.HTTPTargetKey.String(path),
				semconv.NetHostNameKey.String(c.Hostname()),
				semconv.HTTPUserAgentKey.String(string(c.Request().Header.UserAgent())),
			),
		)
		defer span.End()

		// Store span in locals for downstream use
		c.Locals("otel-span", span)
		c.SetUserContext(ctx)

		// Process request
		err := c.Next()

		// Record response status
		status := c.Response().StatusCode()
		span.SetAttributes(semconv.HTTPStatusCodeKey.Int(status))

		// Record error if any
		if err != nil {
			span.RecordError(err)
			span.SetAttributes(attribute.Bool("error", true))
		}

		// Decrement active requests (metrics)
		if HTTPActiveRequests != nil {
			HTTPActiveRequests.Add(c.Context(), -1,
				metric.WithAttributes(
					attribute.String("method", method),
					attribute.String("path", path),
				),
			)
		}

		// Record metrics
		duration := time.Since(start).Seconds()
		statusStr := strconv.Itoa(status)

		if HTTPRequestsTotal != nil {
			HTTPRequestsTotal.Add(c.Context(), 1,
				metric.WithAttributes(
					attribute.String("method", method),
					attribute.String("path", path),
					attribute.String("status", statusStr),
				),
			)
		}

		if HTTPRequestDuration != nil {
			HTTPRequestDuration.Record(c.Context(), duration,
				metric.WithAttributes(
					attribute.String("method", method),
					attribute.String("path", path),
					attribute.String("status", statusStr),
				),
			)
		}

		return err
	}
}

// SpanFromContext gets the current span from fiber context
func SpanFromContext(c *fiber.Ctx) trace.Span {
	span, ok := c.Locals("otel-span").(trace.Span)
	if !ok {
		return nil
	}
	return span
}

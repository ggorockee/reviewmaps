package telemetry

import (
	"github.com/gofiber/fiber/v2"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
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

		// Get tracer
		tr := otel.GetTracerProvider().Tracer(cfg.ServiceName)
		if tr == nil {
			return c.Next()
		}

		// Extract context from incoming request headers
		ctx := otel.GetTextMapPropagator().Extract(c.Context(), propagation.HeaderCarrier(c.GetReqHeaders()))

		// Start span
		spanName := c.Method() + " " + c.Path()
		ctx, span := tr.Start(ctx, spanName,
			trace.WithSpanKind(trace.SpanKindServer),
			trace.WithAttributes(
				semconv.HTTPMethodKey.String(c.Method()),
				semconv.HTTPURLKey.String(c.OriginalURL()),
				semconv.HTTPTargetKey.String(c.Path()),
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

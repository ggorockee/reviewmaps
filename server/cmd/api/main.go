package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	_ "github.com/ggorockee/reviewmaps/server/docs"
	"github.com/ggorockee/reviewmaps/server/internal/config"
	"github.com/ggorockee/reviewmaps/server/internal/database"
	"github.com/ggorockee/reviewmaps/server/internal/handlers"
	"github.com/ggorockee/reviewmaps/server/internal/middleware"
	"github.com/ggorockee/reviewmaps/server/internal/telemetry"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/gofiber/swagger"
	"github.com/joho/godotenv"
)

// @title ReviewMaps API
// @version 1.0.0
// @description 캠페인 추천 시스템 API
// @host api.review-maps.com
// @BasePath /v1
// @schemes https
// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization
func main() {
	// Load .env file
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using environment variables")
	}

	// Load configuration
	cfg := config.Load()

	// Initialize OpenTelemetry Tracer
	ctx := context.Background()
	tracerShutdown, err := telemetry.InitTracer(ctx, "reviewmaps-api", cfg.SigNozEndpoint)
	if err != nil {
		log.Printf("Failed to initialize tracer: %v", err)
	}
	defer func() {
		if err := tracerShutdown(ctx); err != nil {
			log.Printf("Error shutting down tracer: %v", err)
		}
	}()

	// Initialize OpenTelemetry Metrics
	meterShutdown, err := telemetry.InitMeter(ctx, "reviewmaps-api", cfg.SigNozEndpoint)
	if err != nil {
		log.Printf("Failed to initialize metrics: %v", err)
	}
	defer func() {
		if err := meterShutdown(ctx); err != nil {
			log.Printf("Error shutting down metrics: %v", err)
		}
	}()

	// Initialize database
	db, err := database.Connect(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// Run migrations
	if err := database.Migrate(db); err != nil {
		log.Fatalf("Failed to run migrations: %v", err)
	}

	// Initialize Fiber app
	app := fiber.New(fiber.Config{
		AppName:      "ReviewMaps API",
		ErrorHandler: handlers.ErrorHandler,
	})

	// Middleware
	app.Use(recover.New())
	// JSON 구조화 로깅 (원본 Django AccessLogMiddleware와 동일 형식)
	app.Use(logger.New(logger.Config{
		Format:     `{"time":"${time}","status":${status},"latency":"${latency}","ip":"${ip}","method":"${method}","path":"${path}","user_agent":"${ua}","error":"${error}"}` + "\n",
		TimeFormat: "2006-01-02T15:04:05Z07:00",
		TimeZone:   "Asia/Seoul",
	}))
	app.Use(telemetry.New(telemetry.Config{
		ServiceName: "reviewmaps-api",
	}))
	// CORS 설정 (원본 Django 설정과 동일)
	// Mobile app (Android/iOS)에서 API 호출을 위해 모든 origin 허용
	app.Use(cors.New(cors.Config{
		AllowOrigins:     "*",
		AllowMethods:     "GET, POST, PUT, PATCH, DELETE, OPTIONS",
		AllowHeaders:     "Accept, Accept-Encoding, Authorization, Content-Type, DNT, Origin, User-Agent, X-Requested-With, X-API-Key",
		AllowCredentials: false, // AllowOrigins가 "*"일 때는 false여야 함
		ExposeHeaders:    "Content-Length, Content-Type",
		MaxAge:           86400, // Preflight 캐시 24시간
	}))

	// Setup routes
	setupRoutes(app, db, cfg)

	// Start server
	port := cfg.ServerPort
	if port == "" {
		port = "3000"
	}

	// Graceful shutdown
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh

		log.Println("Shutting down server...")
		if err := app.Shutdown(); err != nil {
			log.Printf("Error shutting down server: %v", err)
		}
	}()

	log.Printf("Server starting on port %s", port)
	if err := app.Listen(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
		os.Exit(1)
	}
}

func setupRoutes(app *fiber.App, db *database.DB, cfg *config.Config) {
	// Swagger UI
	app.Get("/v1/docs/*", swagger.HandlerDefault)

	// Health check endpoints for k8s probes
	app.Get("/healthz", handlers.HealthCheck)
	app.Get("/v1/healthz", handlers.HealthCheck)
	app.Get("/v1/health", handlers.HealthCheck)
	app.Get("/v1/readiness", handlers.ReadinessCheck(db))
	app.Get("/v1/liveness", handlers.LivenessCheck)

	// API v1 group
	v1 := app.Group("/v1")

	// Auth routes (no auth required)
	auth := v1.Group("/auth")
	handlers.SetupAuthRoutes(auth, db, cfg)

	// Users routes (auth required)
	users := v1.Group("/users", middleware.AuthRequired(cfg))
	handlers.SetupUserRoutes(users, db)

	// Campaigns routes (public)
	campaigns := v1.Group("/campaigns")
	handlers.SetupCampaignRoutes(campaigns, db)

	// Categories routes (public)
	categories := v1.Group("/categories")
	handlers.SetupCategoryRoutes(categories, db)

	// Keyword alerts routes (auth required)
	keywordAlerts := v1.Group("/keyword-alerts", middleware.AuthRequired(cfg))
	handlers.SetupKeywordAlertRoutes(keywordAlerts, db, cfg)

	// App config routes (public)
	appConfig := v1.Group("/app-config")
	handlers.SetupAppConfigRoutes(appConfig, db)
}

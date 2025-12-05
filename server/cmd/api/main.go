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
// @host localhost:8000
// @BasePath /v1
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

	// Initialize OpenTelemetry
	ctx := context.Background()
	shutdown, err := telemetry.InitTracer(ctx, "reviewmaps-api", cfg.SigNozEndpoint)
	if err != nil {
		log.Printf("Failed to initialize telemetry: %v", err)
	}
	defer func() {
		if err := shutdown(ctx); err != nil {
			log.Printf("Error shutting down telemetry: %v", err)
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
	app.Use(logger.New())
	app.Use(telemetry.New(telemetry.Config{
		ServiceName: "reviewmaps-api",
	}))
	app.Use(cors.New(cors.Config{
		AllowOrigins: "*",
		AllowHeaders: "Origin, Content-Type, Accept, Authorization, X-API-Key",
		AllowMethods: "GET, POST, PUT, PATCH, DELETE, OPTIONS",
	}))

	// Setup routes
	setupRoutes(app, db, cfg)

	// Start server
	port := cfg.ServerPort
	if port == "" {
		port = "8000"
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
	app.Get("/swagger/*", swagger.HandlerDefault)

	// Health check
	app.Get("/v1/healthz", handlers.HealthCheck)

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

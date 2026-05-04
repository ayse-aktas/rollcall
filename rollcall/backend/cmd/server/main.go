package main

import (
	"log"
	"os"

	"rollcall-api/internal/config"
	"rollcall-api/internal/handler"
	"rollcall-api/internal/middleware"
	"rollcall-api/internal/repository"
	"rollcall-api/internal/service"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

func main() {
	// Yapılandırma yükle
	cfg := config.Load()

	// Gin modu
	if cfg.GinMode != "" {
		gin.SetMode(cfg.GinMode)
	}

	// Repository → Service → Handler katmanlama
	verificationRepo := repository.NewVerificationRepository(cfg)
	verificationService := service.NewVerificationService(verificationRepo)
	verificationHandler := handler.NewVerificationHandler(verificationService)
	healthHandler := handler.NewHealthHandler()

	// Router
	r := gin.Default()

	// CORS
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "X-Client-Info", "Apikey"},
		AllowCredentials: true,
	}))

	// Public routes
	api := r.Group("/api")
	{
		api.GET("/health", healthHandler.Health)
	}

	// Protected routes — Supabase JWT doğrulama
	v1 := api.Group("/v1")
	v1.Use(middleware.SupabaseAuth(cfg))
	{
		verification := v1.Group("/verification")
		{
			verification.POST("/verify", verificationHandler.Verify)
			verification.GET("/stats/:course_id", verificationHandler.GetStats)
			verification.GET("/logs/:course_id", verificationHandler.GetLogs)
		}
	}

	// Sunucuyu başlat
	port := cfg.Port
	if port == "" {
		port = "8080"
	}
	log.Printf("🚀 RollCall API sunucusu başlatılıyor: :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Sunucu başlatılamadı: %v", err)
		os.Exit(1)
	}
}

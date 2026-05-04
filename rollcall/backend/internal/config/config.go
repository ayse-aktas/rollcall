package config

import (
	"log"
	"os"

	"github.com/joho/godotenv"
)

// Config uygulama yapılandırması
type Config struct {
	Port                  string
	GinMode               string
	SupabaseURL           string
	SupabaseAnonKey       string
	SupabaseServiceRoleKey string
}

// Load ortam değişkenlerinden yapılandırma yükler
func Load() *Config {
	// .env dosyasını yükle (opsiyonel — production'da env var kullanılır)
	if err := godotenv.Load("config/.env"); err != nil {
		// .env yoksa root'tan dene
		_ = godotenv.Load(".env")
	}

	cfg := &Config{
		Port:                  getEnv("PORT", "8080"),
		GinMode:               getEnv("GIN_MODE", "debug"),
		SupabaseURL:           getEnv("SUPABASE_URL", ""),
		SupabaseAnonKey:       getEnv("SUPABASE_ANON_KEY", ""),
		SupabaseServiceRoleKey: getEnv("SUPABASE_SERVICE_ROLE_KEY", ""),
	}

	if cfg.SupabaseURL == "" {
		log.Println("⚠️  SUPABASE_URL tanımlı değil!")
	}

	return cfg
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

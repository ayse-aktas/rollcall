package middleware

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"rollcall-api/internal/config"

	"github.com/gin-gonic/gin"
)

// SupabaseAuth — Supabase JWT token doğrulama middleware'i.
// Authorization header'ından Bearer token'ı alır ve
// Supabase /auth/v1/user endpoint'i ile doğrular.
func SupabaseAuth(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "Authorization header gerekli",
			})
			return
		}

		token := strings.TrimPrefix(authHeader, "Bearer ")
		if token == authHeader {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "Bearer token formatı gerekli",
			})
			return
		}

		// Supabase'den kullanıcıyı doğrula
		userID, err := verifySupabaseToken(cfg, token)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": fmt.Sprintf("Token doğrulanamadı: %v", err),
			})
			return
		}

		// User ID'yi context'e ekle
		c.Set("user_id", userID)
		c.Next()
	}
}

// verifySupabaseToken — Supabase /auth/v1/user endpoint'i ile token doğrular
func verifySupabaseToken(cfg *config.Config, token string) (string, error) {
	client := &http.Client{}

	req, err := http.NewRequest("GET", cfg.SupabaseURL+"/auth/v1/user", nil)
	if err != nil {
		return "", err
	}

	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("apikey", cfg.SupabaseAnonKey)

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("geçersiz token (status: %d)", resp.StatusCode)
	}

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("yanıt parse hatası: %v", err)
	}

	userID, ok := result["id"].(string)
	if !ok || userID == "" {
		return "", fmt.Errorf("user ID bulunamadı")
	}

	return userID, nil
}

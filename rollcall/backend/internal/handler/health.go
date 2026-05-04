package handler

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// HealthHandler — Sunucu sağlık kontrolü
type HealthHandler struct{}

func NewHealthHandler() *HealthHandler {
	return &HealthHandler{}
}

// Health godoc
// @Summary Sunucu sağlık kontrolü
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Router /api/health [get]
func (h *HealthHandler) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "ok",
		"service": "rollcall-api",
		"time":    time.Now().Format(time.RFC3339),
	})
}

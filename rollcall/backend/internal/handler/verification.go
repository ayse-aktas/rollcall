package handler

import (
	"net/http"

	"rollcall-api/internal/model"
	"rollcall-api/internal/service"

	"github.com/gin-gonic/gin"
)

// VerificationHandler — Yoklama doğrulama HTTP handler'ları
type VerificationHandler struct {
	service *service.VerificationService
}

func NewVerificationHandler(svc *service.VerificationService) *VerificationHandler {
	return &VerificationHandler{service: svc}
}

// Verify godoc
// @Summary Yoklama doğrulama sonucu kaydet
// @Description BLE cihaz sayısı ile kamera kişi sayısını karşılaştırır ve loglar
// @Accept json
// @Produce json
// @Param request body model.VerifyRequest true "Doğrulama verileri"
// @Success 200 {object} model.VerifyResponse
// @Router /api/v1/verification/verify [post]
func (h *VerificationHandler) Verify(c *gin.Context) {
	var req model.VerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "Geçersiz istek: " + err.Error(),
		})
		return
	}

	// Middleware'den user ID al
	teacherID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Kullanıcı kimliği bulunamadı"})
		return
	}

	result, err := h.service.Verify(&req, teacherID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}

// GetStats godoc
// @Summary Ders bazlı doğrulama istatistikleri
// @Produce json
// @Param course_id path string true "Ders ID"
// @Success 200 {object} model.StatsResponse
// @Router /api/v1/verification/stats/{course_id} [get]
func (h *VerificationHandler) GetStats(c *gin.Context) {
	courseID := c.Param("course_id")
	if courseID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "course_id gerekli"})
		return
	}

	teacherID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Kullanıcı kimliği bulunamadı"})
		return
	}

	stats, err := h.service.GetStats(courseID, teacherID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, stats)
}

// GetLogs godoc
// @Summary Doğrulama logları
// @Produce json
// @Param course_id path string true "Ders ID"
// @Success 200 {array} model.VerificationLog
// @Router /api/v1/verification/logs/{course_id} [get]
func (h *VerificationHandler) GetLogs(c *gin.Context) {
	courseID := c.Param("course_id")
	if courseID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "course_id gerekli"})
		return
	}

	teacherID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Kullanıcı kimliği bulunamadı"})
		return
	}

	logs, err := h.service.GetLogs(courseID, teacherID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"course_id": courseID,
		"count":     len(logs),
		"logs":      logs,
	})
}

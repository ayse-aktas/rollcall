package repository

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"rollcall-api/internal/config"
	"rollcall-api/internal/model"
)

// VerificationRepository — Supabase REST API üzerinden veritabanı işlemleri
type VerificationRepository struct {
	cfg *config.Config
}

func NewVerificationRepository(cfg *config.Config) *VerificationRepository {
	return &VerificationRepository{cfg: cfg}
}

// Insert — Yeni doğrulama logu ekler
func (r *VerificationRepository) Insert(log *model.VerificationLog) error {
	body := map[string]interface{}{
		"course_id":            log.CourseID,
		"teacher_id":           log.TeacherID,
		"date":                 log.Date,
		"ble_device_count":     log.BLEDeviceCount,
		"camera_person_count":  log.CameraPersonCount,
		"verification_status":  log.VerificationStatus,
		"confidence_avg":       log.ConfidenceAvg,
	}

	jsonBody, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("JSON marshal hatası: %v", err)
	}

	url := fmt.Sprintf("%s/rest/v1/verification_logs", r.cfg.SupabaseURL)
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonBody))
	if err != nil {
		return err
	}

	r.setHeaders(req)
	req.Header.Set("Prefer", "return=representation")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("Supabase isteği başarısız: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("Supabase hata (%d): %s", resp.StatusCode, string(respBody))
	}

	return nil
}

// GetByCourseID — Ders ID'ye göre doğrulama loglarını getirir
func (r *VerificationRepository) GetByCourseID(courseID, teacherID string, limit int) ([]model.VerificationLog, error) {
	url := fmt.Sprintf(
		"%s/rest/v1/verification_logs?course_id=eq.%s&teacher_id=eq.%s&order=created_at.desc&limit=%d",
		r.cfg.SupabaseURL, courseID, teacherID, limit,
	)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}

	r.setHeaders(req)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("Supabase isteği başarısız: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("Supabase hata (%d): %s", resp.StatusCode, string(respBody))
	}

	var logs []model.VerificationLog
	if err := json.NewDecoder(resp.Body).Decode(&logs); err != nil {
		return nil, fmt.Errorf("JSON decode hatası: %v", err)
	}

	return logs, nil
}

// setHeaders — Supabase REST API için ortak header'ları ayarlar
func (r *VerificationRepository) setHeaders(req *http.Request) {
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apikey", r.cfg.SupabaseServiceRoleKey)
	req.Header.Set("Authorization", "Bearer "+r.cfg.SupabaseServiceRoleKey)
}

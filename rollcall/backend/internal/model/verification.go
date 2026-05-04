package model

import "time"

// VerifyRequest — Flutter'dan gelen doğrulama isteği
type VerifyRequest struct {
	CourseID         string  `json:"course_id" binding:"required"`
	Date             string  `json:"date" binding:"required"`
	BLEDeviceCount   int     `json:"ble_device_count" binding:"required"`
	CameraPersonCount int    `json:"camera_person_count" binding:"required"`
	ConfidenceAvg    float64 `json:"confidence_avg"`
}

// VerificationLog — Veritabanı modeli
type VerificationLog struct {
	ID                 string    `json:"id"`
	CourseID           string    `json:"course_id"`
	TeacherID          string    `json:"teacher_id"`
	Date               string    `json:"date"`
	BLEDeviceCount     int       `json:"ble_device_count"`
	CameraPersonCount  int       `json:"camera_person_count"`
	VerificationStatus string    `json:"verification_status"`
	ConfidenceAvg      float64   `json:"confidence_avg"`
	CreatedAt          time.Time `json:"created_at"`
}

// VerifyResponse — Doğrulama sonucu yanıtı
type VerifyResponse struct {
	Success            bool   `json:"success"`
	VerificationStatus string `json:"verification_status"`
	BLEDeviceCount     int    `json:"ble_device_count"`
	CameraPersonCount  int    `json:"camera_person_count"`
	Difference         int    `json:"difference"`
}

// StatsResponse — İstatistik yanıtı
type StatsResponse struct {
	CourseID            string            `json:"course_id"`
	TotalVerifications  int               `json:"total_verifications"`
	VerifiedCount       int               `json:"verified_count"`
	DeviceExcessCount   int               `json:"device_excess_count"`
	PersonExcessCount   int               `json:"person_excess_count"`
	VerificationRate    string            `json:"verification_rate"`
	AvgConfidence       string            `json:"avg_confidence"`
	RecentLogs          []VerificationLog `json:"recent_logs"`
}

// DetermineStatus — BLE ve kamera sayılarına göre doğrulama durumunu belirler
func DetermineStatus(bleCount, cameraCount int) string {
	if bleCount > cameraCount {
		return "device_excess" // Cihaz fazla, kişi az
	}
	if cameraCount > bleCount {
		return "person_excess" // Kişi fazla, cihaz az
	}
	return "verified" // Eşleşme başarılı
}

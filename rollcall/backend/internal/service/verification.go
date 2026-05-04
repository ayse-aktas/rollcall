package service

import (
	"fmt"
	"math"

	"rollcall-api/internal/model"
	"rollcall-api/internal/repository"
)

// VerificationService — Yoklama doğrulama iş mantığı
type VerificationService struct {
	repo *repository.VerificationRepository
}

func NewVerificationService(repo *repository.VerificationRepository) *VerificationService {
	return &VerificationService{repo: repo}
}

// Verify — Doğrulama işlemi: karşılaştır, logla, sonuç döndür
func (s *VerificationService) Verify(req *model.VerifyRequest, teacherID string) (*model.VerifyResponse, error) {
	status := model.DetermineStatus(req.BLEDeviceCount, req.CameraPersonCount)

	logEntry := &model.VerificationLog{
		CourseID:           req.CourseID,
		TeacherID:          teacherID,
		Date:               req.Date,
		BLEDeviceCount:     req.BLEDeviceCount,
		CameraPersonCount:  req.CameraPersonCount,
		VerificationStatus: status,
		ConfidenceAvg:      req.ConfidenceAvg,
	}

	if err := s.repo.Insert(logEntry); err != nil {
		return nil, fmt.Errorf("doğrulama logu kaydedilemedi: %v", err)
	}

	diff := int(math.Abs(float64(req.BLEDeviceCount - req.CameraPersonCount)))

	return &model.VerifyResponse{
		Success:            true,
		VerificationStatus: status,
		BLEDeviceCount:     req.BLEDeviceCount,
		CameraPersonCount:  req.CameraPersonCount,
		Difference:         diff,
	}, nil
}

// GetStats — Ders bazlı doğrulama istatistikleri
func (s *VerificationService) GetStats(courseID, teacherID string) (*model.StatsResponse, error) {
	logs, err := s.repo.GetByCourseID(courseID, teacherID, 30)
	if err != nil {
		return nil, err
	}

	total := len(logs)
	verified := 0
	deviceExcess := 0
	personExcess := 0
	totalConfidence := 0.0

	for _, l := range logs {
		switch l.VerificationStatus {
		case "verified":
			verified++
		case "device_excess":
			deviceExcess++
		case "person_excess":
			personExcess++
		}
		totalConfidence += l.ConfidenceAvg
	}

	avgConfidence := 0.0
	verificationRate := "0"
	if total > 0 {
		avgConfidence = totalConfidence / float64(total)
		verificationRate = fmt.Sprintf("%.1f", float64(verified)/float64(total)*100)
	}

	return &model.StatsResponse{
		CourseID:           courseID,
		TotalVerifications: total,
		VerifiedCount:      verified,
		DeviceExcessCount:  deviceExcess,
		PersonExcessCount:  personExcess,
		VerificationRate:   verificationRate,
		AvgConfidence:      fmt.Sprintf("%.2f", avgConfidence),
		RecentLogs:         logs,
	}, nil
}

// GetLogs — Son doğrulama loglarını getirir
func (s *VerificationService) GetLogs(courseID, teacherID string) ([]model.VerificationLog, error) {
	return s.repo.GetByCourseID(courseID, teacherID, 50)
}

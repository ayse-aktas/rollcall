-- ============================================================
-- Migration 001: Yoklama Doğrulama Alanları
-- BEACONTrack - Kamera ile kişi sayısı doğrulama desteği
-- ============================================================

-- 1. verification_logs tablosu: Her doğrulama işleminin kaydı
CREATE TABLE IF NOT EXISTS verification_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    course_id UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    teacher_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,

    -- Sayım verileri
    ble_device_count INTEGER NOT NULL DEFAULT 0,       -- BLE ile var işaretlenen öğrenci sayısı
    camera_person_count INTEGER NOT NULL DEFAULT 0,     -- Kamera ile tespit edilen kişi sayısı

    -- Doğrulama sonucu
    verification_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (verification_status IN ('verified', 'device_excess', 'person_excess', 'pending')),

    -- Meta veriler
    confidence_avg DOUBLE PRECISION,                    -- Ortalama algılama güvenilirliği
    created_at TIMESTAMPTZ DEFAULT NOW(),

    -- Bir ders + gün için birden fazla doğrulama olabilir
    UNIQUE(course_id, date, created_at)
);

-- 2. Index'ler
CREATE INDEX IF NOT EXISTS idx_verification_logs_course_date 
    ON verification_logs(course_id, date);

CREATE INDEX IF NOT EXISTS idx_verification_logs_teacher 
    ON verification_logs(teacher_id);

CREATE INDEX IF NOT EXISTS idx_verification_logs_status 
    ON verification_logs(verification_status);

-- 3. RLS (Row Level Security)
ALTER TABLE verification_logs ENABLE ROW LEVEL SECURITY;

-- Öğretmenler kendi doğrulama loglarını görebilir
CREATE POLICY "Teachers can view own verification logs"
    ON verification_logs FOR SELECT
    USING (auth.uid() = teacher_id);

-- Öğretmenler doğrulama logu oluşturabilir
CREATE POLICY "Teachers can insert verification logs"
    ON verification_logs FOR INSERT
    WITH CHECK (auth.uid() = teacher_id);

-- Admin herşeyi görebilir
CREATE POLICY "Admins can view all verification logs"
    ON verification_logs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE users.id = auth.uid()
            AND users.role = 'admin'
        )
    );

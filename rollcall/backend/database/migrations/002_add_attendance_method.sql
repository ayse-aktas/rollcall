ALTER TABLE attendance
ADD COLUMN IF NOT EXISTS attendance_method TEXT NOT NULL DEFAULT 'ble';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'attendance_method_check'
  ) THEN
    ALTER TABLE attendance
    ADD CONSTRAINT attendance_method_check
    CHECK (attendance_method IN ('ble', 'qr', 'manual'));
  END IF;
END $$;

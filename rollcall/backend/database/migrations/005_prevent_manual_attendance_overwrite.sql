-- ============================================================
-- Migration 005: Manuel yoklamanin otomatik akislarda ezilmesini engelle
-- ============================================================

CREATE OR REPLACE FUNCTION prevent_manual_attendance_overwrite()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.verify_method = 'manual'
       AND COALESCE(NEW.verify_method, '') <> 'manual' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_manual_attendance_overwrite ON attendance;

CREATE TRIGGER trg_prevent_manual_attendance_overwrite
BEFORE UPDATE ON attendance
FOR EACH ROW
EXECUTE FUNCTION prevent_manual_attendance_overwrite();

NOTIFY pgrst, 'reload schema';

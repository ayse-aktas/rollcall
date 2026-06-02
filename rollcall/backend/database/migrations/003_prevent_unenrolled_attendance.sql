-- ============================================================
-- Migration 003: Ders Kaydi Olmayan Ogrencilerin Yoklama Yazmasini Engelle
-- ============================================================

CREATE OR REPLACE FUNCTION ensure_student_is_enrolled_for_attendance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM student_courses sc
        WHERE sc.student_id = NEW.student_id
          AND sc.course_id = NEW.course_id
    ) THEN
        RAISE EXCEPTION 'Student % is not enrolled in course %', NEW.student_id, NEW.course_id
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ensure_student_is_enrolled_for_attendance ON attendance;

CREATE TRIGGER trg_ensure_student_is_enrolled_for_attendance
BEFORE INSERT OR UPDATE ON attendance
FOR EACH ROW
EXECUTE FUNCTION ensure_student_is_enrolled_for_attendance();
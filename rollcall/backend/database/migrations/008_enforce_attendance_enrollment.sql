-- ============================================================
-- Migration 008: Attendance kaydi icin ders kaydini DB seviyesinde zorunlu kil
-- QR, BLE, RPC veya dogrudan insert/update fark etmeksizin calisir.
-- ============================================================

CREATE OR REPLACE FUNCTION public.ensure_student_is_enrolled_for_attendance()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.student_id IS NULL OR NEW.course_id IS NULL THEN
    RAISE EXCEPTION 'Attendance requires student_id and course_id'
      USING ERRCODE = '23502';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.student_courses sc
    WHERE sc.student_id = NEW.student_id
      AND sc.course_id = NEW.course_id
  ) THEN
    RAISE EXCEPTION 'Student % is not enrolled in course %', NEW.student_id, NEW.course_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ensure_student_is_enrolled_for_attendance ON public.attendance;

CREATE TRIGGER trg_ensure_student_is_enrolled_for_attendance
BEFORE INSERT OR UPDATE OF student_id, course_id, is_present, verify_method, created_at, slot
ON public.attendance
FOR EACH ROW
EXECUTE FUNCTION public.ensure_student_is_enrolled_for_attendance();

NOTIFY pgrst, 'reload schema';

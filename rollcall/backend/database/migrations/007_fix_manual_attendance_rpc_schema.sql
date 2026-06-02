-- ============================================================
-- Migration 007: Manuel yoklama RPC sema uyumluluk duzeltmesi
-- attendance_method kolonu olmayan production DB icin.
-- ============================================================

CREATE OR REPLACE FUNCTION public.mark_manual_attendance(
  p_student_id uuid,
  p_course_id uuid,
  p_date date,
  p_slot integer,
  p_is_present boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_attendance_id uuid;
  v_row attendance%ROWTYPE;
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM courses c
    WHERE c.id = p_course_id
      AND (
        c.teacher_id = v_actor_id
        OR c.assigned_teacher_id = v_actor_id
        OR EXISTS (
          SELECT 1
          FROM users u
          WHERE u.id = v_actor_id
            AND u.role = 'admin'
        )
      )
  ) THEN
    RAISE EXCEPTION 'Teacher % is not allowed to mark attendance for course %', v_actor_id, p_course_id
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM student_courses sc
    WHERE sc.student_id = p_student_id
      AND sc.course_id = p_course_id
  ) THEN
    RAISE EXCEPTION 'Student % is not enrolled in course %', p_student_id, p_course_id
      USING ERRCODE = '23514';
  END IF;

  SELECT a.id
    INTO v_attendance_id
  FROM attendance a
  WHERE a.student_id = p_student_id
    AND a.course_id = p_course_id
    AND a.date = p_date
    AND (a.slot = p_slot OR a.slot IS NULL)
  ORDER BY a.created_at DESC NULLS LAST
  LIMIT 1;

  IF v_attendance_id IS NULL THEN
    INSERT INTO attendance (
      student_id,
      course_id,
      date,
      slot,
      is_present,
      verify_method,
      created_at
    )
    VALUES (
      p_student_id,
      p_course_id,
      p_date,
      p_slot,
      p_is_present,
      'manual',
      now()
    )
    RETURNING * INTO v_row;
  ELSE
    UPDATE attendance
    SET
      is_present = p_is_present,
      verify_method = 'manual',
      created_at = now()
    WHERE id = v_attendance_id
    RETURNING * INTO v_row;
  END IF;

  RETURN to_jsonb(v_row);
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_manual_attendance(uuid, uuid, date, integer, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_manual_attendance(uuid, uuid, date, integer, boolean) TO service_role;

NOTIFY pgrst, 'reload schema';

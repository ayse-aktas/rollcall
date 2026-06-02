-- ============================================================
-- Migration 004: BLE RPC ile yoklama yazarken ders kaydini zorunlu kıl
-- ============================================================

DROP FUNCTION IF EXISTS public.mark_attendance_by_hash (text, uuid);

CREATE SCHEMA IF NOT EXISTS extensions;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.mark_attendance_by_hash(
  p_beacon_hash text,
  p_course_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_student_id uuid;
  v_target_date date;
  v_hash text;
  v_updated_count integer := 0;
BEGIN
  IF p_beacon_hash IS NULL OR length(trim(p_beacon_hash)) < 8 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'status', 'invalid_hash',
      'hash', p_beacon_hash
    );
  END IF;

  IF p_course_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'status', 'invalid_course_id'
    );
  END IF;

  v_hash := lower(left(trim(p_beacon_hash), 8));
  v_target_date := (now() AT TIME ZONE 'Europe/Istanbul')::date;

  SELECT u.id
    INTO v_student_id
  FROM public.users u
  WHERE u.school_no IS NOT NULL
    AND lower(
      substring(
        encode(extensions.digest(upper(trim(u.school_no)), 'sha256'), 'hex'),
        1,
        8
      )
    ) = v_hash
  LIMIT 1;

  IF v_student_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'status', 'student_not_found',
      'hash', v_hash
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.student_courses sc
    WHERE sc.student_id = v_student_id
      AND sc.course_id = p_course_id
  ) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'status', 'student_not_enrolled',
      'student_id', v_student_id,
      'course_id', p_course_id,
      'date', v_target_date,
      'hash', v_hash
    );
  END IF;

  UPDATE public.attendance
  SET
    is_present = true,
    verify_method = 'ble',
    created_at = now()
  WHERE student_id = v_student_id
    AND course_id = p_course_id
    AND date = v_target_date
    AND COALESCE(verify_method, '') <> 'manual';

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  IF v_updated_count = 0 AND EXISTS (
    SELECT 1
    FROM public.attendance
    WHERE student_id = v_student_id
      AND course_id = p_course_id
      AND date = v_target_date
      AND verify_method = 'manual'
  ) THEN
    RETURN jsonb_build_object(
      'ok', true,
      'status', 'manual_exists',
      'student_id', v_student_id,
      'course_id', p_course_id,
      'date', v_target_date,
      'hash', v_hash
    );
  END IF;

  IF v_updated_count = 0 THEN
    INSERT INTO public.attendance (
      student_id,
      course_id,
      date,
      is_present,
      verify_method,
      created_at
    )
    VALUES (
      v_student_id,
      p_course_id,
      v_target_date,
      true,
      'ble',
      now()
    );

    RETURN jsonb_build_object(
      'ok', true,
      'status', 'inserted',
      'student_id', v_student_id,
      'course_id', p_course_id,
      'date', v_target_date,
      'hash', v_hash
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'status', 'updated',
    'student_id', v_student_id,
    'course_id', p_course_id,
    'date', v_target_date,
    'hash', v_hash
  );
END;
$$;

GRANT
EXECUTE ON FUNCTION public.mark_attendance_by_hash (text, uuid) TO anon;

GRANT
EXECUTE ON FUNCTION public.mark_attendance_by_hash (text, uuid) TO authenticated;

GRANT
EXECUTE ON FUNCTION public.mark_attendance_by_hash (text, uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
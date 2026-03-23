import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/theme/colors/app_colors.dart';

class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key});

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    final profile = await _supabase
        .from('users')
        .select('first_name, last_name, school_no, role')
        .eq('id', uid)
        .single();

    final enrollments = await _supabase
        .from('student_courses')
        .select(
          'course_id, courses(course_name, course_code, course_day, course_time)',
        )
        .eq('student_id', uid);

    final notifs = await _supabase
        .from('notifications')
        .select('message, type, is_read, created_at')
        .eq('student_id', uid)
        .order('created_at', ascending: false)
        .limit(10);

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _courses = List<Map<String, dynamic>>.from(enrollments);
      _notifications = List<Map<String, dynamic>>.from(notifs);
      _loading = false;
    });
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SafeArea(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(profile: _profile, onSignOut: _signOut),
                      const SizedBox(height: 24),
                      if (_notifications.isNotEmpty) ...[
                        _NotificationBanner(notifications: _notifications),
                        const SizedBox(height: 24),
                      ],
                      _SectionTitle('Derslerim'),
                      const SizedBox(height: 12),
                      _CourseList(
                        courses: _courses,
                        studentId: _supabase.auth.currentUser!.id,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Header ──────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final VoidCallback onSignOut;
  const _Header({required this.profile, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final name =
        '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}';
    final no = profile?['school_no'] ?? '';
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.surfaceLight,
          child: Text(
            (profile?['first_name'] ?? 'U')[0].toUpperCase(),
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                no,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(
            Icons.logout_rounded,
            color: AppColors.textSecondary,
            size: 20,
          ),
          onPressed: onSignOut,
        ),
      ],
    );
  }
}

// ── Bildirim Banner ──────────────────────────────────────

class _NotificationBanner extends StatelessWidget {
  final List<Map<String, dynamic>> notifications;
  const _NotificationBanner({required this.notifications});

  @override
  Widget build(BuildContext context) {
    final warnings = notifications
        .where((n) => n['type'] == 'attendance_warning')
        .toList();
    if (warnings.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              warnings.first['message'] ?? '',
              style: const TextStyle(color: AppColors.errorText, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Title ────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ── Ders Listesi ─────────────────────────────────────────

class _CourseList extends StatelessWidget {
  final List<Map<String, dynamic>> courses;
  final String studentId;
  const _CourseList({required this.courses, required this.studentId});

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return const Center(
        child: Text(
          'Kayıtlı ders bulunamadı',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return Column(
      children: courses.map((e) {
        final course = e['courses'] as Map<String, dynamic>? ?? {};
        return _CourseCard(course: course, studentId: studentId);
      }).toList(),
    );
  }
}

class _CourseCard extends StatefulWidget {
  final Map<String, dynamic> course;
  final String studentId;
  const _CourseCard({required this.course, required this.studentId});

  @override
  State<_CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<_CourseCard> {
  double? _rate;

  @override
  void initState() {
    super.initState();
    _loadRate();
  }

  Future<void> _loadRate() async {
    final supabase = Supabase.instance.client;
    final courseRow = await supabase
        .from('courses')
        .select('id')
        .eq('course_code', widget.course['course_code'])
        .maybeSingle();
    if (courseRow == null) return;

    final rows = await supabase
        .from('attendance')
        .select('is_present')
        .eq('student_id', widget.studentId)
        .eq('course_id', courseRow['id']);

    if (rows.isEmpty) return;
    final total = rows.length;
    final present = rows.where((r) => r['is_present'] == true).length;
    if (!mounted) return;
    setState(() => _rate = (present / total) * 100);
  }

  Color get _rateColor {
    if (_rate == null) return AppColors.textSecondary;
    if (_rate! >= 70) return AppColors.success;
    if (_rate! >= 60) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.book_outlined,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.course['course_name'] ?? '',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.course['course_code']} · ${widget.course['course_day']}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (_rate != null)
            Text(
              '%${_rate!.toStringAsFixed(0)}',
              style: TextStyle(
                color: _rateColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

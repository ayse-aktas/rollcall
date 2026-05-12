import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/theme/colors/app_colors.dart';

// ── Translation Helpers ─────────────────────────────────

String _translateDay(String? day) {
  const dayMap = {
    'Monday': 'Pazartesi',
    'Tuesday': 'Salı',
    'Wednesday': 'Çarşamba',
    'Thursday': 'Perşembe',
    'Friday': 'Cuma',
    'Saturday': 'Cumartesi',
    'Sunday': 'Pazar',
  };
  return dayMap[day] ?? day ?? '';
}

String _translateCourseName(String? name) {
  const courseMap = {
    'Mobile Application Development': 'Mobil Uygulama Geliştirme',
    'Database Management Systems': 'Veritabanı Yönetim Sistemleri',
    'Software Engineering': 'Yazılım Mühendisliği',
    'Artificial Intelligence': 'Yapay Zeka',
    'Data Structures': 'Veri Yapıları',
    'Computer Networks': 'Bilgisayar Ağları',
    'Operating Systems': 'İşletim Sistemleri',
    'Algorithms': 'Algoritmalar',
    'Web Development': 'Web Geliştirme',
    'Machine Learning': 'Makine Öğrenmesi',
    'Computer Architecture': 'Bilgisayar Mimarisi',
    'Discrete Mathematics': 'Ayrık Matematik',
    'Linear Algebra': 'Lineer Cebir',
    'Object Oriented Programming': 'Nesne Yönelimli Programlama',
    'Graduation Project': 'Bitirme Projesi',
  };
  return courseMap[name] ?? name ?? '';
}

// ── Main Page ───────────────────────────────────────────

class TeacherHomePage extends StatefulWidget {
  const TeacherHomePage({super.key});

  @override
  State<TeacherHomePage> createState() => _TeacherHomePageState();
}

class _TeacherHomePageState extends State<TeacherHomePage> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _courses = [];
  bool _isLoading = true;

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
        .select('first_name, last_name, school_no')
        .eq('id', uid)
        .single();

    final courses = await _supabase
        .from('courses')
        .select('id, course_name, course_code, course_day, course_time, course_end_time')
        .eq('teacher_id', uid)
        .order('course_code');

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _courses = List<Map<String, dynamic>>.from(courses);
      _isLoading = false;
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
      body: _isLoading
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
                      const SizedBox(height: 28),
                      const Text(
                        'Derslerim',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._courses.map((c) => _TeacherCourseCard(course: c)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Header ───────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final VoidCallback onSignOut;
  const _Header({required this.profile, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final name =
        '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}';
    final schoolNo = profile?['school_no'] ?? '';
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.surfaceLight,
          child: Text(
            (profile?['first_name'] ?? 'T')[0].toUpperCase(),
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
              Row(
                children: [
                  const Icon(
                    Icons.school_outlined,
                    color: AppColors.primary,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Öğretim Üyesi · $schoolNo',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
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

// ── Course Card ──────────────────────────────────────────

class _TeacherCourseCard extends StatefulWidget {
  final Map<String, dynamic> course;
  const _TeacherCourseCard({required this.course});

  @override
  State<_TeacherCourseCard> createState() => _TeacherCourseCardState();
}

class _TeacherCourseCardState extends State<_TeacherCourseCard> {
  int _studentCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final supabase = Supabase.instance.client;
    final courseId = widget.course['id'];

    final enrollments = await supabase
        .from('student_courses')
        .select('student_id')
        .eq('course_id', courseId);

    if (!mounted) return;
    setState(() {
      _studentCount = enrollments.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final translatedName = _translateCourseName(widget.course['course_name']);
    final translatedDay = _translateDay(widget.course['course_day']);

    return InkWell(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/ogretmen-ders-detay',
          arguments: widget.course,
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        translatedName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${widget.course['course_code']} · $translatedDay ${widget.course['course_time']}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppColors.textSecondary,
                  size: 14,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatChip(
                  icon: Icons.people_outline,
                  label: '$_studentCount öğrenci',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

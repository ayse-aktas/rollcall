import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/theme/colors/app_colors.dart';

String _translateNotificationMessage(String message) {
  const courseMap = {
    'Mobile Application Development': 'Mobil Uygulama Geliştirme',
    'Database Management Systems': 'Veritabanı Yönetim Sistemleri',
    'Software Engineering': 'Yazılım Mühendisliği',
    'Artificial Intelligence': 'Yapay Zeka',
  };
  final regex = RegExp(
    r'(.+?)\s*[—–-]\s*Attendance rate:\s*%?([\d.]+)\s*\(minimum\s*(\d+)%?\s*required\)',
    caseSensitive: false,
  );
  final match = regex.firstMatch(message);
  if (match != null) {
    final rawName = match.group(1)?.trim() ?? '';
    final courseName = courseMap[rawName] ?? rawName;
    final rate = match.group(2);
    final minimum = match.group(3);
    return '$courseName — Devam oranı: %$rate (minimum %$minimum gerekli)';
  }
  return message
      .replaceAll('Attendance rate', 'Devam oranı')
      .replaceAll('required', 'gerekli');
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _supabase = Supabase.instance.client;

  int _userCount = 0;
  int _courseCount = 0;
  int _attendanceCount = 0;
  int _warningCount = 0;
  bool _isLoading = true;

  List<Map<String, dynamic>> _recentWarnings = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final users = await _supabase.from('users').select('id');
    final courses = await _supabase.from('courses').select('id');
    final attendance = await _supabase.from('attendance').select('id');
    final warnings = await _supabase
        .from('notifications')
        .select(
          'message, created_at, users(first_name, last_name), courses(course_code)',
        )
        .eq('type', 'attendance_warning')
        .order('created_at', ascending: false)
        .limit(5);

    if (!mounted) return;
    setState(() {
      _userCount = users.length;
      _courseCount = courses.length;
      _attendanceCount = attendance.length;
      _warningCount = warnings.length;
      _recentWarnings = List<Map<String, dynamic>>.from(warnings);
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
                onRefresh: _loadStats,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.admin_panel_settings_outlined,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Yönetim Paneli',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'BEACONTrack',
                                  style: TextStyle(
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
                            onPressed: _signOut,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Stat cards
                      const Text(
                        'Genel Bakış',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.6,
                        children: [
                          _StatCard(
                            label: 'Toplam Kullanıcı',
                            value: '$_userCount',
                            icon: Icons.people_outline,
                            color: AppColors.primary,
                          ),
                          _StatCard(
                            label: 'Toplam Ders',
                            value: '$_courseCount',
                            icon: Icons.book_outlined,
                            color: AppColors.success,
                          ),
                          _StatCard(
                            label: 'Yoklama Kaydı',
                            value: '$_attendanceCount',
                            icon: Icons.check_circle_outline,
                            color: AppColors.warning,
                          ),
                          _StatCard(
                            label: 'Devamsızlık Uyarısı',
                            value: '$_warningCount',
                            icon: Icons.warning_amber_outlined,
                            color: AppColors.error,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Recent warnings
                      if (_recentWarnings.isNotEmpty) ...[
                        const Text(
                          'Son Devamsızlık Uyarıları',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._recentWarnings.map((warning) {
                          final user =
                              warning['users'] as Map<String, dynamic>? ?? {};
                          final course =
                              warning['courses'] as Map<String, dynamic>? ?? {};
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.errorBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.errorBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: AppColors.error,
                                  size: 16,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${user['first_name'] ?? ''} ${user['last_name'] ?? ''} · ${course['course_code'] ?? ''}',
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        _translateNotificationMessage(
                                          warning['message'] ?? '',
                                        ),
                                        style: const TextStyle(
                                          color: AppColors.errorText,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

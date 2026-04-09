import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/theme/colors/app_colors.dart';
import 'course_attendance_detail_page.dart';

// ACADEMIC TERM DATES
final DateTime TERM_START = DateTime(2026, 2, 9);
final DateTime TERM_END = DateTime(2026, 6, 12);

int getScheduledDaysCount(DateTime start, DateTime end, String courseDayRaw) {
  final List<String> scheduledDays = courseDayRaw.toLowerCase().split(',').map((e) => e.trim()).toList();
  int count = 0;
  for (DateTime d = start; d.isBefore(end) || DateUtils.isSameDay(d, end); d = d.add(const Duration(days: 1))) {
    final dayEnglish = DateFormat('EEEE').format(d).toLowerCase();
    if (scheduledDays.contains(dayEnglish)) {
      count++;
    }
  }
  return count;
}

// ── Translation Helpers ─────────────────────────────────


String _translateCourseName(String? name) {
  const courseMap = {
    'Mobile Application Development': 'Mobil Uygulama Geliştirme',
    'Database Management Systems': 'Veritabanı Yönetim Sistemleri',
    'Software Engineering': 'Yazılım Mühendisliği',
    'Artificial Intelligence': 'Yapay Zeka',
    'Data Structures': 'Veri Yapıları',
    'Computer Networks': 'Bilgisayar Ağları',
    'Operating Systems': 'İşletim Sistemleri',
  };
  return courseMap[name] ?? name ?? '';
}

String _translateNotificationMessage(String message) {
  final regex = RegExp(
    r'(.+?)\s*[—–-]\s*Attendance rate:\s*%?([\d.]+)\s*\(minimum\s*(\d+)%?\s*required\)',
    caseSensitive: false,
  );
  final match = regex.firstMatch(message);
  if (match != null) {
    final courseName = _translateCourseName(match.group(1)?.trim());
    final rateStr = match.group(2) ?? '0';
    final rate = double.tryParse(rateStr) ?? 0;
    final absenceRate = (100 - rate).toStringAsFixed(0);
    return '$courseName dersinde %$absenceRate devamsızlık yaptınız. Sınır değere yaklaşıyorsunuz, devamsızlıktan kalma riski bulunmaktadır.';
  }
  return message;
}

// ── Main Page ───────────────────────────────────────────

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final profile = await _supabase
          .from('users')
          .select('first_name, last_name, school_no, role')
          .eq('id', uid)
          .single();

      final enrollments = await _supabase
          .from('student_courses')
          .select(
            'course_id, courses(id, course_name, course_code, course_day, course_time)',
          )
          .eq('student_id', uid);

      final notifications = await _supabase
          .from('notifications')
          .select('id, message, type, is_read, created_at')
          .eq('student_id', uid)
          .order('created_at', ascending: false)
          .limit(100);

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _courses = List<Map<String, dynamic>>.from(enrollments);
        _notifications = List<Map<String, dynamic>>.from(notifications);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAllAsRead() async {
    final unreadIds = _notifications
        .where((n) => n['is_read'] == false)
        .map((n) => n['id'])
        .toList();

    if (unreadIds.isEmpty) return;

    try {
      // Local update
      setState(() {
        for (var n in _notifications) {
          if (unreadIds.contains(n['id'])) n['is_read'] = true;
        }
      });
      
      // PERSIST to Supabase
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .inFilter('id', unreadIds);
          
      // Important: If is_read doesn't support updates by students, we will see it here
      print('DEBUG: Mark all as read result - IDs sent: $unreadIds');
      
    } catch (e) {
      debugPrint('ERROR in markAllAsRead: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirimler güncellenemedi, yetki hatası olabilir.')),
      );
    }
  }

  Future<void> _markAsRead(String id) async {
    try {
      // PERSIST to Supabase FIRST to ensure sync
      await _supabase.from('notifications').update({'is_read': true}).eq('id', id);
      
      // Then local state
      setState(() {
        final index = _notifications.indexWhere((n) => n['id'] == id);
        if (index != -1) _notifications[index]['is_read'] = true;
      });
    } catch (e) {
      debugPrint('ERROR in markAsRead: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bildirim okundu yapılamadı: $e')),
      );
    }
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _NotificationSheet(
        notifications: _notifications,
        onMarkAllRead: _markAllAsRead,
        onMarkRead: _markAsRead,
      ),
    );
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((n) => n['is_read'] == false).length;
    final hasUnread = unreadCount > 0;

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
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withValues(alpha: 0.8),
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(32),
                            bottomRight: Radius.circular(32),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                        child: _Header(
                          profile: _profile, 
                          onSignOut: _signOut,
                          onNotify: _showNotifications,
                          hasUnread: hasUnread,
                          unreadCount: unreadCount,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 24),
                            const _SectionTitle('Haftalık Derslerim'),
                            const SizedBox(height: 16),
                            _CourseList(
                              courses: _courses,
                              studentId: _supabase.auth.currentUser!.id,
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Header (Clean Sky Blue style) ──────────────────────

class _Header extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final VoidCallback onSignOut;
  final VoidCallback onNotify;
  final bool hasUnread;
  final int unreadCount;
  
  const _Header({
    required this.profile, 
    required this.onSignOut,
    required this.onNotify,
    required this.hasUnread,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final name = '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}';
    final schoolNo = profile?['school_no'] ?? '';
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10),
            ],
          ),
          child: CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              (profile?['first_name'] ?? 'U')[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Numara: $schoolNo',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        _HeaderIcon(
          icon: unreadCount > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
          onTap: onNotify,
          hasBadge: unreadCount > 0,
          badgeCount: unreadCount,
        ),
        const SizedBox(width: 8),
        _HeaderIcon(
          icon: Icons.power_settings_new_rounded,
          onTap: onSignOut,
        ),
      ],
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool hasBadge;
  final int badgeCount;
  const _HeaderIcon({required this.icon, required this.onTap, this.hasBadge = false, this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            if (hasBadge)
              Positioned(
                right: -6, top: -6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    badgeCount.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── CUSTOM NOTIFICATION SHEET (TABBED) ──────────────────

class _NotificationSheet extends StatefulWidget {
  final List<Map<String, dynamic>> notifications;
  final VoidCallback onMarkAllRead;
  final Function(String) onMarkRead;
  
  const _NotificationSheet({
    required this.notifications, 
    required this.onMarkAllRead,
    required this.onMarkRead,
  });

  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> {
  @override
  Widget build(BuildContext context) {
    final unread = widget.notifications.where((n) => n['is_read'] == false).toList();
    final read = widget.notifications.where((n) => n['is_read'] == true).toList();

    return DefaultTabController(
      length: 2,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 10), decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Bildirim Merkezi', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w900)),
                  if (unread.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.done_all_rounded, size: 18, color: AppColors.primary),
                      label: const Text('Hepsini Oku', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                      onPressed: () {
                        widget.onMarkAllRead();
                      },
                    ),
                ],
              ),
            ),
            TabBar(
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              tabs: [
                Tab(text: 'YENİ (${unread.length})'),
                Tab(text: 'OKUNANLAR (${read.length})'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _NotificationList(notifications: unread, onMarkRead: (id) { widget.onMarkRead(id); }, isNew: true),
                  _NotificationList(notifications: read, onMarkRead: (_) {}, isNew: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  final List<Map<String, dynamic>> notifications;
  final Function(String) onMarkRead;
  final bool isNew;
  
  const _NotificationList({required this.notifications, required this.onMarkRead, required this.isNew});

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isNew ? Icons.notifications_none_rounded : Icons.history_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(isNew ? 'Hiç yeni bildirim yok.' : 'Henüz okunan bildirim yok.', style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: notifications.length,
      itemBuilder: (context, index) {
        final n = notifications[index];
        final id = n['id'].toString();
        final msg = _translateNotificationMessage(n['message'] ?? '');
        final date = DateTime.tryParse(n['created_at'] ?? '') ?? DateTime.now();
        final dateStr = DateFormat('dd MMM, HH:mm').format(date);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isNew ? AppColors.primaryLight.withValues(alpha: 0.2) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isNew ? AppColors.primary.withValues(alpha: 0.1) : AppColors.border),
            boxShadow: isNew ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))] : null,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(msg, style: TextStyle(fontSize: 14, fontWeight: isNew ? FontWeight.w700 : FontWeight.w400, color: AppColors.textPrimary)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(dateStr, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ),
            trailing: isNew 
            ? InkWell(
                onTap: () => onMarkRead(id),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.done_rounded, color: AppColors.primary, size: 18),
                ),
              )
            : Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.done_all_rounded, color: AppColors.success, size: 18),
              ),
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) {
    return Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 19, fontWeight: FontWeight.w900));
  }
}

class _CourseList extends StatelessWidget {
  final List<Map<String, dynamic>> courses;
  final String studentId;
  const _CourseList({required this.courses, required this.studentId});

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) return const Center(child: Text('Kayıtlı ders bulunamadı'));
    return Column(children: courses.map((e) => _CourseCard(course: e['courses'], studentId: studentId)).toList());
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
  int _total = 0, _attended = 0;
  double _rate = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final sb = Supabase.instance.client;
    final id = widget.course['id'];
    
    // Fetch ALL attendance records for this student and course directly from DB
    final response = await sb
        .from('attendance')
        .select()
        .eq('course_id', id)
        .eq('student_id', widget.studentId);
    
    if (!mounted) return;
    
    final List<Map<String, dynamic>> allRecs = List<Map<String, dynamic>>.from(response);
    final attended = allRecs.where((r) => r['is_present'] == true).length;
    final total = allRecs.length;

    setState(() {
      _total = total;
      _attended = attended;
      _rate = total > 0 ? (_attended / total) * 100 : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CourseAttendanceDetailPage(
                  course: widget.course,
                  studentId: widget.studentId,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(Icons.school_rounded, color: AppColors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _translateCourseName(widget.course['course_name']),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.course['course_code'] ?? '',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _rate >= 70
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '%${_rate.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: _rate >= 70 ? AppColors.success : AppColors.warning,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 1,
                color: AppColors.border.withValues(alpha: 0.6),
                margin: const EdgeInsets.symmetric(horizontal: 20),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      label: 'Dönem Toplam',
                      value: '$_total',
                      icon: Icons.calendar_month_rounded,
                    ),
                    _StatItem(
                      label: 'Katılım',
                      value: '$_attended',
                      icon: Icons.check_rounded,
                      color: AppColors.success,
                    ),
                    _StatItem(
                      label: 'Devamsızlık',
                      value: '${_total - _attended}',
                      icon: Icons.close_rounded,
                      color: AppColors.error,
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color? color;
  const _StatItem({required this.label, required this.value, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: (color ?? AppColors.textSecondary).withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: color ?? AppColors.textPrimary, fontSize: 15)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

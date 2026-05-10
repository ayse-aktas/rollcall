import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/theme/colors/app_colors.dart';
import 'course_attendance_detail_page.dart';
import 'qr_scanner_page.dart';
import '../../../core/services/beacon_attendance_service.dart';

// ACADEMIC TERM DATES
final DateTime termStart = DateTime(2026, 2, 9);
final DateTime termEnd = DateTime(2026, 6, 12);

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

  @override
  void dispose() {
    // Sayfa kapanırken BLE yayınını durdur
    BeaconAttendanceService().stopContinuousBroadcast();
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final profile = await _supabase
          .from('users')
          .select()
          .eq('id', uid)
          .single();

      final enrollments = await _supabase
          .from('student_courses')
          .select(
            'course_id, courses(id, course_name, course_code, course_day, course_time, course_end_time)',
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

      // Initialize Automatic Attendance Service
      _initAutoAttendance(uid);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _initAutoAttendance(String studentId) {
    if (_courses.isEmpty) return;
    
    final service = BeaconAttendanceService();
    service.init();
    
    final courseIds = _courses.map((e) => e['courses']['id'].toString()).toList();
    service.subscribeToCourse(studentId, courseIds);

    // Uygulama açıkken sürekli BLE yayını başlat (ESP32 tespit edebilsin)
    final schoolNo = _profile?['school_no']?.toString() ?? '0';
    service.startContinuousBroadcast(schoolNo);
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
      debugPrint('DEBUG: Mark all as read result - IDs sent: $unreadIds');
      
    } catch (e) {
      debugPrint('ERROR in markAllAsRead: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bildirimler güncellenemedi, yetki hatası olabilir.')),
        );
      }
    }
  }

  Future<void> _markAsRead(String id) async {
    try {
      // PERSIST to Supabase FIRST to ensure sync
      await _supabase.from('notifications').update({'is_read': true}).eq('id', id);
      
      // Then local state
      setState(() {
        final index = _notifications.indexWhere((n) => n['id'].toString() == id);
        if (index != -1) _notifications[index]['is_read'] = true;
      });
    } catch (e) {
      debugPrint('ERROR in markAsRead: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bildirim okundu yapılamadı: $e')),
        );
      }
    }
  }

  Future<void> _deleteAllReadNotifications() async {
    final readIds = _notifications
        .where((n) => n['is_read'] == true)
        .map((n) => n['id'])
        .toList();

    if (readIds.isEmpty) return;

    try {
      await _supabase.from('notifications').delete().inFilter('id', readIds);
      setState(() {
        _notifications.removeWhere((n) => n['is_read'] == true);
      });
    } catch (e) {
      debugPrint('ERROR in _deleteAllReadNotifications: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Okunan bildirimler silinemedi.')),
        );
      }
    }
  }

  Future<void> _deleteNotification(String id) async {
    try {
      await _supabase.from('notifications').delete().eq('id', id);
      setState(() {
        _notifications.removeWhere((n) => n['id'].toString() == id);
      });
    } catch (e) {
      debugPrint('ERROR in _deleteNotification: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bildirim silinemedi.')),
        );
      }
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
        onDeleteAllRead: _deleteAllReadNotifications,
        onDeleteNotification: _deleteNotification,
      ),
    );
  }

  void _showProfile() {
    final email = _supabase.auth.currentUser?.email ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ProfileSheet(
        profile: _profile,
        email: email,
        onSave: (updatedData, newPassword) async {
          try {
            if (newPassword != null && newPassword.isNotEmpty) {
              await _supabase.auth.updateUser(UserAttributes(password: newPassword));
            }
            try {
              await _supabase.from('users').update({
                'first_name': updatedData['first_name'],
                'bio': updatedData['bio'],
                'phone': updatedData['phone'],
                'website': updatedData['website'],
              }).eq('id', _supabase.auth.currentUser!.id);
            } catch (e) {
              debugPrint('Error updating extended profile fields (columns might not exist): $e');
              try {
                await _supabase.from('users').update({
                  'first_name': updatedData['first_name'],
                }).eq('id', _supabase.auth.currentUser!.id);
              } catch (_) {}
            }
            await _loadData();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil güncellendi!')));
            }
          } catch (e) {
            debugPrint('Error updating profile: $e');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil güncellenirken hata oluştu.')));
            }
          }
        },
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
                          onProfileTap: _showProfile,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const QRScannerPage()),
          );
          _loadData();
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
        label: const Text('QR Okut', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ── Header (Clean Sky Blue style) ──────────────────────

class _Header extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final VoidCallback onSignOut;
  final VoidCallback onNotify;
  final VoidCallback onProfileTap;
  final bool hasUnread;
  final int unreadCount;
  
  const _Header({
    required this.profile, 
    required this.onSignOut,
    required this.onNotify,
    required this.onProfileTap,
    required this.hasUnread,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final name = '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}';
    final schoolNo = profile?['school_no'] ?? '';
    return Row(
      children: [
        GestureDetector(
          onTap: onProfileTap,
          child: Container(
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
        ),
        const SizedBox(width: 16),
        Expanded(
          child: GestureDetector(
            onTap: onProfileTap,
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
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function(String) onMarkRead;
  final Future<void> Function() onDeleteAllRead;
  final Future<void> Function(String) onDeleteNotification;
  
  const _NotificationSheet({
    required this.notifications, 
    required this.onMarkAllRead,
    required this.onMarkRead,
    required this.onDeleteAllRead,
    required this.onDeleteNotification,
  });

  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unread = widget.notifications.where((n) => n['is_read'] == false).toList();
    final read = widget.notifications.where((n) => n['is_read'] == true).toList();

    return Container(
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
                if (_tabController.index == 0 && unread.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.done_all_rounded, size: 18, color: AppColors.primary),
                    label: const Text('Hepsini Oku', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                    onPressed: () async {
                      await widget.onMarkAllRead();
                      if (mounted) setState(() {});
                    },
                  )
                else if (_tabController.index == 1 && read.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18, color: AppColors.error),
                    label: const Text('Toplu Sil', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
                    onPressed: () async {
                      await widget.onDeleteAllRead();
                      if (mounted) setState(() {});
                    },
                  ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
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
              controller: _tabController,
              children: [
                _NotificationList(
                  notifications: unread, 
                  onMarkRead: (id) async { 
                    await widget.onMarkRead(id); 
                    if (mounted) setState(() {});
                  }, 
                  isNew: true,
                ),
                _NotificationList(
                  notifications: read, 
                  onMarkRead: (_) {}, 
                  onDelete: (id) async {
                    await widget.onDeleteNotification(id);
                    if (mounted) setState(() {});
                  },
                  isNew: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  final List<Map<String, dynamic>> notifications;
  final Function(String) onMarkRead;
  final Function(String)? onDelete;
  final bool isNew;
  
  const _NotificationList({
    required this.notifications, 
    required this.onMarkRead, 
    this.onDelete,
    required this.isNew,
  });

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
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.done_all_rounded, color: AppColors.success, size: 16),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => onDelete?.call(id),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 16),
                    ),
                  ),
                ],
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
  int _total = 0, _attended = 0, _missed = 0;
  double _rate = 0;
  bool _isAtRisk = false;
  bool _isFailed = false;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final sb = Supabase.instance.client;
    final id = widget.course['id'];
    
    // 1. Fetch ALL attendance records for this student and course
    final response = await sb
        .from('attendance')
        .select()
        .eq('course_id', id)
        .eq('student_id', widget.studentId);
    
    final Map<String, bool> attendanceMap = {};
    for (var rec in response) {
      attendanceMap[rec['date']] = rec['is_present'] ?? false;
    }

    // 2. Calculate full term stats
    final courseDayRaw = widget.course['course_day'] ?? '';
    final List<String> scheduledDays = courseDayRaw.toString().toLowerCase().split(',').map((e) => e.trim()).toList();
    
    int semesterTotal = 0;
    int attendedSessions = 0;
    int missedSessions = 0;

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    for (DateTime d = termStart; d.isBefore(termEnd) || DateUtils.isSameDay(d, termEnd); d = d.add(const Duration(days: 1))) {
      final dayEnglish = DateFormat('EEEE').format(d).toLowerCase();
      if (scheduledDays.contains(dayEnglish)) {
        semesterTotal++;
        final dateStr = DateFormat('yyyy-MM-dd').format(d);
        final bool? isPresentInDb = attendanceMap[dateStr];

        if (isPresentInDb != null) {
          if (isPresentInDb) {
            attendedSessions++;
          } else {
            missedSessions++;
          }
        } else if (DateUtils.isSameDay(d, today)) {
          // Check if class time has passed for today
          try {
            final String startStr = widget.course['course_time'] ?? '00:00:00';
            final String endStr = widget.course['course_end_time'] ?? '00:00:00';
            
            final startParts = startStr.split(':');
            final endParts = endStr.split(':');
            
            final startTotal = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
            int endTotal = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
            if (endTotal <= startTotal) endTotal = startTotal + 180;
            
            final nowTotal = now.hour * 60 + now.minute;
            
            if (nowTotal > endTotal) {
              missedSessions++;
            }
          } catch (_) {}
        } else if (d.isBefore(today)) {
          // Date passed but no record
          missedSessions++;
        }
      }
    }

    if (!mounted) return;

    final occurred = attendedSessions + missedSessions;
    final remaining = semesterTotal - occurred;
    final double devamSiniri = 0.7;
    final gerekenMinimumKatilim = (semesterTotal * devamSiniri).ceil();
    final olasiMaksimumKatilim = attendedSessions + remaining;

    setState(() {
      _total = semesterTotal;
      _attended = attendedSessions;
      _missed = missedSessions;
      _remaining = remaining;
      _rate = occurred > 0 ? (_attended / occurred) * 100 : 100;
      _isFailed = olasiMaksimumKatilim < gerekenMinimumKatilim;
      _isAtRisk = !_isFailed && (olasiMaksimumKatilim == gerekenMinimumKatilim && remaining > 0);
    });

    if (_isAtRisk || _isFailed) {
      _triggerRiskNotification();
    }
  }

  void _triggerRiskNotification() {
    // This could be a local notification or just a UI flag.
    // We already update the UI state, but we could also show a one-time message.
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
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CourseAttendanceDetailPage(
                  course: widget.course,
                  studentId: widget.studentId,
                ),
              ),
            );
            _loadStats();
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
                    if (DateTime.now().isAfter(termEnd.subtract(const Duration(days: 14))))
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isFailed ? AppColors.error : AppColors.success,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _isFailed ? 'KALDI' : 'GEÇTİ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_isFailed || _isAtRisk)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: _isFailed
                        ? AppColors.error.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isFailed
                          ? AppColors.error.withValues(alpha: 0.2)
                          : Colors.orange.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isFailed ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                        color: _isFailed ? AppColors.error : Colors.orange,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _isFailed
                              ? 'Devamsızlıktan kaldınız! (%70 barajı aşıldı)'
                              : 'Dikkat! Kalan $_remaining dersin tamamına katılmanız gerekiyor.',
                          style: TextStyle(
                            color: _isFailed ? AppColors.error : Colors.orange[800],
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isFailed || _isAtRisk)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _rate / 100,
                      backgroundColor: (_isFailed ? AppColors.error : Colors.orange).withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _isFailed ? AppColors.error : Colors.orange,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
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
                      value: '$_missed',
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

// ── CUSTOM PROFILE SHEET ────────────────────────────────
class _ProfileSheet extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final String email;
  final Function(Map<String, dynamic> updatedData, String? newPassword) onSave;

  const _ProfileSheet({
    required this.profile,
    required this.email,
    required this.onSave,
  });

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  bool _isEditing = false;
  
  late TextEditingController _nameController;
  late TextEditingController _bioController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _webController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;

  @override
  void initState() {
    super.initState();
    final firstName = widget.profile?['first_name'] ?? '';
    _nameController = TextEditingController(text: firstName);
    _bioController = TextEditingController(text: widget.profile?['bio'] ?? 'Bilgisayar Mühendisliği Öğrencisi. Yazılım geliştirmeyi ve yeni teknolojileri öğrenmeyi seviyorum.');
    _emailController = TextEditingController(text: widget.email);
    _phoneController = TextEditingController(text: widget.profile?['phone'] ?? '');
    _webController = TextEditingController(text: widget.profile?['website'] ?? '');
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _webController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    setState(() {
      _isEditing = !_isEditing;
    });
  }

  Future<void> _handleSave() async {
    if (_passwordController.text.isNotEmpty && _passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Şifreler eşleşmiyor!')));
      return;
    }

    final updatedData = {
      'first_name': _nameController.text.trim(),
      'bio': _bioController.text.trim(),
      'phone': _phoneController.text.trim(),
      'website': _webController.text.trim(),
    };
    
    await widget.onSave(updatedData, _passwordController.text.isNotEmpty ? _passwordController.text : null);
    
    if (mounted) {
      setState(() {
        _isEditing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 32),
              Expanded(
                child: Text(
                  _isEditing ? 'Profili Düzenle' : 'Profil Sayfası',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.black, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: _isEditing ? _buildEditMode() : _buildViewMode(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewMode() {
    final name = '${widget.profile?['first_name'] ?? ''} ${widget.profile?['last_name'] ?? ''}';
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: const BoxDecoration(
            color: Color(0xFFD1D5DB),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, size: 60, color: Colors.white),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _toggleEdit,
          child: const Text(
            'Düzenle',
            style: TextStyle(color: Color(0xFF0090FF), fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          name.isNotEmpty ? name.trim() : 'Öğrenci',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            _bioController.text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.5),
          ),
        ),
        const SizedBox(height: 32),
        _buildViewField('E-Mail', _emailController.text),
        const SizedBox(height: 16),
        _buildViewField('İletişim', _phoneController.text.isNotEmpty ? _phoneController.text : 'Girilmemiş'),
        const SizedBox(height: 16),
        _buildViewField('Web', _webController.text.isNotEmpty ? _webController.text : 'Girilmemiş'),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _toggleEdit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0090FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              elevation: 0,
            ),
            child: const Text(
              'Profili Düzenle',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildEditMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEditField('Kullanıcı adı', _nameController),
        const SizedBox(height: 16),
        _buildEditField('Biografi', _bioController, maxLines: 3),
        const SizedBox(height: 16),
        _buildEditField('E-Mail', _emailController, readOnly: true),
        const SizedBox(height: 16),
        _buildEditField('İletişim', _phoneController),
        const SizedBox(height: 16),
        _buildEditField('Web', _webController),
        const SizedBox(height: 16),
        _buildEditField('Şifre', _passwordController, isPassword: true, hint: '*************'),
        const SizedBox(height: 16),
        _buildEditField('Şifreyi onayla', _confirmPasswordController, isPassword: true),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _handleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0090FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              elevation: 0,
            ),
            child: const Text(
              'Güncelle',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildViewField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF4B5563)),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
          child: Text(
            value,
            style: const TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
          ),
        ),
      ],
    );
  }

  Widget _buildEditField(String label, TextEditingController controller, {bool isPassword = false, int maxLines = 1, bool readOnly = false, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF4B5563)),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: isPassword,
          maxLines: isPassword ? 1 : maxLines,
          readOnly: readOnly,
          style: const TextStyle(fontSize: 15, color: Color(0xFF374151)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF0090FF), width: 1.5),
            ),
            suffixIcon: readOnly 
                ? null 
                : const Icon(Icons.edit, size: 18, color: Color(0xFF6B7280)),
          ),
        ),
      ],
    );
  }
}

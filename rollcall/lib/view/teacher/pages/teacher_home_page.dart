import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../core/utils/theme/colors/app_colors.dart';
import 'teacher_delegate_page.dart';
import 'teacher_notifications_sheet.dart';

// ── Translation Helpers ─────────────────────────────────

String _translateDay(String? day) {
  const dayMap = {
    'Monday': 'Pazartesi', 'Tuesday': 'Salı', 'Wednesday': 'Çarşamba',
    'Thursday': 'Perşembe', 'Friday': 'Cuma', 'Saturday': 'Cumartesi', 'Sunday': 'Pazar',
  };
  return dayMap[day] ?? day ?? '';
}

String _translateCourseName(String? name) {
  const courseMap = {
    'Mobile Application Development': 'Mobil Uygulama Geliştirme',
    'Database Management Systems': 'Veritabanı Yönetim Sistemleri',
    'Software Engineering': 'Yazılım Mühendisliği',
    'Artificial Intelligence': 'Yapay Zeka',
  };
  return courseMap[name] ?? name ?? '';
}

class TeacherHomePage extends StatefulWidget {
  const TeacherHomePage({super.key});
  @override
  State<TeacherHomePage> createState() => _TeacherHomePageState();
}

class _TeacherHomePageState extends State<TeacherHomePage> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _ownCourses = [];
  List<Map<String, dynamic>> _assignedCourses = [];
  bool _isLoading = true;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    // Her kullanıcıyı kendi ID'si ile oluşturulmuş kanala abone yap
    FirebaseMessaging.instance.subscribeToTopic("user_$uid");

    try {
      // 1. Profile
      final profile = await _supabase.from('users').select().eq('id', uid).single();

      // 2. Fetch Own Courses (En Güvenli Yol: Join ismine güvenmeden çek)
      // Önce dersleri çekiyoruz, sonra hoca isimlerini ekleyeceğiz
      final ownRes = await _supabase.from('courses').select().eq('teacher_id', uid).order('course_code');
      
      // 3. Fetch Assigned Courses
      final assignedRes = await _supabase.from('courses').select().eq('assigned_teacher_id', uid).order('course_code');

      // 4. Notifications
      final notifRes = await _supabase.from('notifications').select('id').eq('user_id', uid).eq('is_read', false);

      // 5. İsimleri Manuel Eşleştirme (Join hatasını önlemek için)
      // Bu kısım opsiyoneldir ama 'Sahibi: ...' yazması için hoca bilgilerini ayrıca çekebiliriz.
      // Şimdilik listelerin dolduğundan emin olalım.

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _ownCourses = List<Map<String, dynamic>>.from(ownRes);
        _assignedCourses = List<Map<String, dynamic>>.from(assignedRes);
        _unreadCount = notifRes.length;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Sorgu Hatası: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: _Header(profile: _profile, unreadCount: _unreadCount, 
                      onNotifTap: () async {
                        await TeacherNotificationsSheet.show(context);
                        _loadData();
                      },
                      onSignOut: () async {
                        await _supabase.auth.signOut();
                        if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
                      }
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                      labelColor: Colors.white,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: const [Tab(text: 'Derslerim'), Tab(text: 'Devralınanlar')],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildList(_ownCourses, true),
                        _buildList(_assignedCourses, false),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> courses, bool isOwner) {
    if (courses.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(height: 400, alignment: Alignment.center,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.book_outlined, size: 48, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text(isOwner ? 'Henüz bir dersiniz yok.' : 'Henüz devralınan bir ders yok.', style: const TextStyle(color: AppColors.textSecondary)),
            ])),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: courses.length,
        itemBuilder: (context, index) => _TeacherCourseCard(course: courses[index], isOwner: isOwner, onRefresh: _loadData),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final int unreadCount;
  final VoidCallback onNotifTap;
  final VoidCallback onSignOut;
  const _Header({required this.profile, required this.unreadCount, required this.onNotifTap, required this.onSignOut});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      CircleAvatar(radius: 22, backgroundColor: AppColors.primary.withValues(alpha: 0.1), child: Text((profile?['first_name'] ?? 'T')[0].toUpperCase(), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        Text('${profile?['title'] ?? 'Öğretim Elemanı'} · ${profile?['school_no'] ?? ''}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ])),
      Stack(children: [
        IconButton(icon: const Icon(Icons.notifications_none_rounded), onPressed: onNotifTap),
        if (unreadCount > 0) Positioned(right: 8, top: 8, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))),
      ]),
      IconButton(icon: const Icon(Icons.logout_rounded, size: 20), onPressed: onSignOut),
    ]);
  }
}

class _TeacherCourseCard extends StatefulWidget {
  final Map<String, dynamic> course;
  final bool isOwner;
  final VoidCallback onRefresh;
  const _TeacherCourseCard({required this.course, required this.isOwner, required this.onRefresh});
  @override
  State<_TeacherCourseCard> createState() => _TeacherCourseCardState();
}

class _TeacherCourseCardState extends State<_TeacherCourseCard> {
  int _studentCount = 0;
  bool _isRevoking = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final res = await Supabase.instance.client.from('student_courses').select('student_id').eq('course_id', widget.course['id']);
    if (mounted) setState(() => _studentCount = res.length);
  }

  @override
  Widget build(BuildContext context) {
    final translatedName = _translateCourseName(widget.course['course_name']);
    final translatedDay = _translateDay(widget.course['course_day']);
    final hasAssigned = widget.course['assigned_teacher_id'] != null;

    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/ogretmen-ders-detay', arguments: widget.course),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: hasAssigned && widget.isOwner ? Colors.orange.withValues(alpha: 0.3) : AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(translatedName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text('${widget.course['course_code']} · $translatedDay ${(widget.course['course_time'] ?? '').substring(0, 5)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ])),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _Badge(icon: Icons.people_outline, label: '$_studentCount öğrenci'),
            const Spacer(),
            if (hasAssigned) _StatusBadge(label: widget.isOwner ? 'Devredildi' : 'Devralındı', color: widget.isOwner ? Colors.orange : AppColors.primary),
          ]),
          if (widget.isOwner) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () async {
                  final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherDelegatePage(course: widget.course)));
                  if (res == true) widget.onRefresh();
                },
                icon: Icon(hasAssigned ? Icons.swap_horiz_rounded : Icons.person_add_alt_rounded, size: 16),
                label: Text(hasAssigned ? 'Devri Yönet' : 'Dersi Devret', style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(foregroundColor: hasAssigned ? Colors.orange : AppColors.primary, side: BorderSide(color: hasAssigned ? Colors.orange.withValues(alpha: 0.5) : AppColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              )),
              if (hasAssigned) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isRevoking ? null : () async {
                    setState(() => _isRevoking = true);
                    await Supabase.instance.client.from('courses').update({'assigned_teacher_id': null}).eq('id', widget.course['id']);
                    widget.onRefresh();
                  },
                  icon: _isRevoking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.assignment_return_rounded, color: Colors.redAccent),
                  style: IconButton.styleFrom(backgroundColor: Colors.red.withValues(alpha: 0.05), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon; final String label;
  const _Badge({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(6)), child: Row(children: [Icon(icon, size: 12, color: AppColors.textSecondary), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))]));
  }
}

class _StatusBadge extends StatelessWidget {
  final String label; final Color color;
  const _StatusBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)));
  }
}

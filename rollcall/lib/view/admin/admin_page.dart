import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/utils/theme/colors/app_colors.dart';
import 'pages/user_detail_page.dart';
import 'pages/course_detail_page.dart';
import 'pages/support_detail_dialog.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  int _currentIndex = 0;
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _allCourses = [];
  List<Map<String, dynamic>> _supportRequests = [];
  List<Map<String, dynamic>> _classrooms = [];
  String _userSearchQuery = '';
  String _selectedRoleFilter = 'all'; // all, student, teacher

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final users = await _supabase
        .from('users')
        .select('id, first_name, last_name, school_no, role, email, title');
    final courses = await _supabase
        .from('courses')
        .select('*, users!teacher_id(first_name, last_name)');
    final supportRequests = await _supabase
        .from('support_requests')
        .select('*')
        .order('created_at', ascending: false);
    final classrooms = await _supabase
        .from('classrooms')
        .select('id, name')
        .order('name');

    if (!mounted) return;
    setState(() {
      _allUsers = List<Map<String, dynamic>>.from(users);
      _allCourses = List<Map<String, dynamic>>.from(courses);
      _supportRequests = List<Map<String, dynamic>>.from(supportRequests);
      _classrooms = List<Map<String, dynamic>>.from(classrooms);
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
          : IndexedStack(
              index: _currentIndex,
              children: [
                _buildDashboard(),
                _buildUserManagement(),
                _buildCourseManagement(),
              ],
            ),
      floatingActionButton: _currentIndex == 1
          ? FloatingActionButton(
              onPressed: _showCreateUserDialog,
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Panel',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_rounded),
            label: 'Kullanıcılar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.book_rounded),
            label: 'Dersler',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 28),
              const Text(
                'Destek Talepleri',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              if (_supportRequests.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text(
                      'Henüz bir destek talebi bulunmuyor.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _supportRequests.length,
                  itemBuilder: (context, i) {
                    final req = _supportRequests[i];
                    final isReplied = req['status'] == 'replied';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                req['full_name'] ?? 'İsimsiz',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isReplied
                                    ? AppColors.success.withValues(alpha: 0.1)
                                    : AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isReplied ? 'Cevaplandı' : 'Bekliyor',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isReplied
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Text(
                              req['issue'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              req['created_at'] != null
                                  ? DateTime.parse(
                                      req['created_at'],
                                    ).toLocal().toString().split('.')[0]
                                  : '',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _showSupportDetail(req),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
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
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(icon: const Icon(Icons.logout_rounded), onPressed: _signOut),
      ],
    );
  }

  void _showSupportDetail(Map<String, dynamic> request) async {
    final result = await showDialog(
      context: context,
      builder: (context) => SupportDetailDialog(request: request),
    );
    if (result == true) _loadStats();
  }

  Widget _buildUserManagement() {
    final filtered = _allUsers.where((u) {
      final matchesSearch =
          '${u['first_name']} ${u['last_name']}'.toLowerCase().contains(
            _userSearchQuery.toLowerCase(),
          ) ||
          (u['school_no']?.toString() ?? '').contains(_userSearchQuery);
      final matchesRole =
          _selectedRoleFilter == 'all' || u['role'] == _selectedRoleFilter;
      return matchesSearch && matchesRole;
    }).toList();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'İsim veya No ile Ara...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (v) => setState(() => _userSearchQuery = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildFilterChip('Hepsi', 'all'),
                _buildFilterChip('Öğrenciler', 'student'),
                _buildFilterChip('Öğretmenler', 'teacher'),
                _buildFilterChip('Adminler', 'admin'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final u = filtered[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: u['role'] == 'teacher'
                          ? AppColors.success
                          : (u['role'] == 'admin'
                                ? AppColors.warning
                                : AppColors.primary),
                      child: Text(
                        u['role']?[0].toUpperCase() ?? 'U',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      '${u['first_name'] ?? 'İsimsiz'} ${u['last_name'] ?? ''}',
                    ),
                    subtitle: Text(
                      '${u['school_no'] ?? '-'} · ${u['role'] ?? 'Rol Yok'}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openUserDetail(u),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateUserDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateUserDialog(
        onUserCreated: _loadStats,
      ),
    );
  }

  void _openUserDetail(Map<String, dynamic> user) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => UserDetailPage(user: user)),
    );
    _loadStats();
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedRoleFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) setState(() => _selectedRoleFilter = value);
        },
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }

  bool _isCourseActive(Map<String, dynamic> course) {
    final day = course['course_day'] as String?;
    final timeStr = course['course_time'] as String?;
    final endTimeStr = course['course_end_time'] as String?;

    if (day == null || timeStr == null || endTimeStr == null) return false;

    final now = DateTime.now();
    final currentDayEnglish = DateFormat('EEEE').format(now);

    if (day.toLowerCase() != currentDayEnglish.toLowerCase()) return false;

    final timeParts = timeStr.split(':');
    final endTimeParts = endTimeStr.split(':');

    if (timeParts.length < 2 || endTimeParts.length < 2) return false;

    final startTime = TimeOfDay(
      hour: int.parse(timeParts[0]),
      minute: int.parse(timeParts[1]),
    );
    final endTime = TimeOfDay(
      hour: int.parse(endTimeParts[0]),
      minute: int.parse(endTimeParts[1]),
    );
    final currentTime = TimeOfDay.fromDateTime(now);

    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;
    final currentMinutes = currentTime.hour * 60 + currentTime.minute;

    return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
  }

  Widget _buildCourseManagement() {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          onRefresh: _loadStats,
          child: ListView.builder(
            itemCount: _allCourses.length,
            itemBuilder: (context, i) {
              final c = _allCourses[i];
              final isActive = _isCourseActive(c);
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                color: isActive ? Colors.lightBlue[50] : null,
                child: ListTile(
                  title: Text(c['course_name'] ?? 'İsimsiz Ders'),
                  subtitle: isActive
                      ? const Text(
                          'Şu an aktif',
                          style: TextStyle(
                            color: Colors.lightBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openCourseDetail(c),
                ),
              );
            },
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showCreateCourseDialog,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _showCreateCourseDialog() {
    final formKey = GlobalKey<FormState>();
    final nameC = TextEditingController();
    final codeC = TextEditingController();
    String? selectedSection;
    String? selectedTeacherId;
    String? selectedClassroomId;
    String day = 'Monday';
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 11, minute: 0);
    int totalWeeks = 14;

    final dayMap = {
      'Monday': 'Pazartesi',
      'Tuesday': 'Salı',
      'Wednesday': 'Çarşamba',
      'Thursday': 'Perşembe',
      'Friday': 'Cuma',
      'Saturday': 'Cumartesi',
      'Sunday': 'Pazar',
    };

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDState) {
          String formatTime(TimeOfDay t) {
            final hour = t.hour.toString().padLeft(2, '0');
            final min = t.minute.toString().padLeft(2, '0');
            return '$hour:$min';
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(
                  Icons.add_circle_outline_rounded,
                  color: AppColors.primary,
                ),
                SizedBox(width: 8),
                Text('Yeni Ders Oluştur'),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: nameC,
                        decoration: const InputDecoration(
                          labelText: 'Ders Adı *',
                          prefixIcon: Icon(Icons.book_outlined),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Ders adı zorunludur'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: codeC,
                              decoration: const InputDecoration(
                                labelText: 'Ders Kodu *',
                                prefixIcon: Icon(Icons.tag_rounded),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Ders kodu zorunludur'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedSection,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Şube / Grup Seçin *',
                                prefixIcon: Icon(Icons.group_work_outlined),
                              ),
                              items:
                                  [
                                        'A Grubu',
                                        'B Grubu',
                                        'C Grubu',
                                        'D Grubu',
                                        'E Grubu',
                                        'F Grubu',
                                        'G Grubu',
                                      ]
                                      .map(
                                        (g) => DropdownMenuItem<String>(
                                          value: g,
                                          child: Text(g),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (v) =>
                                  setDState(() => selectedSection = v),
                              validator: (v) =>
                                  v == null ? 'Şube seçilmelidir' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Öğretmen Seçin *',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedTeacherId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          hintText: 'Hoca Seçin *',
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        items: _allUsers
                            .where((u) => u['role'] == 'teacher')
                            .map((u) {
                              final title = u['title'] != null
                                  ? '${u['title']} '
                                  : '';
                              return DropdownMenuItem(
                                value: u['id'].toString(),
                                child: Text(
                                  '$title${u['first_name']} ${u['last_name']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            })
                            .toList(),
                        onChanged: (v) =>
                            setDState(() => selectedTeacherId = v),
                        validator: (v) =>
                            v == null ? 'Öğretmen seçilmelidir' : null,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Sınıf / Lab Seçin *',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedClassroomId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          hintText: 'Sınıf Seçin *',
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        items: _classrooms
                            .map(
                              (c) => DropdownMenuItem(
                                value: c['id'].toString(),
                                child: Text(
                                  c['name'].toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setDState(() => selectedClassroomId = v),
                        validator: (v) =>
                            v == null ? 'Sınıf seçilmelidir' : null,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Ders Günü Seçin *',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: day,
                        isExpanded: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        items: dayMap.entries
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry.key,
                                child: Text(
                                  entry.value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setDState(() => day = v!),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Ders Saatleri',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: startTime,
                                );
                                if (t != null) {
                                  setDState(() {
                                    startTime = t;
                                    // Eğer başlangıç saati bitişten sonraysa veya eşitse, bitişi başlangıcın 2 saat sonrasına ayarla
                                    final startM =
                                        startTime.hour * 60 + startTime.minute;
                                    final endM =
                                        endTime.hour * 60 + endTime.minute;
                                    if (startM >= endM) {
                                      int newEndHour =
                                          (startTime.hour + 2) % 24;
                                      endTime = TimeOfDay(
                                        hour: newEndHour,
                                        minute: startTime.minute,
                                      );
                                    }
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.access_time_rounded,
                                      size: 18,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Başlangıç',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            formatTime(startTime),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: endTime,
                                );
                                if (t != null) {
                                  setDState(() {
                                    endTime = t;
                                    // Eğer bitiş saati başlangıçtan önceyse veya eşitse, başlangıcı bitişin 2 saat öncesine ayarla
                                    final startM =
                                        startTime.hour * 60 + startTime.minute;
                                    final endM =
                                        endTime.hour * 60 + endTime.minute;
                                    if (startM >= endM) {
                                      int newStartHour =
                                          (endTime.hour - 2 + 24) % 24;
                                      startTime = TimeOfDay(
                                        hour: newStartHour,
                                        minute: endTime.minute,
                                      );
                                    }
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.access_time_rounded,
                                      size: 18,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Bitiş',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            formatTime(endTime),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Hafta Sayısı',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.redAccent,
                              ),
                              onPressed: () {
                                if (totalWeeks > 1) {
                                  setDState(() => totalWeeks--);
                                }
                              },
                            ),
                            Text(
                              '$totalWeeks Hafta',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle_outline,
                                color: AppColors.success,
                              ),
                              onPressed: () => setDState(() => totalWeeks++),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) {
                    return;
                  }

                  final startMin = startTime.hour * 60 + startTime.minute;
                  final endMin = endTime.hour * 60 + endTime.minute;
                  if (startMin >= endMin) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '⚠️ Başlangıç saati bitiş saatinden önce olmalıdır!',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  final name = nameC.text.trim();
                  final code = codeC.text.trim();
                  final section = selectedSection;

                  // Çakışma Kontrolü
                  if (selectedClassroomId != null) {
                    final conflictRes = await _supabase
                        .from('courses')
                        .select('course_name, course_time, course_end_time')
                        .eq('classroom_id', selectedClassroomId!)
                        .eq('course_day', day);

                    bool hasOverlap = false;
                    String conflictCourseName = '';

                    final currentStart = startTime.hour * 60 + startTime.minute;
                    final currentEnd = endTime.hour * 60 + endTime.minute;

                    for (var c in conflictRes) {
                      final otherStartStr = c['course_time'] as String?;
                      final otherEndStr = c['course_end_time'] as String?;

                      if (otherStartStr == null || otherEndStr == null) {
                        continue;
                      }

                      final partsStart = otherStartStr.split(':');
                      final partsEnd = otherEndStr.split(':');
                      if (partsStart.length < 2 || partsEnd.length < 2) {
                        continue;
                      }

                      final otherStart =
                          int.parse(partsStart[0]) * 60 +
                          int.parse(partsStart[1]);
                      final otherEnd =
                          int.parse(partsEnd[0]) * 60 + int.parse(partsEnd[1]);

                      if (currentStart < otherEnd && currentEnd > otherStart) {
                        hasOverlap = true;
                        conflictCourseName =
                            c['course_name'] ?? 'Bilinmeyen Ders';
                        break;
                      }
                    }

                    if (hasOverlap) {
                      if (!dialogContext.mounted) return;
                      final bool? proceed = await showDialog<bool>(
                        context: dialogContext,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('⚠️ Sınıf Çakışması Uyarısı'),
                          content: Text(
                            'Seçilen sınıfta aynı gün ve saat aralığında "$conflictCourseName" dersi bulunmaktadır. Yine de oluşturmak istiyor musunuz?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Hayır, İptal'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('Evet, Oluştur'),
                            ),
                          ],
                        ),
                      );

                      if (proceed != true) return;
                    }
                  }

                  try {
                    await _supabase.from('courses').insert({
                      'course_name': name,
                      'course_code': code.isEmpty ? null : code,
                      'section': section,
                      'teacher_id': selectedTeacherId,
                      'course_day': day,
                      'course_time': '${formatTime(startTime)}:00',
                      'course_end_time': '${formatTime(endTime)}:00',
                      'classroom_id': selectedClassroomId,
                      'total_weeks': totalWeeks,
                      'attendance_interval_hours': 2,
                    });

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ders başarıyla oluşturuldu'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        _loadStats();
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Hata: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Oluştur'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openCourseDetail(Map<String, dynamic> course) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CourseDetailPage(course: course)),
    ).then((_) => _loadStats());
  }
}

class CreateUserDialog extends StatefulWidget {
  final VoidCallback? onUserCreated;
  const CreateUserDialog({super.key, this.onUserCreated});

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController surnameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController schoolNoController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  String selectedRole = "Öğrenci";
  String? selectedTitle;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(
            Icons.person_add_alt_1_rounded,
            color: AppColors.primary,
          ),
          SizedBox(width: 8),
          Text('Yeni Kullanıcı Oluştur'),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// AD
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "Ad *",
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Ad alanı zorunludur' : null,
                ),

                const SizedBox(height: 12),

                /// SOYAD
                TextFormField(
                  controller: surnameController,
                  decoration: const InputDecoration(
                    labelText: "Soyad *",
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Soyad alanı zorunludur' : null,
                ),

                const SizedBox(height: 12),

                /// EMAIL
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "E-posta *",
                    prefixIcon: Icon(Icons.email),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'E-posta alanı zorunludur';
                    if (!v.contains('@')) return 'Geçerli bir e-posta adresi girin';
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                /// OKUL / SICIL NO
                TextFormField(
                  controller: schoolNoController,
                  decoration: const InputDecoration(
                    labelText: "Okul / Sicil No *",
                    prefixIcon: Icon(Icons.badge),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Okul / Sicil No zorunludur';
                    if (selectedRole == 'Öğretmen' && !v.trim().startsWith('t')) {
                      return 'Hoca okul numarası "t" ile başlamalıdır!';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                /// ŞİFRE
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Şifre *",
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Şifre alanı zorunludur';
                    if (v.length < 6) return 'Şifre en az 6 karakter olmalıdır';
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                /// ROL
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: "Öğrenci", child: Text("Öğrenci")),
                    DropdownMenuItem(value: "Öğretmen", child: Text("Öğretmen")),
                    DropdownMenuItem(value: "Admin", child: Text("Admin")),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedRole = value!;
                      if (selectedRole != 'Öğretmen') selectedTitle = null;
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: "Rol *",
                    prefixIcon: Icon(Icons.manage_accounts),
                  ),
                  validator: (v) => v == null ? 'Rol seçilmelidir' : null,
                ),

                if (selectedRole == 'Öğretmen') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTitle,
                    hint: const Text('Akademik Ünvan Seçin'),
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'Prof. Dr.', child: Text('Prof. Dr.')),
                      DropdownMenuItem(value: 'Doç. Dr.', child: Text('Doç. Dr.')),
                      DropdownMenuItem(value: 'Dr. Öğr. Üyesi', child: Text('Dr. Öğr. Üyesi')),
                      DropdownMenuItem(value: 'Öğr. Gör.', child: Text('Öğr. Gör.')),
                      DropdownMenuItem(value: 'Arş. Gör.', child: Text('Arş. Gör.')),
                      DropdownMenuItem(value: 'Dr.', child: Text('Dr.')),
                      DropdownMenuItem(value: 'Öğr. Gör. Dr.', child: Text('Öğr. Gör. Dr.')),
                    ],
                    onChanged: (v) => setState(() => selectedTitle = v),
                    decoration: const InputDecoration(
                      labelText: "Ünvan *",
                      prefixIcon: Icon(Icons.school_outlined),
                    ),
                    validator: (v) => (selectedRole == 'Öğretmen' && v == null)
                        ? 'Ünvan seçilmelidir'
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_formKey.currentState!.validate()) {
                setState(() => _isLoading = true);
                try {
                  final email = emailController.text.trim();
                  final password = passwordController.text.trim();
                  final firstName = nameController.text.trim();
                  final lastName = surnameController.text.trim();
                  final schoolNo = schoolNoController.text.trim();

                  String dbRole = 'student';
                  if (selectedRole == 'Öğretmen') dbRole = 'teacher';
                  if (selectedRole == 'Admin') dbRole = 'admin';

                  final supabase = Supabase.instance.client;

                  // 1. Auth hesabı oluştur
                  final res = await supabase.auth.signUp(
                    email: email,
                    password: password,
                    data: {
                      'first_name': firstName,
                      'last_name': lastName,
                      'school_no': schoolNo,
                      'role': dbRole,
                    },
                  );
                  final userId = res.user?.id;

                  if (userId != null) {
                    // 2. Users tablosuna ekle
                    await supabase.from('users').insert({
                      'id': userId,
                      'email': email,
                      'first_name': firstName,
                      'last_name': lastName,
                      'school_no': schoolNo,
                      'role': dbRole,
                      'title': selectedTitle,
                    });

                    if (!mounted) return;

                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Kullanıcı başarıyla oluşturuldu'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                    widget.onUserCreated?.call();
                    // ignore: use_build_context_synchronously
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (!mounted) return;
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              }
            },
            child: const Text('Oluştur'),
          ),
        ]
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  String _userSearchQuery = '';
  String _selectedRoleFilter = 'all'; // all, student, teacher

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final users = await _supabase.from('users').select('id, first_name, last_name, school_no, role, email');
    final courses = await _supabase.from('courses').select('id, course_name, course_code, teacher_id, users(first_name, last_name)');
    final supportRequests = await _supabase
        .from('support_requests')
        .select('*')
        .order('created_at', ascending: false);

    if (!mounted) return;
    setState(() {
      _allUsers = List<Map<String, dynamic>>.from(users);
      _allCourses = List<Map<String, dynamic>>.from(courses);
      _supportRequests = List<Map<String, dynamic>>.from(supportRequests);
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
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : IndexedStack(
              index: _currentIndex,
              children: [
          _buildDashboard(),
          _buildUserManagement(),
          _buildCourseManagement(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Panel'),
          BottomNavigationBarItem(icon: Icon(Icons.people_rounded), label: 'Kullanıcılar'),
          BottomNavigationBarItem(icon: Icon(Icons.book_rounded), label: 'Dersler'),
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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              if (_supportRequests.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text('Henüz bir destek talebi bulunmuyor.', style: TextStyle(color: AppColors.textSecondary)),
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
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isReplied ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isReplied ? 'Cevaplandı' : 'Bekliyor',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isReplied ? AppColors.success : AppColors.warning,
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
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              req['created_at'] != null ? DateTime.parse(req['created_at']).toLocal().toString().split('.')[0] : '',
                              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
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
          width: 44, height: 44,
          decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Yönetim Paneli', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              Text('BEACONTrack', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
      final matchesSearch = '${u['first_name']} ${u['last_name']}'.toLowerCase().contains(_userSearchQuery.toLowerCase()) ||
                            (u['school_no']?.toString() ?? '').contains(_userSearchQuery);
      final matchesRole = _selectedRoleFilter == 'all' || u['role'] == _selectedRoleFilter;
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                _buildFilterChip('Hocalar', 'teacher'),
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
                      backgroundColor: u['role'] == 'teacher' ? AppColors.success : (u['role'] == 'admin' ? AppColors.warning : AppColors.primary),
                      child: Text(u['role']?[0].toUpperCase() ?? 'U', style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text('${u['first_name'] ?? 'İsimsiz'} ${u['last_name'] ?? ''}'),
                    subtitle: Text('${u['school_no'] ?? '-'} · ${u['role'] ?? 'Rol Yok'}'),
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
        labelStyle: TextStyle(color: isSelected ? AppColors.primary : AppColors.textSecondary),
      ),
    );
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
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: ListTile(
                  title: Text(c['course_name'] ?? 'İsimsiz Ders'),
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
    final nameC = TextEditingController();
    final codeC = TextEditingController();
    String? selectedTeacherId;
    String day = 'Monday';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: const Text('Yeni Ders Oluştur'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Ders Adı')),
                TextField(controller: codeC, decoration: const InputDecoration(labelText: 'Ders Kodu')),
                const Divider(),
                const Text('Öğretmen Seçin', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: selectedTeacherId,
                  hint: const Text('Hoca Seçin'),
                  isExpanded: true,
                  items: _allUsers.where((u) => u['role'] == 'teacher').map((u) => DropdownMenuItem(
                    value: u['id'].toString(),
                    child: Text('${u['first_name']} ${u['last_name']}'),
                  )).toList(),
                  onChanged: (v) => setDState(() => selectedTeacherId = v),
                ),
                const SizedBox(height: 12),
                const Text('Ders Günü', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: day,
                  isExpanded: true,
                  items: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'].map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) => setDState(() => day = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
            ElevatedButton(onPressed: () async {
              if (nameC.text.isEmpty || selectedTeacherId == null) return;
              
              await _supabase.from('courses').insert({
                'course_name': nameC.text,
                'course_code': codeC.text,
                'teacher_id': selectedTeacherId,
                'course_day': day,
                'course_time': '09:00:00',
              });
              
              Navigator.pop(context);
              _loadStats();
            }, child: const Text('Oluştur')),
          ],
        ),
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

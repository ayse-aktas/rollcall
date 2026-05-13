import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/theme/colors/app_colors.dart';

const List<String> kAcademicTitles = [
  'Prof.Dr.',
  'Doç.Dr.',
  'Dr.Öğr.Üyesi',
  'Öğr.Gör.',
  'Arş.Gör.',
  'Dr.',
  '-',
];

class UserDetailPage extends StatefulWidget {
  final Map<String, dynamic> user;
  const UserDetailPage({super.key, required this.user});

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _studentCourses = [];
  bool _isLoading = true;
  String? _selectedTitle;

  @override
  void initState() {
    super.initState();
    _selectedTitle = widget.user['title'] as String?;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final res = await _supabase
          .from('student_courses')
          .select('*, courses(*)')
          .eq('student_id', widget.user['id']);

      if (!mounted) return;
      setState(() {
        _studentCourses = List<Map<String, dynamic>>.from(res);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dersler getirilemedi: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveTitle(String? title) async {
    try {
      await _supabase
          .from('users')
          .update({'title': (title == '-' || title == null) ? null : title})
          .eq('id', widget.user['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unvan güncellendi'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTeacher = widget.user['role'] == 'teacher';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${widget.user['first_name']} ${widget.user['last_name']}'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProfileSection(isTeacher),
                  const SizedBox(height: 24),
                  if (widget.user['role'] == 'student') ...[
                    const Text('Kayıtlı Dersler',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ..._studentCourses.map((sc) => _buildCourseCard(sc)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildProfileSection(bool isTeacher) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.email_outlined, 'E-posta', widget.user['email'] ?? '-'),
          _buildInfoRow(Icons.badge_outlined, 'Okul No', widget.user['school_no']?.toString() ?? '-'),
          _buildInfoRow(Icons.person_outline, 'Rol', _roleLabel(widget.user['role'])),
          if (isTeacher) ...[
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.school_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: 12),
                const Text('Akademik Unvan',
                    style: TextStyle(color: AppColors.textSecondary)),
                const Spacer(),
                DropdownButton<String>(
                  value: kAcademicTitles.contains(_selectedTitle) ? _selectedTitle : '-',
                  underline: const SizedBox(),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                  items: kAcademicTitles
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedTitle = v);
                    _saveTitle(v);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _roleLabel(String? role) {
    const map = {
      'student': 'Öğrenci',
      'teacher': 'Öğretim Elemanı',
      'admin': 'Yönetici',
    };
    return map[role] ?? role ?? '-';
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> sc) {
    final course = sc['courses'] as Map<String, dynamic>? ?? {};
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(course['course_name'] ?? 'İsimsiz Ders'),
        subtitle: Text(course['course_code'] ?? '-'),
        children: [
          _AttendanceList(studentId: widget.user['id'], courseId: course['id']),
        ],
      ),
    );
  }
}

class _AttendanceList extends StatefulWidget {
  final String studentId;
  final String courseId;
  const _AttendanceList({required this.studentId, required this.courseId});

  @override
  State<_AttendanceList> createState() => _AttendanceListState();
}

class _AttendanceListState extends State<_AttendanceList> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final res = await _supabase
        .from('attendance')
        .select('*')
        .eq('student_id', widget.studentId)
        .eq('course_id', widget.courseId)
        .order('date', ascending: false)
        .order('slot', ascending: true);

    if (!mounted) return;
    setState(() {
      _records = List<Map<String, dynamic>>.from(res);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator();
    if (_records.isEmpty) {
      return const Padding(padding: EdgeInsets.all(16), child: Text('Yoklama kaydı bulunamadı.'));
    }

    return Column(
      children: _records.map((r) {
        final slot = r['slot'] as int? ?? 1;
        final slotLabel = slot > 1 ? ' · ${slot}. Ders' : '';
        return ListTile(
          title: Text('${r['date'] ?? '-'}$slotLabel'),
          subtitle: Text(r['is_present'] == true ? 'Geldi' : 'Gelmedi'),
          trailing: IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _showUpdateDialog(r),
          ),
        );
      }).toList(),
    );
  }

  void _showUpdateDialog(Map<String, dynamic> record) {
    final commentC = TextEditingController();
    final docC = TextEditingController();
    bool newIsPresent = record['is_present'] != true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: const Text('Yoklama Güncelle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mevcut Durum: ${record['is_present'] == true ? 'Geldi' : 'Gelmedi'}'),
              const SizedBox(height: 12),
              DropdownButton<bool>(
                value: newIsPresent,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: true, child: Text('Geldi')),
                  DropdownMenuItem(value: false, child: Text('Gelmedi')),
                ],
                onChanged: (v) => setDState(() => newIsPresent = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentC,
                decoration: const InputDecoration(
                    labelText: 'Açıklama (Zorunlu)', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: docC,
                decoration: const InputDecoration(
                    labelText: 'Dilekçe/Belge Kodu (Opsiyonel)',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () async {
                if (commentC.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lütfen açıklama yazın!')));
                  return;
                }
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Onay Gerekiyor'),
                    content: const Text(
                        'Bu yoklama değişikliğini kaydetmek istediğinize emin misiniz?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Hayır')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Evet, Kaydet')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _performUpdate(record, newIsPresent, commentC.text, docC.text);
                  if (mounted) Navigator.pop(context);
                }
              },
              child: const Text('Güncelle ve Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performUpdate(Map<String, dynamic> record, bool newIsPresent,
      String comment, String docCode) async {
    try {
      final adminId = _supabase.auth.currentUser?.id;
      await _supabase
          .from('attendance')
          .update({'is_present': newIsPresent})
          .eq('id', record['id']);
      await _supabase.from('attendance_logs').insert({
        'attendance_id': record['id'],
        'admin_id': adminId,
        'old_status': record['is_present'] == true ? 'Geldi' : 'Gelmedi',
        'new_status': newIsPresent ? 'Geldi' : 'Gelmedi',
        'comment': comment,
        'document_code': docCode,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Yoklama başarıyla güncellendi.'),
              backgroundColor: AppColors.success),
        );
      }
      _loadRecords();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Kayıt sırasında bir hata oluştu: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5)),
        );
      }
    }
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/theme/colors/app_colors.dart';

const List<String> kAcademicTitles = [
  'Prof. Dr.',
  'Doç. Dr.',
  'Dr. Öğr. Üyesi',
  'Öğr. Gör.',
  'Arş. Gör.',
  'Dr.',
  'Öğr. Gör. Dr.',
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
  List<Map<String, dynamic>> _teacherCourses = [];
  List<Map<String, dynamic>> _allTeachers = [];
  bool _isLoading = true;
  bool _isEditing = false;
  String? _selectedTitle;
  String? _selectedRole;
  
  late TextEditingController _emailC;
  late TextEditingController _schoolNoC;

  @override
  void initState() {
    super.initState();
    _selectedTitle = widget.user['title'] as String?;
    _selectedRole = widget.user['role'] as String?;
    _emailC = TextEditingController(text: widget.user['email']);
    _schoolNoC = TextEditingController(text: widget.user['school_no']?.toString() ?? '');
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Öğrenci ise kayıtlı derslerini çek
      if (widget.user['role'] == 'student') {
        final res = await _supabase
            .from('student_courses')
            .select('*, courses(*)')
            .eq('student_id', widget.user['id']);
        _studentCourses = List<Map<String, dynamic>>.from(res);
      }

      // Hoca ise verdiği dersleri çek
      if (widget.user['role'] == 'teacher') {
        final res = await _supabase
            .from('courses')
            .select('*')
            .or('teacher_id.eq.${widget.user['id']},assigned_teacher_id.eq.${widget.user['id']}');
        _teacherCourses = List<Map<String, dynamic>>.from(res);
      }

      // Tüm hocaları çek (Ders devri için)
      final teachersRes = await _supabase
          .from('users')
          .select('id, first_name, last_name, title')
          .eq('role', 'teacher')
          .neq('id', widget.user['id']);
      _allTeachers = List<Map<String, dynamic>>.from(teachersRes);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veriler getirilemedi: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final isTeacher = _selectedRole == 'teacher';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${widget.user['first_name']} ${widget.user['last_name']}'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.save_rounded : Icons.edit_rounded, color: _isEditing ? AppColors.success : AppColors.primary),
            onPressed: () {
              if (_isEditing) {
                _saveUserInfo();
              } else {
                setState(() => _isEditing = true);
              }
            },
          ),
        ],
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
                  if (_selectedRole == 'student') ...[
                    const Text('Kayıtlı Dersler',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ..._studentCourses.map((sc) => _buildCourseCard(sc)),
                  ],
                  if (_selectedRole == 'teacher') ...[
                    const Text('Verdiği Dersler',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ..._teacherCourses.map((c) => _buildTeacherCourseCard(c)),
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
          _isEditing
              ? _buildEditableRow(Icons.email_outlined, 'E-posta', _emailC)
              : _buildInfoRow(Icons.email_outlined, 'E-posta', _emailC.text),
          _isEditing
              ? _buildEditableRow(Icons.badge_outlined, 'Okul No', _schoolNoC)
              : _buildInfoRow(Icons.badge_outlined, 'Okul No', _schoolNoC.text),
          _isEditing
              ? _buildRoleDropdown()
              : _buildInfoRow(Icons.person_outline, 'Rol', _roleLabel(_selectedRole)),
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
                  onChanged: _isEditing ? (v) {
                    setState(() => _selectedTitle = v);
                  } : null,
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

  Widget _buildEditableRow(IconData icon, String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(width: 24),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          const Text('Rol', style: TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          DropdownButton<String>(
            value: _selectedRole,
            underline: const SizedBox(),
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            items: const [
              DropdownMenuItem(value: 'student', child: Text('Öğrenci')),
              DropdownMenuItem(value: 'teacher', child: Text('Öğretim Elemanı')),
              DropdownMenuItem(value: 'admin', child: Text('Yönetici')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedRole = v);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherCourseCard(Map<String, dynamic> course) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(course['course_name'] ?? 'İsimsiz Ders'),
        subtitle: Text('${course['course_code'] ?? '-'} · ${course['course_day'] ?? '-'} ${course['course_time'] ?? ''}'),
        trailing: ElevatedButton.icon(
          onPressed: () => _showReassignDialog(course),
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: const Text('Ata'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary.withOpacity(0.1),
            foregroundColor: AppColors.primary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
        ),
      ),
    );
  }

  Future<void> _saveUserInfo() async {
    // Validasyonlar
    final email = _emailC.text.trim();
    final schoolNo = _schoolNoC.text.trim();

    if (email.isEmpty || schoolNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-posta ve Okul No boş bırakılamaz!'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_selectedRole == 'teacher' && !schoolNo.startsWith('t')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hoca okul numarası "t" ile başlamalıdır!'), backgroundColor: Colors.red),
      );
      return;
    }

    // Rol değişikliği kontrolü
    if (widget.user['role'] == 'teacher' && _selectedRole != 'teacher' && _teacherCourses.isNotEmpty) {
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('⚠️ Dikkat'),
          content: const Text('Bu hocanın üzerinde aktif dersler bulunmaktadır. Rolü değiştirmeden önce lütfen dersleri başka akademisyenlere atayın.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Tamam')),
          ],
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Okul no benzersizlik kontrolü
      final existing = await _supabase
          .from('users')
          .select('id')
          .eq('school_no', schoolNo)
          .neq('id', widget.user['id']);

      if (existing.isNotEmpty) {
        throw 'Bu okul numarası başka bir kullanıcı tarafından kullanılıyor!';
      }

      await _supabase.from('users').update({
        'email': email,
        'school_no': schoolNo,
        'role': _selectedRole,
        'title': _selectedTitle == '-' ? null : _selectedTitle,
      }).eq('id', widget.user['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı bilgileri güncellendi'), backgroundColor: AppColors.success),
        );
        setState(() {
          _isEditing = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  String _teacherLabel(Map<String, dynamic> t) {
    final title = t['title'] != null ? '${t['title']} ' : '';
    return '$title${t['first_name']} ${t['last_name']}';
  }

  int _timeToMinutes(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length < 2) return 0;
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  void _showReassignDialog(Map<String, dynamic> course) {
    String? selectedTeacherId;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: const Text('Dersi Başkasına Ata'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('"${course['course_name']}" dersini kime atamak istiyorsunuz?'),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: selectedTeacherId,
                hint: const Text('Hoca Seçin'),
                isExpanded: true,
                items: _allTeachers.map((t) => DropdownMenuItem(
                  value: t['id'].toString(),
                  child: Text(_teacherLabel(t)),
                )).toList(),
                onChanged: (v) => setDState(() => selectedTeacherId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () async {
                if (selectedTeacherId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen bir hoca seçin!'), backgroundColor: Colors.red),
                  );
                  return;
                }
                
                final targetTeacherId = selectedTeacherId!;
                final courseDay = course['course_day'] as String?;
                final courseTime = course['course_time'] as String?;
                final courseEndTime = course['course_end_time'] as String?;
                
                if (courseDay != null && courseTime != null && courseEndTime != null) {
                  final targetCourses = await _supabase
                      .from('courses')
                      .select('course_name, course_time, course_end_time')
                      .or('teacher_id.eq.$targetTeacherId,assigned_teacher_id.eq.$targetTeacherId')
                      .eq('course_day', courseDay);
                      
                  bool hasOverlap = false;
                  String conflictCourseName = '';
                  
                  final currentStart = _timeToMinutes(courseTime);
                  final currentEnd = _timeToMinutes(courseEndTime);
                  
                  for (var tc in targetCourses) {
                    final otherStartStr = tc['course_time'] as String?;
                    final otherEndStr = tc['course_end_time'] as String?;
                    
                    if (otherStartStr == null || otherEndStr == null) continue;
                    
                    final otherStart = _timeToMinutes(otherStartStr);
                    final otherEnd = _timeToMinutes(otherEndStr);
                    
                    if (currentStart < otherEnd && currentEnd > otherStart) {
                      hasOverlap = true;
                      conflictCourseName = tc['course_name'] ?? 'Bilinmeyen Ders';
                      break;
                    }
                  }
                  
                  if (hasOverlap) {
                    final bool? proceed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('⚠️ Çakışma Uyarısı'),
                        content: Text('Bu hocanın o gün ve saatte "$conflictCourseName" dersi bulunmaktadır. Yine de devam etmek istiyor musunuz?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hayır, İptal')),
                          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Evet, Devam Et')),
                        ],
                      ),
                    );
                    
                    if (proceed != true) return;
                  }
                }
                
                try {
                  await _supabase
                      .from('courses')
                      .update({'teacher_id': targetTeacherId})
                      .eq('id', course['id']);
                      
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ders başarıyla devredildi'), backgroundColor: AppColors.success),
                    );
                    Navigator.pop(context);
                    _loadData();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Ata'),
            ),
          ],
        ),
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

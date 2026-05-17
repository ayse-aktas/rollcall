import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/theme/colors/app_colors.dart';

class TeacherDelegatePage extends StatefulWidget {
  final Map<String, dynamic> course;

  const TeacherDelegatePage({super.key, required this.course});

  @override
  State<TeacherDelegatePage> createState() => _TeacherDelegatePageState();
}

class _TeacherDelegatePageState extends State<TeacherDelegatePage> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _filtered = [];
  String? _currentAssignedId;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _currentAssignedId = widget.course['assigned_teacher_id']?.toString();
    _selectedId = _currentAssignedId;
    _loadTeachers();
    _searchController.addListener(_filterTeachers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTeachers() async {
    final myId = _supabase.auth.currentUser?.id;
    try {
      final res = await _supabase
          .from('users')
          .select('id, first_name, last_name, title, school_no')
          .eq('role', 'teacher')
          .order('first_name');

      final list = List<Map<String, dynamic>>.from(res)
          .where((u) => u['id'] != myId) // don't show yourself
          .toList();

      if (!mounted) return;
      setState(() {
        _teachers = list;
        _filtered = list;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Teachers could not be loaded: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hocalar yüklenirken hata oluştu: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _filterTeachers() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _teachers.where((t) {
        final name = '${t['first_name']} ${t['last_name']}'.toLowerCase();
        final no = (t['school_no'] ?? '').toString();
        final title = (t['title'] ?? '').toLowerCase();
        return name.contains(q) || no.contains(q) || title.contains(q);
      }).toList();
    });
  }

  String _teacherLabel(Map<String, dynamic> t) {
    final title = t['title'] != null ? '${t['title']} ' : '';
    return '$title${t['first_name']} ${t['last_name']}';
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final myId = _supabase.auth.currentUser?.id;
    try {
      // 1. Update the course
      await _supabase.from('courses').update({
        'assigned_teacher_id': _selectedId,
      }).eq('id', widget.course['id']);

      // 2. Send notification to the new teacher (if assigned)
      if (_selectedId != null && _selectedId != _currentAssignedId) {
        final myProfile = await _supabase.from('users').select('first_name, last_name, title').eq('id', myId!).single();
        final senderName = '${myProfile['title'] ?? ''} ${myProfile['first_name']} ${myProfile['last_name']}'.trim();
        
        await _supabase.from('notifications').insert({
          'user_id': _selectedId,
          'title': 'Yeni Ders Ataması',
          'message': '$senderName hocamız size "${widget.course['course_name']}" dersini devretti.',
          'type': 'course_assignment',
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // 3. Send notification to the old teacher (if revoked)
      if (_selectedId == null && _currentAssignedId != null) {
        await _supabase.from('notifications').insert({
          'user_id': _currentAssignedId,
          'title': 'Ders Ataması İptal Edildi',
          'message': '"${widget.course['course_name']}" dersi üzerinizden geri alındı.',
          'type': 'course_revocation',
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (mounted) {
        final msg = _selectedId == null
            ? 'Ders devri iptal edildi'
            : 'Ders başarıyla devredildi';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final courseName = widget.course['course_name'] ?? '';
    final courseCode = widget.course['course_code'] ?? '';
    final section = widget.course['section'] != null ? ' · Şube ${widget.course['section']}' : '';
    final hasChanged = _selectedId != _currentAssignedId;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Dersi Devret', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Course Info Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(courseName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('$courseCode$section',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Revoke button if there's an active assignment
                if (_currentAssignedId != null)
                  _buildCurrentAssigneeCard(),
                if (_currentAssignedId != null) const SizedBox(height: 16),

                const Text('Dersi Devredecek Kişi',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('Seçilen kişi bu ders için tam yetkiye sahip olacak.',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Ad, soyad veya okul no ile ara...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _filtered.isEmpty
                    ? const Center(child: Text('Sonuç bulunamadı', style: TextStyle(color: AppColors.textSecondary)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final teacher = _filtered[index];
                          final tid = teacher['id'].toString();
                          final isSelected = _selectedId == tid;
                          final title = teacher['title'] != null ? '${teacher['title']} ' : '';

                          return GestureDetector(
                            onTap: () => setState(() => _selectedId = isSelected ? null : tid),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? AppColors.primary : AppColors.border,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isSelected ? AppColors.primary : AppColors.surfaceLight,
                                    child: Text(
                                      (teacher['first_name'] ?? 'T')[0].toUpperCase(),
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$title${teacher['first_name']} ${teacher['last_name']}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          teacher['school_no'] ?? '-',
                                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle_rounded, color: AppColors.primary),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: (hasChanged && _selectedId != null)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedId == null ? Colors.redAccent : AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: Icon(
                    _selectedId == null ? Icons.undo_rounded : Icons.swap_horiz_rounded,
                    color: Colors.white,
                  ),
                  label: Text(
                    _selectedId == null ? 'Devri İptal Et' : '${_teacherLabel(_filtered.firstWhere((t) => t['id'].toString() == _selectedId!, orElse: () => {}))} — Devret',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildCurrentAssigneeCard() {
    final current = _teachers.where((t) => t['id'].toString() == _currentAssignedId).firstOrNull;
    if (current == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Mevcut Devir', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                Text(_teacherLabel(current), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showCancelConfirmation(context),
            child: const Text('İptal Et', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  void _showCancelConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Devri İptal Et'),
        content: const Text('Bu dersin devrini iptal etmek istediğinize emin misiniz? Yetki tekrar sizde olacaktır.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              setState(() => _selectedId = null);
              _save(); // Directly save!
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Evet, İptal Et', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

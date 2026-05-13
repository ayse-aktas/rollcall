import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/theme/colors/app_colors.dart';

class CourseDetailPage extends StatefulWidget {
  final Map<String, dynamic> course;
  const CourseDetailPage({super.key, required this.course});

  @override
  State<CourseDetailPage> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends State<CourseDetailPage> {
  final _supabase = Supabase.instance.client;
  late TextEditingController _nameC;
  late TextEditingController _codeC;
  late TextEditingController _classroomC;
  late TextEditingController _sectionC;
  String? _selectedTeacherId;
  String? _selectedAssignedTeacherId;
  String? _selectedDay;
  int _attendanceIntervalHours = 0;
  List<Map<String, dynamic>> _teachers = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController(text: widget.course['course_name']);
    _codeC = TextEditingController(text: widget.course['course_code']);
    _classroomC = TextEditingController(text: widget.course['classroom'] ?? '');
    _sectionC = TextEditingController(text: widget.course['section'] ?? '');
    _selectedTeacherId = widget.course['teacher_id']?.toString();
    _selectedAssignedTeacherId = widget.course['assigned_teacher_id']?.toString();
    _selectedDay = widget.course['course_day'];
    _attendanceIntervalHours = (widget.course['attendance_interval_hours'] as int?) ?? 0;
    _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    final res = await _supabase
        .from('users')
        .select('id, first_name, last_name, title')
        .eq('role', 'teacher')
        .order('first_name');
    setState(() => _teachers = List<Map<String, dynamic>>.from(res));
  }

  String _teacherLabel(Map<String, dynamic> t) {
    final title = t['title'] != null ? '${t['title']} ' : '';
    return '$title${t['first_name']} ${t['last_name']}';
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      await _supabase.from('courses').update({
        'course_name': _nameC.text,
        'course_code': _codeC.text,
        'classroom': _classroomC.text,
        'section': _sectionC.text.trim().isEmpty ? null : _sectionC.text.trim(),
        'teacher_id': _selectedTeacherId,
        'assigned_teacher_id': _selectedAssignedTeacherId,
        'course_day': _selectedDay,
        'attendance_interval_hours': _attendanceIntervalHours,
      }).eq('id', widget.course['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ders güncellendi'), backgroundColor: AppColors.success));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ders Düzenle'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          if (_isSaving)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(icon: const Icon(Icons.check_rounded), onPressed: _saveChanges),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField(_nameC, 'Ders Adı', Icons.book_outlined),
            _buildTextField(_codeC, 'Ders Kodu', Icons.tag_rounded),
            _buildTextField(_classroomC, 'Sınıf / Lab', Icons.meeting_room_outlined),
            _buildTextField(_sectionC, 'Şube (A, B, C ... boş bırakılabilir)', Icons.group_work_outlined),
            const SizedBox(height: 16),
            _buildSectionHeader('Ana Öğretmen'),
            const SizedBox(height: 8),
            _buildTeacherDropdown(
              label: 'Ana Hoca',
              value: _selectedTeacherId,
              onChanged: (v) => setState(() => _selectedTeacherId = v),
            ),
            const SizedBox(height: 16),
            _buildSectionHeader('Atanan Öğretmen (Ders Devri)'),
            const SizedBox(height: 4),
            Text(
              'Boş bırakılırsa ana hoca işler. Devredilirse atanan kişi tam yetkiye sahip olur.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            _buildTeacherDropdown(
              label: 'Atanan Hoca (Devir)',
              value: _selectedAssignedTeacherId,
              allowNull: true,
              onChanged: (v) => setState(() => _selectedAssignedTeacherId = v),
            ),
            const SizedBox(height: 16),
            _buildSectionHeader('Ders Günü'),
            const SizedBox(height: 8),
            _buildDayDropdown(),
            const SizedBox(height: 16),
            _buildSectionHeader('Yoklama Aralığı'),
            const SizedBox(height: 4),
            Text(
              'Saatlik yoklama: 0 = Tek yoklama (gün başında), 1+ = Her X saatte bir yoklama alınır.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            _buildIntervalSelector(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary));
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildTeacherDropdown({
    required String label,
    required String? value,
    bool allowNull = false,
    required void Function(String?) onChanged,
  }) {
    final items = [
      if (allowNull)
        const DropdownMenuItem<String>(value: null, child: Text('— Devir Yok —')),
      ..._teachers.map((t) => DropdownMenuItem(
            value: t['id'].toString(),
            child: Text(_teacherLabel(t)),
          )),
    ];

    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildDayDropdown() {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const dayLabels = {
      'Monday': 'Pazartesi', 'Tuesday': 'Salı', 'Wednesday': 'Çarşamba',
      'Thursday': 'Perşembe', 'Friday': 'Cuma', 'Saturday': 'Cumartesi', 'Sunday': 'Pazar'
    };
    return DropdownButtonFormField<String>(
      value: _selectedDay,
      decoration: InputDecoration(
        labelText: 'Ders Günü',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      items: days
          .map((d) => DropdownMenuItem(value: d, child: Text(dayLabels[d] ?? d)))
          .toList(),
      onChanged: (v) => setState(() => _selectedDay = v),
    );
  }

  Widget _buildIntervalSelector() {
    final options = [
      (0, 'Tek Yoklama'),
      (1, 'Her 1 Saat'),
      (2, 'Her 2 Saat'),
      (3, 'Her 3 Saat'),
    ];
    return Wrap(
      spacing: 8,
      children: options.map((opt) {
        final isSelected = _attendanceIntervalHours == opt.$1;
        return ChoiceChip(
          label: Text(opt.$2),
          selected: isSelected,
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          onSelected: (_) => setState(() => _attendanceIntervalHours = opt.$1),
        );
      }).toList(),
    );
  }
}

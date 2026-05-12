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
  String? _selectedTeacherId;
  String? _selectedDay;
  List<Map<String, dynamic>> _teachers = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController(text: widget.course['course_name']);
    _codeC = TextEditingController(text: widget.course['course_code']);
    _classroomC = TextEditingController(text: widget.course['classroom'] ?? '');
    _selectedTeacherId = widget.course['teacher_id']?.toString();
    _selectedDay = widget.course['course_day'];
    _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    final res = await _supabase.from('users').select('id, first_name, last_name').eq('role', 'teacher');
    setState(() => _teachers = List<Map<String, dynamic>>.from(res));
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      await _supabase.from('courses').update({
        'course_name': _nameC.text,
        'course_code': _codeC.text,
        'classroom': _classroomC.text,
        'teacher_id': _selectedTeacherId,
        'course_day': _selectedDay,
      }).eq('id', widget.course['id']);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ders güncellendi')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
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
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(icon: const Icon(Icons.check_rounded), onPressed: _saveChanges),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildTextField(_nameC, 'Ders Adı'),
            _buildTextField(_codeC, 'Ders Kodu'),
            _buildTextField(_classroomC, 'Sınıf / Lab'),
            const SizedBox(height: 16),
            _buildTeacherDropdown(),
            const SizedBox(height: 16),
            _buildDayDropdown(),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildTeacherDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedTeacherId,
      decoration: InputDecoration(
        labelText: 'Öğretmen',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      items: _teachers.map((t) => DropdownMenuItem(
        value: t['id'].toString(),
        child: Text('${t['first_name']} ${t['last_name']}'),
      )).toList(),
      onChanged: (v) => setState(() => _selectedTeacherId = v),
    );
  }

  Widget _buildDayDropdown() {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return DropdownButtonFormField<String>(
      value: _selectedDay,
      decoration: InputDecoration(
        labelText: 'Ders Günü',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      items: days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
      onChanged: (v) => setState(() => _selectedDay = v),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
  late TextEditingController _sectionC;
  late TextEditingController _startTimeC;
  late TextEditingController _endTimeC;
  String? _selectedTeacherId;
  String? _selectedAssignedTeacherId;
  String? _selectedDay;
  String? _selectedClassroomId;
  int _attendanceIntervalHours = 0;
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _classrooms = [];
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _otherCoursesInClassroom = [];
  Set<String> _selectedSessions = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController(text: widget.course['course_name']);
    _codeC = TextEditingController(text: widget.course['course_code']);
    _sectionC = TextEditingController(text: widget.course['section'] ?? '');
    _startTimeC = TextEditingController(text: widget.course['course_time'] ?? '09:00');
    _endTimeC = TextEditingController(text: widget.course['course_end_time'] ?? '11:00');
    _selectedTeacherId = widget.course['teacher_id']?.toString();
    _selectedAssignedTeacherId = widget.course['assigned_teacher_id']?.toString();
    _selectedDay = widget.course['course_day'];
    _selectedClassroomId = widget.course['classroom_id']?.toString();
    _attendanceIntervalHours = (widget.course['attendance_interval_hours'] as int?) ?? 0;
    _loadTeachers();
    _loadClassrooms();
    _loadSessions();
    _loadOtherCourses();
  }

  Future<void> _loadSessions() async {
    try {
      final res = await _supabase
          .from('attendance')
          .select('date, created_at')
          .eq('course_id', widget.course['id'])
          .order('created_at', ascending: false);

      final Map<String, Map<String, dynamic>> sessionsMap = {};
      for (var row in res) {
        final date = row['date'] as String;
        final createdAt = row['created_at'] as String?;
        if (createdAt != null) {
          final dt = DateTime.parse(createdAt).toLocal();
          final timeStr = DateFormat('HH:mm').format(dt);
          final key = '$date $timeStr';
          sessionsMap.putIfAbsent(key, () => {
            'key': key,
            'date': date,
            'time': timeStr,
            'dateTime': dt,
          });
        }
      }
      final sessionList = sessionsMap.values.toList();
      sessionList.sort((a, b) => b['dateTime'].compareTo(a['dateTime']));
      setState(() => _sessions = sessionList);
    } catch (e) {
      print('Oturum yükleme hatası: $e');
    }
  }

  Future<void> _loadTeachers() async {
    final res = await _supabase
        .from('users')
        .select('id, first_name, last_name, title')
        .eq('role', 'teacher')
        .order('first_name');
    setState(() => _teachers = List<Map<String, dynamic>>.from(res));
  }

  Future<void> _loadClassrooms() async {
    try {
      final res = await _supabase
          .from('classrooms')
          .select('id, name')
          .order('name');
      setState(() => _classrooms = List<Map<String, dynamic>>.from(res));
    } catch (e) {
      print('Sınıf yükleme hatası: $e');
    }
  }

  Future<void> _loadOtherCourses() async {
    if (_selectedClassroomId == null || _selectedDay == null) return;
    try {
      final res = await _supabase
          .from('courses')
          .select('course_name, course_time, course_end_time')
          .eq('classroom_id', _selectedClassroomId!)
          .eq('course_day', _selectedDay!)
          .neq('id', widget.course['id']);
          
      setState(() => _otherCoursesInClassroom = List<Map<String, dynamic>>.from(res));
    } catch (e) {
      print('Diğer dersleri yükleme hatası: $e');
    }
  }

  Widget _buildTimePicker(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.access_time, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      onTap: () async {
        final timeStr = controller.text;
        TimeOfDay initialTime = TimeOfDay.now();
        if (timeStr.contains(':')) {
          final parts = timeStr.split(':');
          initialTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        
        final time = await showTimePicker(
          context: context,
          initialTime: initialTime,
        );
        if (time != null) {
          setState(() {
            controller.text = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
          });
        }
      },
    );
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

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      // 1. Değişiklik Onayı
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Değişiklikleri Onayla'),
          content: const Text('Bu ders bilgilerini güncellemek istediğinize emin misiniz?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Onayla')),
          ],
        ),
      );

      if (confirm != true) {
        setState(() => _isSaving = false);
        return;
      }

      // 2. Çakışma Kontrolü (Aynı sınıf, aynı gün ve SAAT çakışması)
      final conflictRes = await _supabase
          .from('courses')
          .select('id, course_name, course_time, course_end_time')
          .eq('classroom_id', _selectedClassroomId ?? '')
          .eq('course_day', _selectedDay ?? '')
          .neq('id', widget.course['id']);

      bool hasOverlap = false;
      String conflictCourseName = '';

      final currentStart = _timeToMinutes(_startTimeC.text);
      final currentEnd = _timeToMinutes(_endTimeC.text);

      for (var c in conflictRes) {
        final otherStartStr = c['course_time'] as String?;
        final otherEndStr = c['course_end_time'] as String?;
        
        if (otherStartStr == null || otherEndStr == null) continue;
        
        final otherStart = _timeToMinutes(otherStartStr);
        final otherEnd = _timeToMinutes(otherEndStr);

        // Çakışma durumu: startA < endB && endA > startB
        if (currentStart < otherEnd && currentEnd > otherStart) {
          hasOverlap = true;
          conflictCourseName = c['course_name'] ?? 'Bilinmeyen Ders';
          break;
        }
      }

      if (hasOverlap) {
        final bool? proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('⚠️ Çakışma Uyarısı'),
            content: Text('Bu sınıfta aynı gün ve saatte "$conflictCourseName" dersi bulunmaktadır. Yine de devam etmek istiyor musunuz?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hayır, İptal')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Evet, Devam Et')),
            ],
          ),
        );

        if (proceed != true) {
          setState(() => _isSaving = false);
          return;
        }
      }

      await _supabase.from('courses').update({
        'course_name': _nameC.text,
        'course_code': _codeC.text,
        'classroom_id': _selectedClassroomId,
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
            
            // Sınıf Seçimi Dropdown
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: DropdownButtonFormField<String>(
                value: _selectedClassroomId,
                decoration: InputDecoration(
                  labelText: 'Sınıf / Lab',
                  prefixIcon: const Icon(Icons.meeting_room_outlined, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                items: _classrooms.map((c) => DropdownMenuItem<String>(
                  value: c['id'].toString(),
                  child: Text(c['name'].toString()),
                )).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedClassroomId = v;
                    _loadOtherCourses();
                  });
                },
              ),
            ),

            // Saat Seçimi
            Row(
              children: [
                Expanded(child: _buildTimePicker('Başlangıç Saati', _startTimeC)),
                const SizedBox(width: 12),
                Expanded(child: _buildTimePicker('Bitiş Saati', _endTimeC)),
              ],
            ),
            const SizedBox(height: 16),

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

            if (_otherCoursesInClassroom.isNotEmpty) ...[
              _buildSectionHeader('Bu Sınıftaki Diğer Dersler (Aynı Gün)'),
              const SizedBox(height: 4),
              ..._otherCoursesInClassroom.map((c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 8, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      '${c['course_name']}: ${c['course_time']} - ${c['course_end_time']}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 16),
            ],
            const Divider(),
            const SizedBox(height: 16),
            _buildSectionHeader('Raporlar'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _downloadFullReport(),
              icon: const Icon(Icons.file_download_rounded),
              label: const Text('Tüm Dönem Raporu İndir'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, 
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionHeader('Alınan Yoklamalar'),
            const SizedBox(height: 4),
            Text(
              'İndirmek istediğiniz yoklama oturumlarını seçin.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('Henüz alınmış yoklama yok.', style: TextStyle(color: AppColors.textSecondary))),
              )
            else
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final isSelected = _selectedSessions.contains(session['key']);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedSessions.remove(session['key']);
                          } else {
                            _selectedSessions.add(session['key']);
                          }
                        });
                      },
                      child: SizedBox(
                        width: 100,
                        child: Stack(
                          children: [
                            // Aradaki Çizgi
                            if (index < _sessions.length - 1)
                              Positioned(
                                left: 50, // Dairenin merkezi
                                top: 20, // Dairenin merkezi (dikeyde)
                                right: -50, // Bir sonraki dairenin merkezine kadar uzat
                                child: Container(
                                  height: 2,
                                  color: AppColors.primary.withOpacity(0.5),
                                ),
                              ),
                            Column(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected ? AppColors.primary : Colors.white,
                                    border: Border.all(color: AppColors.primary, width: 2),
                                  ),
                                  child: Icon(
                                    Icons.check,
                                    color: isSelected ? Colors.white : AppColors.primary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  DateFormat('dd/MM/yy').format(session['dateTime']),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  session['time'],
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            if (_selectedSessions.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () => _downloadSelectedSessionsReport(),
                icon: const Icon(Icons.file_download_rounded),
                label: Text('Seçilen Raporları İndir (${_selectedSessions.length})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success, 
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
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

    // Değer listede yoksa (veriler yüklenirken) hata vermemesi için null yapıyoruz
    final hasValue = items.any((item) => item.value == value);

    return DropdownButtonFormField<String>(
      value: hasValue ? value : null,
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
      onChanged: (v) {
        setState(() {
          _selectedDay = v;
          _loadOtherCourses();
        });
      },
    );
  }

  Future<void> _downloadFullReport() async {
    if (_sessions.isEmpty) {
      await _loadSessions();
    }
    final keys = _sessions.map((s) => s['key'].toString()).toList()..sort();
    await _generatePdfReport(keys);
  }

  Future<void> _downloadSelectedSessionsReport() async {
    final keys = _selectedSessions.toList()..sort();
    await _generatePdfReport(keys);
  }

  Future<void> _generatePdfReport(List<String> sessionKeys) async {
    if (sessionKeys.isEmpty) return;
    
    setState(() => _isSaving = true);
    try {
      final studentsRes = await _supabase
          .from('student_courses')
          .select('student_id, users(id, first_name, last_name, school_no)')
          .eq('course_id', widget.course['id']);
      
      final students = List<Map<String, dynamic>>.from(studentsRes);

      final attendanceRes = await _supabase
          .from('attendance')
          .select('date, student_id, is_present, created_at')
          .eq('course_id', widget.course['id']);
      
      final records = List<Map<String, dynamic>>.from(attendanceRes);

      final List<String> headers = ['Okul No', 'İsim Soyisim'];
      headers.addAll(sessionKeys);

      final List<List<String>> data = [];
      for (var s in students) {
        final user = s['users'] as Map<String, dynamic>?;
        if (user == null) continue;
        
        final List<String> row = [
          user['school_no'] ?? '-',
          '${user['first_name']} ${user['last_name']}',
        ];

        for (var sessionKey in sessionKeys) {
          final record = records.firstWhere((r) {
            final date = r['date'] as String;
            final createdAt = r['created_at'] as String?;
            if (createdAt == null) return false;
            final dt = DateTime.parse(createdAt).toLocal();
            final timeStr = DateFormat('HH:mm').format(dt);
            final key = '$date $timeStr';
            return r['student_id'] == user['id'] && key == sessionKey;
          }, orElse: () => {});

          if (record.isEmpty) {
            row.add('-');
          } else {
            row.add(record['is_present'] == true ? 'VAR' : 'YOK');
          }
        }
        data.add(row);
      }

      final pdf = pw.Document();
      final font = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          theme: pw.ThemeData.withFont(base: font, bold: boldFont),
          build: (pw.Context context) => [
            pw.Header(
              level: 0,
              child: pw.Text('Yoklama Raporu - ${widget.course['course_name']}'),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: data,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
              cellStyle: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      await Printing.sharePdf(bytes: bytes, filename: 'yoklama_raporu_${widget.course['course_code']}.pdf');

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rapor oluşturulurken hata: $e')));
    } finally {
      setState(() => _isSaving = false);
    }
  }
}

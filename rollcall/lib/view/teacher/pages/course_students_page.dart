import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/theme/colors/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import 'dart:async';

// ACADEMIC TERM DATES
final DateTime TERM_START = DateTime(2026, 2, 9);
final DateTime TERM_END = DateTime(2026, 6, 12);

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

String _translateDay(String? day) {
  if (day == null) return '';
  final days = day.split(',').map((d) => d.trim()).toList();
  const dayMap = {
    'Monday': 'Pazartesi',
    'Tuesday': 'Salı',
    'Wednesday': 'Çarşamba',
    'Thursday': 'Perşembe',
    'Friday': 'Cuma',
    'Saturday': 'Cumartesi',
    'Sunday': 'Pazar',
  };
  return days.map((d) => dayMap[d] ?? d).join(', ');
}

String _getDayInEnglish(DateTime date) {
  return DateFormat('EEEE').format(date);
}

String _formatTimeRange(String? startTime) {
  if (startTime == null || startTime.isEmpty) return '';
  try {
    final parts = startTime.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final endHour = (hour + 3) % 24;
    return '${hour.toString().padLeft(2, '0')}:$minute - ${endHour.toString().padLeft(2, '0')}:$minute';
  } catch (e) {
    return startTime;
  }
}

class CourseStudentsPage extends StatefulWidget {
  const CourseStudentsPage({super.key});

  @override
  State<CourseStudentsPage> createState() => _CourseStudentsPageState();
}

class _CourseStudentsPageState extends State<CourseStudentsPage> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  Map<String, dynamic>? _course;
  List<Map<String, dynamic>> _students = [];
  Map<String, bool> _attendanceMap = {};
  DateTime _selectedDate = DateTime.now().isBefore(TERM_START) 
      ? TERM_START 
      : (DateTime.now().isAfter(TERM_END) ? TERM_END : DateTime.now());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_course == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _course = args;
        _loadData();
      }
    }
  }

  Future<void> _loadData() async {
    if (_course == null) return;

    setState(() => _isLoading = true);
    final courseId = _course!['id'];

    final studentCourses = await _supabase
        .from('student_courses')
        .select('student_id, users(id, first_name, last_name, school_no)')
        .eq('course_id', courseId);

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final attendanceRecords = await _supabase
        .from('attendance')
        .select('student_id, is_present')
        .eq('course_id', courseId)
        .eq('date', dateStr);

    final Map<String, bool> attendanceMap = {};
    for (var record in attendanceRecords) {
      attendanceMap[record['student_id']] = record['is_present'] ?? false;
    }

    if (!mounted) return;
    setState(() {
      _students = List<Map<String, dynamic>>.from(studentCourses);
      _students.sort((a, b) {
        final noA = (a['users']?['school_no'] ?? '').toString();
        final noB = (b['users']?['school_no'] ?? '').toString();
        return noA.compareTo(noB);
      });
      _attendanceMap = attendanceMap;
      _isLoading = false;
    });
  }

  Future<void> _toggleAttendance(String studentId, bool? currentVal) async {
    final newVal = !(currentVal ?? false);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final courseId = _course!['id'];

    setState(() {
      _attendanceMap[studentId] = newVal;
    });

    try {
      await _supabase.from('attendance').upsert({
        'student_id': studentId,
        'course_id': courseId,
        'date': dateStr,
        'is_present': newVal,
      }, onConflict: 'student_id, course_id, date');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata oluştu: $e'), backgroundColor: AppColors.error),
      );
      setState(() {
        _attendanceMap[studentId] = currentVal ?? false;
      });
    }
  }

  bool _isScheduledDay(DateTime date) {
    if (_course == null) return true;
    final courseDayRaw = _course?['course_day'] ?? '';
    final List<String> scheduledDays = courseDayRaw.toString().split(',').map((e) => e.trim().toLowerCase()).toList();
    final dayEnglish = _getDayInEnglish(date).toLowerCase();
    return scheduledDays.contains(dayEnglish);
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _CustomCalendarDialog(
        initialDate: _selectedDate,
        isScheduledDay: _isScheduledDay,
      ),
    );
    
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadData();
    }
  }

  void _showQRCode() {
    if (_course == null) return;
    
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    
    showDialog(
      context: context,
      builder: (context) => _QRDisplayDialog(
        courseId: _course!['id'],
        courseName: _translateCourseName(_course?['course_name']),
        dateStr: dateStr,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final courseName = _course != null ? _course!['course_name'] : 'Ders Detayı';
    final courseDayRaw = _course?['course_day'] ?? '';
    final courseTimeRaw = _course?['course_time'] ?? '';
    final dateDisplay = DateFormat('dd MMMM yyyy').format(_selectedDate);
    final selectedDayEnglish = _getDayInEnglish(_selectedDate);
    final isCorrectDay = _isScheduledDay(_selectedDate);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _translateCourseName(courseName),
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
            onPressed: isCorrectDay ? _showQRCode : null,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Header Accent (Like Student Page)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(color: AppColors.primary.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 5)),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Program Günü', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(_translateDay(courseDayRaw), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Saat Aralığı', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(_formatTimeRange(courseTimeRaw), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _selectDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$dateDisplay (${_translateDay(selectedDayEnglish)})',
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down_circle_outlined, color: AppColors.primary, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: !isCorrectDay 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy_rounded, color: AppColors.primary.withValues(alpha: 0.2), size: 80),
                      const SizedBox(height: 16),
                      const Text('Ders Programı Dışı', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Lütfen takvimden yeşil noktalı günleri seçin.', style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                )
              : _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.people_alt_rounded, color: AppColors.primary, size: 16),
                            const SizedBox(width: 8),
                            Text('${_students.length} Öğrenci Kayıtlı', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            const Text('Sıralama: Okul No', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          itemCount: _students.length,
                          itemBuilder: (context, index) {
                            final student = _students[index]['users'] as Map<String, dynamic>;
                            final sid = student['id'];
                            final isPresent = _attendanceMap[sid] ?? false;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.border),
                                boxShadow: [
                                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4)),
                                ],
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: AppColors.primaryLight,
                                    child: Text(student['first_name'][0].toUpperCase(), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${student['first_name']} ${student['last_name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                        Text(student['school_no'] ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => _toggleAttendance(sid, isPresent),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isPresent ? AppColors.success : AppColors.error,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(isPresent ? 'Var' : 'Yok', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: isCorrectDay
          ? FloatingActionButton.extended(
              onPressed: _showQRCode,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
              label: const Text('QR Oluştur', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }
}

class _QRDisplayDialog extends StatefulWidget {
  final String courseId;
  final String courseName;
  final String dateStr;

  const _QRDisplayDialog({
    required this.courseId,
    required this.courseName,
    required this.dateStr,
  });

  @override
  State<_QRDisplayDialog> createState() => _QRDisplayDialogState();
}

class _QRDisplayDialogState extends State<_QRDisplayDialog> {
  late String _qrData;
  Timer? _timer;
  int _secondsLeft = 60;

  @override
  void initState() {
    super.initState();
    _generateData();
    _startTimer();
  }

  void _generateData() {
    setState(() {
      _qrData = jsonEncode({
        'type': 'attendance_qr',
        'course_id': widget.courseId,
        'date': widget.dateStr,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      _secondsLeft = 60;
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        _generateData();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Yoklama QR Kodu',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.courseName} - ${widget.dateStr}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: QrImageView(
                data: _qrData,
                version: QrVersions.auto,
                size: 220.0,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppColors.primary,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'QR kod $_secondsLeft saniye sonra yenilenecek',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Öğrenciler bu kodu okutarak yoklama verebilirler.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  'Kapat',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomCalendarDialog extends StatefulWidget {
  final DateTime initialDate;
  final bool Function(DateTime) isScheduledDay;
  const _CustomCalendarDialog({required this.initialDate, required this.isScheduledDay});

  @override
  State<_CustomCalendarDialog> createState() => _CustomCalendarDialogState();
}

class _CustomCalendarDialogState extends State<_CustomCalendarDialog> {
  late DateTime _displayedMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _displayedMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
    _selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    final daysCount = DateUtils.getDaysInMonth(_displayedMonth.year, _displayedMonth.month);
    final firstDay = DateTime(_displayedMonth.year, _displayedMonth.month, 1).weekday - 1;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left, color: AppColors.primary), onPressed: () => setState(() => _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1))),
                Text(DateFormat('MMMM yyyy').format(_displayedMonth), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(icon: const Icon(Icons.chevron_right, color: AppColors.primary), onPressed: () => setState(() => _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['P', 'S', 'Ç', 'P', 'C', 'C', 'P'].map((d) => Text(d, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))).toList(),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
              itemCount: 42,
              itemBuilder: (context, index) {
                final day = index - firstDay + 1;
                if (day < 1 || day > daysCount) return const SizedBox();
                final date = DateTime(_displayedMonth.year, _displayedMonth.month, day);
                final bool inTerm = (date.isAfter(TERM_START) || DateUtils.isSameDay(date, TERM_START)) && (date.isBefore(TERM_END) || DateUtils.isSameDay(date, TERM_END));
                final bool isSched = inTerm && widget.isScheduledDay(date);
                final bool isSelected = DateUtils.isSameDay(date, _selectedDate);

                return InkWell(
                  onTap: isSched ? () => setState(() => _selectedDate = date) : null,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(color: isSelected ? AppColors.primary : Colors.transparent, shape: BoxShape.circle),
                        child: Center(
                          child: Text(day.toString(), style: TextStyle(color: isSelected ? Colors.white : (isSched ? AppColors.textPrimary : Colors.grey[300]), fontWeight: isSched || isSelected ? FontWeight.bold : FontWeight.normal)),
                        ),
                      ),
                      if (isSched) Container(margin: const EdgeInsets.only(top: 2), width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal', style: TextStyle(color: Colors.grey))),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selectedDate),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('Seç', style: TextStyle(color: Colors.white)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/theme/colors/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import 'dart:async';
import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/utils/security_utils.dart';

// ACADEMIC TERM DATES
final DateTime TERM_START = DateTime(2026, 2, 9);
final DateTime TERM_END = DateTime(2026, 6, 12);

int getScheduledDaysCount(DateTime start, DateTime end, String courseDayRaw) {
  final List<String> scheduledDays = courseDayRaw
      .toLowerCase()
      .split(',')
      .map((e) => e.trim())
      .toList();
  int count = 0;
  for (
    DateTime d = start;
    d.isBefore(end) || DateUtils.isSameDay(d, end);
    d = d.add(const Duration(days: 1))
  ) {
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

String _formatTimeRange(String? startTime, String? endTime) {
  if (startTime == null || startTime.isEmpty) return '';
  try {
    final startParts = startTime.split(':');
    final startH = int.parse(startParts[0]);
    final startM = startParts[1];

    String endDisplay;
    if (endTime != null && endTime.isNotEmpty) {
      final endParts = endTime.split(':');
      endDisplay = '${endParts[0]}:${endParts[1]}';
    } else {
      final endHour = (startH + 3) % 24;
      endDisplay = '${endHour.toString().padLeft(2, '0')}:$startM';
    }

    return '${startH.toString().padLeft(2, '0')}:$startM - $endDisplay';
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

  StreamSubscription? _attendanceSubscription;
  RealtimeChannel? _realtimeChannel;
  bool _isRealtimeEnabled = false;
  bool _isAutomationRunning = false;
  int _automationTimer = 0;
  Timer? _automationCountdownTimer;

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

    final courseDetails = await _supabase
        .from('courses')
        .select(
          '*, classrooms(id, name, faculty_id, beacon_major, beacon_secret, faculties(name))',
        )
        .eq('id', courseId)
        .single();

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
      _course = courseDetails;
      _students = List<Map<String, dynamic>>.from(studentCourses);
      _students.sort((a, b) {
        final noA = (a['users']?['school_no'] ?? '').toString();
        final noB = (b['users']?['school_no'] ?? '').toString();
        return noA.compareTo(noB);
      });
      _attendanceMap = attendanceMap;
      _isLoading = false;
    });

    if (_isRealtimeEnabled) {
      _initRealtime();
    }
    _setupRealtimeChannel();
  }

  void _setupRealtimeChannel() {
    if (_course == null) return;
    final courseId = _course!['id'];
    _realtimeChannel = _supabase.channel(
      'course_$courseId',
      opts: const RealtimeChannelConfig(self: true),
    );
    _realtimeChannel!.subscribe();
  }

  void _initRealtime() {
    _attendanceSubscription?.cancel();

    final courseId = _course!['id'];
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    _attendanceSubscription = _supabase
        .from('attendance')
        .stream(primaryKey: ['student_id', 'course_id', 'date'])
        .listen((List<Map<String, dynamic>> data) {
          final Map<String, bool> newMap = {};

          final filteredData = data.where(
            (r) => r['course_id'] == courseId && r['date'] == dateStr,
          );

          for (var record in filteredData) {
            newMap[record['student_id']] = record['is_present'] ?? false;
          }
          if (mounted) {
            setState(() {
              _attendanceMap = newMap;
            });
          }
        });
  }

  void _startAutomaticAttendance() async {
    if (_isAutomationRunning) return;

    setState(() {
      _isAutomationRunning = true;
      _automationTimer = 60;
    });

    // 1. Update Classroom to signal Hardware (ESP32)
    try {
      // Find Classroom ID from course data
      final classroomId = _course?['classroom_id'] ?? _course?['classrooms']?['id'];
      
      print('--- AUTOMATION DEBUG START ---');
      print('Target Classroom ID: $classroomId');
      print('Course Data Keys: ${_course?.keys.toList()}');
      if (_course?['classrooms'] != null) {
        print('Classroom Data Keys: ${(_course?['classrooms'] as Map).keys.toList()}');
      }

      if (classroomId != null) {
        final response = await _supabase
            .from('classrooms')
            .update({
              'is_automation_on': true,
              'active_course_id': _course!['id'], // Donanımın hangi ders olduğunu bilmesi için
            })
            .eq('id', classroomId.toString().trim())
            .select();
            
        print('Supabase Update Response: $response');
        
        if (response.isEmpty) {
          print('WARNING: Update successful but no rows were affected.');
          print('!!! DİKKAT: Bu durum genelde Supabase RLS Policy (Update izni olmaması) kaynaklıdır.');
        } else {
          print('SUCCESS: Classroom automation flag set to TRUE with active_course_id');
        }
      } else {
        print('ERROR: Classroom ID is NULL. Cannot update database.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hata: Sınıf bilgisi bulunamadı!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
      print('--- AUTOMATION DEBUG END ---');
    } catch (e) {
      print('CRITICAL UPDATE ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Veritabanı hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      _isAutomationRunning = false;
      return;
    }

    // 2. Send Realtime Broadcast to Students
    await _realtimeChannel?.sendBroadcastMessage(
      event: 'start_automation',
      payload: {
        'course_id': _course!['id'],
        'major': _course!['classrooms']?['beacon_major'] ?? 101,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    _automationCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      if (_automationTimer > 0) {
        setState(() => _automationTimer--);
      } else {
        await _stopAutomaticAttendance();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Otomatik yoklama başlatıldı! Öğrenciler taranıyor...'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _stopAutomaticAttendance() async {
    _automationCountdownTimer?.cancel();

    // Reset database flag for hardware (Classroom only)
    final classroomId =
        _course?['classroom_id'] ?? _course?['classrooms']?['id'];

    if (classroomId != null) {
      await _supabase
          .from('classrooms')
          .update({
            'is_automation_on': false,
            'active_course_id': null
          })
          .eq('id', classroomId);
    }

    setState(() {
      _isAutomationRunning = false;
      _automationTimer = 0;
    });
  }

  void _toggleRealtime() {
    setState(() {
      _isRealtimeEnabled = !_isRealtimeEnabled;
      if (_isRealtimeEnabled) {
        _initRealtime();
      } else {
        _attendanceSubscription?.cancel();
      }
    });
  }

  // ... (rest of the class remains same)
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
        SnackBar(
          content: Text('Hata oluştu: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() {
        _attendanceMap[studentId] = currentVal ?? false;
      });
    }
  }

  bool _isScheduledDay(DateTime date) {
    if (_course == null) return true;
    final courseDayRaw = _course?['course_day'] ?? '';
    final List<String> scheduledDays = courseDayRaw
        .toString()
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .toList();
    final dayEnglish = _getDayInEnglish(date).toLowerCase();
    return scheduledDays.contains(dayEnglish);
  }

  bool _canOpenQR() {
    if (_course == null) return false;
    if (!DateUtils.isSameDay(_selectedDate, DateTime.now())) return false;
    if (!_isScheduledDay(DateTime.now())) return false;

    try {
      final String startTimeStr = _course!['course_time'] ?? '00:00:00';
      final String endTimeStr = _course!['course_end_time'] ?? '00:00:00';

      final startParts = startTimeStr.split(':');
      final endParts = endTimeStr.split(':');

      final int startH = int.parse(startParts[0]);
      final int startM = int.parse(startParts[1]);
      final int endH = int.parse(endParts[0]);
      final int endM = int.parse(endParts[1]);

      final now = DateTime.now();
      final nowTotal = now.hour * 60 + now.minute;
      final startTotal = startH * 60 + startM;
      int endTotal = endH * 60 + endM;
      if (endTotal <= startTotal) {
        endTotal = startTotal + 180;
      }

      return nowTotal >= startTotal && nowTotal <= endTotal;
    } catch (e) {
      return false;
    }
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
    final courseName = _course != null
        ? _course!['course_name']
        : 'Ders Detayı';
    final courseTimeRaw = _course?['course_time'] ?? '';
    final courseEndTimeRaw = _course?['course_end_time'] ?? '';
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
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _translateCourseName(courseName),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: Colors.white),
            onPressed: () {
              if (_course != null) {
                Navigator.pushNamed(
                  context,
                  '/ogretmen-analiz',
                  arguments: _course,
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
            onPressed: _canOpenQR() ? _showQRCode : null,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
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
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Program Günü',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _translateCourseName(
                                        _course?['course_name'],
                                      ) +
                                      (_course?['classrooms'] != null
                                          ? ' - ${_course?['classrooms']['name']}'
                                          : ''),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _translateDay(_course?['course_day']),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Saat Aralığı',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatTimeRange(
                                  courseTimeRaw,
                                  courseEndTimeRaw,
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _AutomationButton(
                              isActive: _isAutomationRunning,
                              timer: _automationTimer,
                              onTap: _startAutomaticAttendance,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _selectDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$dateDisplay (${_translateDay(selectedDayEnglish)})',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_drop_down_circle_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: !isCorrectDay
                ? _buildEmptyState(
                    'Ders Programı Dışı',
                    'Lütfen takvimden yeşil noktalı günleri seçin.',
                    Icons.event_busy_rounded,
                  )
                : _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : Column(
                    children: [
                      _buildHeaderStats(),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          itemCount: _students.length,
                          itemBuilder: (context, index) {
                            final student =
                                _students[index]['users']
                                    as Map<String, dynamic>;
                            final sid = student['id'];
                            final isPresent = _attendanceMap[sid] ?? false;
                            return _StudentItem(
                              student: student,
                              isPresent: isPresent,
                              onTap: () => _toggleAttendance(sid, isPresent),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: _canOpenQR() ? _buildFABs() : null,
    );
  }

  Widget _buildEmptyState(String title, String subtitle, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary.withValues(alpha: 0.2), size: 80),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          const Icon(
            Icons.people_alt_rounded,
            color: AppColors.primary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            '${_attendanceMap.values.where((v) => v).length} / ${_students.length} Öğrenci Sınıfta',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_isRealtimeEnabled) ...[
            const SizedBox(width: 8),
            const Icon(Icons.circle, color: AppColors.success, size: 8),
            const SizedBox(width: 4),
            const Text(
              'CANLI',
              style: TextStyle(
                color: AppColors.success,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const Spacer(),
          const Text(
            'Sıralama: Okul No',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildFABs() {
    return FloatingActionButton.extended(
      onPressed: _showQRCode,
      backgroundColor: AppColors.primary,
      heroTag: 'qr',
      icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
      label: const Text(
        'QR Oluştur',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  void dispose() {
    _attendanceSubscription?.cancel();
    _automationCountdownTimer?.cancel();
    if (_realtimeChannel != null) {
      _supabase.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }
}

class _StudentItem extends StatelessWidget {
  final Map<String, dynamic> student;
  final bool isPresent;
  final VoidCallback onTap;
  const _StudentItem({
    required this.student,
    required this.isPresent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              student['first_name'][0].toUpperCase(),
              style: const TextStyle(
                color: AppColors.primary,
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
                  '${student['first_name']} ${student['last_name']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  student['school_no'] ?? '',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isPresent ? AppColors.success : AppColors.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isPresent ? 'Var' : 'Yok',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutomationButton extends StatelessWidget {
  final bool isActive;
  final int timer;
  final VoidCallback onTap;
  const _AutomationButton({
    required this.isActive,
    required this.timer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isActive ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? Icons.bluetooth_searching_rounded : Icons.bolt_rounded,
              color: isActive ? AppColors.primary : Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              isActive
                  ? 'Taranıyor... ($timer s)'
                  : 'Otomatik Yoklamayı Başlat',
              style: TextStyle(
                color: isActive ? AppColors.primary : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
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
  final BeaconBroadcast _beaconBroadcast = BeaconBroadcast();
  bool _isBeaconActive = false;
  String _currentBeaconToken = '';

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndStart();
    _generateData();
    _startTimer();
  }

  Future<void> _checkPermissionsAndStart() async {
    final status = await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    if (status.values.every((s) => s.isGranted)) _startBeacon();
  }

  void _startBeacon() async {
    try {
      _currentBeaconToken = SecurityUtils.generateTimeToken(widget.courseId);
      final int minor = int.tryParse(_currentBeaconToken) ?? 0;
      await _beaconBroadcast
          .setUUID('E2C56DB5-DFFB-48D2-B060-D0F5A71096E0')
          .setMajorId(1)
          .setMinorId(minor)
          .setTransmissionPower(-59)
          .setAdvertiseMode(AdvertiseMode.balanced)
          .start();
      setState(() => _isBeaconActive = true);
    } catch (e) {
      debugPrint('Beacon Error: $e');
    }
  }

  void _stopBeacon() => _beaconBroadcast.stop();

  void _generateData() {
    _currentBeaconToken = SecurityUtils.generateTimeToken(widget.courseId);
    setState(() {
      _qrData = jsonEncode({
        'type': 'attendance_qr',
        'course_id': widget.courseId,
        'date': widget.dateStr,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'beacon_token': _currentBeaconToken,
        'secure': true,
      });
      _secondsLeft = 30;
    });
    if (_isBeaconActive) _startBeacon();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0)
        setState(() => _secondsLeft--);
      else
        _generateData();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopBeacon();
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Yoklama QR Kodu',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (_isBeaconActive) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.bluetooth_searching_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ],
              ],
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
                const Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'QR kod $_secondsLeft saniye sonra yenilenecek',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
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
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
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
  const _CustomCalendarDialog({
    required this.initialDate,
    required this.isScheduledDay,
  });
  @override
  State<_CustomCalendarDialog> createState() => _CustomCalendarDialogState();
}

class _CustomCalendarDialogState extends State<_CustomCalendarDialog> {
  late DateTime _displayedMonth, _selectedDate;
  @override
  void initState() {
    super.initState();
    _displayedMonth = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
    );
    _selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    final daysCount = DateUtils.getDaysInMonth(
      _displayedMonth.year,
      _displayedMonth.month,
    );
    final firstDay =
        DateTime(_displayedMonth.year, _displayedMonth.month, 1).weekday - 1;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.chevron_left,
                    color: AppColors.primary,
                  ),
                  onPressed: () => setState(
                    () => _displayedMonth = DateTime(
                      _displayedMonth.year,
                      _displayedMonth.month - 1,
                    ),
                  ),
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_displayedMonth),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.chevron_right,
                    color: AppColors.primary,
                  ),
                  onPressed: () => setState(
                    () => _displayedMonth = DateTime(
                      _displayedMonth.year,
                      _displayedMonth.month + 1,
                    ),
                  ),
                ),
              ],
            ),
            GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
              ),
              itemCount: 42,
              itemBuilder: (context, index) {
                final day = index - firstDay + 1;
                if (day < 1 || day > daysCount) return const SizedBox();
                final date = DateTime(
                  _displayedMonth.year,
                  _displayedMonth.month,
                  day,
                );
                final bool inTerm =
                    (date.isAfter(TERM_START) ||
                        DateUtils.isSameDay(date, TERM_START)) &&
                    (date.isBefore(TERM_END) ||
                        DateUtils.isSameDay(date, TERM_END));
                final bool isSched = inTerm && widget.isScheduledDay(date);
                final bool isSelected = DateUtils.isSameDay(
                  date,
                  _selectedDate,
                );
                return InkWell(
                  onTap: isSched
                      ? () => setState(() => _selectedDate = date)
                      : null,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            day.toString(),
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : (isSched
                                        ? AppColors.textPrimary
                                        : Colors.grey[300]),
                              fontWeight: isSched || isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                      if (isSched)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'İptal',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selectedDate),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Seç',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/theme/colors/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import 'dart:async';

import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/utils/security_utils.dart';
import '../../../core/services/person_detector_service.dart';
import 'verification_camera_page.dart';

// ACADEMIC TERM DATES
final DateTime termStart = DateTime(2026, 2, 9);
final DateTime termEnd = DateTime(2026, 6, 12);

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
  DateTime _selectedDate = DateTime.now().isBefore(termStart)
      ? termStart
      : (DateTime.now().isAfter(termEnd) ? termEnd : DateTime.now());

  RealtimeChannel? _realtimeChannel;

  bool _isAutomationRunning = false;
  int _automationTimer = 0;
  Timer? _automationCountdownTimer;
  String _sortBy = 'Okul No';
  final int _selectedSlot = 1;
  Timer? _plannedAttendanceCheckTimer;
  bool _isIntervalMode = false;
  int _intervalMinutes = 30;
  bool _isDelegated = false;
  int _lastTriggeredMinute = -1;
  String _countdownText = '';

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
        .eq('date', dateStr)
        .eq('slot', _selectedSlot);

    final Map<String, bool> attendanceMap = {};
    for (var record in attendanceRecords) {
      attendanceMap[record['student_id']] = record['is_present'] ?? false;
    }
    
    final myId = _supabase.auth.currentUser?.id;
    final assignedTeacherId = courseDetails['assigned_teacher_id'];
    final isDelegated = assignedTeacherId != null && assignedTeacherId != myId;

    if (!mounted) return;
    setState(() {
      _course = courseDetails;
      _isDelegated = isDelegated;
      _students = List<Map<String, dynamic>>.from(studentCourses);
      _students.sort((a, b) {
        final noA = (a['users']?['school_no'] ?? '').toString();
        final noB = (b['users']?['school_no'] ?? '').toString();
        return noA.compareTo(noB);
      });
      _attendanceMap = attendanceMap;
      _isLoading = false;
    });

    _sortStudents();
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



  void _startAutomaticAttendance() async {
    if (_isAutomationRunning) return;

    setState(() {
      _isAutomationRunning = true;
      _automationTimer = 60;
    });

    // Sınıf veritabanı güncelle (ESP32 tetikleme)
    try {
      final classroomId =
          _course?['classroom_id'] ?? _course?['classrooms']?['id'];

      if (classroomId != null) {
        await _supabase
            .from('classrooms')
            .update({
              'is_automation_on': true,
              'active_course_id': _course!['id'],
            })
            .eq('id', classroomId.toString().trim());
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hata: Sınıf bilgisi bulunamadı!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Otomatik yoklama başlatıldı! Öğrenciler taranıyor...'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _stopAutomaticAttendance() async {
    _automationCountdownTimer?.cancel();

    // 1. Update UI state immediately so it doesn't get stuck at (0 s)
    setState(() {
      _isAutomationRunning = false;
      _automationTimer = 0;
    });

    // 2. Reset database flag for hardware (Classroom only)
    try {
      final classroomId =
          _course?['classroom_id'] ?? _course?['classrooms']?['id'];

      if (classroomId != null) {
        await _supabase
            .from('classrooms')
            .update({'is_automation_on': false, 'active_course_id': null})
            .eq('id', classroomId.toString().trim());
      }

      // 3. Optional: Send broadcast to students that automation ended
      await _realtimeChannel?.sendBroadcastMessage(
        event: 'stop_automation',
        payload: {'course_id': _course?['id']},
      );
    } catch (e) {
      // Ağ hatası olsa bile UI zaten güncellendi
    }

    // Otomatik yoklama bitince yoklama verilerini güncelle
    await _loadData();
  }

  Future<void> _toggleAttendance(String studentId, bool? currentVal) async {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    if (!isToday) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Geçmiş veya gelecek tarihli yoklamalar değiştirilemez.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final newVal = !(currentVal ?? false);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final courseId = _course!['id'];

    setState(() {
      _attendanceMap[studentId] = newVal;
    });

    try {
      final existing = await _supabase
          .from('attendance')
          .select('id')
          .eq('student_id', studentId)
          .eq('course_id', courseId)
          .eq('date', dateStr)
          .eq('slot', _selectedSlot)
          .maybeSingle();

      if (existing != null) {
        await _supabase
            .from('attendance')
            .update({
              'is_present': newVal,
            })
            .eq('id', existing['id']);
      } else {
        await _supabase
            .from('attendance')
            .insert({
              'student_id': studentId,
              'course_id': courseId,
              'date': dateStr,
              'slot': _selectedSlot,
              'is_present': newVal,
            });
      }
      if (_sortBy == 'Durum') _sortStudents();
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

  void _sortStudents() {
    setState(() {
      if (_sortBy == 'Okul No') {
        _students.sort((a, b) {
          final noA = (a['users']?['school_no'] ?? '').toString();
          final noB = (b['users']?['school_no'] ?? '').toString();
          return noA.compareTo(noB);
        });
      } else if (_sortBy == 'İsim Soyisim') {
        _students.sort((a, b) {
          final nameA =
              '${a['users']?['first_name']} ${a['users']?['last_name']}'
                  .toLowerCase();
          final nameB =
              '${b['users']?['first_name']} ${b['users']?['last_name']}'
                  .toLowerCase();
          return nameA.compareTo(nameB);
        });
      } else if (_sortBy == 'Durum') {
        _students.sort((a, b) {
          final sidA = a['users']?['id'];
          final sidB = b['users']?['id'];
          final presentA = _attendanceMap[sidA] ?? false;
          final presentB = _attendanceMap[sidB] ?? false;
          if (presentA == presentB) {
            final noA = (a['users']?['school_no'] ?? '').toString();
            final noB = (b['users']?['school_no'] ?? '').toString();
            return noA.compareTo(noB);
          }
          return presentA ? -1 : 1;
        });
      }
    });
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

  void _showPlannedAttendanceDialog() {
    if (_course == null) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Planlı Yoklama Ayarla', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Her kaç dakikada bir yoklama alınsın?', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: DropdownButton<int>(
                        value: _intervalMinutes,
                        isExpanded: true,
                        underline: const SizedBox(),
                        items: [30, 45, 60, 90, 120].map((int val) {
                          return DropdownMenuItem<int>(
                            value: val,
                            child: Text('$val dakikada bir'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              _intervalMinutes = val;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'En fazla sıklık olarak 30 dk seçilebilir.',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat', style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setDialogState(() {
                      _isIntervalMode = true; // Always true now
                    });
                    _startPlannedAttendanceMonitoring();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  child: const Text('Kaydet'),
                ),
              ],
            );
          }
        );
      },
    );


  }

  void _startPlannedAttendanceMonitoring() {
    _plannedAttendanceCheckTimer?.cancel();
    if (!_isIntervalMode) return;

    _plannedAttendanceCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_course == null) return;
      
      final String startTimeStr = _course!['course_time'] ?? '00:00:00';
      final startParts = startTimeStr.split(':');
      final int startH = int.parse(startParts[0]);
      final int startM = int.parse(startParts[1]);

      final now = DateTime.now();
      final classStartTime = DateTime(now.year, now.month, now.day, startH, startM);
      
      final elapsedMinutes = now.difference(classStartTime).inMinutes;

      // Calculate countdown to next interval
      final nextAttendanceMinute = ((elapsedMinutes ~/ _intervalMinutes) + 1) * _intervalMinutes;
      final nextAttendanceTime = classStartTime.add(Duration(minutes: nextAttendanceMinute));
      final remaining = nextAttendanceTime.difference(now);
      
      if (remaining.isNegative) {
        _countdownText = '00:00:00';
      } else {
        final hours = remaining.inHours.toString().padLeft(2, '0');
        final minutes = (remaining.inMinutes % 60).toString().padLeft(2, '0');
        final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
        _countdownText = '$hours:$minutes:$seconds';
      }
      
      setState(() {}); // Update UI for countdown

      if (elapsedMinutes > 0 && elapsedMinutes != _lastTriggeredMinute) {
        if (elapsedMinutes % _intervalMinutes == 0) {
          if (!_isAutomationRunning) {
            _startAutomaticAttendance();
            _lastTriggeredMinute = elapsedMinutes;
          }
        }
      }
    });
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
      builder: (ctx) => _QRDisplayDialog(
        courseId: _course!['id'],
        courseName: _translateCourseName(_course?['course_name']),
        dateStr: dateStr,
        slot: _selectedSlot,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
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
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                                  'Ders Adı',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  _translateCourseName(
                                    _course?['course_name'],
                                  ),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Zaman & Yer',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _formatTimeRange(
                                  courseTimeRaw,
                                  courseEndTimeRaw,
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                _translateDay(_course?['course_day']),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                              if (_course?['classrooms'] != null)
                                Text(
                                  'Derslik: ${_course?['classrooms']['name']}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (_canOpenQR()) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _AutomationButton(
                                isActive: _isAutomationRunning,
                                isEnabled: !_isDelegated,
                                timer: _automationTimer,
                                onTap: _startAutomaticAttendance,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _isDelegated ? null : _showPlannedAttendanceDialog,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _isDelegated ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _isDelegated ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        color: _isDelegated ? Colors.white54 : Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isIntervalMode && _countdownText.isNotEmpty
                                          ? 'Sonraki: $_countdownText'
                                          : 'Planlı Yoklama Ayarla',
                                        style: TextStyle(
                                          color: _isDelegated ? Colors.white54 : Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _isDelegated ? null : _showQRCode,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _isDelegated ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _isDelegated ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.qr_code_2_rounded,
                                        color: _isDelegated ? Colors.white54 : Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'QR Oluştur',
                                        style: TextStyle(
                                          color: _isDelegated ? Colors.white54 : Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _selectDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$dateDisplay (${_translateDay(selectedDayEnglish)})',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_drop_down_circle_outlined,
                          color: AppColors.primary,
                          size: 18,
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
      bottomNavigationBar: _buildVerifyBar(),
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
          const Spacer(),
          PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            onSelected: (value) {
              setState(() => _sortBy = value);
              _sortStudents();
            },
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            color: Colors.white,
            elevation: 10,
            itemBuilder: (context) => [
              'Okul No',
              'İsim Soyisim',
              'Durum',
            ].map((s) => PopupMenuItem(
              value: s,
              height: 40,
              child: Row(
                children: [
                  Icon(
                    s == 'Okul No' ? Icons.numbers_rounded :
                    s == 'İsim Soyisim' ? Icons.person_rounded :
                    Icons.check_circle_rounded,
                    size: 18,
                    color: _sortBy == s ? AppColors.primary : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    s,
                    style: TextStyle(
                      color: _sortBy == s ? AppColors.primary : AppColors.textPrimary,
                      fontWeight: _sortBy == s ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  if (_sortBy == s)
                    const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 16),
                ],
              ),
            )).toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Sırala: $_sortBy',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.sort_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Doğrulama Barı ──────────────────────────────────────
  Widget? _buildVerifyBar() {
    final presentCount = _attendanceMap.values.where((v) => v).length;
    if (presentCount == 0 || _isLoading) return null;
    if (!DateUtils.isSameDay(_selectedDate, DateTime.now())) return null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _verifyAttendance,
            icon: const Icon(Icons.verified_user_rounded, size: 20),
            label: const Text(
              'Kamera ile Doğrula',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ),
      ),
    );
  }

  // ── Doğrulama Mantığı ──────────────────────────────────
  Future<void> _verifyAttendance() async {
    final result = await Navigator.push<PersonDetectionResult>(
      context,
      MaterialPageRoute(builder: (_) => const VerificationCameraPage()),
    );

    if (result == null || !mounted) return;

    final bleCount = _attendanceMap.values.where((v) => v).length;
    final cameraCount = result.personCount;

    // Supabase'e doğrulama logunu kaydet
    try {
      await _supabase.from('verification_logs').insert({
        'course_id': _course!['id'],
        'teacher_id': _supabase.auth.currentUser?.id,
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'ble_device_count': bleCount,
        'camera_person_count': cameraCount,
        'verification_status': bleCount > cameraCount
            ? 'device_excess'
            : (cameraCount > bleCount ? 'person_excess' : 'verified'),
        'confidence_avg': result.averageConfidence,
      });
    } catch (e) {
      debugPrint('Verification log kayıt hatası: $e');
    }

    if (!mounted) return;

    // Sonuca göre dialog göster
    if (bleCount > cameraCount) {
      _showDeviceExcessDialog(bleCount, cameraCount);
    } else if (cameraCount > bleCount) {
      _showPersonExcessDialog(bleCount, cameraCount);
    } else {
      _showVerifiedDialog(bleCount, cameraCount);
    }
  }

  // ⚠️ Cihaz sayısı > Kişi sayısı
  void _showDeviceExcessDialog(int bleCount, int cameraCount) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: AppColors.error, size: 32),
              ),
              const SizedBox(height: 16),
              const Text('Uyumsuzluk Tespit Edildi!',
                  style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(
                'Kişi sayısı eksik, cihaz sayısı fazla!',
                style: TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.w600,
                  fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _buildCountComparison(bleCount, cameraCount),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.error, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'Sınıfta olmayan öğrenciler BLE ile yoklamaya giriş yapmış olabilir.',
                      style: TextStyle(color: AppColors.errorText, fontSize: 12),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Tamam',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ℹ️ Kişi sayısı > Cihaz sayısı
  void _showPersonExcessDialog(int bleCount, int cameraCount) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_disabled_rounded,
                    color: Color(0xFFE67E22), size: 32),
              ),
              const SizedBox(height: 16),
              const Text('Eksik Cihaz Tespit Edildi',
                  style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              const Text(
                'Telefonunda sorun olan öğrenci var mı?',
                style: TextStyle(
                  color: Color(0xFFE67E22), fontWeight: FontWeight.w600,
                  fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _buildCountComparison(bleCount, cameraCount),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: Color(0xFFE67E22), size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'Telefonunda sorun olan öğrenciler QR kod ile giriş yapabilir.',
                      style: TextStyle(color: Color(0xFFE67E22), fontSize: 12),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Kapat'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showQRCode();
                      },
                      icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                      label: const Text('QR Aç'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ Eşleşme başarılı
  void _showVerifiedDialog(int bleCount, int cameraCount) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 36),
              ),
              const SizedBox(height: 16),
              const Text('Yoklama Doğrulandı!',
                  style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(
                'Kamera ve BLE sonuçları eşleşiyor',
                style: TextStyle(
                  color: AppColors.success, fontWeight: FontWeight.w600,
                  fontSize: 14),
              ),
              const SizedBox(height: 16),
              _buildCountComparison(bleCount, cameraCount),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Harika!',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountComparison(int bleCount, int cameraCount) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.bluetooth_rounded, color: AppColors.primary, size: 24),
                const SizedBox(height: 6),
                Text('$bleCount', style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
                const Text('BLE Cihaz', style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.compare_arrows_rounded,
              color: AppColors.textSecondary, size: 24),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.camera_alt_rounded, color: Color(0xFF6C63FF), size: 24),
                const SizedBox(height: 6),
                Text('$cameraCount', style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold,
                  color: Color(0xFF6C63FF))),
                const Text('Kamera Kişi', style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ),
      ],
    );
  }


  @override
  void dispose() {
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              student['first_name'][0].toUpperCase(),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${student['first_name']} ${student['last_name']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  student['school_no'] ?? '',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
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
  final bool isEnabled;
  final int timer;
  final VoidCallback onTap;
  const _AutomationButton({
    required this.isActive,
    this.isEnabled = true,
    required this.timer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool effectiveEnabled = isEnabled && !isActive;
    return InkWell(
      onTap: effectiveEnabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive 
              ? Colors.white 
              : (isEnabled ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEnabled ? Colors.white.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isActive) ...[
              const Icon(
                Icons.bluetooth_searching_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              isActive
                  ? 'Taranıyor... ($timer s)'
                  : 'Otomatik Yoklamayı Başlat',
              style: TextStyle(
                color: isActive 
                    ? AppColors.primary 
                    : (isEnabled ? Colors.white : Colors.white54),
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
  final int slot;
  const _QRDisplayDialog({
    required this.courseId,
    required this.courseName,
    required this.dateStr,
    required this.slot,
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
  double? _teacherLat;
  double? _teacherLng;

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
    if (status.values.every((s) => s.isGranted)) {
      _startBeacon();
      _getTeacherLocation();
    }
  }

  Future<void> _getTeacherLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(() {
        _teacherLat = position.latitude;
        _teacherLng = position.longitude;
      });
      // Regenerate QR data with location!
      _generateData();
    } catch (e) {
      debugPrint('Location Error: $e');
    }
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
        'slot': widget.slot,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'beacon_token': _currentBeaconToken,
        'secure': true,
        'lat': _teacherLat,
        'lng': _teacherLng,
      });
      _secondsLeft = 30;
    });
    if (_isBeaconActive) _startBeacon();
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
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 45,
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
                    (date.isAfter(termStart) ||
                        DateUtils.isSameDay(date, termStart)) &&
                    (date.isBefore(termEnd) ||
                        DateUtils.isSameDay(date, termEnd));
                final bool isSched = inTerm && widget.isScheduledDay(date);
                final bool isSelected = DateUtils.isSameDay(
                  date,
                  _selectedDate,
                );
                return InkWell(
                  onTap: isSched && (date.isBefore(DateTime.now()) || DateUtils.isSameDay(date, DateTime.now()))
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



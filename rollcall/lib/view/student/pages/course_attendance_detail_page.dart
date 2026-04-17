import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/theme/colors/app_colors.dart';

// ACADEMIC TERM DATES
final DateTime termStart = DateTime(2026, 2, 9);
final DateTime termEnd = DateTime(2026, 6, 12);

class CourseAttendanceDetailPage extends StatefulWidget {
  final Map<String, dynamic> course;
  final String studentId;

  const CourseAttendanceDetailPage({
    super.key,
    required this.course,
    required this.studentId,
  });

  @override
  State<CourseAttendanceDetailPage> createState() =>
      _CourseAttendanceDetailPageState();
}

class _CourseAttendanceDetailPageState
    extends State<CourseAttendanceDetailPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _timelineData = [];

  @override
  void initState() {
    super.initState();
    _loadTimelineData();
  }

  Future<void> _loadTimelineData() async {
    try {
      final sb = Supabase.instance.client;

      // 1. Fetch current attendance records from DB
      final attendanceRecords = await sb
          .from('attendance')
          .select()
          .eq('course_id', widget.course['id'])
          .eq('student_id', widget.studentId);

      final Map<String, bool> attendanceMap = {};
      for (var rec in attendanceRecords) {
        attendanceMap[rec['date']] = rec['is_present'] ?? false;
      }

      // 2. Generate all course dates for the term
      final courseDayRaw = widget.course['course_day'] ?? '';
      final List<String> scheduledDays = courseDayRaw
          .toString()
          .toLowerCase()
          .split(',')
          .map((e) => e.trim())
          .toList();

      List<Map<String, dynamic>> timeline = [];
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);

      for (
        DateTime d = termStart;
        d.isBefore(termEnd) || DateUtils.isSameDay(d, termEnd);
        d = d.add(const Duration(days: 1))
      ) {
        final dayEnglish = DateFormat('EEEE').format(d).toLowerCase();

        if (scheduledDays.contains(dayEnglish)) {
          final dateStr = DateFormat('yyyy-MM-dd').format(d);
          final bool? isPresentInDb = attendanceMap[dateStr];

          String status = 'not_started';
          if (isPresentInDb != null) {
            status = isPresentInDb ? 'present' : 'absent';
          } else if (DateUtils.isSameDay(d, today)) {
            // Check if class is ongoing
            try {
              final String startStr = widget.course['course_time'] ?? '00:00:00';
              final String endStr = widget.course['course_end_time'] ?? '00:00:00';
              
              final startParts = startStr.split(':');
              final endParts = endStr.split(':');
              
              final startTotal = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
              int endTotal = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
              if (endTotal <= startTotal) endTotal = startTotal + 180;
              
              final nowTotal = now.hour * 60 + now.minute;
              
              if (nowTotal >= startTotal && nowTotal <= endTotal) {
                status = 'ongoing';
              } else if (nowTotal > endTotal) {
                status = 'absent';
              }
            } catch (_) {}
          } else if (d.isBefore(today)) {
            // No DB record but date passed -> student missed it
            status = 'absent';
          }

          timeline.add({'date': d, 'status': status});
        }
      }

      // Reverse to show newest first
      timeline = timeline.reversed.toList();

      if (!mounted) return;
      setState(() {
        _timelineData = timeline;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Veriler yüklenemedi: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final courseName = _translateCourseName(widget.course['course_name']);
    final courseCode = widget.course['course_code'] ?? '';

    final attendedCount = _timelineData
        .where((r) => r['status'] == 'present')
        .length;
    final absentCount = _timelineData
        .where((r) => r['status'] == 'absent')
        .length;
    final totalScheduled = _timelineData.length;

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
        title: Column(
          children: [
            Text(
              courseName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              courseCode,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SummaryStat(
                  label: 'Katılım',
                  value: attendedCount.toString(),
                  icon: Icons.check_circle_outline_rounded,
                  color: Colors.greenAccent,
                ),
                _SummaryStat(
                  label: 'Devamsızlık',
                  value: absentCount.toString(),
                  icon: Icons.highlight_off_rounded,
                  color: Colors.redAccent,
                ),
                _SummaryStat(
                  label: 'Toplam Ders',
                  value: totalScheduled.toString(),
                  icon: Icons.calendar_today_rounded,
                  color: Colors.white,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _timelineData.isEmpty
                ? Center(
                    child: Text(
                      'Ders programı bulunamadı.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                    itemCount: _timelineData.length,
                    itemBuilder: (context, index) {
                      final item = _timelineData[index];
                      return _TimelineTile(
                        date: item['date'],
                        status: item['status'],
                        isFirst: index == 0,
                        isLast: index == _timelineData.length - 1,
                        courseTime: _formatTimeRange(
                          widget.course['course_time'],
                          widget.course['course_end_time'],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color.withValues(alpha: 0.8), size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final DateTime date;
  final String status;
  final bool isFirst, isLast;
  final String courseTime;

  const _TimelineTile({
    required this.date,
    required this.status,
    required this.isFirst,
    required this.isLast,
    required this.courseTime,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case 'present':
        statusColor = Colors.green;
        statusIcon = Icons.check;
        statusText = 'KATILDI';
        break;
      case 'absent':
        statusColor = Colors.red;
        statusIcon = Icons.close;
        statusText = 'KATILMADI';
        break;
      case 'ongoing':
        statusColor = Colors.orange;
        statusIcon = Icons.motion_photos_on_rounded;
        statusText = 'DEVAM EDİYOR';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.timer_outlined;
        statusText = 'HENÜZ BAŞLAMADI';
    }

    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst
                        ? Colors.transparent
                        : AppColors.primary.withValues(alpha: 0.1),
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(statusIcon, size: 10, color: Colors.white),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : AppColors.primary.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('dd MMMM yyyy', 'tr').format(date),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              courseTime,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status == 'not_started'
                            ? '-'
                            : (status == 'present' ? 'Oran: 1/1' : 'Oran: 0/1'),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

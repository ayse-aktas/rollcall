import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/theme/colors/app_colors.dart';

class CourseAttendanceDetailPage extends StatefulWidget {
  final Map<String, dynamic> course;
  final String studentId;

  const CourseAttendanceDetailPage({
    super.key,
    required this.course,
    required this.studentId,
  });

  @override
  State<CourseAttendanceDetailPage> createState() => _CourseAttendanceDetailPageState();
}

class _CourseAttendanceDetailPageState extends State<CourseAttendanceDetailPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _attendanceRecords = [];

  @override
  void initState() {
    super.initState();
    _fetchAttendanceRecords();
  }

  Future<void> _fetchAttendanceRecords() async {
    try {
      final sb = Supabase.instance.client;
      final response = await sb
          .from('attendance')
          .select()
          .eq('course_id', widget.course['id'])
          .eq('student_id', widget.studentId)
          .order('date', ascending: false);

      if (!mounted) return;
      setState(() {
        _attendanceRecords = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Veriler yüklenemedi: $e'), backgroundColor: AppColors.error),
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

  @override
  Widget build(BuildContext context) {
    final courseName = _translateCourseName(widget.course['course_name']);
    final courseCode = widget.course['course_code'] ?? '';

    final attendedCount = _attendanceRecords.where((r) => r['is_present'] == true).length;
    final totalCount = _attendanceRecords.length;

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
        title: Column(
          children: [
            Text(courseName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(courseCode, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
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
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
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
                  value: (totalCount - attendedCount).toString(),
                  icon: Icons.highlight_off_rounded,
                  color: Colors.redAccent,
                ),
                _SummaryStat(
                  label: 'Toplam Ders',
                  value: totalCount.toString(),
                  icon: Icons.calendar_today_rounded,
                  color: Colors.white,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _attendanceRecords.isEmpty
                    ? Center(child: Text('Yoklama kaydı bulunamadı.', style: TextStyle(color: AppColors.textSecondary)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                        itemCount: _attendanceRecords.length,
                        itemBuilder: (context, index) {
                          final record = _attendanceRecords[index];
                          final dateStr = record['date'] ?? '';
                          final isPresent = record['is_present'] ?? false;
                          final date = DateTime.tryParse(dateStr) ?? DateTime.now();
                          
                          return _TimelineTile(
                            date: date,
                            isPresent: isPresent,
                            isFirst: index == 0,
                            isLast: index == _attendanceRecords.length - 1,
                            courseTime: widget.course['course_time'] ?? '--:--',
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
  const _SummaryStat({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color.withValues(alpha: 0.8), size: 24),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final DateTime date;
  final bool isPresent;
  final bool isFirst, isLast;
  final String courseTime;

  const _TimelineTile({
    required this.date,
    required this.isPresent,
    required this.isFirst,
    required this.isLast,
    required this.courseTime,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor = isPresent ? Colors.green : Colors.red;
    IconData statusIcon = isPresent ? Icons.check : Icons.close;

    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Expanded(child: Container(width: 2, color: isFirst ? Colors.transparent : AppColors.primary.withValues(alpha: 0.1))),
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Icon(statusIcon, size: 10, color: Colors.white),
                ),
                Expanded(child: Container(width: 2, color: isLast ? Colors.transparent : AppColors.primary.withValues(alpha: 0.1))),
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
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('dd MMMM yyyy', 'tr').format(date),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(courseTime, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isPresent ? 'KATILDI' : 'KATILMADI',
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Oran: ${isPresent ? "1/1" : "0/1"}',
                        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
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

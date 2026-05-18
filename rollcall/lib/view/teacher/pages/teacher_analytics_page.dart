import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/theme/colors/app_colors.dart';

// Term dates - Should ideally come from a config or DB, but using constants for now as in CourseStudentsPage
final DateTime termStart = DateTime(2026, 2, 9);
final DateTime termEnd = DateTime(2026, 6, 12);

class TeacherAnalyticsPage extends StatefulWidget {
  final Map<String, dynamic> course;

  const TeacherAnalyticsPage({super.key, required this.course});

  @override
  State<TeacherAnalyticsPage> createState() => _TeacherAnalyticsPageState();
}

class _TeacherAnalyticsPageState extends State<TeacherAnalyticsPage> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;

  Map<DateTime, int> _heatmapData = {};
  List<FlSpot> _trendSpots = [];
  List<String> _dateLabels = [];
  int _totalStudents = 0;
  double _averageAttendanceRate = 0;
  List<Map<String, dynamic>> _allAttendanceRecords = [];
  
  List<Map<String, dynamic>> _students = [];
  List<DateTime> _allScheduledDates = [];
  Set<String> _selectedStudentIds = {};
  List<Map<String, dynamic>> _tableColumns = [];

  // Stats
  int _totalLectures = 0;
  int _lecturesHeld = 0;

  int _currentPage = 0;
  final int _rowsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _fetchAnalyticsData();
  }

  Future<void> _fetchAnalyticsData() async {
    setState(() => _isLoading = true);

    try {
      final courseId = widget.course['id'];
      final courseDayRaw = widget.course['course_day'] ?? '';
    final List<String> scheduledDays = courseDayRaw
        .toString()
        .toLowerCase()
        .split(',')
        .map((e) => e.trim())
        .toList();

    // 1. Fetch all students registered to this course
    final studentsRes = await _supabase
        .from('student_courses')
        .select('student_id, users(id, first_name, last_name, school_no)')
        .eq('course_id', courseId);
    
    _students = List<Map<String, dynamic>>.from(studentsRes);
    _students.sort((a, b) {
      final noA = (a['users']?['school_no'] ?? '').toString();
      final noB = (b['users']?['school_no'] ?? '').toString();
      return noA.compareTo(noB);
    });
    _totalStudents = _students.length;

    // 2. Fetch all attendance records
      // NOT: Supabase veritabanında 'taken_by' kolonu ve foreign key henüz tanımlanmadığı için 
      // sayfanın çökmesini engellemek adına o kısımları sorgudan çıkardık.
      final attendanceRes = await _supabase
          .from('attendance')
          .select('date, student_id, is_present, slot, created_at')
          .eq('course_id', courseId)
          .order('date');

      _allAttendanceRecords = List<Map<String, dynamic>>.from(attendanceRes);

    // 3. Generate ALL scheduled dates for the term
    _allScheduledDates = [];
    for (
      DateTime d = termStart;
      d.isBefore(termEnd) || DateUtils.isSameDay(d, termEnd);
      d = d.add(const Duration(days: 1))
    ) {
      final dayEnglish = DateFormat('EEEE').format(d).toLowerCase();
      if (scheduledDays.contains(dayEnglish)) {
        _allScheduledDates.add(d);
      }
    }

    _totalLectures = _allScheduledDates.length;
    _lecturesHeld = 0;

    // Find all unique (date, time) in attendance records
    Map<String, Set<String>> dateTimes = {};
    for (var record in _allAttendanceRecords) {
      final date = record['date'] as String;
      final createdAt = record['created_at'] as String?;
      String time = '-';
      if (createdAt != null) {
        final dt = DateTime.parse(createdAt).toLocal();
        time = DateFormat('HH:mm').format(dt);
      }
      dateTimes.putIfAbsent(date, () => {}).add(time);
    }

    _tableColumns = [];
    for (var date in _allScheduledDates) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final times = dateTimes[dateStr];
      if (times != null && times.isNotEmpty) {
        final sortedTimes = times.toList()..sort();
        for (var time in sortedTimes) {
          _tableColumns.add({
            'date': date,
            'dateStr': dateStr,
            'time': time,
          });
        }
      } else {
        // No attendance taken on this day
        _tableColumns.add({
          'date': date,
          'dateStr': dateStr,
          'time': '-',
        });
      }
    }

    // 4. Group attendance by date for charts
    Map<String, List<bool>> groupedByDate = {};
    for (var record in _allAttendanceRecords) {
      final date = record['date'] as String;
      final isPresent = record['is_present'] as bool;
      groupedByDate.putIfAbsent(date, () => []).add(isPresent);
    }

    Map<DateTime, int> heatmap = {};
    List<FlSpot> spots = [];
    List<String> labels = [];
    double totalRateSum = 0;
    int dayIndex = 0;

    for (var date in _allScheduledDates) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final hasData = groupedByDate.containsKey(dateStr);
      
      // If the date has data or it is a date in the past (where a lecture should have happened)
      if (hasData || date.isBefore(DateTime.now())) {
        final list = groupedByDate[dateStr] ?? [];
        final presentCount = list.where((p) => p == true).length;
        
        heatmap[DateTime(date.year, date.month, date.day)] = presentCount;

        final rate = _totalStudents > 0 ? (presentCount / _totalStudents) * 100 : 0.0;
        spots.add(FlSpot(dayIndex.toDouble(), rate));
        labels.add(DateFormat('dd/MM').format(date));
        
        if (hasData) {
          totalRateSum += rate;
          _lecturesHeld++;
        } else if (date.isBefore(DateTime.now())) {
            _lecturesHeld++;
        }
        dayIndex++;
      }
    }

    if (_lecturesHeld > 0) {
      _averageAttendanceRate = totalRateSum / _lecturesHeld;
    }

      if (!mounted) return;
      setState(() {
        _heatmapData = heatmap;
        _trendSpots = spots;
        _dateLabels = labels;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Veriler yüklenirken hata oluştu: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportToPDF() async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    
    // Build headers
    final List<String> headers = ['Okul No', 'İsim Soyisim'];
    for (var col in _tableColumns) {
      final date = col['date'] as DateTime;
      final time = col['time'] as String;
      headers.add(time != '-' ? '${DateFormat('dd/MM').format(date)}\n($time)' : DateFormat('dd/MM').format(date));
    }

    // Build data rows
    final List<List<String>> data = [];
    for (var studentData in _students) {
      final student = studentData['users'] as Map<String, dynamic>;
      final studentId = student['id'];
      final studentAttendance = _allAttendanceRecords.where((r) => r['student_id'] == studentId).toList();
      
      final List<String> row = [
        student['school_no'] ?? '-',
        '${student['first_name']} ${student['last_name']}',
      ];
      
      for (var col in _tableColumns) {
        final dateStr = col['dateStr'] as String;
        final time = col['time'] as String;
        
        final records = studentAttendance.where((r) => r['date'] == dateStr).toList();
        Map<String, dynamic> record = {};
        if (time == '-') {
          if (records.isNotEmpty) record = records.first;
        } else {
          record = records.firstWhere((r) {
            final createdAt = r['created_at'] as String?;
            if (createdAt == null) return false;
            final dt = DateTime.parse(createdAt).toLocal();
            return DateFormat('HH:mm').format(dt) == time;
          }, orElse: () => {});
        }
        
        if (record.isEmpty) {
          if (col['date'].isBefore(DateTime.now())) {
            row.add('X'); // Absent
          } else {
            row.add('-'); // Future
          }
        } else {
          row.add(record['is_present'] == true ? 'V' : 'X');
        }
      }
      data.add(row);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Yoklama Raporu - ${widget.course['course_name']}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Kurs Kodu: ${widget.course['course_code']}'),
          pw.Text('Rapor Tarihi: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}'),
          pw.Text('Ortalama Katılım: %${_averageAttendanceRate.toStringAsFixed(1)}'),
          pw.Text('Yapılan Ders: $_lecturesHeld / $_totalLectures'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: data,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6),
            cellStyle: const pw.TextStyle(fontSize: 6),
          ),
        ],
      ),
    );

    final Uint8List bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'yoklama_raporu_${widget.course['course_code']}.pdf');
  }

  Future<void> _exportSelectedStudentsPDF() async {
    if (_selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir öğrenci seçin')),
      );
      return;
    }

    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    
    final selectedStudents = _students.where((s) => _selectedStudentIds.contains(s['student_id'])).toList();

    if (selectedStudents.length > 1) {
      // Landscape table for multiple students
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          theme: pw.ThemeData.withFont(base: font, bold: boldFont),
          build: (pw.Context context) => [

            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Öğrenci Devam Çizelgesi', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                  pw.Text(widget.course['course_code'], style: pw.TextStyle(color: PdfColors.grey)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Ders: ${widget.course['course_name']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('Rapor Tarihi: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}'),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: [
                'No', 'Okul No', 'İsim Soyisim',
                ..._tableColumns.map((col) {
                  final date = col['date'] as DateTime;
                  final time = col['time'] as String;
                  return time != '-' ? '${DateFormat('dd/MM').format(date)}\n($time)' : DateFormat('dd/MM').format(date);
                })
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6),
              cellStyle: const pw.TextStyle(fontSize: 6),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              data: List.generate(selectedStudents.length, (index) {
                final studentData = selectedStudents[index];
                final student = studentData['users'] as Map<String, dynamic>;
                final studentId = student['id'];
                final studentAttendance = _allAttendanceRecords.where((r) => r['student_id'] == studentId).toList();
                
                final List<String> row = [
                  (index + 1).toString(),
                  student['school_no'] ?? '-',
                  '${student['first_name']} ${student['last_name']}',
                ];
                
                for (var col in _tableColumns) {
                  final dateStr = col['dateStr'] as String;
                  final time = col['time'] as String;
                  
                  final records = studentAttendance.where((r) => r['date'] == dateStr).toList();
                  Map<String, dynamic> record = {};
                  if (time == '-') {
                    if (records.isNotEmpty) record = records.first;
                  } else {
                    record = records.firstWhere((r) {
                      final createdAt = r['created_at'] as String?;
                      if (createdAt == null) return false;
                      final dt = DateTime.parse(createdAt).toLocal();
                      return DateFormat('HH:mm').format(dt) == time;
                    }, orElse: () => {});
                  }
                  
                  if (record.isEmpty) {
                    if (col['date'].isBefore(DateTime.now())) {
                      row.add('X'); // Absent
                    } else {
                      row.add('-'); // Future
                    }
                  } else {
                    row.add(record['is_present'] == true ? 'V' : 'X');
                  }
                }
                return row;
              }),
            ),
          ],
        ),
      );
    } else {
      // Single student detailed report (if only 1 selected, maybe keep the detailed view but fixed)
      final studentData = selectedStudents.first;
      final student = studentData['users'] as Map<String, dynamic>;
      final studentId = student['id'];
      
      // Attendance for this student - unique dates only
      final studentAttendance = _allAttendanceRecords.where((r) => r['student_id'] == studentId).toList();
      
      // Calculate stats based on unique scheduled dates
      int presentCount = 0;
      int totalPossibleHeld = 0;
      
      for (var date in _allScheduledDates) {
        if (date.isAfter(DateTime.now())) continue;
        totalPossibleHeld++;
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final hasRecord = studentAttendance.any((r) => r['date'] == dateStr && r['is_present'] == true);
        if (hasRecord) presentCount++;
      }
      
      final rate = totalPossibleHeld > 0 ? (presentCount / totalPossibleHeld) * 100 : 0.0;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: font, bold: boldFont),
          build: (pw.Context context) => [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Öğrenci Devam Raporu', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                  pw.Text(widget.course['course_code'], style: pw.TextStyle(color: PdfColors.grey)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Container(
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Text('Öğrenci:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(width: 5),
                      pw.Text('${student['first_name']} ${student['last_name']}'),
                    ],
                  ),
                  pw.SizedBox(height: 5),
                  pw.Row(
                    children: [
                      pw.Text('Okul No:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(width: 5),
                      pw.Text(student['school_no'] ?? '-'),
                    ],
                  ),
                  pw.SizedBox(height: 5),
                  pw.Row(
                    children: [
                      pw.Text('Ders:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(width: 5),
                      pw.Text(widget.course['course_name']),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildPdfStatCard('İşlenen Ders', totalPossibleHeld.toString()),
                _buildPdfStatCard('Katılım Sağlanan', presentCount.toString()),
                _buildPdfStatCard('Devam Oranı', '%${rate.toStringAsFixed(1)}'),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Text('Detaylı Yoklama Listesi', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: ['No', 'Tarih', 'Durum'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.center,
              data: List.generate(_allScheduledDates.length, (index) {
                final date = _allScheduledDates[index];
                final dateStr = DateFormat('yyyy-MM-dd').format(date);
                final record = studentAttendance.firstWhere((r) => r['date'] == dateStr, orElse: () => {});
                
                String status = '-';
                if (record.isNotEmpty) {
                  status = record['is_present'] ? 'VAR' : 'YOK';
                } else if (date.isBefore(DateTime.now())) {
                  status = 'YOK';
                }

                return [
                  (index + 1).toString(),
                  DateFormat('dd.MM.yyyy').format(date),
                  status,
                ];
              }),
            ),
          ],
        ),
      );
    }

    final Uint8List bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'ogrenci_devam_raporu_${widget.course['course_code']}.pdf');
  }

  pw.Widget _buildPdfStatCard(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _exportToExcel() async {
    var excel = ex.Excel.createExcel();
    ex.Sheet sheetObject = excel['Yoklama Raporu'];
    excel.delete('Sheet1');

    List<ex.CellValue> headerRow = [
      ex.TextCellValue('Okul No'),
      ex.TextCellValue('İsim Soyisim'),
    ];
    
    for (var col in _tableColumns) {
      final date = col['date'] as DateTime;
      final time = col['time'] as String;
      final label = time != '-' ? '${DateFormat('dd/MM').format(date)} ($time)' : DateFormat('dd/MM').format(date);
      headerRow.add(ex.TextCellValue(label));
    }
    
    sheetObject.appendRow(headerRow);

    for (var studentData in _students) {
      final student = studentData['users'] as Map<String, dynamic>;
      final studentId = student['id'];
      final studentAttendance = _allAttendanceRecords.where((r) => r['student_id'] == studentId).toList();
      
      List<ex.CellValue> row = [
        ex.TextCellValue((student['school_no'] ?? '-').toString()),
        ex.TextCellValue('${student['first_name']} ${student['last_name']}'),
      ];
      
      for (var col in _tableColumns) {
        final dateStr = col['dateStr'] as String;
        final time = col['time'] as String;
        
        final records = studentAttendance.where((r) => r['date'] == dateStr).toList();
        Map<String, dynamic> record = {};
        if (time == '-') {
          if (records.isNotEmpty) record = records.first;
        } else {
          record = records.firstWhere((r) {
            final createdAt = r['created_at'] as String?;
            if (createdAt == null) return false;
            final dt = DateTime.parse(createdAt).toLocal();
            return DateFormat('HH:mm').format(dt) == time;
          }, orElse: () => {});
        }
        
        if (record.isEmpty) {
          if (col['date'].isBefore(DateTime.now())) {
            row.add(ex.TextCellValue('YOK'));
          } else {
            row.add(ex.TextCellValue('-'));
          }
        } else {
          row.add(ex.TextCellValue(record['is_present'] ? 'VAR' : 'YOK'));
        }
      }
      
      sheetObject.appendRow(row);
    }

    final fileBytes = excel.save();
    
    if (fileBytes != null) {
      final String fileName = 'yoklama_raporu_${widget.course['course_code']}.xlsx';
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/$fileName').create();
      await file.writeAsBytes(fileBytes);
      
      if (context.mounted) {
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Yoklama Raporu',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final courseName = _translateCourseName(widget.course['course_name']);
    final courseDayRaw = widget.course['course_day'] ?? '';
    final courseTimeRaw = widget.course['course_time'] ?? '';
    final courseEndTimeRaw = widget.course['course_end_time'] ?? '';

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
        title: const Text(
          'Ders İstatistikleri',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (context) => _buildExportSheet(),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Replicated Header from CourseStudentsPage
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
                              Text(
                                courseName,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
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
                                        _translateDay(courseDayRaw),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
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
                                        _formatTimeRange(courseTimeRaw, courseEndTimeRaw),
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
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryCards(),
                        const SizedBox(height: 28),
                        _buildSectionHeader('Ders Yoğunluğu (Isı Haritası)', Icons.grid_view_rounded),
                        const SizedBox(height: 12),
                        _buildHeatmap(),
                        const SizedBox(height: 32),
                        _buildSectionHeader('Katılım Trendi (%)', Icons.show_chart_rounded),
                        const SizedBox(height: 12),
                        _buildTrendChart(),
                        const SizedBox(height: 32),
                        _buildSectionHeader('Öğrenci Listesi & Devam Durumu', Icons.people_outline_rounded),
                        const SizedBox(height: 12),
                        _buildStudentAttendanceTable(),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: _selectedStudentIds.isNotEmpty 
        ? FloatingActionButton.extended(
            onPressed: _exportSelectedStudentsPDF,
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
            label: Text('Seçilenleri İndir (${_selectedStudentIds.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        : null,
    );
  }

  Widget _buildStudentAttendanceTable() {
    if (_students.isEmpty) return const SizedBox();

    final int totalPages = (_students.length / _rowsPerPage).ceil();
    final int startIndex = _currentPage * _rowsPerPage;
    final int endIndex = (startIndex + _rowsPerPage > _students.length) 
        ? _students.length 
        : startIndex + _rowsPerPage;
    final paginatedStudents = _students.sublist(startIndex, endIndex);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 10)),
        ],
        border: Border.all(color: AppColors.border.withAlpha(5*25)),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(24),
              topRight: const Radius.circular(24),
              bottomLeft: totalPages > 1 ? Radius.zero : const Radius.circular(24),
              bottomRight: totalPages > 1 ? Radius.zero : const Radius.circular(24),
            ),
            child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 24,
            horizontalMargin: 20,
            headingRowHeight: 56,
            dataRowMaxHeight: 60,
            headingRowColor: WidgetStateProperty.all(AppColors.primary.withAlpha(1*25)),
            columns: [
              DataColumn(
                label: Row(
                  children: [
                    const Text('Öğrenci', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Tüm Sayfalardaki Öğrencileri Seç',
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (_selectedStudentIds.length == _students.length) {
                              _selectedStudentIds.clear();
                            } else {
                              _selectedStudentIds = _students.map((s) => s['student_id'] as String).toSet();
                            }
                          });
                        },
                        child: Icon(
                          Icons.select_all_rounded, 
                          size: 20, 
                          color: _selectedStudentIds.length == _students.length ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...List.generate(_tableColumns.length, (index) {
                final col = _tableColumns[index];
                final date = col['date'] as DateTime;
                final time = col['time'] as String;
                
                return DataColumn(
                  label: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('dd/MM').format(date),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                      ),
                      if (time != '-')
                        Text(
                          time,
                          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                );
              }),
            ],
            rows: paginatedStudents.map((studentData) {
              final student = studentData['users'] as Map<String, dynamic>;
              final studentId = student['id'];
              final isSelected = _selectedStudentIds.contains(studentId);
              
              final studentAttendance = _allAttendanceRecords.where((r) => r['student_id'] == studentId).toList();

              return DataRow(
                selected: isSelected,
                onSelectChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedStudentIds.add(studentId);
                    } else {
                      _selectedStudentIds.remove(studentId);
                    }
                  });
                },
                cells: [
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${student['first_name']} ${student['last_name']}', 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(student['school_no'] ?? '-', 
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ),
                  ..._tableColumns.map((col) {
                    final dateStr = col['dateStr'] as String;
                    final time = col['time'] as String;
                    
                    final records = studentAttendance.where((r) => r['date'] == dateStr).toList();
                    Map<String, dynamic> record = {};
                    if (time == '-') {
                      if (records.isNotEmpty) record = records.first;
                    } else {
                      record = records.firstWhere((r) {
                        final createdAt = r['created_at'] as String?;
                        if (createdAt == null) return false;
                        final dt = DateTime.parse(createdAt).toLocal();
                        return DateFormat('HH:mm').format(dt) == time;
                      }, orElse: () => {});
                    }
                    
                    if (record.isEmpty) {
                      if (col['date'].isBefore(DateTime.now())) {
                        return const DataCell(Icon(Icons.close_rounded, color: Colors.redAccent, size: 18));
                      }
                      return const DataCell(Text('-', style: TextStyle(color: Colors.grey)));
                    }

                    return DataCell(
                      Icon(
                        record['is_present'] ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: record['is_present'] ? Colors.green : Colors.redAccent,
                        size: 20,
                      ),
                    );
                  }),
                ],
              );
            }).toList(),
          ),
        ),
      ),
          if (totalPages > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border.withAlpha(5*25))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${startIndex + 1}-$endIndex / ${_students.length} Öğrenci',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, size: 20),
                        color: AppColors.primary,
                        onPressed: _currentPage > 0 ? () {
                          setState(() { _currentPage--; });
                        } : null,
                      ),
                      Text(
                        '${_currentPage + 1} / $totalPages',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded, size: 20),
                        color: AppColors.primary,
                        onPressed: _currentPage < totalPages - 1 ? () {
                          setState(() { _currentPage++; });
                        } : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Adding translation helpers as they are used in the new UI
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

  Widget _buildExportSheet() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          const Text('Raporu Dışa Aktar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          _ExportTile(
            icon: Icons.picture_as_pdf_rounded,
            title: 'PDF Olarak Kaydet',
            subtitle: 'Profesyonel yoklama belgesi',
            color: Colors.redAccent,
            onTap: () {
              Navigator.pop(context);
              _exportToPDF();
            },
          ),
          const SizedBox(height: 12),
          _ExportTile(
            icon: Icons.table_chart_rounded,
            title: 'Excel Olarak Kaydet',
            subtitle: 'Veri analizi için .xlsx dosyası',
            color: Colors.green,
            onTap: () {
              Navigator.pop(context);
              _exportToExcel();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Toplam Öğrenci',
                value: _totalStudents.toString(),
                icon: Icons.people_rounded,
                color: Color(0xFF6366F1), // Indigo
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _StatCard(
                title: 'Ort. Katılım',
                value: '%${_averageAttendanceRate.toStringAsFixed(1)}',
                icon: Icons.analytics_rounded,
                color: Color(0xFF10B981), // Emerald
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Yapılan Ders',
                value: '$_lecturesHeld / $_totalLectures',
                icon: Icons.calendar_month_rounded,
                color: Color(0xFFF59E0B), // Amber
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeatmap() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 10)),
        ],
        border: Border.all(color: AppColors.border.withAlpha(5*25)),
      ),
      child: HeatMap(
        datasets: _heatmapData,
        colorsets: {
          1: Color(0xFFD1FAE5),
          max(1, (_totalStudents / 3).floor()): Color(0xFF6EE7B7),
          max(2, (_totalStudents * 2 / 3).floor()): Color(0xFF10B981),
          max(3, _totalStudents): Color(0xFF059669),
        },
        colorMode: ColorMode.color,
        showText: true,
        scrollable: true,
        size: 32,
        borderRadius: 8,
        fontSize: 11,
        margin: const EdgeInsets.all(3),
        onClick: (date) {
          final count = _heatmapData[DateTime(date.year, date.month, date.day)] ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${DateFormat('dd.MM.yyyy').format(date)}: $count öğrenci katıldı'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrendChart() {
    if (_trendSpots.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Text('Veri bulunamadı', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return Container(
      height: 280,
      padding: const EdgeInsets.fromLTRB(10, 28, 24, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 10)),
        ],
        border: Border.all(color: AppColors.border.withAlpha(5*25)),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withAlpha(1*25), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  int idx = value.toInt();
                  if (idx >= 0 && idx < _dateLabels.length && idx % (max(1, _dateLabels.length~/5)) == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(_dateLabels[idx], style: TextStyle(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                    );
                  }
                  return const Text('');
                },
                reservedSize: 30,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value % 20 != 0) return const Text('');
                  return Text('%${value.toInt()}', style: TextStyle(fontSize: 10, color: AppColors.textSecondary));
                },
                reservedSize: 35,
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: _trendSpots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: AppColors.primary,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                  radius: 4,
                  color: Colors.white,
                  strokeWidth: 2,
                  strokeColor: AppColors.primary,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.primary.withAlpha(2*25), AppColors.primary.withValues(alpha: 0.01)],
                ),
              ),
            ),
          ],
          minY: 0,
          maxY: 105,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (items) => items.map((i) => LineTooltipItem('%${i.y.toStringAsFixed(1)}', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 10)),
        ],
        border: Border.all(color: color.withAlpha(1*25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withAlpha(1*25), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ExportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withAlpha(1*25), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

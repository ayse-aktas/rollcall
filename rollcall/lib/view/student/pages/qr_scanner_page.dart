import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../../../core/utils/theme/colors/app_colors.dart';
import '../../../core/utils/security_utils.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final MobileScannerController controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _processQR(String code) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      try {
        await controller.stop();
      } catch (e) {
        debugPrint('Error stopping mobile scanner: $e');
      }

      final data = jsonDecode(code);
      if (data['type'] != 'attendance_qr') {
        throw 'Geçersiz QR kodu';
      }

      final String courseId = data['course_id'];
      final String date = data['date'];
      final int slot = data['slot'] ?? 1;
      final double? teacherLat = data['lat'];
      final double? teacherLng = data['lng'];

      // NEW: Distance Check (15 meters)
      if (teacherLat != null && teacherLng != null) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            throw 'Konum izni reddedildi.';
          }
        }

        final studentPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );

        final distance = Geolocator.distanceBetween(
          teacherLat,
          teacherLng,
          studentPosition.latitude,
          studentPosition.longitude,
        );

        if (distance > 15) {
          throw 'Hocaya çok uzaksınız. QR kodu okutabilmek için hocaya 15 metreden daha yakın olmalısınız. (Uzaklık: ${distance.toStringAsFixed(1)} m)';
        }
      }

      final supabase = Supabase.instance.client;
      final studentId = supabase.auth.currentUser?.id;

      if (studentId == null) throw 'Oturum açılmamış';

      // 1. Double check device binding
      final currentDeviceId = await SecurityUtils.getUniqueDeviceId();
      final userProfile = await supabase
          .from('users')
          .select('device_id')
          .eq('id', studentId)
          .single();

      if (userProfile['device_id'] != null &&
          userProfile['device_id'] != currentDeviceId) {
        throw 'Bu cihaz hesabınızla eşleşmiyor. Lütfen kayıtlı cihazınızı kullanın.';
      }

      // 2. Check if student is enrolled in this course
      final enrollment = await supabase
          .from('student_courses')
          .select('course_id')
          .eq('student_id', studentId)
          .eq('course_id', courseId)
          .maybeSingle();

      if (enrollment == null) {
        throw 'Bu derse kayıtlı değilsiniz. Lütfen doğru dersin QR kodunu okuttuğunuzdan emin olun.';
      }

      // 3. Record attendance
      try {
        final didSaveAttendance = await _upsertAttendanceWithOptionalMethod({
          'student_id': studentId,
          'course_id': courseId,
          'date': date,
          'slot': slot,
          'is_present': true,
          'verify_method': 'qr',
          'created_at': DateTime.now().toIso8601String(),
        });
        if (!didSaveAttendance) {
          throw 'Bu yoklama öğretmen tarafından manuel düzenlenmiş. QR ile değiştirilemez.';
        }
      } on PostgrestException catch (e) {
        if (e.code == '42501') {
          throw 'Yoklama kaydedilemedi. Veritabanı yetki hatası (RLS). Lütfen yöneticinizle iletişime geçin.';
        }
        rethrow;
      }

      if (!mounted) return;

      _showResultDialog(
        success: true,
        message: 'Yoklamanız güvenli bir şekilde alındı.',
      );
    } catch (e) {
      if (!mounted) return;

      String errorMessage = e.toString();
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11);
      } else if (e is PostgrestException) {
        errorMessage = 'Veritabanı hatası: ${e.message}';
      }

      _showResultDialog(success: false, message: errorMessage);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool> _upsertAttendanceWithOptionalMethod(
    Map<String, dynamic> values,
  ) async {
    final supabaseClient = Supabase.instance.client;
    try {
      final existing = await supabaseClient
          .from('attendance')
          .select('id, verify_method')
          .eq('student_id', values['student_id'])
          .eq('course_id', values['course_id'])
          .eq('date', values['date'])
          .eq('slot', values['slot'])
          .maybeSingle();

      if (existing != null) {
        if ((existing['verify_method'] ?? '').toString().toLowerCase() ==
            'manual') {
          return false;
        }
        await supabaseClient
            .from('attendance')
            .update(values)
            .eq('id', existing['id']);
      } else {
        await supabaseClient.from('attendance').insert(values);
      }
      return true;
    } on PostgrestException catch (e) {
      final message = e.message.toLowerCase();
      final isMissingMethodColumn =
          e.code == 'PGRST204' ||
          e.code == '42703' ||
          message.contains('verify_method') ||
          message.contains('column');
      if (!isMissingMethodColumn) rethrow;

      final fallbackValues = Map<String, dynamic>.from(values)
        ..remove('verify_method');

      final existing = await supabaseClient
          .from('attendance')
          .select('id, verify_method')
          .eq('student_id', fallbackValues['student_id'])
          .eq('course_id', fallbackValues['course_id'])
          .eq('date', fallbackValues['date'])
          .eq('slot', fallbackValues['slot'])
          .maybeSingle();

      if (existing != null) {
        if ((existing['verify_method'] ?? '').toString().toLowerCase() ==
            'manual') {
          return false;
        }
        await supabaseClient
            .from('attendance')
            .update(fallbackValues)
            .eq('id', existing['id']);
      } else {
        await supabaseClient.from('attendance').insert(fallbackValues);
      }
      return true;
    }
  }

  void _showResultDialog({required bool success, required String message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Icon(
          success ? Icons.check_circle_rounded : Icons.error_rounded,
          color: success ? AppColors.success : AppColors.error,
          size: 60,
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              if (success) {
                Navigator.pop(context); // Close scanner page
              } else {
                try {
                  await controller.start();
                } catch (e) {
                  debugPrint('Error starting mobile scanner: $e');
                }
              }
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'QR Okut',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primary,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _processQR(barcode.rawValue!);
                }
              }
            },
          ),
          // Scanner Overlay
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

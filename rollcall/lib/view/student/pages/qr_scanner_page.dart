import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../../../core/utils/theme/colors/app_colors.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final MobileScannerController controller = MobileScannerController();
  bool _isProcessing = false;

  Future<void> _processQR(String code) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final data = jsonDecode(code);
      if (data['type'] != 'attendance_qr') {
        throw 'Geçersiz QR kodu';
      }

      final String courseId = data['course_id'];
      final String date = data['date'];
      // final int timestamp = data['timestamp']; // Can be used for expiration check

      final supabase = Supabase.instance.client;
      final studentId = supabase.auth.currentUser?.id;

      if (studentId == null) throw 'Oturum açılmamış';

      // 1. Check if student is enrolled in this course
      final enrollment = await supabase
          .from('student_courses')
          .select()
          .eq('student_id', studentId)
          .eq('course_id', courseId)
          .maybeSingle();

      if (enrollment == null) {
        throw 'Bu dersin kayıtlı öğrencisi değilsiniz.';
      }

      // 2. Record attendance
      await supabase.from('attendance').upsert({
        'student_id': studentId,
        'course_id': courseId,
        'date': date,
        'is_present': true,
      }, onConflict: 'student_id, course_id, date');

      if (!mounted) return;
      
      _showResultDialog(
        success: true,
        message: 'Yoklamanız başarıyla alındı.',
      );
    } catch (e) {
      if (!mounted) return;
      _showResultDialog(
        success: false,
        message: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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
            onPressed: () {
              Navigator.pop(context); // Close dialog
              if (success) {
                Navigator.pop(context); // Close scanner page
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
        title: const Text('QR Okut', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
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
                border: Border.all(color: Colors.white, width: 2),
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

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:permission_handler/permission_handler.dart';
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

  // Beacon variables
  StreamSubscription<RangingResult>? _beaconSubscription;
  bool _proximityVerified = false;
  String? _detectedBeaconToken;

  @override
  void initState() {
    super.initState();
    _initBeaconScanning();
  }

  Future<void> _initBeaconScanning() async {
    final status = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (status.values.every((s) => s.isGranted)) {
      try {
        await flutterBeacon.initializeScanning;

        // Match the UUID used in Teacher app
        final regions = <Region>[
          Region(
            identifier: 'RollCallBeacon',
            proximityUUID: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
          ),
        ];

        _beaconSubscription = flutterBeacon.ranging(regions).listen((result) {
          if (result.beacons.isNotEmpty) {
            // Sort by signal strength (RSSI)
            final closest = result.beacons.reduce(
              (a, b) => a.rssi > b.rssi ? a : b,
            );

            // Proximity check (approximately < 5-10 meters if RSSI > -85)
            if (closest.rssi > -85) {
              setState(() {
                _proximityVerified = true;
                _detectedBeaconToken = closest.minor.toString();
              });
            }
          }
        });
      } catch (e) {
        debugPrint('Beacon Scan Error: $e');
      }
    }
  }

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
      final bool isSecure = data['secure'] ?? false;
      final String? expectedBeaconToken = data['beacon_token'];

      // SECURE MODE VALIDATION
      if (isSecure && expectedBeaconToken != null) {
        if (!_proximityVerified) {
          // USER FALLBACK: QR only session (as per user request)
          debugPrint(
            'SECURITY WARNING: Proximity NOT verified. Proceeding with QR-only fallback.',
          );
        } else if (_detectedBeaconToken != expectedBeaconToken) {
          // Token mismatch (could be old beacon scan or buddy reporting attempt)
          // But since tokens rotate every 30s, we allow a small window.
          final bool isValidToken = SecurityUtils.verifyTimeToken(
            courseId,
            _detectedBeaconToken!,
          );
          if (!isValidToken) {
            debugPrint('SECURITY WARNING: Beacon token mismatch.');
          }
        }
      }

      final supabase = Supabase.instance.client;

      // NEW: GPS & Beacon Secret Verification (Geofencing)
      final courseData = await supabase
          .from('courses')
          .select('*, classrooms(*, faculties(*))')
          .eq('id', courseId)
          .single();

      String? classroomSecret;

      if (courseData['classrooms'] != null &&
          courseData['classrooms']['faculties'] != null) {
        final faculty = courseData['classrooms']['faculties'];
        final double targetLat = faculty['latitude'] ?? 0.0;
        final double targetLng = faculty['longitude'] ?? 0.0;
        final int radius = faculty['radius_meters'] ?? 100;

        // Check GPS permissions
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            throw 'Konum izni reddedildi.';
          }
        }

        // Get current position
        final Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );

        // Calculate distance
        final double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          targetLat,
          targetLng,
        );

        /*
        if (distance > radius) {
          throw 'Fakülte sınırları dışındasınız. Lütfen sınıfa girin. (Uzaklık: ${distance.toStringAsFixed(0)}m)';
        }
        */

        classroomSecret = courseData['classrooms']['beacon_secret'];
      }

      // SECURE MODE VALIDATION (Updated to use classroom secret)
      if (isSecure && classroomSecret != null) {
        if (!_proximityVerified || _detectedBeaconToken == null) {
          throw 'Sınıfta olduğunuz beacon cihazı tarafından doğrulanmadı.';
        }

        final bool isValidToken = SecurityUtils.verifyTimeToken(
          classroomSecret,
          _detectedBeaconToken!,
        );
        if (!isValidToken) {
          throw 'Güvenlik kodu uyuşmuyor. Lütfen beacon cihazına yakınlaşın.';
        }
      }
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
        await _upsertAttendanceWithOptionalMethod({
          'student_id': studentId,
          'course_id': courseId,
          'date': date,
          'is_present': true,
          'attendance_method': 'qr',
        });
      } on PostgrestException catch (e) {
        if (e.code == '42501') {
          throw 'Yoklama kaydedilemedi. Veritabanı yetki hatası (RLS). Lütfen yöneticinizle iletişime geçin.';
        }
        rethrow;
      }

      if (!mounted) return;

      _showResultDialog(
        success: true,
        message: _proximityVerified
            ? 'Yoklamanız güvenli bir şekilde alındı.'
            : 'Yoklamanız alındı (Yakınlık doğrulaması başarısız).',
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

  Future<void> _upsertAttendanceWithOptionalMethod(
    Map<String, dynamic> values,
  ) async {
    final supabaseClient = Supabase.instance.client;
    try {
      await supabaseClient
          .from('attendance')
          .upsert(values, onConflict: 'student_id, course_id, date');
    } on PostgrestException catch (e) {
      final message = e.message.toLowerCase();
      final isMissingMethodColumn =
          e.code == 'PGRST204' ||
          e.code == '42703' ||
          message.contains('attendance_method') ||
          message.contains('column');
      if (!isMissingMethodColumn) rethrow;

      final fallbackValues = Map<String, dynamic>.from(values)
        ..remove('attendance_method');
      await supabaseClient
          .from('attendance')
          .upsert(fallbackValues, onConflict: 'student_id, course_id, date');
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
                  color: _proximityVerified
                      ? AppColors.success
                      : Colors.white.withValues(alpha: 0.5),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _proximityVerified
                  ? const Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.bluetooth_connected_rounded,
                          color: AppColors.success,
                          size: 28,
                        ),
                      ),
                    )
                  : null,
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
    _beaconSubscription?.cancel();
    controller.dispose();
    super.dispose();
  }
}

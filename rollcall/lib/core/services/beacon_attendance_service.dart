import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_beacon/flutter_beacon.dart' hide BeaconBroadcast;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/logger.dart';

class BeaconAttendanceService {
  static final BeaconAttendanceService _instance =
      BeaconAttendanceService._internal();
  factory BeaconAttendanceService() => _instance;
  BeaconAttendanceService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final BeaconBroadcast _beaconBroadcast = BeaconBroadcast();

  StreamSubscription? _beaconSubscription;
  bool _isScanning = false;
  bool _isContinuousBroadcasting = false;

  // Faculty Coordinates (DISABLED FOR TESTING)
  /*
  static const double facultyLat = 40.742347;
  static const double facultyLng = 30.325473;
  static const double geofenceRadius = 200.0; // 200 meters
  */

  Future<void> init() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
    const InitializationSettings initializationSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    await _notifications.initialize(settings: initializationSettings);
  }

  /// Okul numarasını SHA256 ile hashleyip Major + Minor ID üret
  static Map<String, int> hashSchoolNo(String schoolNo) {
    final bytes = utf8.encode(schoolNo.trim().toUpperCase());
    final hash = sha256.convert(bytes);

    final major = (hash.bytes[0] << 8) | hash.bytes[1];
    final minor = (hash.bytes[2] << 8) | hash.bytes[3];

    return {'major': major, 'minor': minor};
  }

  /// Uygulama açıkken sürekli BLE yayını başlat
  Future<void> startContinuousBroadcast(String schoolNo) async {
    if (_isContinuousBroadcasting) return;

    try {
      AppLogger.i('📱 Bluetooth izinleri isteniyor...');

      final advertiseStatus = await Permission.bluetoothAdvertise.request();
      final scanStatus = await Permission.bluetoothScan.request();
      final connectStatus = await Permission.bluetoothConnect.request();

      // Location permission commented out for pure beacon broadcast if needed,
      // but note that scanning still requires location on most Android versions.
      // final locationStatus = await Permission.locationWhenInUse.request();

      AppLogger.d('📱 Advertise izni: $advertiseStatus');
      AppLogger.d('📱 Scan izni: $scanStatus');
      AppLogger.d('📱 Connect izni: $connectStatus');
      // AppLogger.d('📱 Location izni: $locationStatus');

      if (!advertiseStatus.isGranted) {
        AppLogger.w('⚠️ BLUETOOTH_ADVERTISE izni verilmedi! Yayın yapılamaz.');

        return;
      }

      final isSupported = await _beaconBroadcast.checkTransmissionSupported();
      AppLogger.i('📡 Beacon Transmit Desteği: $isSupported');

      if (isSupported != BeaconStatus.supported) {
        AppLogger.w('⚠️ Bu cihaz beacon yayını desteklemiyor: $isSupported');

        return;
      }

      final hashResult = hashSchoolNo(schoolNo);
      final int hashMajor = hashResult['major']!;
      final int hashMinor = hashResult['minor']!;

      AppLogger.i('🟢 Sürekli BLE Yayını Başlatılıyor');
      AppLogger.d('   Okul No: $schoolNo');
      AppLogger.d('   Hash Major: $hashMajor, Hash Minor: $hashMinor');

      _beaconBroadcast
          .setUUID('E2C56DB5-DFFB-48D2-B060-D0F5A71096B1')
          .setMajorId(hashMajor)
          .setMinorId(hashMinor)
          .setTransmissionPower(-59)
          .start();

      _isContinuousBroadcasting = true;
      AppLogger.i('🟢 BLE Yayını Aktif!');
    } catch (e) {
      AppLogger.e('❌ BLE Yayın Hatası: $e');
    }
  }

  void stopContinuousBroadcast() {
    if (!_isContinuousBroadcasting) return;
    try {
      _beaconBroadcast.stop();
      _isContinuousBroadcasting = false;
      AppLogger.i('🔴 Sürekli BLE Yayını Durduruldu');
    } catch (e) {
      AppLogger.e('❌ BLE Durdurma Hatası: $e');
    }
  }

  void subscribeToCourse(String studentId, List<String> courseIds) {
    for (var courseId in courseIds) {
      final channel = _supabase.channel('course_$courseId');
      channel
          .onBroadcast(
            event: 'start_automation',
            callback: (payload) {
              AppLogger.i('Automation Signal Received: $payload');

              _handleAutomationTrigger(studentId, payload);
            },
          )
          .subscribe();
    }
  }

  Future<void> _handleAutomationTrigger(
    String studentId,
    Map<String, dynamic> payload,
  ) async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      final courseId = payload['course_id'];
      final expectedMajor = payload['major'];

      await _startScanning(expectedMajor, (minor) async {
        await _verifyAndSubmit(studentId, courseId, expectedMajor, minor);
      });
    } catch (e) {
      AppLogger.e('Automation Error: $e');
    } finally {
      Future.delayed(const Duration(seconds: 45), () {
        _stopScanning();
        _isScanning = false;
      });
    }
  }

  Future<void> _startScanning(int major, Function(int) onFound) async {
    await flutterBeacon.initializeScanning;

    final regions = <Region>[
      Region(
        identifier: 'RollCall_Automation',
        proximityUUID: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
        major: major,
      ),
    ];

    _beaconSubscription = flutterBeacon.ranging(regions).listen((
      RangingResult result,
    ) {
      if (result.beacons.isNotEmpty) {
        final beacon = result.beacons.first;
        onFound(beacon.minor);
        _stopScanning();
      }
    });
  }

  void _stopScanning() {
    _beaconSubscription?.cancel();
    _beaconSubscription = null;
  }

  Future<void> _verifyAndSubmit(
    String studentId,
    String courseId,
    int major,
    int minor,
  ) async {
    try {
      final courseData = await _supabase
          .from('courses')
          .select(
            'course_name, classrooms(id, beacon_secret), users!student_courses(school_no)',
          )
          .eq('id', courseId)
          .single();

      final enrollment = await _supabase
          .from('student_courses')
          .select('course_id')
          .eq('student_id', studentId)
          .eq('course_id', courseId)
          .maybeSingle();

      if (enrollment == null) {
        AppLogger.w(
          'Skipping BLE attendance because $studentId is not enrolled in $courseId',
        );
        return;
      }

      final secret =
          courseData['classrooms']['beacon_secret'] ?? 'secret_yaz_lab_1';
      final courseName = courseData['course_name'];

      final userData = await _supabase
          .from('users')
          .select('school_no')
          .eq('id', studentId)
          .single();
      final schoolNo = userData['school_no'] ?? '0';

      int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 30000;
      bool isValid =
          _verifyToken(secret, timestamp, minor) ||
          _verifyToken(secret, timestamp - 1, minor);

      if (!isValid) {
        AppLogger.w('Security Reject: Invalid Token');

        return;
      }

      final dateStr = DateTime.now().toIso8601String().split('T')[0];

      // Prevent automatic BLE updates from overwriting a teacher's manual mark.
      final existingRows = await _supabase
          .from('attendance')
          .select('id, verify_method, created_at')
          .eq('student_id', studentId)
          .eq('course_id', courseId)
          .eq('date', dateStr)
          .order('created_at', ascending: false)
          .limit(1);
      final existing = existingRows.isNotEmpty ? existingRows.first : null;

      if (existing != null &&
          (existing['verify_method'] ?? '').toString().toLowerCase() ==
              'manual') {
        // Respect manual override — do not overwrite.
        AppLogger.i(
          'Skipping BLE upsert because manual attendance exists for $studentId',
        );
        return;
      } else {
        await _supabase.from('attendance').upsert({
          'student_id': studentId,
          'course_id': courseId,
          'date': dateStr,
          'is_present': true,
          'verify_method': 'ble',
          'created_at': DateTime.now().toIso8601String(),
        }, onConflict: 'student_id, course_id, date');
      }

      _startSelfIdentification(schoolNo);
      _showSuccessNotification(courseName);
    } catch (e) {
      AppLogger.e('Verification Error: $e');
    }
  }

  void _startSelfIdentification(String schoolNo) async {
    int studentMinor =
        int.tryParse(schoolNo.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    studentMinor = studentMinor % 65535;
    if (studentMinor == 0) studentMinor = 1;

    AppLogger.i('Starting Self-Identification Beacon: Minor $studentMinor');

    _beaconBroadcast
        .setUUID('E2C56DB5-DFFB-48D2-B060-D0F5A71096B1')
        .setMajorId(999)
        .setMinorId(studentMinor)
        .setTransmissionPower(-59)
        .start();

    Future.delayed(const Duration(seconds: 30), () {
      _beaconBroadcast.stop();
      AppLogger.i('Self-Identification Beacon Stopped');
    });
  }

  bool _verifyToken(String secret, int timestamp, int receivedMinor) {
    String key = "$secret-$timestamp";
    int hash = 5381;
    for (int i = 0; i < key.length; i++) {
      hash = (((hash << 5) + hash) + key.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    int expectedMinor = hash & 0xFFFF;
    if (expectedMinor == 0) expectedMinor = 1;

    return expectedMinor == receivedMinor;
  }

  Future<void> _showSuccessNotification(String courseName) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'rollcall_auto',
          'Otomatik Yoklama',
          importance: Importance.max,
          priority: Priority.high,
        );

    await _notifications.show(
      id: 0,
      title: 'Yoklama Onaylandı! ✅',
      body:
          '${_translateCourseName(courseName)} dersine katılımınız otomatik olarak onaylandı.',
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
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
}

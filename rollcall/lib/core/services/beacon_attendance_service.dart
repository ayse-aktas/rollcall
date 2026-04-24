import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_beacon/flutter_beacon.dart' hide BeaconBroadcast;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'dart:io';

class BeaconAttendanceService {
  static final BeaconAttendanceService _instance = BeaconAttendanceService._internal();
  factory BeaconAttendanceService() => _instance;
  BeaconAttendanceService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final BeaconBroadcast _beaconBroadcast = BeaconBroadcast();
  
  StreamSubscription? _beaconSubscription;
  bool _isScanning = false;

  // Faculty Coordinates (Example: Sakarya University Engineering Faculty)
  static const double FACULTY_LAT = 40.742347;
  static const double FACULTY_LNG = 30.325473;
  static const double GEOFENCE_RADIUS = 200.0; // 200 meters

  Future<void> init() async {
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
    const InitializationSettings initializationSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    
    await _notifications.initialize(
      settings: initializationSettings,
    );
  }

  void subscribeToCourse(String studentId, List<String> courseIds) {
    for (var courseId in courseIds) {
      final channel = _supabase.channel('course_$courseId');
      channel.onBroadcast(
        event: 'start_automation',
        callback: (payload) {
          print('Automation Signal Received: $payload');
          _handleAutomationTrigger(studentId, payload);
        },
      ).subscribe();
    }
  }

  Future<void> _handleAutomationTrigger(String studentId, Map<String, dynamic> payload) async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      final courseId = payload['course_id'];
      final expectedMajor = payload['major'];

      // 1. GPS Check
      bool isInFaculty = await _checkLocation();
      if (!isInFaculty) {
        print('Security Reject: Not in Faculty');
        _isScanning = false;
        return;
      }

      // 2. Start Beacon Scan
      await _startScanning(expectedMajor, (minor) async {
        await _verifyAndSubmit(studentId, courseId, expectedMajor, minor);
      });

    } catch (e) {
      print('Automation Error: $e');
    } finally {
      // Auto-stop scanning after a timeout
      Future.delayed(const Duration(seconds: 45), () {
        _stopScanning();
        _isScanning = false;
      });
    }
  }

  Future<bool> _checkLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        FACULTY_LAT,
        FACULTY_LNG,
      );
      
      return distance <= GEOFENCE_RADIUS;
    } catch (e) {
      return false;
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

    _beaconSubscription = flutterBeacon.ranging(regions).listen((RangingResult result) {
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

  Future<void> _verifyAndSubmit(String studentId, String courseId, int major, int minor) async {
    try {
      // 1. Fetch secret from DB
      final courseData = await _supabase
          .from('courses')
          .select('course_name, classrooms(id, beacon_secret), users!student_courses(school_no)')
          .eq('id', courseId)
          .single();

      final secret = courseData['classrooms']['beacon_secret'] ?? 'secret_yaz_lab_1';
      final courseName = courseData['course_name'];
      
      // Get student's school number for self-identification
      final userData = await _supabase.from('users').select('school_no').eq('id', studentId).single();
      final schoolNo = userData['school_no'] ?? '0';

      // 2. Token Verification (djb2)
      int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 30000;
      bool isValid = _verifyToken(secret, timestamp, minor) || 
                     _verifyToken(secret, timestamp - 1, minor);

      if (!isValid) {
        print('Security Reject: Invalid Token');
        return;
      }

      // 3. Submit Attendance
      final dateStr = DateTime.now().toIso8601String().split('T')[0];
      
      await _supabase.from('attendance').upsert({
        'student_id': studentId,
        'course_id': courseId,
        'date': dateStr,
        'is_present': true,
        'verification_type': 'automatic_beacon',
      }, onConflict: 'student_id, course_id, date');

      // 4. KİMLİK YAYINI: ESP32'nin bizi tanıması için kendi beacon sinyalimizi yayalım
      _startSelfIdentification(schoolNo);

      // 5. Show Notification
      _showSuccessNotification(courseName);

    } catch (e) {
      print('Verification Error: $e');
    }
  }

  void _startSelfIdentification(String schoolNo) async {
    // Okul numarasının son 5 hanesini minor olarak kullanalım (Max 65535 limitine takılmamak için)
    int studentMinor = int.tryParse(schoolNo.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    studentMinor = studentMinor % 65535;
    if (studentMinor == 0) studentMinor = 1;

    print('Starting Self-Identification Beacon: Minor $studentMinor');

    _beaconBroadcast
        .setUUID('E2C56DB5-DFFB-48D2-B060-D0F5A71096B1') // Öğrenci UUID
        .setMajorId(999) // Öğrenci Major
        .setMinorId(studentMinor)
        .setTransmissionPower(-59)
        .start();

    // 30 saniye sonra yayını durdur
    Future.delayed(const Duration(seconds: 30), () {
      _beaconBroadcast.stop();
      print('Self-Identification Beacon Stopped');
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
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'rollcall_auto',
      'Otomatik Yoklama',
      importance: Importance.max,
      priority: Priority.high,
    );
    
    await _notifications.show(
      id: 0,
      title: 'Yoklama Onaylandı! ✅',
      body: '${_translateCourseName(courseName)} dersine katılımınız otomatik olarak onaylandı.',
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

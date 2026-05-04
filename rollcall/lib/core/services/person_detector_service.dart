import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';

/// ML Kit Face Detection ile yüksek isabetli kişi sayısı tespit servisi.
class PersonDetectorService {
  static PersonDetectorService? _instance;
  FaceDetector? _faceDetector;

  PersonDetectorService._();

  static PersonDetectorService get instance {
    _instance ??= PersonDetectorService._();
    return _instance!;
  }

  void _initDetector() {
    if (_faceDetector != null) return;

    // 'accurate' moduna geçtik: Daha yavaş ama çok daha isabetli.
    // Sınıfın arkasındaki öğrencileri bile yakalar.
    final options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: false,
      enableLandmarks: false,
      enableContours: false,
      enableTracking: false,
    );

    _faceDetector = FaceDetector(options: options);
    debugPrint('🔍 PersonDetectorService: Accurate Face Detector initialized');
  }

  /// Verilen [InputImage] üzerinde yüz sayısını tespit eder.
  Future<PersonDetectionResult> detectPersons(InputImage inputImage) async {
    _initDetector();

    try {
      final List<Face> faces = await _faceDetector!.processImage(inputImage);
      
      debugPrint('👥 Tespit edilen kişi sayısı: ${faces.length}');
      
      // Eğer hala 0 buluyorsa log basalım
      if (faces.isEmpty) {
        debugPrint('⚠️ Uyarı: Hiç yüz bulunamadı. Işıklandırmayı veya kamera açısını kontrol edin.');
      }

      return PersonDetectionResult(
        personCount: faces.length,
        averageConfidence: 1.0,
        totalObjectsDetected: faces.length,
        faces: faces,
      );
    } catch (e) {
      debugPrint('❌ PersonDetectorService hatası: $e');
      return PersonDetectionResult(
        personCount: 0,
        averageConfidence: 0,
        totalObjectsDetected: 0,
        faces: [],
        error: e.toString(),
      );
    }
  }

  void dispose() {
    _faceDetector?.close();
    _faceDetector = null;
    _instance = null;
  }
}

class PersonDetectionResult {
  final int personCount;
  final double averageConfidence;
  final int totalObjectsDetected;
  final List<Face> faces;
  final String? error;

  const PersonDetectionResult({
    required this.personCount,
    required this.averageConfidence,
    required this.totalObjectsDetected,
    required this.faces,
    this.error,
  });

  bool get hasError => error != null;
  bool get isSuccessful => !hasError && personCount >= 0;
}

import 'package:logger/logger.dart';

class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0, // Hangi fonksiyondan geldiğini gizleyerek kalabalığı azaltır
      errorMethodCount: 5, // Hata durumunda yığın izleme derinliği
      lineLength: 80, // Çizgi uzunluğunu daraltır
      colors: true, // Renkli çıktı
      printEmojis: true, // Emoji desteği
      printTime: false, // Zaman damgasını gizleyerek satırı sadeleştirir
    ),
  );

  // Bilgi logu
  static void i(String message) {
    _logger.i(message);
  }

  // Hata logu
  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  // Uyarı logu
  static void w(String message) {
    _logger.w(message);
  }

  // Debug logu
  static void d(String message) {
    _logger.d(message);
  }

  // Verbose/Trace logu
  static void t(String message) {
    _logger.t(message);
  }
}

import 'package:flutter/widgets.dart';

/// Desktop için responsive boyutlandırma sınıfı
/// Referans boyutlar: 1512x982 (genişlik x yükseklik)
class ResponsiveDesktopSize {
  static final double _baseHeight = 982.0; // Referans yükseklik
  static final double _baseWidth = 1512.0; // Referans genişlik

  // Yükseklik oranı hesapla
  static double _heightRatio(BuildContext context) {
    return MediaQuery.sizeOf(context).height / _baseHeight;
  }

  // Genişlik oranı hesapla
  static double _widthRatio(BuildContext context) {
    return MediaQuery.sizeOf(context).width / _baseWidth;
  }

  /// Responsive yükseklik - Responsive Height
  /// Kullanım: ResponsiveDesktopSize.rh(context, 100)
  static double rh(BuildContext context, double height) {
    return height * _heightRatio(context);
  }

  /// Responsive genişlik - Responsive Width
  /// Kullanım: ResponsiveDesktopSize.rw(context, 200)
  static double rw(BuildContext context, double width) {
    return width * _widthRatio(context);
  }

  /// Responsive metin boyutu - Scale Point
  /// Genişlik ve yükseklik oranlarının ortalamasını kullanır
  /// Kullanım: ResponsiveDesktopSize.sp(context, 16)
  static double sp(BuildContext context, double size) {
    double ratio = (_heightRatio(context) + _widthRatio(context)) / 2;
    return size * ratio;
  }

  /// Ekran genişliğini döndürür
  static double width(BuildContext context) {
    return MediaQuery.sizeOf(context).width;
  }

  /// Ekran yüksekliğini döndürür
  static double height(BuildContext context) {
    return MediaQuery.sizeOf(context).height;
  }

  /// Ekran türünü belirler - Telefon mu?
  static bool isMobile(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 600;
  }

  /// Ekran türünü belirler - Desktop mi?
  static bool isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 1024;
  }
}

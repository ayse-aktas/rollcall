import 'package:flutter/widgets.dart';

/// Mobil için responsive boyutlandırma sınıfı
/// Referans boyutlar: 414x896 (genişlik x yükseklik)
class ResponsiveMobileSize {
  static final double _baseHeight = 896.0; // Referans yükseklik
  static final double _baseWidth = 414.0; // Referans genişlik

  // Yükseklik oranı hesapla
  static double _heightRatio(BuildContext context) {
    return MediaQuery.sizeOf(context).height / _baseHeight;
  }

  // Genişlik oranı hesapla
  static double _widthRatio(BuildContext context) {
    return MediaQuery.sizeOf(context).width / _baseWidth;
  }

  /// Responsive yükseklik - Responsive Height
  /// Kullanım: ResponsiveMobileSize.rh(context, 100)
  static double rh(BuildContext context, double height) {
    return height * _heightRatio(context);
  }

  /// Responsive genişlik - Responsive Width
  /// Kullanım: ResponsiveMobileSize.rw(context, 200)
  static double rw(BuildContext context, double width) {
    return width * _widthRatio(context);
  }

  /// Responsive metin boyutu - Scale Point
  /// Genişlik ve yükseklik oranlarının ortalamasını kullanır
  /// Kullanım: ResponsiveMobileSize.sp(context, 16)
  static double sp(BuildContext context, double size) {
    // Genişlik ve yükseklik oranlarının ortalamasını al
    double ratio = (_heightRatio(context) + _widthRatio(context)) / 2;
    return size * ratio;
  }
}

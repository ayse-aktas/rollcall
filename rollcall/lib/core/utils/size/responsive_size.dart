import 'package:flutter/widgets.dart';
import 'responsive_mobile_size.dart';
import 'responsive_desktop_size.dart';

// Tüm sayfaların tek import ile her iki sınıfa erişmesi için export
export 'responsive_desktop_size.dart';
export 'responsive_mobile_size.dart';

/// Responsive yönlendirici - Mobil mi yoksa Desktop mu olduğunu belirler
/// ve uygun boyutlandırma sınıfına delege eder
///
/// Kullanım:
///   final isMobile = ResponsiveSize.isMobile(context);
///   if (isMobile) return _buildMobile(context);
///   return _buildDesktop(context);
class ResponsiveSize {
  /// Ekranın mobil mi olduğunu belirler
  /// 430 (mobil) ve 1512 (desktop) referans genişliklerine en yakın olanı seçer
  static bool _isMobile(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    const mobileBase = 430.0;
    const desktopBase = 1512.0;
    return (width - mobileBase).abs() < (width - desktopBase).abs();
  }

  /// Dışarıdan erişilebilir mobil kontrolü
  static bool isMobile(BuildContext context) => _isMobile(context);

  /// Responsive genişlik - Mobil veya Desktop'a yönlendirir
  static double rw(BuildContext context, double size) {
    return _isMobile(context)
        ? ResponsiveMobileSize.rw(context, size)
        : ResponsiveDesktopSize.rw(context, size);
  }

  /// Responsive yükseklik - Mobil veya Desktop'a yönlendirir
  static double rh(BuildContext context, double size) {
    return _isMobile(context)
        ? ResponsiveMobileSize.rh(context, size)
        : ResponsiveDesktopSize.rh(context, size);
  }

  /// Responsive metin boyutu - Mobil veya Desktop'a yönlendirir
  static double sp(BuildContext context, double size) {
    return _isMobile(context)
        ? ResponsiveMobileSize.sp(context, size)
        : ResponsiveDesktopSize.sp(context, size);
  }
}

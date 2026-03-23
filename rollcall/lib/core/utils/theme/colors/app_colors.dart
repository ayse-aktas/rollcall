import 'package:flutter/material.dart';

/// BEACONTrack renk paleti
/// Kullanım: AppColors.primary, AppColors.background vs.
class AppColors {
  AppColors._();

  // ── Ana Renkler ──────────────────────────────────────
  static const Color primary = Color(0xFF4E9BFF); // Mavi — buton, link, odak
  static const Color primaryDark = Color(0xFF2A7FE8); // Hover / pressed

  // ── Arkaplan ─────────────────────────────────────────
  static const Color background = Color(0xFF0A0E1A); // Sayfa zemini
  static const Color surface = Color(0xFF131929); // Input, card zemini
  static const Color surfaceLight = Color(0xFF1A2642); // İkon bg, chip

  // ── Metin ─────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF); // Başlık
  static const Color textSecondary = Color(
    0x99FFFFFF,
  ); // %60 beyaz — alt başlık
  static const Color textHint = Color(0x33FFFFFF); // %20 beyaz — placeholder

  // ── Kenarlık ──────────────────────────────────────────
  static const Color border = Color(0x14FFFFFF); // %8 beyaz — normal
  static const Color borderFocus = Color(0xFF4E9BFF); // Odaklanmış input
  static const Color borderPrimary = Color(
    0x4D4E9BFF,
  ); // %30 mavi — logo kutusu

  // ── Durum Renkleri ────────────────────────────────────
  static const Color success = Color(0xFF4CAF7D); // Başarılı
  static const Color successBg = Color(0x1A4CAF7D); // Başarı arka planı
  static const Color error = Color(0xFFFF4D4D); // Hata
  static const Color errorBg = Color(0x1AFF4D4D); // Hata arka planı
  static const Color errorText = Color(0xFFFF8A8A); // Hata metni
  static const Color errorBorder = Color(0x4DFF4D4D); // Hata kenarlık
  static const Color warning = Color(0xFFFFB347); // Uyarı

  // ── Devam Durumu (yoklama) ────────────────────────────
  static const Color attendanceOk = Color(0xFF4CAF7D); // %70 üzeri
  static const Color attendanceWarn = Color(0xFFFFB347); // %60–70 arası
  static const Color attendanceFail = Color(0xFFFF4D4D); // %60 altı
}

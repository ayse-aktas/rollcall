import 'package:flutter/material.dart';

class AppColors {
  // ── Light Theme (Clean Blue & White) ──────────────────
  static const background = Colors.white;
  static const surface = Colors.white;
  static const surfaceLight = Color(0xFFF0F7FF); 
  
  static const primary = Color(0xFF007BFF); 
  static const primaryLight = Color(0xFFE1F0FF);
  
  static const textPrimary = Color(0xFF2D3436);
  static const textSecondary = Color(0xFF636E72);
  
  static const success = Color(0xFF2ECC71);
  static const warning = Color(0xFFF1C40F);
  static const error = Color(0xFFE74C3C);
  
  static const border = Color(0xFFE9ECEF);
  static const errorBg = Color(0xFFFDEDEB);
  static const successBg = Color(0xFFEAF9EE);

  // ── Compatibility & Legacy Support Colors ──────────────
  static const borderFocus = Color(0xFF007BFF); 
  static const borderPrimary = Color(0xFFE9ECEF); 
  static const errorText = Color(0xFFE74C3C);   
  static const errorBorder = Color(0xFFE74C3C); 
  static const surfaceDark = Color(0xFFF8F9FA); 
  static const textHint = Color(0xFFA0AEC0); // Soft grey for hints
}

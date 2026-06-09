import 'package:flutter/material.dart';

/// Central design system for Scale Runner.
///
/// Dark, modern, vibrant: a deep slate canvas, a teal→indigo accent, large
/// rounded cards, and a clearly-defined palette for the keyboard's feedback
/// states (target / correct / wrong) so the whole app stays consistent.
class AppColors {
  AppColors._();

  // Canvas
  static const Color bg = Color(0xFF0E1117); // deep slate
  static const Color surface = Color(0xFF171B23); // cards
  static const Color surfaceHigh = Color(0xFF1F2530); // raised cards
  static const Color border = Color(0xFF2A3140);

  // Accent gradient (teal → indigo)
  static const Color accent = Color(0xFF2DD4BF); // teal
  static const Color accent2 = Color(0xFF6366F1); // indigo
  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Text
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Feedback states (shared by keyboard + quiz UI)
  static const Color correct = Color(0xFF34D399); // green glow
  static const Color wrong = Color(0xFFF87171); // red
  static const Color target = Color(0xFF38BDF8); // sky-blue hint

  // Keyboard
  static const Color whiteKey = Color(0xFFF8FAFC);
  static const Color whiteKeyShadow = Color(0xFFCBD5E1);
  static const Color blackKey = Color(0xFF1E232C);
  static const Color blackKeyTop = Color(0xFF2E3543);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent2,
      brightness: Brightness.dark,
    ).copyWith(
      surface: AppColors.surface,
      primary: AppColors.accent,
      secondary: AppColors.accent2,
      error: AppColors.wrong,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: scheme,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        elevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent2,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

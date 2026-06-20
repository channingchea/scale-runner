import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design system for Scale Runner — see BRAND_GUIDE.md.
///
/// Focused & modern, dark-first. Blue-slate canvas (never pure black) with
/// "Resonance Teal" as the single accent and warm amber for streaks. The
/// keyboard palette is theme-stable: ivory whites, beveled slate-blacks, and
/// a felt rail so keys never blend into the background.
class AppColors {
  AppColors._();

  // Canvas (dark theme)
  static const Color bg = Color(0xFF0F141B); // blue-slate, never #000
  static const Color surface = Color(0xFF171E28); // cards
  static const Color surfaceHigh = Color(0xFF1F2835); // raised cards / tray
  static const Color border = Color(0xFF2C3645);

  // Accents
  static const Color accent = Color(0xFF36D6C3); // Resonance Teal (primary)
  static const Color accent2 = Color(0xFFF5A524); // warm amber (streaks)
  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, Color(0xFF1FA396)], // teal → deep teal (single-hue brand)
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Text
  static const Color textPrimary = Color(0xFFE8ECF1); // never pure white
  static const Color textSecondary = Color(0xFF94A1B2);
  static const Color textMuted = Color(0xFF5B6878);

  // Feedback states (shared by keyboard + quiz UI)
  static const Color correct = Color(0xFF4ADE80);
  static const Color wrong = Color(0xFFF4717F); // rose, easier on the eyes
  static const Color target = Color(0xFF36D6C3); // teal hint = play this next

  // Keyboard (theme-stable — identical in any future light theme)
  static const Color whiteKey = Color(0xFFF4F1EA); // ivory, never pure white
  static const Color whiteKeyShadow = Color(0xFFC9C3B6);
  static const Color blackKey = Color(0xFF262B33); // lighter than bg
  static const Color blackKeyTop = Color(0xFF3A414C); // bevel separates from bg
  static const Color felt = Color(0xFF8E3B46); // felt rail above the keys
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      surface: AppColors.surface,
      primary: AppColors.accent,
      onPrimary: const Color(0xFF06251F),
      secondary: AppColors.accent2,
      onSecondary: const Color(0xFF2A1B00),
      error: AppColors.wrong,
      outline: AppColors.border,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
    );

    final text = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: scheme,
      textTheme: text.copyWith(
        displayLarge: GoogleFonts.spaceGrotesk(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        headlineMedium: GoogleFonts.spaceGrotesk(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleLarge: GoogleFonts.spaceGrotesk(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        elevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: const Color(0xFF06251F),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
    );
  }

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    const accent = AppColors.accent;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: accent,
      onPrimary: const Color(0xFF06251F),
      secondary: AppColors.accent2,
      onSecondary: const Color(0xFF2A1B00),
      error: AppColors.wrong,
    );

    final text = GoogleFonts.interTextTheme(base.textTheme);

    return base.copyWith(
      colorScheme: scheme,
      textTheme: text.copyWith(
        titleLarge: GoogleFonts.spaceGrotesk(
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: GoogleFonts.spaceGrotesk(
          fontSize: 26,
          fontWeight: FontWeight.w600,
        ),
        displayLarge: GoogleFonts.spaceGrotesk(
          fontSize: 32,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFF06251F),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Tabular figures for tempo/score/timer text — prevents number jitter.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

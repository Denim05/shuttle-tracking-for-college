import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Color Tokens ────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Brand Accents - Modern High-Contrast Palette
  static const Color primary        = Color(0xFF2563EB); // Electric Royal Blue
  static const Color primaryLight   = Color(0xFF38BDF8); // Sky / Ice Blue Accent
  static const Color primaryDark    = Color(0xFF1D4ED8);
  static const Color accent         = Color(0xFF06B6D4); // Vivid Cyan
  static const Color accentPurple   = Color(0xFF6366F1); // Ultra Indigo
  static const Color accentGreen    = Color(0xFF10B981); // Crisp Emerald Live

  // Background / Surface
  static const Color bg             = Color(0xFF070A10); // Deep Obsidian Velvet
  static const Color bgSecondary    = Color(0xFF0C121D); // Midnight Navy Slate
  static const Color surface        = Color(0xFF121927); // Obsidian Card Surface
  static const Color surfaceLight   = Color(0xFF1A2336); // Raised Module Surface
  static const Color card           = Color(0xFF121927); // Deep Card Glass

  // Text Hierarchy (WCAG AAA High Contrast)
  static const Color text           = Color(0xFFFFFFFF); // Pure Crisp White
  static const Color textSecondary  = Color(0xFF94A3B8); // Soft Slate Gray
  static const Color textMuted      = Color(0xFF64748B); // Muted Label Slate
  static const Color textDisabled   = Color(0xFF334155);

  // Semantic
  static const Color success        = Color(0xFF10B981); // Emerald
  static const Color warning        = Color(0xFFF59E0B); // Amber
  static const Color danger         = Color(0xFFF43F5E); // Crimson Rose
  static const Color info           = Color(0xFF2563EB); // Blue

  // Operational Status
  static const Color statusOnline   = Color(0xFF10B981);
  static const Color statusDelayed  = Color(0xFFF59E0B);
  static const Color statusOffline  = Color(0xFF64748B);
  static const Color statusPending  = Color(0xFFF59E0B);

  // Borders / Dividers
  static Color get border      => Colors.white.withValues(alpha: 0.08);
  static Color get borderFocus => primaryLight.withValues(alpha: 0.6);
  static Color get divider     => Colors.white.withValues(alpha: 0.06);
}

// ─── Spacing Tokens ──────────────────────────────────────────────────────────

class AppSpacing {
  AppSpacing._();
  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 16.0;
  static const double lg   = 24.0;
  static const double xl   = 32.0;
  static const double xxl  = 48.0;
  static const double xxxl = 64.0;
}

// ─── Border Radius Tokens ────────────────────────────────────────────────────

class AppRadius {
  AppRadius._();
  static const double xs   = 6.0;
  static const double sm   = 10.0;
  static const double md   = 16.0;
  static const double lg   = 22.0;
  static const double xl   = 28.0;
  static const double xxl  = 36.0;
  static const double full = 999.0;
}

// ─── Shadow Tokens ───────────────────────────────────────────────────────────

class AppShadows {
  AppShadows._();

  static List<BoxShadow> get card => [
    BoxShadow(
      color     : Colors.black.withValues(alpha: 0.4),
      blurRadius: 20,
      offset    : const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get primary => [
    BoxShadow(
      color     : AppColors.primary.withValues(alpha: 0.35),
      blurRadius: 18,
      offset    : const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> get accent => [
    BoxShadow(
      color     : AppColors.accent.withValues(alpha: 0.25),
      blurRadius: 18,
      offset    : const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> get danger => [
    BoxShadow(
      color     : AppColors.danger.withValues(alpha: 0.3),
      blurRadius: 18,
      offset    : const Offset(0, 4),
    ),
  ];
}

// ─── Decoration Helpers ──────────────────────────────────────────────────────

class AppDecorations {
  AppDecorations._();

  static BoxDecoration get glassCard => BoxDecoration(
    color        : AppColors.surface.withValues(alpha: 0.85),
    borderRadius : BorderRadius.circular(AppRadius.lg),
    border       : Border.all(color: AppColors.border),
    boxShadow    : AppShadows.card,
  );

  static BoxDecoration glassCardWithAccent(Color accent) => BoxDecoration(
    color        : AppColors.surface.withValues(alpha: 0.85),
    borderRadius : BorderRadius.circular(AppRadius.lg),
    border       : Border.all(color: accent.withValues(alpha: 0.25)),
    boxShadow    : [
      BoxShadow(
        color      : accent.withValues(alpha: 0.1),
        blurRadius : 20,
        spreadRadius: 1,
      ),
    ],
  );

  static BoxDecoration get screenBackground => const BoxDecoration(
    gradient: LinearGradient(
      begin  : Alignment.topLeft,
      end    : Alignment.bottomRight,
      colors : [AppColors.bg, AppColors.bgSecondary, Color(0xFF080C14)],
    ),
  );

  static BoxDecoration inputField({bool focused = false, String? error}) {
    final borderColor = error != null
        ? AppColors.danger.withValues(alpha: 0.6)
        : focused
            ? AppColors.primary.withValues(alpha: 0.7)
            : Colors.white.withValues(alpha: 0.08);
    final bgColor = focused
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.03);
    return BoxDecoration(
      color       : bgColor,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border      : Border.all(color: borderColor, width: focused ? 1.5 : 1.0),
    );
  }

  static BoxDecoration statusChip(Color color) => BoxDecoration(
    color       : color.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(AppRadius.full),
    border      : Border.all(color: color.withValues(alpha: 0.3)),
  );
}

// ─── Text Style Helpers ──────────────────────────────────────────────────────

class AppTextStyles {
  AppTextStyles._();

  static TextStyle get displayLarge => GoogleFonts.plusJakartaSans(
    fontSize  : 36,
    fontWeight: FontWeight.w900,
    color     : AppColors.text,
    letterSpacing: -1.2,
    height    : 1.1,
  );

  static TextStyle get displayMedium => GoogleFonts.plusJakartaSans(
    fontSize  : 28,
    fontWeight: FontWeight.w800,
    color     : AppColors.text,
    letterSpacing: -0.5,
  );

  static TextStyle get headlineLarge => GoogleFonts.plusJakartaSans(
    fontSize  : 20,
    fontWeight: FontWeight.w700,
    color     : AppColors.text,
  );

  static TextStyle get headlineMedium => GoogleFonts.plusJakartaSans(
    fontSize  : 16,
    fontWeight: FontWeight.w700,
    color     : AppColors.text,
  );

  static TextStyle get headlineSmall => GoogleFonts.plusJakartaSans(
    fontSize  : 14,
    fontWeight: FontWeight.w600,
    color     : AppColors.text,
  );

  static TextStyle get bodyLarge => GoogleFonts.plusJakartaSans(
    fontSize  : 14,
    fontWeight: FontWeight.w400,
    color     : AppColors.textSecondary,
    height    : 1.5,
  );

  static TextStyle get bodyMedium => GoogleFonts.plusJakartaSans(
    fontSize  : 12,
    fontWeight: FontWeight.w400,
    color     : AppColors.textSecondary,
    height    : 1.4,
  );

  static TextStyle get label => GoogleFonts.plusJakartaSans(
    fontSize  : 10,
    fontWeight: FontWeight.w800,
    color     : AppColors.textMuted,
    letterSpacing: 1.5,
  );

  static TextStyle get caption => GoogleFonts.plusJakartaSans(
    fontSize  : 9,
    fontWeight: FontWeight.w600,
    color     : AppColors.textMuted,
    letterSpacing: 0.5,
  );
}

// ─── Full MaterialApp ThemeData ──────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
    brightness            : Brightness.dark,
    useMaterial3          : true,
    scaffoldBackgroundColor: AppColors.bg,
    primaryColor           : AppColors.primary,
    colorScheme: const ColorScheme.dark(
      primary  : AppColors.primary,
      secondary: AppColors.accent,
      surface  : AppColors.surface,
      error    : AppColors.danger,
    ),
    textTheme: ThemeData.dark().textTheme.copyWith(
      displayLarge : AppTextStyles.displayLarge,
      headlineLarge: AppTextStyles.headlineLarge,
      bodyLarge    : AppTextStyles.bodyLarge,
      bodyMedium   : AppTextStyles.bodyMedium,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide  : BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide  : BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide  : const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide  : const BorderSide(color: AppColors.danger),
      ),
      filled   : true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
      labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
      errorStyle: GoogleFonts.plusJakartaSans(color: AppColors.danger, fontSize: 11),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize  : 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface,
      contentTextStyle: GoogleFonts.plusJakartaSans(color: AppColors.text, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: AppColors.border),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: DividerThemeData(
      color    : AppColors.divider,
      thickness: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      labelStyle     : GoogleFonts.plusJakartaSans(color: AppColors.text, fontSize: 12),
      side           : BorderSide(color: AppColors.border),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation      : 0,
      centerTitle    : true,
      titleTextStyle : GoogleFonts.plusJakartaSans(
        color       : AppColors.text,
        fontSize    : 16,
        fontWeight  : FontWeight.w800,
        letterSpacing: 1.5,
      ),
      iconTheme: const IconThemeData(color: AppColors.text),
    ),
    iconTheme: const IconThemeData(color: AppColors.textSecondary),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
    ),
  );
}

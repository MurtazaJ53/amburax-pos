import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Brand + semantic colours shared across light and dark themes.
final class AppPalette {
  // Brand Colors
  static const Color primary = Color(0xFF0369A1);
  static const Color primaryHover = Color(0xFF075985);
  static const Color primaryDark = Color(0xFF0C4A6E);
  static const Color primaryLight = Color(0xFF0EA5E9);

  // Pale ground for buttons
  static const Color primaryPale = Color(0xFFE0F2FE);

  // Secondary accent
  static const Color accent = Color(0xFF075985);
  static const Color accentHover = Color(0xFF0C4A6E);
  static const Color accentLight = Color(0xFF0369A1);

  // Semantic Colors
  static const Color success = Color(0xFF15803D);
  static const Color warning = Color(0xFFB45309);
  static const Color error = Color(0xFFB91C1C);
  static const Color info = Color(0xFF1D4ED8);

  // Dark Theme Neutrals (Hand-crafted, not inverted)
  static const Color backgroundDark = Color(0xFF0B1120);
  static const Color backgroundSoftDark = Color(0xFF0F172A);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color surfaceStrongDark = Color(0xFF334155);
  static const Color borderSoftDark = Color(0xFF334155);
  static const Color borderDark = Color(0xFF475569);

  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFFCBD5E1);
  static const Color textTertiaryDark = Color(0xFF94A3B8);
  static const Color textDisabledDark = Color(0xFF64748B);

  /// The pale ground a primary button sits on, and the ink that reads on it.
  /// Light uses [primaryPale] + [primaryDark]; these are the dark-mode pair.
  /// The ink matches the web's dark `--primary`.
  static const Color primaryGroundDark = Color(0xFF0B3A52);
  static const Color primaryInkDark = Color(0xFF7DD3FC);

  // Domain Colors
  static const Color revenue = success;
  static const Color expense = error;
  static const Color inventory = primary;
  static const Color customer = primaryHover;
  static const Color alert = warning;

  // Backward-compatible aliases used across existing screens.
  static const Color panel = Color(0xFFFDFEFF);
  static const Color lineSoft = Color(0xFFDCEAF5);
  static const Color coral = error;
}

/// Light-mode neutral/surface/text tokens.
final class AppPaletteLight {
  static const Color background = Color(0xFFEFF6FC);
  static const Color backgroundSoft = Color(0xFFF1F7FC);
  static const Color surface = Color(0xFFFDFEFF);
  static const Color surfaceStrong = Color(0xFFF1F7FC);
  static const Color borderSoft = Color(0xFFDCEAF5);
  static const Color border = Color(0xFFC5DCEC);

  static const Color textPrimary = Color(0xFF0F2942);
  static const Color textSecondary = Color(0xFF3D5A73);
  static const Color textTertiary = Color(0xFF64748B);
  // #A1A1AA was a neutral zinc grey, the one token in the light set that was
  // not tuned to the palette's hue. Next to text that is all cool navy it read
  // as washed out. The web's copy of this palette already carries the tuned
  // value; the app is catching up to it.
  static const Color textDisabled = Color(0xFF93A8BC);
}

class _ThemeTokens {
  const _ThemeTokens({
    required this.brightness,
    required this.background,
    required this.backgroundSoft,
    required this.surface,
    required this.surfaceStrong,
    required this.borderSoft,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.primaryGround,
    required this.primaryInk,
  });

  final Brightness brightness;

  /// The ground and ink a primary button uses. These are a pair and must stay
  /// one: the app's whole visual argument is that a button is ink on a pale
  /// ground rather than white on a dark fill, and a theme that supplied only
  /// one of the two would break that in exactly one mode.
  final Color primaryGround;
  final Color primaryInk;

  final Color background;
  final Color backgroundSoft;
  final Color surface;
  final Color surfaceStrong;
  final Color borderSoft;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
}

final class AppTheme {
  static ThemeData get dark => _build(
    const _ThemeTokens(
      brightness: Brightness.dark,
      background: AppPalette.backgroundDark,
      backgroundSoft: AppPalette.backgroundSoftDark,
      surface: AppPalette.surfaceDark,
      surfaceStrong: AppPalette.surfaceStrongDark,
      borderSoft: AppPalette.borderSoftDark,
      border: AppPalette.borderDark,
      textPrimary: AppPalette.textPrimaryDark,
      textSecondary: AppPalette.textSecondaryDark,
      textTertiary: AppPalette.textTertiaryDark,
      textDisabled: AppPalette.textDisabledDark,
      primaryGround: AppPalette.primaryGroundDark,
      primaryInk: AppPalette.primaryInkDark,
    ),
  );

  static ThemeData get light => _build(
    const _ThemeTokens(
      brightness: Brightness.light,
      background: AppPaletteLight.background,
      backgroundSoft: AppPaletteLight.backgroundSoft,
      surface: AppPaletteLight.surface,
      surfaceStrong: AppPaletteLight.surfaceStrong,
      borderSoft: AppPaletteLight.borderSoft,
      border: AppPaletteLight.border,
      textPrimary: AppPaletteLight.textPrimary,
      textSecondary: AppPaletteLight.textSecondary,
      textTertiary: AppPaletteLight.textTertiary,
      textDisabled: AppPaletteLight.textDisabled,
      primaryGround: AppPalette.primaryPale,
      primaryInk: AppPalette.primaryDark,
    ),
  );

  static ThemeData _build(_ThemeTokens t) {
    final isDark = t.brightness == Brightness.dark;
    final base = isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    final scheme = ColorScheme(
      brightness: t.brightness,
      primary: AppPalette.primary,
      onPrimary: const Color(0xFFFFFFFF),
      secondary: AppPalette.accent,
      onSecondary: const Color(0xFFFFFFFF),
      tertiary: AppPalette.info,
      onTertiary: const Color(0xFFFFFFFF),
      error: AppPalette.error,
      onError: const Color(0xFFFFFFFF),
      surface: t.surface,
      onSurface: t.textPrimary,
      outline: t.border,
      surfaceContainerHighest: t.surfaceStrong,
      secondaryContainer: t.backgroundSoft,
      tertiaryContainer: t.background,
    );

    // Apply Google Fonts (Outfit)
    final textTheme = GoogleFonts.outfitTextTheme(base.textTheme)
        .apply(bodyColor: t.textPrimary, displayColor: t.textPrimary)
        .copyWith(
          displayLarge: GoogleFonts.outfit(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.1,
            color: t.textPrimary,
          ),
          displayMedium: GoogleFonts.outfit(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            height: 1.15,
            color: t.textPrimary,
          ),
          displaySmall: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            height: 1.2,
            color: t.textPrimary,
          ),
          headlineLarge: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            height: 1.25,
            color: t.textPrimary,
          ),
          headlineMedium: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            height: 1.3,
            color: t.textPrimary,
          ),
          headlineSmall: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            height: 1.35,
            color: t.textPrimary,
          ),
          titleLarge: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            height: 1.4,
            color: t.textPrimary,
          ),
          titleMedium: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            height: 1.4,
            color: t.textPrimary,
          ),
          titleSmall: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            height: 1.4,
            color: t.textPrimary,
          ),
          bodyLarge: GoogleFonts.outfit(
            fontSize: 16,
            color: t.textSecondary,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.2,
            height: 1.5,
          ),
          bodyMedium: GoogleFonts.outfit(
            fontSize: 15,
            color: t.textSecondary,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.2,
            height: 1.5,
          ),
          bodySmall: GoogleFonts.outfit(
            fontSize: 14,
            color: t.textTertiary,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.2,
            height: 1.5,
          ),
          labelLarge: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            color: t.textPrimary,
          ),
          labelMedium: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            color: t.textPrimary,
          ),
          labelSmall: GoogleFonts.outfit(
            fontSize: 12,
            color: t.textTertiary,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
          ),
        );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[
        isDark ? AppColors.dark : AppColors.light,
      ],
      scaffoldBackgroundColor: t.background,
      colorScheme: scheme,
      canvasColor: t.backgroundSoft,
      splashColor: AppPalette.primary.withValues(alpha: 0.12),
      highlightColor: AppPalette.primaryLight.withValues(alpha: 0.08),
      dividerColor: t.borderSoft,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: t.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: t.borderSoft.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.surfaceStrong,
        contentTextStyle: GoogleFonts.outfit(
          color: t.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        elevation: 16,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 24,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.background,
        elevation: 0,
        centerTitle: false,
        foregroundColor: t.textPrimary,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: t.textPrimary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.primaryGround,
          foregroundColor: t.primaryInk,
          disabledBackgroundColor: t.surfaceStrong,
          disabledForegroundColor: t.textDisabled,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          side: BorderSide(color: t.border, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppPalette.primary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: t.surfaceStrong,
        selectedColor: AppPalette.primary.withValues(alpha: 0.2),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelStyle: GoogleFonts.outfit(
          color: t.textSecondary,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        hintStyle: GoogleFonts.outfit(
          color: t.textTertiary,
          fontWeight: FontWeight.w400,
          fontSize: 15,
        ),
        labelStyle: GoogleFonts.outfit(
          color: t.textSecondary,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        prefixIconColor: t.textTertiary,
        suffixIconColor: t.textTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: t.borderSoft, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: t.borderSoft, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppPalette.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppPalette.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppPalette.primary,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppPalette.primary,
        foregroundColor: Color(0xFFFFFFFF),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.surface,
        indicatorColor: AppPalette.primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppPalette.primary,
            );
          }
          return GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: t.textTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppPalette.primary, size: 24);
          }
          return IconThemeData(color: t.textTertiary, size: 24);
        }),
      ),
    );
  }
}

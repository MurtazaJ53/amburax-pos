import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Brightness-aware neutral tokens for screens.
///
/// Brand and semantic colours (primary, success, error, …) are constant across
/// modes and stay on [AppPalette]. The neutral surfaces/borders/text below
/// differ between light and dark, so screens read them through
/// `AppColors.of(context)` instead of the hard-coded dark constants. Registered
/// on both [AppTheme.light] and [AppTheme.dark] via `ThemeData.extensions`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
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
  });

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

  static const AppColors dark = AppColors(
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
  );

  static const AppColors light = AppColors(
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
  );

  /// Convenience accessor. Falls back to the dark set if the extension is
  /// somehow missing so screens never crash on a null lookup.
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? dark;

  @override
  AppColors copyWith({
    Color? background,
    Color? backgroundSoft,
    Color? surface,
    Color? surfaceStrong,
    Color? borderSoft,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
  }) {
    return AppColors(
      background: background ?? this.background,
      backgroundSoft: backgroundSoft ?? this.backgroundSoft,
      surface: surface ?? this.surface,
      surfaceStrong: surfaceStrong ?? this.surfaceStrong,
      borderSoft: borderSoft ?? this.borderSoft,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      backgroundSoft: Color.lerp(backgroundSoft, other.backgroundSoft, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceStrong: Color.lerp(surfaceStrong, other.surfaceStrong, t)!,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
    );
  }
}

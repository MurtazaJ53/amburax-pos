import 'package:business_hub_mobile/core/theme/app_colors.dart';
import 'package:business_hub_mobile/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// These assert the intended palette values directly (deterministic, no font
// loading). Building AppTheme.* pulls in google_fonts, which needs network in
// the test sandbox; the brand colours are what actually matter here.
void main() {
  test('brand primary is the Business Hub blue', () {
    expect(AppPalette.primary, const Color(0xFF0369A1));
    expect(AppPalette.accent, const Color(0xFF075985));
  });

  test('semantic money/alert colours are preserved', () {
    expect(AppPalette.success, const Color(0xFF15803D));
    expect(AppPalette.error, const Color(0xFFB91C1C));
    expect(AppPalette.warning, const Color(0xFFB45309));
  });

  test('light neutrals are the blue-and-white surfaces', () {
    expect(AppColors.light.background, const Color(0xFFEFF6FC));
    expect(AppColors.light.surface, const Color(0xFFFDFEFF));
    expect(AppColors.light.textPrimary, const Color(0xFF0F2942));
  });

  test('dark neutrals are hand-crafted, not inverted light ones', () {
    expect(AppColors.dark.background, const Color(0xFF0B1120));
    expect(AppColors.dark.surface, const Color(0xFF1E293B));
    expect(AppColors.dark.textPrimary, const Color(0xFFF8FAFC));
  });

  test('every neutral token differs between the two modes', () {
    const light = AppColors.light;
    const dark = AppColors.dark;
    expect(light.background, isNot(dark.background));
    expect(light.backgroundSoft, isNot(dark.backgroundSoft));
    expect(light.surface, isNot(dark.surface));
    expect(light.surfaceStrong, isNot(dark.surfaceStrong));
    expect(light.borderSoft, isNot(dark.borderSoft));
    expect(light.border, isNot(dark.border));
    expect(light.textPrimary, isNot(dark.textPrimary));
    expect(light.textSecondary, isNot(dark.textSecondary));
    expect(light.textTertiary, isNot(dark.textTertiary));
    expect(light.textDisabled, isNot(dark.textDisabled));
  });
}

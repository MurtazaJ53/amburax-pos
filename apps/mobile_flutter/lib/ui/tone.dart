import 'package:flutter/material.dart';

import '../core/money/money.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';

/// What a piece of UI *means*, rather than what colour it is.
///
/// The surface this replaces took a raw `accent: Color` on every tag, lead and
/// metric card. That is how `AppPalette` constants ended up hardcoded across
/// 180 call sites, and why the light/dark refactor broke the build: a screen
/// picked a literal colour that only worked on one ground.
///
/// A tone is resolved here, once, against the live theme. A screen says
/// "this is a warning"; it never says "this is `0xFFB45309`".
enum AppTone {
  /// Default. Reads as ordinary information.
  neutral,

  /// The brand blue. Actions, the current selection, links.
  primary,

  /// Money in, stock received, a sync that completed.
  success,

  /// Low stock, an overdue khata, something that needs a look.
  warning,

  /// Money out, a failed sync, a destructive action.
  danger,

  /// Advisory notes that are neither good nor bad.
  info,
}

/// The three colours a toned component needs: the mark itself, the wash behind
/// it, and the hairline that separates the wash from the page.
@immutable
class ToneColors {
  const ToneColors({
    required this.foreground,
    required this.background,
    required this.border,
  });

  /// Text and icons.
  final Color foreground;

  /// The tinted ground behind them.
  final Color background;

  /// Hairline border. Carries the shape when the wash is nearly invisible,
  /// which happens on both grounds at low alpha.
  final Color border;
}

/// Resolve a tone against the current theme.
///
/// Dark mode is not an inversion. The semantic colours on [AppPalette] are
/// picked for a light ground — `success` is a deep forest green that vanishes
/// on `#0B1120`. On a dark ground each one lifts to its brighter sibling, and
/// the wash alpha rises, because a 10% tint that reads on white disappears on
/// near-black.
ToneColors toneColorsOf(BuildContext context, AppTone tone) {
  final colors = AppColors.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  if (tone == AppTone.neutral) {
    return ToneColors(
      foreground: colors.textSecondary,
      background: colors.surfaceStrong,
      border: colors.borderSoft,
    );
  }

  final Color mark = switch (tone) {
    AppTone.primary => isDark ? AppPalette.primaryLight : AppPalette.primary,
    AppTone.success => isDark ? const Color(0xFF4ADE80) : AppPalette.success,
    AppTone.warning => isDark ? const Color(0xFFFBBF24) : AppPalette.warning,
    AppTone.danger => isDark ? const Color(0xFFF87171) : AppPalette.error,
    AppTone.info => isDark ? const Color(0xFF60A5FA) : AppPalette.info,
    AppTone.neutral => colors.textSecondary,
  };

  return ToneColors(
    foreground: mark,
    background: mark.withValues(alpha: isDark ? 0.18 : 0.10),
    border: mark.withValues(alpha: isDark ? 0.34 : 0.22),
  );
}

/// The tone that suits a signed amount: what came in is [AppTone.success],
/// what went out is [AppTone.danger], and zero is not an event.
///
/// Kept here rather than in each screen so a refund, an expense and a khata
/// payment are never coloured by three different opinions.
AppTone toneForAmount(Money amount) {
  if (amount.paise > 0) return AppTone.success;
  if (amount.paise < 0) return AppTone.danger;
  return AppTone.neutral;
}

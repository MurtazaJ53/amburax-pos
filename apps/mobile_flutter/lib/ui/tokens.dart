import 'package:flutter/widgets.dart';

/// Design tokens for the rebuilt UI layer.
///
/// Colours are NOT here — they live on `AppColors` in `core/theme/app_colors.dart`
/// and are read per-build with `AppColors.of(context)`, because they change
/// between light and dark. Everything in this file is constant across themes.
///
/// The visual direction is deliberately tighter than the screens it replaces.
/// A till is read at arm's length, in a shop with bad overhead lighting, by
/// someone holding a customer's items in the other hand. That argues for
/// density and edge definition over softness: smaller radii, hairline borders
/// that actually separate things, and no drop shadows except where an element
/// genuinely floats above the page.

/// Spacing scale. Use these instead of raw numbers so rhythm stays consistent
/// when a screen is assembled from widgets written weeks apart.
abstract final class Gap {
  /// 4 — between an icon and its label.
  static const double xxs = 4;

  /// 8 — between tightly related items in a row.
  static const double xs = 8;

  /// 12 — inside a control; between a title and its subtitle.
  static const double sm = 12;

  /// 16 — the default. Card padding, list row padding, gap between cards.
  static const double md = 16;

  /// 20 — screen horizontal margin.
  static const double lg = 20;

  /// 24 — between distinct groups on a screen.
  static const double xl = 24;

  /// 32 — between major sections.
  static const double xxl = 32;

  /// 96 — bottom padding on a scrolling screen, so the last row clears the
  /// nav bar and any floating action.
  static const double scrollBottom = 96;
}

/// Corner radii. The old surface used 24–32 throughout, which reads soft and
/// costs horizontal room on a 360dp phone. These are tighter.
abstract final class Radii {
  /// 8 — tags, small chips.
  static const double sm = 8;

  /// 12 — buttons, fields, list rows.
  static const double md = 12;

  /// 16 — cards and panels.
  static const double lg = 16;

  /// 24 — bottom sheets (top corners only).
  static const double sheet = 24;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));

  /// Bottom sheets round only at the top — the bottom is off-screen.
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
}

/// Border widths. One hairline everywhere, one heavier for focus/selection.
abstract final class Strokes {
  static const double hairline = 1;
  static const double emphasis = 1.5;
}

/// Minimum tap target. Below this, a thumb misses — and at a counter a missed
/// tap means re-scanning an item with a queue waiting.
abstract final class TapTarget {
  static const double min = 48;

  /// Numeric keypad and quantity steppers, used at speed.
  static const double large = 56;
}

/// Layout breakpoints. The app targets phones and tablets only.
abstract final class Breakpoints {
  /// Below this, drop to single-column and shrink paddings.
  static const double compact = 400;

  /// At or above this, a tablet layout can show a side panel.
  static const double wide = 720;

  /// True on a narrow phone, where every horizontal pixel is contested.
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;

  /// True where there is room for a two-pane layout.
  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;
}

import 'package:flutter/material.dart';

/// Motion tokens for the rebuilt UI layer.
///
/// Ported from the motion-foundations rules the web side follows, with the
/// web-only parts dropped. There is no server render to hydrate against here,
/// and `prefers-reduced-motion` arrives as [MediaQueryData.disableAnimations]
/// instead of a CSS media query — but the three principles survive intact:
///
///  1. Motion must guide attention, communicate state, or preserve spatial
///     continuity. Decoration is removed, not tuned.
///  2. Responsiveness outranks smoothness. A till that animates before it
///     responds feels slower than a till that does not animate at all.
///  3. Reduced motion overrides everything. Transforms go, opacity may stay.
///
/// The durations below are shorter than the web defaults on purpose. This is a
/// counter app: the operator has already moved on to the next barcode before a
/// 350ms card entrance finishes, and an animation still running when the next
/// tap lands reads as lag.
abstract final class AppMotion {
  /// 80ms — a tag changing colour, a focus ring, a badge counting up.
  static const Duration instant = Duration(milliseconds: 80);

  /// 140ms — button press feedback, icon swap, chip toggle. The default.
  static const Duration fast = Duration(milliseconds: 140);

  /// 220ms — a sheet opening, a card expanding, a row entering.
  static const Duration normal = Duration(milliseconds: 220);

  /// 320ms — a full-screen transition. Nothing in this app should be slower.
  static const Duration slow = Duration(milliseconds: 320);

  /// Decelerating; the standard for something arriving and settling.
  static const Curve smooth = Cubic(0.22, 1, 0.36, 1);

  /// Symmetrical; for something changing in place rather than travelling.
  static const Curve sharp = Cubic(0.4, 0, 0.2, 1);

  /// Overshoots. Reserved for confirmation — the moment a sale completes.
  /// Never for routine state.
  static const Curve bounce = Cubic(0.34, 1.56, 0.64, 1);

  /// Travel distances for enter/exit offsets, in logical pixels.
  static const double nudge = 4;
  static const double riseSmall = 8;
  static const double rise = 16;

  /// Press feedback scale. 0.97 is felt without being seen — anything deeper
  /// looks like the row is being dragged rather than tapped.
  static const double pressScale = 0.97;

  /// True when the operating system has been told to reduce motion, or the
  /// platform is otherwise animation-hostile.
  ///
  /// Flutter routes the Android "Remove animations" accessibility setting
  /// here, so this is the same switch a screen-reader user flips.
  static bool enabled(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context);

  /// [base], or zero when motion is disabled.
  ///
  /// Prefer this over branching at the call site: an implicit animation with a
  /// zero duration still lands on the correct end state, so the widget tree
  /// stays one shape in both modes.
  static Duration durationOf(BuildContext context, Duration base) =>
      enabled(context) ? base : Duration.zero;

  /// The distance a widget should travel on entry — zero when motion is
  /// disabled, so an entrance degrades to a plain fade rather than vanishing.
  static double offsetOf(BuildContext context, double base) =>
      enabled(context) ? base : 0;
}

/// Spring presets, for the few places a curve is the wrong model — anything
/// the finger is still touching, where the end position can change mid-flight.
abstract final class AppSprings {
  /// Default for controls that snap back: chips, toggles, nav items.
  static const SpringDescription snappy = SpringDescription(
    mass: 1,
    stiffness: 300,
    damping: 30,
  );

  /// Cards, sheets and panels landing softly.
  static const SpringDescription gentle = SpringDescription(
    mass: 1,
    stiffness: 120,
    damping: 14,
  );

  /// A sheet released mid-drag, continuing under its own momentum.
  static const SpringDescription release = SpringDescription(
    mass: 1,
    stiffness: 200,
    damping: 20,
  );
}

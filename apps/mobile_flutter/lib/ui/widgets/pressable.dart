import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';
import '../tone.dart';

/// Wraps a tappable surface so it acknowledges the finger before the work
/// behind it finishes.
///
/// The audit that produced this found one `Semantics` node in the whole app
/// and no reduced-motion handling anywhere, so both are built in here rather
/// than left to each call site to remember:
///
///  * a press shrinks the surface by [scale] for [AppMotion.fast] — the only
///    feedback a product tile gets today is the ripple, which is invisible
///    against a dark card in a bright shop;
///  * the child is announced as a button with [semanticLabel], because a card
///    made of a `GestureDetector` is silent to TalkBack;
///  * it takes keyboard focus and draws a ring when it has it. A bare
///    `GestureDetector` does not, and a shop running a Bluetooth barcode
///    scanner has a keyboard attached whether it thinks so or not;
///  * when the system asks for reduced motion the scale is skipped entirely,
///    not merely shortened. A transform is the thing being objected to.
///
/// Use this where a ripple is wrong — image tiles, dense grid cards. Rows and
/// list items should keep `InkWell`, which is already correct for them.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.scale = AppMotion.pressScale,
    this.borderRadius,
  });

  final Widget child;

  final VoidCallback? onTap;

  final VoidCallback? onLongPress;

  /// What a screen reader says. Null leaves the child's own semantics alone,
  /// which is right when the child is already a labelled row of text.
  final String? semanticLabel;

  final double scale;

  /// Clips the child while it is scaled, so a card's corners stay square with
  /// its border instead of bleeding past it.
  final BorderRadius? borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _focused = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  void _setDown(bool value) {
    if (!_interactive || _down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final animate = AppMotion.enabled(context);
    final radius = widget.borderRadius ?? Radii.mdAll;

    Widget result = AnimatedScale(
      scale: _down && animate ? widget.scale : 1,
      duration: AppMotion.durationOf(context, AppMotion.fast),
      curve: AppMotion.sharp,
      child: widget.child,
    );

    if (widget.borderRadius != null) {
      result = ClipRRect(borderRadius: widget.borderRadius!, child: result);
    }

    if (!_interactive) {
      return widget.semanticLabel == null
          ? result
          : Semantics(label: widget.semanticLabel, child: result);
    }

    // Painted over the child rather than around it, so gaining focus never
    // changes the surface's size and nudges its neighbours.
    result = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: _focused
            ? Border.all(
                color: toneColorsOf(context, AppTone.primary).foreground,
                width: Strokes.emphasis,
              )
            : null,
      ),
      child: result,
    );

    return Semantics(
      button: true,
      enabled: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: (_) => _setDown(true),
          onTapUp: (_) => _setDown(false),
          onTapCancel: () => _setDown(false),
          child: result,
        ),
      ),
    );
  }
}

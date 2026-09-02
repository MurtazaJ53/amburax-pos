import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../motion.dart';
import '../tokens.dart';
import '../tone.dart';

/// Minus, the number, plus — the control that changes how many of something
/// the customer is buying.
///
/// Promoted out of `pos_screen_v3.dart`, where it lived as a private
/// `_QtyStepper` alongside 19 other widgets. Inventory, stocktake, purchase
/// orders and returns all need the same control and each was about to grow
/// its own.
///
/// Two changes on the way out:
///   * the hardcoded `AppPalette.primary` became [tone], so a returns sheet
///     can render the same control in red without a second copy;
///   * the tap target went from 40x44 to 48. Below that a thumb misses, and a
///     missed tap at a till means re-scanning an item with a queue waiting.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    this.onTapQuantity,
    this.tone = AppTone.primary,
    this.dense = false,
  });

  final double quantity;

  final VoidCallback onIncrement;

  /// Called at any quantity, including 1 — removing the last one is the
  /// caller's decision, not this widget's.
  final VoidCallback onDecrement;

  /// Tap the number to type an exact quantity. Null hides the affordance;
  /// weighed goods need it, counted goods usually do not.
  final VoidCallback? onTapQuantity;

  final AppTone tone;

  /// Shrinks to fit a cart line, where the row is already carrying a name and
  /// a price. Still 40 tall — never smaller.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = toneColorsOf(context, tone);
    final height = dense ? 40.0 : TapTarget.min;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: Radii.mdAll,
        border: Border.all(color: c.border, width: Strokes.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StepButton(
            icon: Icons.remove_rounded,
            onTap: onDecrement,
            colour: c.foreground,
            height: height,
            semanticLabel: 'One fewer',
          ),
          GestureDetector(
            onTap: onTapQuantity,
            child: SizedBox(
              width: dense ? 34 : 40,
              child: Text(
                formatQuantity(quantity),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: dense ? 15 : 16,
                  color: c.foreground,
                  decoration: onTapQuantity == null
                      ? null
                      : TextDecoration.underline,
                  decorationColor: c.foreground,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            onTap: onIncrement,
            colour: c.foreground,
            height: height,
            semanticLabel: 'One more',
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.colour,
    required this.height,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color colour;
  final double height;
  final String semanticLabel;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  bool _down = false;

  void _setDown(bool value) {
    if (_down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    // The ripple alone is not enough here. This is the most-tapped control in
    // the app and it is often pressed repeatedly against a dark card in a
    // brightly lit shop, where a low-contrast ripple is invisible — so the
    // icon itself shrinks to confirm the tap registered.
    final animate = AppMotion.enabled(context);

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: InkWell(
        onTap: widget.onTap,
        onTapDown: (_) => _setDown(true),
        onTapUp: (_) => _setDown(false),
        onTapCancel: () => _setDown(false),
        borderRadius: Radii.mdAll,
        child: SizedBox(
          width: widget.height,
          height: widget.height,
          child: AnimatedScale(
            scale: _down && animate ? 0.82 : 1,
            duration: AppMotion.durationOf(context, AppMotion.instant),
            curve: AppMotion.sharp,
            child: Icon(widget.icon, size: 20, color: widget.colour),
          ),
        ),
      ),
    );
  }
}

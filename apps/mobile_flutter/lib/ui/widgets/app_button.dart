import 'dart:async';

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../tone.dart';

/// How much weight a button carries on the screen it sits on.
enum AppButtonVariant {
  /// Solid fill. One per screen — the thing the operator came to do.
  filled,

  /// Outlined. The alternative to the filled action, not a lesser copy of it.
  outline,

  /// Text only. Dismissals, "not now", anything that undoes rather than does.
  text,
}

/// A button that knows what it costs and whether it is still running.
///
/// The app already themes `FilledButton` and friends, so this is not a
/// reskin. It exists to close the two gaps that theming cannot:
///
/// **Tone.** Every filled button in the app renders in the same pale primary,
/// so "Save" and "Delete this shop" are the same button wearing different
/// words. [tone] makes destructive actions look destructive.
///
/// **Async state.** There are 199 hand-rolled busy flags and 39 hand-rolled
/// spinners across the feature folders, because every screen that saves
/// something re-solved this. Give [onPressed] a callback that returns a
/// `Future` and the button disables itself and shows a spinner until that
/// future settles — including when it throws, which is the case the
/// hand-rolled versions most often get wrong and leave the button dead.
///
/// A synchronous callback behaves like an ordinary button; nothing changes.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = AppTone.primary,
    this.variant = AppButtonVariant.filled,
    this.busy = false,
    this.fullWidth = false,
    this.semanticLabel,
  });

  final String label;

  /// Null disables the button.
  ///
  /// Returning a `Future` opts into the managed busy state; returning nothing
  /// does not. Both are valid — a filter toggle should not spin.
  final FutureOr<void> Function()? onPressed;

  final IconData? icon;

  final AppTone tone;

  final AppButtonVariant variant;

  /// Forces the busy state on, for callers that already track it themselves
  /// (a form whose submit is driven by a provider, say). The managed state
  /// from [onPressed] is ORed with this, never overwritten by it.
  final bool busy;

  /// Stretches to the available width. Sheets and action bars want this;
  /// a button inline in a row does not.
  final bool fullWidth;

  /// Overrides what a screen reader announces. Use when [label] is short
  /// enough to be ambiguous out of context — "Remove" alone does not say
  /// remove what.
  final String? semanticLabel;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _running = false;

  bool get _busy => widget.busy || _running;

  Future<void> _handlePress() async {
    final callback = widget.onPressed;
    if (callback == null || _busy) return;

    final result = callback();
    if (result is! Future<void>) return;

    setState(() => _running = true);
    try {
      await result;
    } catch (error, stack) {
      // Reported, not rethrown. Nothing awaits this method — the button's
      // onPressed discards it — so rethrowing would produce an unhandled
      // async error that no caller can catch and that crashes the zone in
      // release. Routing it through FlutterError keeps it visible to the
      // error reporter while leaving the widget in a usable state.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'business hub ui',
          context: ErrorDescription('running the AppButton "${widget.label}"'),
        ),
      );
    } finally {
      // The button must come back even when the work threw. A dead button
      // after a failed save is worse than the failure — the operator cannot
      // retry, and nothing on screen says why.
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !_busy;
    final c = toneColorsOf(context, widget.tone);
    final spinnerColour = c.foreground;

    final Widget leading = _busy
        ? _Spinner(colour: spinnerColour)
        : (widget.icon == null
              ? const SizedBox.shrink()
              : Icon(widget.icon, size: 20));

    // The slot keeps its width whether it holds an icon, a spinner or
    // nothing, so a button does not resize the moment it is pressed.
    final Widget child = Row(
      mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (widget.icon != null || _busy) ...<Widget>[
          SizedBox(width: 20, height: 20, child: Center(child: leading)),
          const SizedBox(width: Gap.xs),
        ],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    final Widget button = switch (widget.variant) {
      // Pale ground, dark ink — not a solid fill under white text.
      //
      // The first version of this used a solid tone fill with white on top,
      // which is the thing the web spent four attempts getting away from: its
      // palette file records that white text forces a dark fill to stay
      // legible, and a dark fill is what makes a light screen look heavy. The
      // app's own filledButtonTheme already had it right and this was
      // overriding it. The ink measures well past 4.5:1 on the pale ground in
      // both themes, and the border keeps the button's edge readable.
      AppButtonVariant.filled => FilledButton(
        onPressed: enabled ? _handlePress : null,
        style: FilledButton.styleFrom(
          backgroundColor: c.background,
          foregroundColor: c.foreground,
          side: BorderSide(color: c.border, width: Strokes.hairline),
          minimumSize: const Size(0, TapTarget.large),
        ),
        child: child,
      ),
      AppButtonVariant.outline => OutlinedButton(
        onPressed: enabled ? _handlePress : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: c.foreground,
          side: BorderSide(color: c.border, width: Strokes.emphasis),
          minimumSize: const Size(0, TapTarget.large),
        ),
        child: child,
      ),
      AppButtonVariant.text => TextButton(
        onPressed: enabled ? _handlePress : null,
        style: TextButton.styleFrom(
          foregroundColor: c.foreground,
          minimumSize: const Size(0, TapTarget.min),
        ),
        child: child,
      ),
    };

    return Semantics(
      label: widget.semanticLabel,
      // A button that is working is not a button that is broken. Without
      // this the only signal is that nothing happens when tapped.
      hint: _busy ? 'Working' : null,
      child: SizedBox(
        width: widget.fullWidth ? double.infinity : null,
        child: button,
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) {
    // A spinner is the one animation that must survive reduced motion: it is
    // the only thing saying the work is still running.
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: colour),
    );
  }
}

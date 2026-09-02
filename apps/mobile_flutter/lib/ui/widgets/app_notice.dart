import 'package:flutter/material.dart';

import '../tokens.dart';
import '../tone.dart';

/// A quiet line of text that tells the operator something the screen would
/// otherwise hide from them.
///
/// Not a banner and not a dialog: it does not interrupt, it does not need
/// dismissing, and it sits in the flow where the thing it describes is. The
/// case it was written for is a catalogue showing 50 of 5,000 products with
/// nothing on screen admitting the other 4,950 exist.
///
/// [tone] carries the weight. `neutral` is a statement of fact — the default,
/// and the right choice most of the time. `warning` is for something the
/// operator may need to act on. Reach for `danger` only when the screen is
/// showing something wrong, not merely incomplete.
class AppNotice extends StatelessWidget {
  const AppNotice({
    super.key,
    required this.message,
    this.tone = AppTone.neutral,
    this.icon,
  });

  final String message;

  final AppTone tone;

  /// Omit for a plain statement. An icon reads as an alert, so it earns its
  /// place only when the operator is meant to do something.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = toneColorsOf(context, tone);
    final theme = Theme.of(context);

    return Semantics(
      // Announced when it appears rather than only when focus reaches it: the
      // whole point is that the operator does not already know.
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.sm,
          vertical: Gap.xs + 2,
        ),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: Radii.mdAll,
          border: Border.all(color: c.border, width: Strokes.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 16, color: c.foreground),
              const SizedBox(width: Gap.xs),
            ],
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: c.foreground,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

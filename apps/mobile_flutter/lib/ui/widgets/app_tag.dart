import 'package:flutter/material.dart';

import '../tokens.dart';
import '../tone.dart';

/// A small status mark: `PAID`, `LOW STOCK`, `3 DOZEN`, `SYNCING`.
///
/// Replaces `MobileTag`, the most-used widget in the old surface (146 call
/// sites). The API change is deliberate: the old one took `accent: Color`, so
/// every screen picked its own literal and the meaning lived in the caller's
/// head. This takes an [AppTone], so "overdue" is the same amber everywhere
/// and dark mode is handled once.
class AppTag extends StatelessWidget {
  const AppTag({
    super.key,
    required this.label,
    this.icon,
    this.tone = AppTone.neutral,
  });

  /// Short, and upper-cased on screen. A tag that needs a sentence is not a tag.
  final String label;

  final IconData? icon;

  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final c = toneColorsOf(context, tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: Radii.smAll,
        border: Border.all(color: c.border, width: Strokes.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.xs,
          vertical: Gap.xxs + 1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, color: c.foreground, size: 13),
              const SizedBox(width: Gap.xxs + 1),
            ],
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: c.foreground,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tag whose label is a count — `12 LOW`, `3 QUEUED`.
///
/// Exists because the count-plus-noun pattern appeared by hand all over the old
/// screens, each spelling the spacing and pluralisation slightly differently.
class AppCountTag extends StatelessWidget {
  const AppCountTag({
    super.key,
    required this.count,
    required this.noun,
    this.icon,
    this.tone = AppTone.neutral,
  });

  final int count;

  /// Written singular; pluralised here when [count] is not 1.
  final String noun;

  final IconData? icon;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final plural = count == 1 ? noun : '${noun}s';
    return AppTag(label: '$count $plural', icon: icon, tone: tone);
  }
}

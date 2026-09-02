import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../tokens.dart';
import '../tone.dart';

/// Opens a bottom sheet with the app's shape, safe-area handling and
/// scrolling already correct.
///
/// There are 38 `showModalBottomSheet` calls across the feature folders and
/// each one re-specified `isScrollControlled`, a background colour, a
/// `SafeArea` and its own padding. They do not agree with each other: some
/// clip behind the gesture bar, some cannot scroll when the keyboard is up,
/// and one caps its height at a hardcoded 680 that is taller than a small
/// phone.
///
/// This takes those decisions once:
///
///  * the sheet never exceeds [maxHeightFactor] of the screen, so it cannot
///    open taller than the device it is on;
///  * content scrolls inside the sheet rather than the sheet growing, and the
///    scroll view is padded by the keyboard inset, so a field being typed
///    into stays visible;
///  * a drag handle is drawn, because a sheet with no handle reads as a page
///    and the operator looks for a back button that is not there;
///  * the barrier is labelled, so dismissing by tapping outside is
///    discoverable to a screen reader rather than being a silent gesture.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  double maxHeightFactor = 0.9,
}) {
  final colors = AppColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    backgroundColor: colors.background,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
    ),
    builder: (context) => AppSheet(child: Builder(builder: builder)),
  );
}

/// The inside of a bottom sheet: handle, safe area, keyboard-aware scroll.
///
/// Use [showAppSheet] rather than this directly. It is public only so a sheet
/// that must be pushed as a route can still get the same shape.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Excluded from semantics: it is a visual affordance for a gesture
          // the screen reader already offers as "dismiss".
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(top: Gap.sm, bottom: Gap.xs),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderSoft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                Gap.lg,
                Gap.xs,
                Gap.lg,
                Gap.xl + keyboard,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// The title block at the top of a sheet.
///
/// Replaces `MobileSheetHeader` (15 call sites). Two changes on the way over:
/// [subtitle] and [icon] are optional, because half the call sites were
/// passing filler to satisfy a required parameter; and the accent is an
/// [AppTone] rather than a raw `Color`, so a sheet that voids a sale can be
/// red without the caller reaching for `AppPalette`.
class AppSheetHeader extends StatelessWidget {
  const AppSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.eyebrow,
    this.tone = AppTone.primary,
    this.tags = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? eyebrow;
  final AppTone tone;
  final List<Widget> tags;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final c = toneColorsOf(context, tone);

    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Container(
                  width: TapTarget.min,
                  height: TapTarget.min,
                  decoration: BoxDecoration(
                    color: c.background,
                    borderRadius: Radii.lgAll,
                    border: Border.all(
                      color: c.border,
                      width: Strokes.hairline,
                    ),
                  ),
                  child: Icon(icon, color: c.foreground, size: 22),
                ),
                const SizedBox(width: Gap.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (eyebrow != null) ...<Widget>[
                      Text(
                        eyebrow!.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: Gap.xxs),
                    ],
                    Text(title, style: theme.textTheme.titleLarge),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: Gap.xxs),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: Gap.sm),
            Wrap(spacing: Gap.xs, runSpacing: Gap.xs, children: tags),
          ],
        ],
      ),
    );
  }
}

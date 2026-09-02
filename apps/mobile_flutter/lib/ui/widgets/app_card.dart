import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../tokens.dart';

/// A plain raised surface: the ground most content sits on.
///
/// Deliberately has no shadow. The old surface put a 24px-blur drop shadow on
/// every card, which on a screen holding eight of them reads as mush. Here a
/// hairline border does the separating, and elevation is reserved for things
/// that genuinely float — sheets and dialogs.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.md),
    this.onTap,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// When set, the whole card is tappable and takes an ink ripple.
  final VoidCallback? onTap;

  /// Draws the border in the brand colour. For the shop you are currently in,
  /// the payment mode you picked, the variant in the cart.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Radii.lgAll,
        border: Border.all(
          color: selected ? scheme.primary : colors.borderSoft,
          width: selected ? Strokes.emphasis : Strokes.hairline,
        ),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return decorated;

    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: Radii.lgAll, child: decorated),
    );
  }
}

/// A card with a title bar and an optional action on the right.
///
/// Replaces `MobilePanel` (121 call sites). Title is now optional — a good
/// third of those uses passed a title only because the widget demanded one.
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.title,
    this.action,
    this.padding = const EdgeInsets.all(Gap.md),
  });

  final Widget child;

  /// Omit for an untitled container; use [AppCard] directly if you also want
  /// no padding opinion.
  final String? title;

  /// Usually an [AppTag] or a small text button. Sits opposite the title.
  final Widget? action;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasHeader = title != null || action != null;

    return AppCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasHeader) ...<Widget>[
            Row(
              children: <Widget>[
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                if (action != null) ...<Widget>[
                  const SizedBox(width: Gap.xs),
                  action!,
                ],
              ],
            ),
            const SizedBox(height: Gap.sm),
          ],
          child,
        ],
      ),
    );
  }
}

/// The small upper-case label that names a group of rows — `MANAGE`, `MORE`,
/// `ACCOUNT`.
///
/// The old settings screen had exactly one of these, `_SectionLabel('Manage')`,
/// private to that file, with 23 tiles beneath it. Phase 2 needs several, so it
/// becomes a shared primitive.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(this.label, {super.key, this.trailing});

  final String label;

  /// Optional right-hand affordance — a count, or a "See all".
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: Gap.xxs,
        right: Gap.xxs,
        top: Gap.xl,
        bottom: Gap.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

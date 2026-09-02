import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../tokens.dart';
import '../tone.dart';

/// One tappable row in a settings list or a picker.
///
/// Replaces `MobileListTile` (28 call sites). Keeps the leading icon, title and
/// subtitle; adds an optional [trailing] so a row can carry a tag or a count
/// without the caller rebuilding the layout.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.trailing,
    this.onTap,
    this.tone = AppTone.neutral,
    this.showChevron = true,
  });

  final String title;

  /// One line explaining what the row does in the shopkeeper's words. The old
  /// settings list proved these earn their space — "What came in today, and
  /// what went out on credit" tells you more than "Day book" alone.
  final String? subtitle;

  final IconData? leadingIcon;

  /// Sits before the chevron. Usually an `AppTag`.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// Tints the leading icon. Use [AppTone.danger] for destructive rows.
  final AppTone tone;

  /// Hidden for rows that open a sheet in place rather than navigating.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final c = toneColorsOf(context, tone);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.sm,
            vertical: Gap.sm,
          ),
          child: Row(
            children: <Widget>[
              if (leadingIcon != null) ...<Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.background,
                    borderRadius: Radii.mdAll,
                    border: Border.all(
                      color: c.border,
                      width: Strokes.hairline,
                    ),
                  ),
                  child: Icon(leadingIcon, size: 19, color: c.foreground),
                ),
                const SizedBox(width: Gap.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: Gap.xs),
                trailing!,
              ],
              if (showChevron && onTap != null) ...<Widget>[
                const SizedBox(width: Gap.xxs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colors.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown where a list would otherwise be blank.
///
/// Replaces `MobileEmptyState` (58 call sites). The [action] is new: an empty
/// state that only explains is a dead end, and most of these appear where the
/// shopkeeper can do something about it — add the first item, take a count,
/// clear a filter.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.tone = AppTone.neutral,
  });

  final IconData icon;

  /// What is not here, stated plainly. Not "No data".
  final String title;

  /// Why it is empty, and what fills it.
  final String body;

  /// Optional button — usually the thing that ends the emptiness.
  final Widget? action;

  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = toneColorsOf(context, tone);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.lg,
        vertical: Gap.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.background,
              borderRadius: Radii.lgAll,
              border: Border.all(color: c.border, width: Strokes.hairline),
            ),
            child: Icon(icon, size: 26, color: c.foreground),
          ),
          const SizedBox(height: Gap.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: Gap.xxs + 2),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: Gap.md),
            action!,
          ],
        ],
      ),
    );
  }
}

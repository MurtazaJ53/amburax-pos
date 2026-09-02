import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

class MobileStandaloneScaffold extends StatelessWidget {
  const MobileStandaloneScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final compact = MediaQuery.sizeOf(context).width < 420;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              colors.background,
              colors.backgroundSoft,
              colors.backgroundSoft,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 18,
                  compact ? 14 : 18,
                  compact ? 14 : 18,
                  compact ? 8 : 10,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.backgroundSoft.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(compact ? 22 : 24),
                    border: Border.all(color: colors.borderSoft),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 12 : 14,
                      vertical: compact ? 10 : 12,
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: compact ? 44 : 48,
                          height: compact ? 44 : 48,
                          decoration: BoxDecoration(
                            color: colors.surfaceStrong,
                            borderRadius: BorderRadius.circular(
                              compact ? 15 : 18,
                            ),
                            border: Border.all(color: colors.borderSoft),
                          ),
                          child: IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: Icon(
                              Icons.arrow_back_rounded,
                              size: compact ? 20 : 24,
                            ),
                            color: colors.textPrimary,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                ),
                          ),
                        ),
                        if (trailing != null) ...<Widget>[
                          const SizedBox(width: 10),
                          trailing!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class MobileHeroBanner extends StatelessWidget {
  const MobileHeroBanner({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.accent = AppPalette.primary,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 420;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 24 : 30),
        color: colors.surface,
        border: Border.all(color: colors.borderSoft),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: compact ? -24 : -32,
            right: compact ? -12 : -18,
            child: Container(
              width: compact ? 104 : 130,
              height: compact ? 104 : 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            bottom: compact ? -34 : -46,
            left: compact ? -18 : -24,
            child: Container(
              width: compact ? 118 : 150,
              height: compact ? 118 : 150,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x1A0EA5E9),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 18 : 22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    trailing != null &&
                    constraints.maxWidth < (compact ? 520 : 470);
                final content = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      eyebrow.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: compact ? 1.4 : 1.8,
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 12),
                    Text(
                      title,
                      maxLines: compact ? 3 : null,
                      overflow: compact ? TextOverflow.ellipsis : null,
                      style:
                          (compact
                                  ? theme.textTheme.headlineSmall
                                  : theme.textTheme.headlineMedium)
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: compact ? 0.98 : 0.94,
                                letterSpacing: compact ? -0.8 : -1.15,
                              ),
                    ),
                    SizedBox(height: compact ? 10 : 14),
                    Text(
                      subtitle,
                      maxLines: compact ? 3 : null,
                      overflow: compact ? TextOverflow.ellipsis : null,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: compact ? 1.4 : 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );

                if (trailing == null) {
                  return content;
                }

                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      content,
                      SizedBox(height: compact ? 14 : 18),
                      trailing!,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: content),
                    const SizedBox(width: 16),
                    trailing!,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MobilePanel extends StatelessWidget {
  const MobilePanel({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 420;
    final headerChildren = <Widget>[
      Expanded(
        child: Text(
          title,
          style:
              (compact
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.titleLarge)
                  ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.45),
        ),
      ),
      if (action case final nextAction?) ...<Widget>[nextAction],
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        border: Border.all(color: colors.borderSoft.withValues(alpha: 0.72)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: headerChildren),
            SizedBox(height: compact ? 10 : 14),
            child,
          ],
        ),
      ),
    );
  }
}

class MobileScreenLead extends StatelessWidget {
  const MobileScreenLead({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.primaryTag,
    this.secondaryTag,
    this.accent = AppPalette.primary,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? primaryTag;
  final Widget? secondaryTag;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 420;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        border: Border.all(color: colors.borderSoft.withValues(alpha: 0.64)),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: compact ? 42 : 48,
                  height: compact ? 42 : 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(compact ? 14 : 16),
                  ),
                  child: Icon(icon, color: accent, size: compact ? 20 : 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style:
                            (compact
                                    ? theme.textTheme.titleLarge
                                    : theme.textTheme.headlineSmall)
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.6,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (primaryTag != null || secondaryTag != null) ...<Widget>[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  ...<Widget?>[primaryTag, secondaryTag].whereType<Widget>(),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MobileMetricCard extends StatelessWidget {
  const MobileMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent = AppPalette.info,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 420;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        child: Ink(
          decoration: BoxDecoration(
            color: colors.surfaceStrong,
            borderRadius: BorderRadius.circular(compact ? 20 : 24),
            border: Border.all(color: colors.borderSoft),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 18),
            // On phones the stacked icon-above-label layout made these tiles
            // near-square and they ate a third of the screen. Compact puts the
            // icon inline with the label and keeps the caption to one line.
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(icon, color: accent, size: 15),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.textTertiary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          maxLines: 1,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.7,
                          ),
                        ),
                      ),
                      if (caption != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          caption!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: accent, size: 22),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        label.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        value,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.7,
                        ),
                      ),
                      if (caption != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          caption!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class MobileActionCard extends StatelessWidget {
  const MobileActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.kicker,
    this.accent = AppPalette.primary,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final String? kicker;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 420;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 22 : 28),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 22 : 28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                accent.withValues(alpha: 0.34),
                accent.withValues(alpha: 0.14),
                colors.surfaceStrong,
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.26)),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: compact ? 48 : 56,
                  height: compact ? 48 : 56,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(compact ? 14 : 18),
                  ),
                  child: Icon(
                    icon,
                    color: accent,
                    size: compact ? 24 : 28,
                  ),
                ),
                const Spacer(),
                if (kicker != null) ...<Widget>[
                  Text(
                    kicker!.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.textPrimary.withValues(alpha: 0.76),
                      fontWeight: FontWeight.w900,
                      letterSpacing: compact ? 1.1 : 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  title,
                  style:
                      (compact
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.headlineSmall)
                          ?.copyWith(fontWeight: FontWeight.w900, height: 0.98),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  maxLines: compact ? 3 : null,
                  overflow: compact ? TextOverflow.ellipsis : null,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MobileTag extends StatelessWidget {
  const MobileTag({
    super.key,
    required this.label,
    this.icon,
    this.accent = AppPalette.primary,
  });

  final String label;
  final IconData? icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, color: accent, size: 16),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MobileEmptyState extends StatelessWidget {
  const MobileEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.backgroundSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: colors.textSecondary, size: 26),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class MobileSheetHeader extends StatelessWidget {
  const MobileSheetHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.eyebrow,
    this.accent = AppPalette.primary,
    this.tags = const <Widget>[],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? eyebrow;
  final Color accent;
  final List<Widget> tags;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (eyebrow != null) ...<Widget>[
                        Text(
                          eyebrow!.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.textTertiary,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (tags.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: tags),
            ],
          ],
        ),
      ),
    );
  }
}

class MobileListTile extends StatelessWidget {
  const MobileListTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.leadingIcon,
    this.trailing,
    this.accent = AppPalette.primary,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData? leadingIcon;
  final Widget? trailing;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: colors.surfaceStrong.withValues(alpha: 0.66),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.borderSoft.withValues(alpha: 0.62)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                if (leadingIcon != null) ...<Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(leadingIcon, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: 12),
                  trailing!,
                ] else if (onTap != null) ...<Widget>[
                  const SizedBox(width: 10),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textTertiary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MobileActionBar extends StatelessWidget {
  const MobileActionBar({
    super.key,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimaryPressed,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondaryPressed,
  });

  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimaryPressed;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 390;
    final primary = FilledButton.icon(
      onPressed: onPrimaryPressed,
      icon: Icon(primaryIcon),
      label: Text(primaryLabel),
    );
    final secondary = secondaryLabel == null
        ? null
        : OutlinedButton.icon(
            onPressed: onSecondaryPressed,
            icon: Icon(secondaryIcon ?? Icons.arrow_forward_rounded),
            label: Text(secondaryLabel!),
          );

    if (secondary == null) {
      return SizedBox(width: double.infinity, child: primary);
    }

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[primary, const SizedBox(height: 10), secondary],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(child: primary),
        const SizedBox(width: 10),
        Expanded(child: secondary),
      ],
    );
  }
}

class MobileSheetSection extends StatelessWidget {
  const MobileSheetSection({
    super.key,
    required this.title,
    required this.child,
    this.accent = AppPalette.warning,
  });

  final String title;
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceStrong.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderSoft.withValues(alpha: 0.64)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

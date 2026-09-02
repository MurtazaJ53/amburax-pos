import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../../ui/tokens.dart';
import '../../ui/tone.dart';
import '../../ui/widgets/app_button.dart';

/// Widgets shared by the dashboard, inventory and customer screens.
///
/// Named for a visual direction — "Electric Ocean", vibrant gradients — that
/// the app has since moved away from. The gradients are gone; the file stays
/// only until Phase 3 rebuilds those three screens against `lib/ui/`, at
/// which point it is deleted rather than renamed.

/// The single largest figure on a screen — today's takings, stock value.
class HeroMetricCard extends StatelessWidget {
  const HeroMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    this.trend,
    this.accentColor,
  });

  final String label;
  final String value;
  final String caption;
  final String? trend;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final c = toneColorsOf(context, AppTone.primary);

    // This was a full-bleed gradient slab with a drop shadow and 48pt white
    // figures — the loudest object on the home screen, for a number that is
    // usually zero before the shop opens. It is now the same flat card as
    // everything around it, which is what the web does with the same figure.
    //
    // The white text is the specific thing that had to go. White forces a
    // dark fill to stay legible, and a dark fill on a light background is
    // what read as heavy. Ink on a pale ground carries the same emphasis
    // without the weight.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Radii.lgAll,
        border: Border.all(color: colors.borderSoft, width: Strokes.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              height: 1.1,
              color: colors.textPrimary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  caption,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              if (trend != null) ...[
                const SizedBox(width: Gap.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: c.background,
                    borderRadius: Radii.mdAll,
                    border: Border.all(
                      color: c.border,
                      width: Strokes.hairline,
                    ),
                  ),
                  child: Text(
                    trend!,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.foreground,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The one thing a screen is asking the shopkeeper to do.
///
/// Now a thin wrapper over [AppButton] rather than a second implementation.
/// It was a gradient fill with a coloured drop shadow and white text; the
/// shadow and the gradient are gone, and the label sits as ink on a solid
/// tone that meets contrast in both themes. Its `loading` flag maps onto
/// AppButton's busy state, which also disables the button — the old one
/// stayed tappable while loading and only removed its own onTap.
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      busy: loading,
      fullWidth: true,
    );
  }
}

/// Quick Action Tile - Fast access to features (Glassmorphic soft)
class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accentColor,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, size: 32, color: accent),
                ),
                const SizedBox(height: 20),
                // Label
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                // Subtitle
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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

/// Enhanced List Item - Display items with soft hover states
class EnhancedListItem extends StatelessWidget {
  const EnhancedListItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.leading,
    this.leadingIcon,
    this.leadingColor,
    this.trailing,
    this.showChevron = true,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? leading;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final Widget? trailing;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = leadingColor ?? theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Leading
                leading ??
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        leadingIcon ?? Icons.circle,
                        size: 26,
                        color: accent,
                      ),
                    ),
                const SizedBox(width: 16),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Trailing
                trailing ??
                    (showChevron
                        ? Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.05,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          )
                        : const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Premium Search Bar - Soft rounded
class PremiumSearchBar extends StatelessWidget {
  const PremiumSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        textCapitalization: TextCapitalization.sentences,
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Icon(
              Icons.search_rounded,
              size: 24,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 22,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  onPressed: () {
                    controller.clear();
                    onClear?.call();
                  },
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
        ),
      ),
    );
  }
}

/// Status Badge
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.showDot = true,
  });

  final String label;
  final Color color;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section Header
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Empty State
class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(icon, size: 48, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 32),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (action != null) ...[const SizedBox(height: 32), action!],
          ],
        ),
      ),
    );
  }
}

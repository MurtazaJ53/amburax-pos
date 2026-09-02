import 'package:flutter/material.dart';

import '../../core/money/money.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../tokens.dart';
import '../tone.dart';

/// An amount of money, rendered once, the same way everywhere.
///
/// Always goes through [formatCurrency] so the region layer picks the symbol
/// and the grouping — a figure must never be assembled with a hardcoded `₹`.
///
/// Digits are tabular so a column of amounts lines up at the decimal. In a
/// khata list where the shopkeeper is scanning for the largest debt, ragged
/// digits are the difference between finding it and reading every row.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.style,
    this.tone,
    this.showFraction = true,
    this.signed = false,
  });

  final Money amount;

  /// Defaults to `titleMedium`. Pass a larger style for a headline figure.
  final TextStyle? style;

  /// Overrides the colour. When null the amount takes the ambient text colour —
  /// which is right for a neutral total, and wrong for a signed movement.
  /// Pass `toneForAmount(amount)` where in and out need to read differently.
  final AppTone? tone;

  /// Drop the paise for a headline figure where they add noise.
  final bool showFraction;

  /// Prefix a `+` on positive amounts. For ledgers where direction matters and
  /// the reader needs the sign, not just the colour — colour alone fails for a
  /// colour-blind shopkeeper and in direct sunlight.
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    final text = formatCurrency(amount.rupees, showFraction: showFraction);
    final withSign = signed && amount.paise > 0 ? '+$text' : text;

    final resolved = (style ?? theme.textTheme.titleMedium)?.copyWith(
      color: tone == null
          ? colors.textPrimary
          : toneColorsOf(context, tone!).foreground,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    return Text(withSign, style: resolved);
  }
}

/// A single figure with its label — today's takings, what is owed, items low.
///
/// Replaces `MobileMetricCard` (20 call sites). The old one took an `accent`
/// colour and an icon; this takes a [tone] and makes the icon optional, because
/// on a dashboard of six tiles the icons were decoration competing with the
/// numbers they sat beside.
class AppMetric extends StatelessWidget {
  const AppMetric({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.tone = AppTone.neutral,
    this.onTap,
  });

  /// What the figure counts. Short.
  final String label;

  /// Pre-formatted. Use a [MoneyText] for money so the region layer applies.
  final Widget value;

  /// Optional context under the figure — "vs ₹4,200 yesterday".
  final String? caption;

  final IconData? icon;

  final AppTone tone;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final c = toneColorsOf(context, tone);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 15, color: c.foreground),
              const SizedBox(width: Gap.xxs + 1),
            ],
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        value,
        if (caption != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            caption!,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Radii.lgAll,
        border: Border.all(color: colors.borderSoft, width: Strokes.hairline),
      ),
      child: Padding(padding: const EdgeInsets.all(Gap.sm + 2), child: content),
    );

    if (onTap == null) return decorated;

    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: Radii.lgAll, child: decorated),
    );
  }
}

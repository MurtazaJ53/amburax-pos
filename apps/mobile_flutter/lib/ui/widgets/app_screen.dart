import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../tokens.dart';

/// The shell every pushed screen sits in.
///
/// Replaces `MobileStandaloneScaffold` (49 call sites), which painted a
/// three-stop gradient behind every page and hand-rolled its own back button
/// inside a bordered pill. Both are gone: the gradient cost a full-screen
/// repaint for an effect nobody could name, and the custom back button did not
/// match the platform gesture it sat beside.
class AppScreen extends StatelessWidget {
  const AppScreen({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.bottomBar,
    this.scrollable = true,
  });

  final String title;

  final Widget child;

  /// App-bar actions. Keep to two — a third is a menu.
  final List<Widget> actions;

  /// Pinned above the system inset. For the primary action on a screen the
  /// shopkeeper is completing, so it stays reachable with the keyboard up.
  final Widget? bottomBar;

  /// Set false when [child] manages its own scrolling (a `ListView`, or a POS
  /// grid that must not be wrapped in a second scroll view).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    final body = scrollable
        ? SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Gap.lg,
              Gap.md,
              Gap.lg,
              Gap.scrollBottom,
            ),
            child: child,
          )
        : child;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(top: false, child: body),
      bottomNavigationBar: bottomBar == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.lg,
                  Gap.xs,
                  Gap.lg,
                  Gap.sm,
                ),
                child: bottomBar,
              ),
            ),
    );
  }
}

/// The block at the top of a screen that says what it is for.
///
/// Replaces `MobileScreenLead` (14 call sites). Flatter than its predecessor:
/// no bordered card, no icon tile, because on a pushed screen the app-bar title
/// already names the page and repeating it in a box wasted the first 90px of
/// every screen.
class AppScreenLead extends StatelessWidget {
  const AppScreenLead({
    super.key,
    required this.subtitle,
    this.tags = const <Widget>[],
  });

  /// One sentence on what this screen is for, in the shopkeeper's words.
  final String subtitle;

  /// Status tags — plan, role, sync state. Wrap rather than overflow.
  final List<Widget> tags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(subtitle, style: theme.textTheme.bodyMedium),
        if (tags.isNotEmpty) ...<Widget>[
          const SizedBox(height: Gap.sm),
          Wrap(spacing: Gap.xs, runSpacing: Gap.xs, children: tags),
        ],
        const SizedBox(height: Gap.md),
      ],
    );
  }
}

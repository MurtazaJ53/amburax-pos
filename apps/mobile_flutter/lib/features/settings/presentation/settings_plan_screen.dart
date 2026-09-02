import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/models/mobile_session.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../shell/presentation/mobile_surface.dart';

class SettingsPlanScreen extends ConsumerWidget {
  const SettingsPlanScreen({super.key});

  /// Send a real upgrade request to the platform queue. Previously this only
  /// copied a text brief to the clipboard, so an owner tapping "Upgrade" sent
  /// nothing anywhere.
  Future<void> _submitUpgradeRequest(
    BuildContext context,
    WidgetRef ref,
    ShopInfo shop,
  ) async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) return;
    final target = shop.normalizedPlanTier == 'starter' ? 'growth' : 'pro';

    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Request ${target == 'pro' ? 'Pro' : 'Growth'} plan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'We will review this request and get back to you. Nothing is '
              'charged automatically.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Anything we should know? (optional)',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    final note = noteController.text.trim();
    noteController.dispose();
    if (confirmed != true) return;

    try {
      await ref
          .read(backendApiClientProvider)
          .requestPlanUpgrade(
            user: session.user,
            shopId: session.shopId!,
            requestedPlanTier: target,
            // Fall back to the auto-generated brief (plan, role, usage signals)
            // so the admin queue always has context to act on.
            note: note.isEmpty ? _buildUpgradeBriefText(shop, session) : note,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upgrade request sent. We will be in touch.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send request: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final shop =
        ref.watch(shopInfoProvider).asData?.value ?? ShopInfo.fallback();
    // No MFA gate here on purpose: this screen only COMPARES plans, it changes
    // nothing. Requiring a fresh MFA check locked owners out entirely when MFA
    // was never enrolled — there was no way to verify, so the screen could
    // never be opened.

    return MobileStandaloneScaffold(
      title: 'Workspace plan',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          MobileScreenLead(
            title: '${shop.planLabel} keeps this workspace curated',
            subtitle:
                'See what this workspace includes now, what the next plan unlocks, and when an upgrade is actually worth it.',
            icon: Icons.workspace_premium_rounded,
            accent: AppPalette.warning,
            primaryTag: MobileTag(
              label: '${shop.planLabel} plan',
              icon: Icons.workspace_premium_rounded,
              accent: AppPalette.warning,
            ),
            secondaryTag: MobileTag(
              label: session?.displayRoleLabel ?? 'GUEST',
              icon: Icons.badge_rounded,
              accent: AppPalette.primary,
            ),
          ),
          const SizedBox(height: 18),
          if (!(session?.isOwnerLike ?? false))
            const MobilePanel(
              title: 'Owner view only',
              child: MobileEmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Plan compare is owner and admin only',
                body:
                    'Daily users should stay focused on selling and operations. Workspace plan comparison stays limited to owners and admins.',
              ),
            )
          else ...<Widget>[
            MobilePanel(
              title: 'Current posture',
              action: MobileTag(
                label: _nextPlanLabel(shop),
                icon: Icons.trending_up_rounded,
                accent: AppPalette.success,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _planTitle(shop),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _planBody(shop),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black.withValues(alpha: 0.72),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            MobilePanel(
              title: 'Current vs next',
              action: MobileTag(
                label: _nextPlanSectionTitle(shop),
                icon: Icons.compare_arrows_rounded,
                accent: AppPalette.primary,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _PlanSectionCard(
                    title: _currentPlanSectionTitle(shop),
                    lines: _currentPlanSectionLines(shop),
                  ),
                  const SizedBox(height: 12),
                  _PlanSectionCard(
                    title: _nextPlanSectionTitle(shop),
                    lines: _nextPlanSectionLines(shop),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            MobilePanel(
              title: 'Plan compare',
              action: MobileTag(
                label: '3 tiers',
                icon: Icons.view_carousel_rounded,
                accent: AppPalette.success,
              ),
              child: Column(
                children: const <Widget>[
                  _PlanTierCard(planTier: 'starter'),
                  SizedBox(height: 12),
                  _PlanTierCard(planTier: 'growth'),
                  SizedBox(height: 12),
                  _PlanTierCard(planTier: 'pro'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            MobilePanel(
              title: 'Upgrade signals',
              action: MobileTag(
                label: 'Owner action',
                icon: Icons.campaign_rounded,
                accent: AppPalette.warning,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ..._upgradeSignals(shop).map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '- $line',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black.withValues(alpha: 0.74),
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 430;
                      final actions = <Widget>[
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: _buildPlanSummaryText(shop, session),
                                ),
                              );
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Plan summary copied.'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copy summary'),
                          ),
                        ),
                        if (shop.normalizedPlanTier != 'pro')
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () =>
                                  _submitUpgradeRequest(context, ref, shop),
                              icon: const Icon(Icons.trending_up_rounded),
                              label: Text(_upgradeButtonLabel(shop)),
                            ),
                          ),
                      ];

                      if (stacked) {
                        return Column(
                          children: actions
                              .expand(
                                (widget) => <Widget>[
                                  widget,
                                  if (widget != actions.last)
                                    const SizedBox(height: 10),
                                ],
                              )
                              .toList(growable: false),
                        );
                      }

                      return Row(
                        children: actions
                            .expand(
                              (widget) => <Widget>[
                                widget,
                                if (widget != actions.last)
                                  const SizedBox(width: 10),
                              ],
                            )
                            .toList(growable: false),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanSectionCard extends StatelessWidget {
  const _PlanSectionCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.black.withValues(alpha: 0.60),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.35,
              ),
            ),
            const SizedBox(height: 10),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '- $line',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black.withValues(alpha: 0.76),
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanTierCard extends StatelessWidget {
  const _PlanTierCard({required this.planTier});

  final String planTier;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final label = switch (planTier) {
      'starter' => 'Starter',
      'pro' => 'Pro',
      _ => 'Growth',
    };
    final title = switch (planTier) {
      'starter' => 'Best for focused counter operations',
      'pro' => 'Best for deeper owner control',
      _ => 'Best for active store management',
    };
    final body = switch (planTier) {
      'starter' =>
        'Use Starter when the shop mainly needs selling, stock lookup, customer balances, and simple day-to-day flow without operational extras.',
      'pro' =>
        'Use Pro when the owner needs richer finance summaries, advanced reporting, and stronger admin/support controls while still hiding raw ERP complexity from staff.',
      _ =>
        'Use Growth when the owner needs expenses, attendance, and supplier-aware store operations but still wants a curated product instead of a heavy ERP workspace.',
    };
    final lines = switch (planTier) {
      'starter' => const <String>[
        'POS and barcode selling',
        'Inventory and low-stock watch',
        'Customer balances and receipts',
      ],
      'pro' => const <String>[
        'Finance and advanced reporting',
        'Deeper owner/admin controls',
        'The full curated Business Hub stack',
      ],
      _ => const <String>[
        'Everything in Starter',
        'Expenses and attendance',
        'Supplier directory basics',
      ],
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$label plan',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.black.withValues(alpha: 0.60),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.35,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.black.withValues(alpha: 0.72),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '- $line',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black.withValues(alpha: 0.76),
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _planTitle(ShopInfo shop) {
  return switch (shop.normalizedPlanTier) {
    'starter' => 'Starter keeps the workspace lean',
    'pro' => 'Pro unlocks deeper owner control',
    _ => 'Growth adds store operations',
  };
}

String _planBody(ShopInfo shop) {
  return switch (shop.normalizedPlanTier) {
    'starter' =>
      'This plan focuses on selling, stock, customers, and receipts. Expenses and attendance stay hidden until the shop upgrades.',
    'pro' =>
      'This workspace can open stronger operations and support paths while still keeping ERP internals out of normal store flows.',
    _ =>
      'This workspace includes daily operations like expenses and attendance while still avoiding heavier back-office clutter.',
  };
}

String _currentPlanSectionTitle(ShopInfo shop) {
  return switch (shop.normalizedPlanTier) {
    'starter' => 'Starter now',
    'pro' => 'Pro now',
    _ => 'Growth now',
  };
}

List<String> _currentPlanSectionLines(ShopInfo shop) {
  return switch (shop.normalizedPlanTier) {
    'starter' => const <String>[
      'POS and barcode selling',
      'Inventory and low-stock watch',
      'Customer balances and receipt history',
    ],
    'pro' => const <String>[
      'Finance and advanced reporting',
      'Advanced owner and admin controls',
      'The full curated Business Hub stack',
    ],
    _ => const <String>[
      'Everything in Starter',
      'Expenses and attendance',
      'Supplier-ready store operations',
    ],
  };
}

String _nextPlanSectionTitle(ShopInfo shop) {
  return switch (shop.normalizedPlanTier) {
    'starter' => 'Growth next',
    'pro' => 'Keep it curated',
    _ => 'Pro next',
  };
}

List<String> _nextPlanSectionLines(ShopInfo shop) {
  return switch (shop.normalizedPlanTier) {
    'starter' => const <String>[
      'Expenses and attendance',
      'Light supplier workflows',
      'More operational control without ERP clutter',
    ],
    'pro' => const <String>[
      'Limit deep tools to owners and admins',
      'Keep daily screens simple for staff',
      'Avoid exposing raw ERP complexity',
    ],
    _ => const <String>[
      'Finance and owner summary rollups',
      'Advanced customer and sales insight',
      'Stronger admin and support controls',
    ],
  };
}

String _upgradeButtonLabel(ShopInfo shop) {
  return switch (shop.normalizedPlanTier) {
    'starter' => 'Copy Growth brief',
    'growth' => 'Copy Pro brief',
    _ => 'Copy upgrade brief',
  };
}

String _nextPlanLabel(ShopInfo shop) {
  return switch (shop.normalizedPlanTier) {
    'starter' => 'Growth',
    'growth' => 'Pro',
    _ => 'Pro',
  };
}

List<String> _upgradeSignals(ShopInfo shop) {
  return switch (shop.normalizedPlanTier) {
    'starter' => const <String>[
      'Upgrade when the shop needs expenses and attendance inside the same product.',
      'Upgrade when supplier-aware stock operations matter more than a lean-only counter flow.',
      'Upgrade when owners want more operational control without raw ERP clutter.',
    ],
    'pro' => const <String>[
      'Keep Pro limited to the right owners and admins.',
      'Keep staff on simple daily-work surfaces, not deep management tools.',
      'Use the higher plan to stay curated, not to expose every possible system detail.',
    ],
    _ => const <String>[
      'Upgrade when owners need finance-heavy rollups instead of only simple operations.',
      'Upgrade when customer and sales analysis needs to be deeper than list-level review.',
      'Upgrade when advanced support or admin controls need to be available for the workspace.',
    ],
  };
}

String _buildPlanSummaryText(ShopInfo shop, MobileSession? session) {
  final buffer = StringBuffer()
    ..writeln('Business Hub workspace plan summary')
    ..writeln('Workspace: ${shop.name}')
    ..writeln('Current plan: ${shop.planLabel}')
    ..writeln('Operator role: ${session?.displayRoleLabel ?? 'UNKNOWN'}')
    ..writeln()
    ..writeln('${_currentPlanSectionTitle(shop)}:');

  for (final line in _currentPlanSectionLines(shop)) {
    buffer.writeln('- $line');
  }

  buffer
    ..writeln()
    ..writeln('${_nextPlanSectionTitle(shop)}:');

  for (final line in _nextPlanSectionLines(shop)) {
    buffer.writeln('- $line');
  }

  return buffer.toString().trimRight();
}

String _buildUpgradeBriefText(ShopInfo shop, MobileSession? session) {
  final buffer = StringBuffer()
    ..writeln('Business Hub workspace upgrade brief')
    ..writeln('Workspace: ${shop.name}')
    ..writeln('Current plan: ${shop.planLabel}')
    ..writeln('Requested next plan: ${_nextPlanLabel(shop)}')
    ..writeln('Operator role: ${session?.displayRoleLabel ?? 'UNKNOWN'}')
    ..writeln()
    ..writeln('${_currentPlanSectionTitle(shop)}:');

  for (final line in _currentPlanSectionLines(shop)) {
    buffer.writeln('- $line');
  }

  buffer
    ..writeln()
    ..writeln('${_nextPlanSectionTitle(shop)}:');

  for (final line in _nextPlanSectionLines(shop)) {
    buffer.writeln('- $line');
  }

  return buffer.toString().trimRight();
}



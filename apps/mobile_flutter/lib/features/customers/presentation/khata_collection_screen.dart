import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/database/mobile_repository.dart';
import '../../../core/khata/khata_reminder.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/runtime/mobile_runtime_config.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/whatsapp.dart';
import '../../../core/utils/formatters.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

final khataDebtorsProvider = StreamProvider.autoDispose<List<KhataDebtor>>(
  (ref) => ref.watch(customerRepositoryProvider).watchDebtors(),
);

/// Udhaar collection: who owes what, who has already been chased, and a guided
/// run through everyone still outstanding.
///
/// WhatsApp has no bulk-send from a normal account, so "Remind all" is a queue
/// the owner taps through rather than a fire-and-forget blast. Each send is
/// recorded, so the list survives interruptions and nobody gets chased twice.
class KhataCollectionScreen extends ConsumerStatefulWidget {
  const KhataCollectionScreen({super.key});

  @override
  ConsumerState<KhataCollectionScreen> createState() =>
      _KhataCollectionScreenState();
}

class _KhataCollectionScreenState extends ConsumerState<KhataCollectionScreen> {
  bool _onlyOverdue = true;
  bool _running = false;

  List<KhataDebtor> _visible(List<KhataDebtor> all) {
    final list = all.where((d) => d.hasPhone).toList();
    if (!_onlyOverdue) return list;
    return list.where((d) => d.isOverdue).toList();
  }

  /// Mint the customer's private statement link, or return empty on failure.
  ///
  /// A failure here must not stop the chase: sending a reminder without the
  /// statement is far better than not chasing the money at all. Same call the
  /// UPI link makes when a shop's VPA is misconfigured.
  Future<String> _statementUrl(KhataDebtor debtor) async {
    // Check the origin BEFORE calling the server. Minting a link we cannot
    // build a URL for would retire the customer's previous link and hand back
    // a token nobody can open — worse than doing nothing.
    final origin = MobileRuntimeConfig.webAppBaseUrl.trim();
    if (origin.isEmpty) return '';

    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) return '';
    try {
      final result = await ref
          .read(backendApiClientProvider)
          .createCustomerStatementLink(
            user: session.user,
            shopId: session.shopId!,
            customerId: debtor.id,
          );
      final path = (result['path'] ?? '').toString();
      if (path.isEmpty) return '';
      return '${origin.replaceAll(RegExp(r"/$"), "")}$path';
    } catch (_) {
      return '';
    }
  }

  Future<bool> _remind(KhataDebtor debtor) async {
    final shop = ref.read(shopInfoProvider).asData?.value;
    final statementUrl = await _statementUrl(debtor);
    final message = buildKhataReminder(
      shopName: shop?.name ?? 'our shop',
      customerName: debtor.name,
      balance: debtor.balance,
      statementUrl: statementUrl,
      // The shop's SAVED UPI id, so the pay link actually appears. This used
      // to read a compile-time String.fromEnvironment, which is empty in every
      // normal build — the pay link silently never rendered.
      upiVpa: shop?.upiVpa ?? '',
    );
    final opened = await openWhatsApp(phone: debtor.phone, message: message);
    if (opened) {
      // Via the coordinator so the reminder is shared with the web and every
      // other device, not just this phone.
      await ref
          .read(mobileSyncCoordinatorProvider)
          .markCustomerReminded(debtor.id);
    }
    return opened;
  }

  Future<void> _remindOne(KhataDebtor debtor) async {
    final ok = await _remind(debtor);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open WhatsApp for ${debtor.name}.')),
      );
    }
  }

  /// Walk the list one customer at a time. WhatsApp opens, the owner hits send,
  /// comes back, and we offer the next one — with progress so a long list
  /// doesn't feel endless.
  Future<void> _remindAll(List<KhataDebtor> debtors) async {
    final queue = debtors.where((d) => !d.remindedToday).toList();
    if (queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Everyone here has been reminded today.')),
      );
      return;
    }

    final start = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remind ${queue.length} customers'),
        content: Text(
          'WhatsApp will open for each customer with the message ready. '
          'Send it, then come back here and we will move to the next one.\n\n'
          'Total outstanding: '
          '${formatCurrency(queue.fold<double>(0, (s, d) => s + d.balance))}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (start != true) return;

    setState(() => _running = true);
    for (var i = 0; i < queue.length; i++) {
      if (!mounted) break;
      final debtor = queue[i];
      final ok = await _remind(debtor);
      if (!mounted) break;

      if (i == queue.length - 1) break;
      final next = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${i + 1} of ${queue.length} done'),
          content: Text(
            ok
                ? 'Sent to ${debtor.name}. Continue with ${queue[i + 1].name}?'
                : 'Could not open WhatsApp for ${debtor.name}. Skip and '
                      'continue with ${queue[i + 1].name}?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Stop'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Next'),
            ),
          ],
        ),
      );
      if (next != true) break;
    }
    if (mounted) {
      setState(() => _running = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reminder run finished.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final async = ref.watch(khataDebtorsProvider);
    final all = async.asData?.value ?? const <KhataDebtor>[];
    final visible = _visible(all);
    final totalDue = all.fold<double>(0, (sum, d) => sum + d.balance);
    final noPhone = all.where((d) => !d.hasPhone).length;

    return MobileStandaloneScaffold(
      title: L.of(context).collectTitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          _SummaryCard(
            totalDue: totalDue,
            customerCount: all.length,
            overdueCount: all.where((d) => d.isOverdue && d.hasPhone).length,
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running || visible.isEmpty
                      ? null
                      : () => _remindAll(visible),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  icon: const Icon(Icons.campaign_rounded),
                  label: Text(
                    _running ? 'Sending...' : 'Remind all (${visible.length})',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _onlyOverdue,
            onChanged: (v) => setState(() => _onlyOverdue = v),
            title: Text(L.of(context).collectOnlyOverdue),
            subtitle: const Text('Not reminded in the last 7 days'),
          ),
          if (noPhone > 0) ...<Widget>[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppPalette.warning.withValues(alpha: 0.32),
                ),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.phone_disabled_rounded,
                    size: 18,
                    color: AppPalette.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$noPhone customer(s) owe money but have no mobile '
                      'number, so they cannot be reminded.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (async.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (visible.isEmpty)
            AppPanel(
              title: _onlyOverdue ? 'Nothing overdue' : 'No dues',
              child: AppEmptyState(
                icon: Icons.check_circle_rounded,
                title: _onlyOverdue
                    ? 'Everyone has been reminded recently'
                    : 'No customer owes you money',
                body: _onlyOverdue
                    ? 'Turn off "Only overdue" to see every customer with a '
                          'balance.'
                    : 'Credit sales will appear here automatically.',
              ),
            )
          else
            for (final debtor in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DebtorTile(
                  debtor: debtor,
                  busy: _running,
                  onRemind: () => _remindOne(debtor),
                ),
              ),
          const SizedBox(height: 12),
          Text(
            'The message includes a UPI pay link for the exact amount, so the '
            'customer can clear their balance in one tap.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalDue,
    required this.customerCount,
    required this.overdueCount,
  });

  final double totalDue;
  final int customerCount;
  final int overdueCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.warning.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'TOTAL OUTSTANDING',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: AppColors.of(context).textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatCurrency(totalDue),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppPalette.warning,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$customerCount customer(s) owe you  ·  $overdueCount overdue',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DebtorTile extends StatelessWidget {
  const _DebtorTile({
    required this.debtor,
    required this.busy,
    required this.onRemind,
  });

  final KhataDebtor debtor;
  final bool busy;
  final VoidCallback onRemind;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  debtor.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatCurrency(debtor.balance),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppPalette.warning,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: <Widget>[
                    Icon(
                      debtor.remindedToday
                          ? Icons.check_circle_rounded
                          : Icons.schedule_rounded,
                      size: 13,
                      color: debtor.remindedToday
                          ? AppPalette.success
                          : colors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      debtor.reminderStatus,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: debtor.remindedToday
                            ? AppPalette.success
                            : colors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : onRemind,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppPalette.success,
              side: const BorderSide(color: AppPalette.success),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: Text(debtor.remindedToday ? 'Again' : 'Remind'),
          ),
        ],
      ),
    );
  }
}

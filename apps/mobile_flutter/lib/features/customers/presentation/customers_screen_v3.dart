import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/database/mobile_repository.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/runtime/mobile_runtime_config.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/khata/khata_reminder.dart';
import '../../../core/util/whatsapp.dart';
import 'khata_collection_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/premium_components.dart';

/// Redesigned Customers Screen v3.0
/// Simple, Clean, Premium, Professional
class CustomersScreenV3 extends ConsumerStatefulWidget {
  const CustomersScreenV3({super.key});

  @override
  ConsumerState<CustomersScreenV3> createState() => _CustomersScreenV3State();
}

class _CustomersScreenV3State extends ConsumerState<CustomersScreenV3> {
  final TextEditingController _searchController = TextEditingController();

  String _search = '';
  bool _showWithDuesOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);
    final customers =
        customersAsync.asData?.value ?? const <BackendCustomerSummary>[];

    // When searching, query the SERVER so you can find any customer (not just
    // the recent window held locally). Otherwise show the local list.
    final query = _search.trim();
    final searchingServer = query.length >= 2;
    final serverResults = searchingServer
        ? (ref.watch(customerSearchProvider(query)).asData?.value ??
              const <BackendCustomerSummary>[])
        : null;
    final baseList = serverResults ?? customers;

    final filteredCustomers = baseList.where((customer) {
      // Server search already matched name/phone; only local-filter when not
      // searching the server.
      if (!searchingServer &&
          _search.isNotEmpty &&
          !customer.name.toLowerCase().contains(_search.toLowerCase())) {
        return false;
      }
      if (_showWithDuesOnly && customer.balance <= 0) {
        return false;
      }
      return true;
    }).toList();

    // Calculate metrics
    final totalCustomers = customers.length;
    final totalDues = customers.fold<double>(
      0,
      (sum, c) => sum + (c.balance > 0 ? c.balance : 0),
    );
    final customersWithDues = customers.where((c) => c.balance > 0).length;

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: SafeArea(
        // Search, metrics and the dues filter now scroll away with the list so
        // more customer rows stay visible while scrolling.
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(child: _buildHeader(context)),
            // Udhaar collection is the daily money job, so it gets a first-class
            // entry point here rather than being buried in Settings.
            SliverToBoxAdapter(child: _buildCollectBanner(context)),
            SliverToBoxAdapter(
              child: _buildMetrics(
                totalCustomers: totalCustomers,
                totalDues: totalDues,
                customersWithDues: customersWithDues,
              ),
            ),
            SliverToBoxAdapter(child: _buildFilters()),
            if (customersAsync.isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filteredCustomers.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyStateWidget(
                  icon: Icons.groups_rounded,
                  title: 'No customers found',
                  message: _search.isEmpty
                      ? 'Start adding customers to track sales'
                      : 'Try a different search term',
                ),
              )
            else
              SliverList.builder(
                itemCount: filteredCustomers.length,
                itemBuilder: (context, index) =>
                    _buildCustomerRow(filteredCustomers[index]),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
      // Add customer FAB
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCustomerSheet(context),
        backgroundColor: AppPalette.primary,
        icon: const Icon(Icons.person_add_rounded, size: 20),
        label: const Text(
          'Add',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      // End-aligned: a centre-floating FAB sat on top of the customer rows.
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  /// Total outstanding + a one-tap route into the collection run.
  Widget _buildCollectBanner(BuildContext context) {
    final debtors =
        ref.watch(khataDebtorsProvider).asData?.value ?? const <KhataDebtor>[];
    if (debtors.isEmpty) return const SizedBox.shrink();
    final total = debtors.fold<double>(0, (sum, d) => sum + d.balance);
    final overdue = debtors.where((d) => d.isOverdue && d.hasPhone).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: AppPalette.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/settings/collect'),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppPalette.warning.withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppPalette.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${formatCurrency(total)} udhaar pending',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        overdue > 0
                            ? '$overdue customer(s) need a reminder'
                            : '${debtors.length} customer(s) owe you',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.of(context).textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    // No title/back here — the surrounding shell already shows "Customers" and a
    // back button; a second one wasted a whole row and read as a nested screen.
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        border: Border(
          bottom: BorderSide(color: AppColors.of(context).borderSoft, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PremiumSearchBar(
            controller: _searchController,
            hintText: L.of(context).custSearchHint,
            onChanged: (value) {
              setState(() {
                _search = value;
              });
            },
            onClear: () {
              setState(() {
                _search = '';
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics({
    required int totalCustomers,
    required double totalDues,
    required int customersWithDues,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        border: Border(
          bottom: BorderSide(color: AppColors.of(context).borderSoft, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildMetricBox(
              label: 'Total',
              value: '$totalCustomers',
              icon: Icons.groups_rounded,
              color: AppPalette.customer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildMetricBox(
              label: 'Dues',
              value: formatCurrency(totalDues),
              icon: Icons.account_balance_wallet_rounded,
              color: totalDues > 0 ? AppPalette.warning : AppPalette.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBox({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    // Compact single-line stat: icon + label on one row, value right under it.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        border: Border(
          bottom: BorderSide(color: AppColors.of(context).borderSoft, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Show customers with dues only',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.of(context).textPrimary,
              ),
            ),
          ),
          Switch(
            value: _showWithDuesOnly,
            onChanged: (value) {
              setState(() {
                _showWithDuesOnly = value;
              });
            },
            activeThumbColor: AppPalette.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerRow(BackendCustomerSummary customer) {
    final hasDues = customer.balance > 0;
    return EnhancedListItem(
      title: customer.name,
      subtitle: (customer.phone ?? '').isEmpty
          ? (hasDues ? 'Due: ${formatCurrency(customer.balance)}' : 'No dues')
          : '${customer.phone}${hasDues ? ' • Due: ${formatCurrency(customer.balance)}' : ''}'
                '${customer.loyaltyPoints > 0 ? ' • ${customer.loyaltyPoints} pts' : ''}',
      leadingIcon: Icons.person_rounded,
      leadingColor: hasDues ? AppPalette.warning : AppPalette.customer,
      trailing: hasDues
          ? StatusBadge(
              label: formatCurrency(customer.balance),
              color: AppPalette.warning,
              showDot: false,
            )
          : null,
      onTap: () => _showCustomerDetails(context, customer),
    );
  }

  void _showCustomerDetails(
    BuildContext context,
    BackendCustomerSummary customer,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.of(context).background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.of(context).border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Customer details
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppPalette.customer.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    size: 32,
                    color: AppPalette.customer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.of(context).textPrimary,
                        ),
                      ),
                      if ((customer.phone ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          customer.phone!,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.of(context).textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Balance
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: customer.balance > 0
                    ? AppPalette.warning.withValues(alpha: 0.1)
                    : AppPalette.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: customer.balance > 0
                      ? AppPalette.warning.withValues(alpha: 0.2)
                      : AppPalette.success.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BALANCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: customer.balance > 0
                          ? AppPalette.warning
                          : AppPalette.success,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatCurrency(customer.balance),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: customer.balance > 0
                          ? AppPalette.warning
                          : AppPalette.success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                if (customer.balance > 0) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _recordPayment(context, customer);
                      },
                      icon: const Icon(Icons.payments_rounded),
                      label: const Text('Record payment'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddCustomerSheet(context, existing: customer);
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showLedger(context, customer);
                    },
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('Khata'),
                  ),
                ),
                if ((customer.phone ?? '').trim().isNotEmpty)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _messageOnWhatsApp(context, customer),
                      icon: const Icon(Icons.chat_rounded),
                      label: const Text('WhatsApp'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF25D366),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _messageOnWhatsApp(
    BuildContext context,
    BackendCustomerSummary customer,
  ) async {
    final shop = ref.read(shopInfoProvider).asData?.value;
    final message = buildKhataReminder(
      shopName: shop?.name ?? 'our shop',
      customerName: customer.name,
      balance: customer.balance,
      // Use the UPI id saved in Business settings. This read a compile-time
      // String.fromEnvironment, which is empty in every normal build, so the
      // pay link silently never appeared in the reminder.
      upiVpa: shop?.upiVpa ?? '',
    );
    final ok = await openWhatsApp(
      phone: customer.phone ?? '',
      message: message,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp for this number.'),
        ),
      );
    }
  }

  /// Unified credit + payment timeline with a running balance.
  void _showLedger(BuildContext context, BackendCustomerSummary customer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Khata · ${customer.name}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Current due ${formatCurrency(customer.balance)}',
                  style: TextStyle(
                    color: customer.balance > 0
                        ? AppPalette.error
                        : AppPalette.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 360,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final entries =
                          ref
                              .watch(customerLedgerProvider(customer.id))
                              .asData
                              ?.value ??
                          const <CustomerLedgerRecord>[];
                      if (entries.isEmpty) {
                        // Distinguish "nothing has happened" from "there is a
                        // due but no record of it" - the second is a real gap
                        // the owner should understand, not a blank screen.
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              customer.balance != 0
                                  ? 'This balance was carried over (imported or '
                                        'set directly), so there are no entries '
                                        'behind it. New credit sales and payments '
                                        'will be listed here.'
                                  : 'No credit or payments yet.\nCredit sales and '
                                        'payments will appear here.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final e = entries[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              e.isPayment
                                  ? Icons.south_west_rounded
                                  : e.isOpening
                                  ? Icons.flag_rounded
                                  : Icons.north_east_rounded,
                              color: e.isPayment
                                  ? AppPalette.success
                                  : e.isOpening
                                  ? AppPalette.info
                                  : AppPalette.error,
                            ),
                            title: Text(
                              '${e.typeLabel} '
                              '${formatCurrency(e.amount.abs())}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${e.createdAt.toIso8601String().split('T').first}'
                              '${e.note.isNotEmpty ? ' · ${e.note}' : ''}',
                            ),
                            trailing: Text(
                              'Due ${formatCurrency(e.balanceAfter)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddCustomerSheet(
    BuildContext context, {
    BackendCustomerSummary? existing,
  }) {
    final isEdit = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final phoneController = TextEditingController(text: existing?.phone ?? '');
    final emailController = TextEditingController(text: existing?.email ?? '');
    final notesController = TextEditingController(text: existing?.notes ?? '');
    final balanceController = TextEditingController();
    var isSaving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> save() async {
            if (isSaving) return;
            final name = nameController.text.trim();
            final phone = phoneController.text.trim();
            // Name + mobile are required so a customer is always identifiable
            // and reachable (dues recovery, WhatsApp, matching on next sale).
            if (name.isEmpty || phone.length < 7) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                const SnackBar(
                  content: Text('Enter a name and a valid mobile number.'),
                ),
              );
              return;
            }
            setSheetState(() => isSaving = true);
            try {
              final now = DateTime.now();
              final email = emailController.text.trim();
              final notes = notesController.text.trim();
              final opening =
                  double.tryParse(balanceController.text.trim()) ?? 0;
              final session = ref.read(mobileSessionProvider).asData?.value;
              final api = ref.read(backendApiClientProvider);
              final repo = ref.read(customerRepositoryProvider);

              // Push to the server so the customer actually syncs. Falls back to
              // a local-only record when offline / the backend is unreachable,
              // so the offline-first flow still works and the outbox-style pull
              // reconciles later.
              BackendCustomerSummary? synced;
              var offline = false;
              final existingIsRemote =
                  isEdit && !(existing.id).startsWith('local-');
              if (session != null &&
                  session.hasShop &&
                  MobileRuntimeConfig.backendSyncEnabled) {
                try {
                  if (existingIsRemote) {
                    synced = await api.updateCustomer(
                      user: session.user,
                      shopId: session.shopId!,
                      customerId: existing.id,
                      name: name,
                      phone: phone,
                      email: email,
                      notes: notes,
                    );
                  } else {
                    synced = await api.createCustomer(
                      user: session.user,
                      shopId: session.shopId!,
                      name: name,
                      phone: phone,
                      email: email,
                      notes: notes,
                      openingBalance: isEdit ? existing.balance : opening,
                    );
                  }
                } catch (_) {
                  offline = true;
                }
              } else {
                offline = true;
              }

              final id =
                  synced?.id ??
                  existing?.id ??
                  'local-cust-${now.microsecondsSinceEpoch}';
              await repo.mergeRemoteCustomerDocument(id, <String, dynamic>{
                'name': name,
                'phone': phone,
                'email': email,
                'notes': notes,
                'status': 'active',
                'balance':
                    synced?.balance ?? (isEdit ? existing.balance : opening),
                'total_spent':
                    synced?.totalSpent ?? (isEdit ? existing.totalSpent : 0),
                'tombstone': false,
                'updatedAt': now.toIso8601String(),
              }, updatedAt: now.millisecondsSinceEpoch);
              // If a local-only customer was just promoted to a real server
              // record, tombstone the stale local row so it isn't duplicated.
              if (synced != null && isEdit && !existingIsRemote) {
                await repo
                    .mergeRemoteCustomerDocument(existing.id, <String, dynamic>{
                      'tombstone': true,
                      'status': 'archived',
                      'updatedAt': now.toIso8601String(),
                    }, updatedAt: now.millisecondsSinceEpoch);
              }
              ref.invalidate(customersProvider);
              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    offline
                        ? '$name saved on this device — will sync when online.'
                        : '$name ${isEdit ? 'updated' : 'added'} and synced.',
                  ),
                ),
              );
            } catch (error) {
              if (!sheetContext.mounted) return;
              setSheetState(() => isSaving = false);
              ScaffoldMessenger.of(
                sheetContext,
              ).showSnackBar(SnackBar(content: Text('Save failed: $error')));
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.of(sheetContext).background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.of(sheetContext).border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        isEdit ? 'Edit Customer' : 'Add New Customer',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email (optional)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                        ),
                      ),
                      if (!isEdit) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: balanceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Opening due (optional)',
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      PrimaryActionButton(
                        label: isSaving
                            ? 'Saving...'
                            : (isEdit ? 'Save Changes' : 'Create Customer'),
                        icon: isEdit
                            ? Icons.check_rounded
                            : Icons.person_add_rounded,
                        onPressed: isSaving ? null : save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      nameController.dispose();
      phoneController.dispose();
      emailController.dispose();
      notesController.dispose();
      balanceController.dispose();
    });
  }

  void _recordPayment(BuildContext context, BackendCustomerSummary customer) {
    final amountController = TextEditingController();
    var isSaving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> save() async {
            final amount = double.tryParse(amountController.text.trim()) ?? 0;
            if (amount <= 0 || isSaving) return;
            setSheetState(() => isSaving = true);
            try {
              final newBalance = await ref
                  .read(customerRepositoryProvider)
                  .recordPayment(
                    customerId: customer.id,
                    amount: amount,
                    actorName: ref
                        .read(mobileSessionProvider)
                        .asData
                        ?.value
                        ?.user
                        .displayName,
                  );
              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Payment recorded. New due ${formatCurrency(newBalance)}.',
                  ),
                ),
              );
            } catch (error) {
              if (!sheetContext.mounted) return;
              setSheetState(() => isSaving = false);
              ScaffoldMessenger.of(
                sheetContext,
              ).showSnackBar(SnackBar(content: Text('Failed: $error')));
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.of(sheetContext).background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.of(sheetContext).border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Record payment',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${customer.name} · due ${formatCurrency(customer.balance)}',
                      style: TextStyle(
                        color: AppColors.of(sheetContext).textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: amountController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount received',
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryActionButton(
                      label: isSaving ? 'Saving...' : 'Record payment',
                      icon: Icons.payments_rounded,
                      onPressed: isSaving ? null : save,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() => amountController.dispose());
  }
}

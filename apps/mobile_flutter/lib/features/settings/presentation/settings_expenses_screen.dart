import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/mobile_models.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/utils/formatters.dart';
import '../../shell/presentation/mobile_surface.dart';

class SettingsExpensesScreen extends ConsumerStatefulWidget {
  const SettingsExpensesScreen({super.key});

  @override
  ConsumerState<SettingsExpensesScreen> createState() =>
      _SettingsExpensesScreenState();
}

class _SettingsExpensesScreenState
    extends ConsumerState<SettingsExpensesScreen> {
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  Future<void> _refreshExpenses() async {
    ref.invalidate(expenseSummaryProvider);
    ref.invalidate(expensesProvider);
    await Future.wait<void>(<Future<void>>[
      ref.read(expenseSummaryProvider.future).then((_) {}),
      ref.read(expensesProvider.future).then((_) {}),
    ]);
  }

  Future<bool> _createExpense({
    required String category,
    required double amount,
    required DateTime expenseDate,
    String description = '',
    String paymentMethod = 'CASH',
    String paymentReference = '',
  }) async {
    setState(() {
      _busy = true;
      _message = null;
      _messageIsError = false;
    });
    try {
      await ref
          .read(mobileSyncCoordinatorProvider)
          .recordExpense(
            category: category,
            amount: amount,
            expenseDate: expenseDate,
            description: description,
            paymentMethod: paymentMethod,
            paymentReference: paymentReference,
            actorName: ref
                .read(mobileSessionProvider)
                .asData
                ?.value
                ?.user
                .displayName,
          );
      if (!mounted) {
        return true;
      }
      setState(() {
        _messageIsError = false;
        _message = 'Expense saved.';
      });
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _messageIsError = true;
        _message = error.toString();
      });
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openAddExpenseSheet(BuildContext context) async {
    final colors = AppColors.of(context);
    final categoryController = TextEditingController();
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    final paymentReferenceController = TextEditingController();
    var selectedPaymentMethod = 'CASH';
    var saving = false;
    String? errorText;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.background,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  24 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    MobileSheetHeader(
                      eyebrow: 'Store expenses',
                      title: L.of(context).expAdd,
                      subtitle:
                          'Capture practical store spending from the phone without opening a heavy finance desk.',
                      icon: Icons.payments_rounded,
                    ),
                    const SizedBox(height: 16),
                    MobileSheetSection(
                      title: L.of(context).expDetails,
                      child: Column(
                        children: <Widget>[
                          TextField(
      textCapitalization: TextCapitalization.sentences,
                            controller: categoryController,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              hintText: 'Packaging, Transport, Internet',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                              hintText: '240.00',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: selectedPaymentMethod,
                            items: const <DropdownMenuItem<String>>[
                              DropdownMenuItem(
                                value: 'CASH',
                                child: Text('Cash'),
                              ),
                              DropdownMenuItem(
                                value: 'UPI',
                                child: Text('UPI'),
                              ),
                              DropdownMenuItem(
                                value: 'BANK',
                                child: Text('Bank'),
                              ),
                              DropdownMenuItem(
                                value: 'CARD',
                                child: Text('Card'),
                              ),
                              DropdownMenuItem(
                                value: 'OTHER',
                                child: Text('Other'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                selectedPaymentMethod = value;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Payment method',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
      textCapitalization: TextCapitalization.sentences,
                            controller: paymentReferenceController,
                            decoration: const InputDecoration(
                              labelText: 'Reference',
                              hintText: 'UPI ref, cheque, invoice, etc.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
      textCapitalization: TextCapitalization.sentences,
                            controller: descriptionController,
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              hintText: 'What was this store expense for?',
                            ),
                          ),
                          if (errorText != null) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              errorText!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AppPalette.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final category = categoryController.text
                                          .trim();
                                      final amount = double.tryParse(
                                        amountController.text.trim(),
                                      );
                                      if (category.isEmpty) {
                                        setState(() {
                                          errorText = 'Category is required.';
                                        });
                                        return;
                                      }
                                      if (amount == null || amount <= 0) {
                                        setState(() {
                                          errorText =
                                              'Enter a valid expense amount.';
                                        });
                                        return;
                                      }
                                      setState(() {
                                        saving = true;
                                        errorText = null;
                                      });
                                      final success = await _createExpense(
                                        category: category,
                                        amount: amount,
                                        expenseDate: DateTime.now(),
                                        description: descriptionController.text
                                            .trim(),
                                        paymentMethod: selectedPaymentMethod,
                                        paymentReference:
                                            paymentReferenceController.text
                                                .trim(),
                                      );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      if (success) {
                                        Navigator.of(context).pop();
                                      } else {
                                        setState(() {
                                          saving = false;
                                          errorText = _message;
                                        });
                                      }
                                    },
                              icon: saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle_rounded),
                              label: Text(
                                saving ? 'Saving expense' : 'Save expense',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    categoryController.dispose();
    amountController.dispose();
    descriptionController.dispose();
    paymentReferenceController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final shop =
        ref.watch(shopInfoProvider).asData?.value ?? ShopInfo.fallback();
    final summaryAsync = ref.watch(expenseSummaryProvider);
    final summary = summaryAsync.asData?.value;
    final expensesAsync = ref.watch(expensesProvider);
    final expenses = expensesAsync.asData?.value ?? const <ExpenseRecord>[];

    if (session == null) {
      return MobileStandaloneScaffold(
        title: L.of(context).settingsExpenses,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            MobilePanel(
              title: 'Loading expenses',
              child: MobileEmptyState(
                icon: Icons.sync_rounded,
                title: 'Checking workspace access',
                body:
                    'Business Hub is loading the signed-in workspace before opening expenses.',
              ),
            ),
          ],
        ),
      );
    }

    if (!shop.supportsExpenses) {
      return MobileStandaloneScaffold(
        title: L.of(context).settingsExpenses,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            MobilePanel(
              title: 'Expenses unlock on Growth and Pro',
              child: MobileEmptyState(
                icon: Icons.workspace_premium_rounded,
                title: 'Expenses are not active on this plan',
                body:
                    'This workspace is on a lighter plan, so expense tracking stays hidden here until the owner upgrades the shop plan.',
              ),
            ),
          ],
        ),
      );
    }

    final topExpenses = [...expenses]
      ..sort((left, right) => right.amount.compareTo(left.amount));

    return MobileStandaloneScaffold(
      title: L.of(context).settingsExpenses,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          MobileScreenLead(
            title: session.isOwnerLike ? 'Store spend desk' : 'Store expenses',
            subtitle:
                'Track outgoing spend, capture payment references, and keep day-to-day business costs visible from the same product.',
            icon: Icons.payments_rounded,
            accent: AppPalette.warning,
            primaryTag: MobileTag(
              label: shop.planLabel,
              icon: Icons.workspace_premium_rounded,
              accent: AppPalette.warning,
            ),
            secondaryTag: MobileTag(
              label: expenses.isEmpty
                  ? (expensesAsync.isLoading ? 'Refreshing' : 'No entries')
                  : '${expenses.length} entries',
              icon: Icons.receipt_long_rounded,
              accent: AppPalette.primary,
            ),
          ),
          const SizedBox(height: 18),
          if (_message != null) ...<Widget>[
            MobilePanel(
              title: _messageIsError ? 'Expense issue' : 'Expense saved',
              child: Text(
                _message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black.withValues(alpha: 0.76),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          MobilePanel(
            title: 'Expense posture',
            action: FilledButton.tonalIcon(
              onPressed: _busy ? null : _refreshExpenses,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth > 520 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: count,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: constraints.maxWidth < 420 ? 1.45 : 1.02,
                  children: <Widget>[
                    MobileMetricCard(
                      label: 'Entries',
                      value: '${summary?.totalEntries ?? expenses.length}',
                      caption: 'Tracked spend records',
                      icon: Icons.receipt_long_rounded,
                      accent: AppPalette.primary,
                    ),
                    MobileMetricCard(
                      label: 'Total spend',
                      value: formatCurrency(summary?.totalAmount ?? 0),
                      caption: 'Visible outgoing amount',
                      icon: Icons.currency_rupee_rounded,
                      accent: AppPalette.error,
                    ),
                    MobileMetricCard(
                      label: 'Categories',
                      value: '${summary?.uniqueCategories ?? 0}',
                      caption: 'Spend buckets tracked',
                      icon: Icons.category_rounded,
                      accent: AppPalette.success,
                    ),
                    MobileMetricCard(
                      label: 'Top category',
                      value: summary?.biggestCategory ?? 'None',
                      caption: 'Largest spend bucket',
                      icon: Icons.trending_up_rounded,
                      accent: AppPalette.info,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          MobilePanel(
            title: L.of(context).expAdd,
            action: MobileTag(
              label: session.isViewer ? 'View only' : 'Daily ops',
              icon: session.isViewer
                  ? Icons.visibility_rounded
                  : Icons.add_circle_rounded,
              accent: AppPalette.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  session.isViewer
                      ? 'This account can review store spending, but only daily operators and above can create or update expense records.'
                      : 'Capture small daily store costs like travel, packaging, internet, rent support, or urgent purchases directly from the phone.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black.withValues(alpha: 0.72),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: session.isViewer || _busy
                      ? null
                      : () => _openAddExpenseSheet(context),
                  icon: const Icon(Icons.add_circle_rounded),
                  label: const Text('Add store expense'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          MobilePanel(
            title: 'Recent expenses',
            action: MobileTag(
              label: topExpenses.isEmpty
                  ? 'No outflow'
                  : '${topExpenses.length} visible',
              icon: Icons.payments_rounded,
              accent: AppPalette.warning,
            ),
            child: expensesAsync.isLoading
                ? const MobileEmptyState(
                    icon: Icons.sync_rounded,
                    title: 'Refreshing store spend',
                    body:
                        'Business Hub is loading the latest outgoing expense records for this workspace.',
                  )
                : topExpenses.isEmpty
                ? const MobileEmptyState(
                    icon: Icons.wallet_rounded,
                    title: 'No expense activity yet',
                    body:
                        'Add the first store expense and it will appear here with category, payment method, and amount.',
                  )
                : Column(
                    children: topExpenses
                        .take(8)
                        .map(
                          (expense) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ExpenseCard(expense: expense),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expense});

  final ExpenseRecord expense;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
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
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    expense.category,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                MobileTag(
                  label: formatCurrency(expense.amount),
                  icon: Icons.currency_rupee_rounded,
                  accent: AppPalette.error,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${formatCompactDate(expense.expenseDate)}  ·  ${_paymentMethodLabel(expense.paymentMethod)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black.withValues(alpha: 0.68),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (expense.description.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                expense.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black.withValues(alpha: 0.70),
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                MobileTag(
                  label: _paymentMethodLabel(expense.paymentMethod),
                  icon: Icons.account_balance_wallet_rounded,
                  accent: AppPalette.primary,
                ),
                if (expense.paymentReference.trim().isNotEmpty)
                  MobileTag(
                    label: expense.paymentReference,
                    icon: Icons.tag_rounded,
                    accent: AppPalette.success,
                  ),
                if ((expense.actorName ?? '').trim().isNotEmpty)
                  MobileTag(
                    label: expense.actorName!,
                    icon: Icons.person_rounded,
                    accent: AppPalette.info,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _paymentMethodLabel(String value) {
  switch (value.trim().toUpperCase()) {
    case 'UPI':
      return 'UPI';
    case 'BANK':
      return 'Bank';
    case 'CARD':
      return 'Card';
    case 'OTHER':
      return 'Other';
    default:
      return 'Cash';
  }
}

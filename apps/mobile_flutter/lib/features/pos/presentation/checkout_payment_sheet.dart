import 'package:flutter/material.dart';

import '../../../core/checkout/checkout_policy.dart';
import '../../../core/pos/upi_qr.dart';
import '../../../core/tax/gst.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import 'upi_qr_view.dart';

const List<String> _paymentModes = <String>['CASH', 'CARD', 'UPI'];

/// A single payment line in a (possibly split) checkout.
class _PayLine {
  _PayLine(this.mode, double initial)
    : amount = TextEditingController(
        text: initial > 0 ? initial.toStringAsFixed(2) : '',
      );

  String mode;
  final TextEditingController amount;

  double get value => double.tryParse(amount.text.trim()) ?? 0;

  void dispose() => amount.dispose();
}

/// Checkout sheet with a real, user-defined split payment.
///
/// Any number of payment lines (CASH/CARD/UPI) can be entered. If the entered
/// total is less than the amount due, the balance is recorded as a customer due
/// (khata); if it exceeds a cash payment, the surplus is shown as change.
class CheckoutPaymentSheet extends StatefulWidget {
  const CheckoutPaymentSheet({
    super.key,
    required this.cartTotal,
    required this.gstSummary,
    this.upiVpa = '',
    this.shopName = '',
    this.availablePoints = 0,
  });

  final double cartTotal;
  final GstCartSummary gstSummary;
  final String upiVpa;
  final String shopName;

  /// Loyalty points the selected customer holds. Zero hides the whole control.
  final int availablePoints;

  @override
  State<CheckoutPaymentSheet> createState() => _CheckoutPaymentSheetState();
}

class _CheckoutPaymentSheetState extends State<CheckoutPaymentSheet> {
  final TextEditingController _buyerGstin = TextEditingController();
  final List<_PayLine> _lines = <_PayLine>[];
  int _redeemPoints = 0;

  /// Points are worth Rs.1 each by default. The SERVER re-decides and clamps
  /// this, so a shop on a different point value can never be short-changed by
  /// what the till displays — the bill it saves is the server's figure.
  double get _redeemValue => _redeemPoints.toDouble();

  int get _maxRedeemable {
    final byBill = widget.cartTotal.floor();
    return widget.availablePoints < byBill ? widget.availablePoints : byBill;
  }

  @override
  void initState() {
    super.initState();
    // Start with the full amount tendered in cash — the common case.
    _lines.add(_PayLine('CASH', widget.cartTotal));
  }

  @override
  void dispose() {
    _buyerGstin.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  /// Resolve tender lines into what is actually recorded (cash over-tender
  /// becomes change, never collected money) — the single source of truth for
  /// the summary and for saving.
  TenderResolution get _resolution => resolveCashierTender(
    total: widget.cartTotal,
    lines: _lines
        .map((l) => CheckoutPaymentEntry(mode: l.mode, amount: l.value))
        .toList(growable: false),
  );

  double get _paid => _resolution.totalCollected;

  /// Total tendered on UPI lines — what the collect-QR should ask for.
  double get _upiAmount {
    var sum = 0.0;
    for (final line in _lines) {
      if (line.mode == 'UPI' && line.value > 0) sum += line.value;
    }
    return sum;
  }

  double get _due => _resolution.dueFor(widget.cartTotal);
  double get _change => _resolution.change;

  void _addLine() {
    setState(() => _lines.add(_PayLine('CASH', _due)));
  }

  void _removeLine(int index) {
    setState(() {
      _lines.removeAt(index).dispose();
      if (_lines.isEmpty) {
        _lines.add(_PayLine('CASH', 0));
      }
    });
  }

  /// Show a scannable UPI QR for the amount due (or full bill), using the
  /// shop's saved UPI ID. Any UPI app pre-fills the merchant and exact amount.
  void _showPaymentQr(BuildContext context) {
    final amount = _due > 0 ? _due : widget.cartTotal;
    final String uri;
    try {
      uri = buildUpiUri(
        payeeVpa: widget.upiVpa,
        payeeName: widget.shopName,
        amount: amount,
        note: 'Bill ${widget.shopName}',
      );
    } on UpiRequestError catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Scan to pay'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            UpiQrView(data: uri),
            const SizedBox(height: 12),
            Text(
              formatCurrency(amount),
              style: Theme.of(dialogContext).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppPalette.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.upiVpa,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _completeSale() {
    final resolution = _resolution;
    if (resolution.overcharged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A card/UPI amount is more than the bill. You can only give change '
            'on cash — reduce that line.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'payments': resolution.payments,
      'paymentMode': paymentModeFor(resolution.payments),
      'redeemPoints': _redeemPoints,
      'buyerGstin': _buyerGstin.text.trim().isEmpty
          ? null
          : _buyerGstin.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final isSplit = _lines.length > 1;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    Text(
                      'Checkout',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      formatCurrency(widget.cartTotal),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppPalette.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  isSplit ? 'SPLIT PAYMENT' : 'PAYMENT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(height: 10),
                for (int i = 0; i < _lines.length; i++) ...<Widget>[
                  _PaymentLineRow(
                    line: _lines[i],
                    canRemove: _lines.length > 1,
                    onModeChanged: (mode) =>
                        setState(() => _lines[i].mode = mode),
                    onAmountChanged: () => setState(() {}),
                    onRemove: () => _removeLine(i),
                  ),
                  const SizedBox(height: 10),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add split'),
                  ),
                ),
                if (_maxRedeemable > 0) ...<Widget>[
                  const SizedBox(height: 12),
                  _LoyaltyRedeemCard(
                    available: widget.availablePoints,
                    maxRedeemable: _maxRedeemable,
                    redeeming: _redeemPoints,
                    onChanged: (points) =>
                        setState(() => _redeemPoints = points),
                  ),
                ],
                const SizedBox(height: 12),
                // Live summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.borderSoft),
                  ),
                  child: Column(
                    children: <Widget>[
                      _SummaryLine(label: 'Total', value: widget.cartTotal),
                      if (_redeemPoints > 0) ...<Widget>[
                        const SizedBox(height: 6),
                        _SummaryLine(
                          label: '$_redeemPoints points',
                          value: -_redeemValue,
                          valueColor: AppPalette.success,
                        ),
                      ],
                      const SizedBox(height: 6),
                      _SummaryLine(
                        label: 'Paid',
                        value: _paid,
                        valueColor: AppPalette.success,
                      ),
                      if (_due > 0) ...<Widget>[
                        const SizedBox(height: 6),
                        _SummaryLine(
                          label: 'Balance due',
                          value: _due,
                          valueColor: AppPalette.warning,
                          bold: true,
                        ),
                      ],
                      if (_change > 0) ...<Widget>[
                        const SizedBox(height: 6),
                        _SummaryLine(
                          label: 'Change',
                          value: _change,
                          valueColor: AppPalette.primary,
                          bold: true,
                        ),
                      ],
                    ],
                  ),
                ),
                // Picking UPI shows the collect-QR straight away for the exact
                // amount on that line — the cashier shouldn't have to hunt for
                // a button before the customer can scan.
                if (_upiAmount > 0 &&
                    widget.upiVpa.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _UpiCollectCard(
                    vpa: widget.upiVpa.trim(),
                    shopName: widget.shopName,
                    amount: _upiAmount,
                  ),
                ] else if (widget.upiVpa.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _showPaymentQr(context),
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: Text(
                      'Show UPI QR (${formatCurrency(_due > 0 ? _due : widget.cartTotal)})',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.primary,
                      side: const BorderSide(color: AppPalette.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _buyerGstin,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Buyer GSTIN (optional)',
                    hintText: 'For a B2B tax invoice',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _completeSale,
                    child: Text(
                      _due > 0
                          ? 'Save with ${formatCurrency(_due)} due'
                          : 'Complete sale',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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

/// Inline collect-QR shown as soon as UPI is chosen, so the customer can scan
/// while the cashier is still on the checkout sheet.
/// Spend a customer's loyalty points on this bill.
class _LoyaltyRedeemCard extends StatelessWidget {
  const _LoyaltyRedeemCard({
    required this.available,
    required this.maxRedeemable,
    required this.redeeming,
    required this.onChanged,
  });

  final int available;
  final int maxRedeemable;
  final int redeeming;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.success.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.card_giftcard_rounded,
                color: AppPalette.success,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$available points available',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (redeeming > 0)
                TextButton(
                  onPressed: () => onChanged(0),
                  child: const Text('Clear'),
                ),
            ],
          ),
          if (redeeming > 0)
            Text(
              'Using $redeeming points - ${formatCurrency(redeeming.toDouble())} off',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.success,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Text(
              // Be explicit that the bill caps it, so a cashier isn't confused
              // when a big balance only knocks off part of a small bill.
              'Up to $maxRedeemable can be used on this bill',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          Slider(
            value: redeeming.toDouble().clamp(0, maxRedeemable.toDouble()),
            max: maxRedeemable.toDouble(),
            divisions: maxRedeemable > 0 ? maxRedeemable : null,
            label: '$redeeming',
            onChanged: (value) => onChanged(value.round()),
          ),
        ],
      ),
    );
  }
}

class _UpiCollectCard extends StatelessWidget {
  const _UpiCollectCard({
    required this.vpa,
    required this.shopName,
    required this.amount,
  });

  final String vpa;
  final String shopName;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    String? uri;
    try {
      uri = buildUpiUri(
        payeeVpa: vpa,
        payeeName: shopName,
        amount: amount,
        note: 'Bill $shopName',
      );
    } on UpiRequestError {
      uri = null;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.qr_code_2_rounded, color: AppPalette.primary),
              const SizedBox(width: 8),
              Text(
                'Scan to pay',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                formatCurrency(amount),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppPalette.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (uri == null)
            Text(
              'Add a valid UPI ID in Business settings to show a payment QR.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
            )
          else ...<Widget>[
            UpiQrView(data: uri, size: 190),
            const SizedBox(height: 8),
            Text(
              vpa,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: 6),
            Text(
              'Confirm the payment in your UPI app, then complete the sale.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentLineRow extends StatelessWidget {
  const _PaymentLineRow({
    required this.line,
    required this.canRemove,
    required this.onModeChanged,
    required this.onAmountChanged,
    required this.onRemove,
  });

  final _PayLine line;
  final bool canRemove;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onAmountChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.borderSoft),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: line.mode,
              borderRadius: BorderRadius.circular(14),
              items: _paymentModes
                  .map(
                    (m) => DropdownMenuItem<String>(
                      value: m,
                      child: Text(
                        m,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (m) {
                if (m != null) onModeChanged(m);
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: line.amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onAmountChanged(),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Amount',
              prefixText: '₹ ',
            ),
          ),
        ),
        if (canRemove)
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline_rounded),
            color: AppPalette.error,
          ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  final String label;
  final double value;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          formatCurrency(value),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

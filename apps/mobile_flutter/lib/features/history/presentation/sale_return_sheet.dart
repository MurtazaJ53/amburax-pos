import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

/// Refund methods the server accepts, in the order a counter reaches for them.
///
/// EXCHANGE is last and deliberately worded as a swap rather than a refund: it
/// records a zero refund because the value carries into the replacement bill
/// the cashier rings up next, and calling it a refund invites paying the money
/// out as well.
const List<({String value, String label})> kRefundModes = <({
  String value,
  String label
})>[
  (value: 'CASH', label: 'Cash'),
  (value: 'UPI', label: 'UPI'),
  (value: 'CARD', label: 'Card'),
  (value: 'BANK', label: 'Bank'),
  (value: 'KHATA', label: 'Reduce khata'),
  (value: 'EXCHANGE', label: 'Exchange'),
];

/// Quantities and money arrive from DRF as JSON strings.
double parseAmount(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0;
  return 0;
}

String showQuantity(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

/// One line of a bill, as the server reports what is still returnable on it.
class ReturnableLine {
  const ReturnableLine({
    required this.saleItemId,
    required this.name,
    required this.size,
    required this.sold,
    required this.returned,
    required this.returnable,
    required this.unitPrice,
  });

  factory ReturnableLine.fromJson(Map<String, dynamic> json) => ReturnableLine(
        saleItemId: '${json['sale_item_id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        size: '${json['size'] ?? ''}',
        sold: parseAmount(json['sold']),
        returned: parseAmount(json['returned']),
        returnable: parseAmount(json['returnable']),
        unitPrice: parseAmount(json['unit_price']),
      );

  final String saleItemId;
  final String name;
  final String size;
  final double sold;
  final double returned;
  final double returnable;
  final double unitPrice;
}

/// The refund a set of quantities adds up to.
///
/// An exchange is worth zero on purpose — the goods are swapped, so no money
/// leaves the till. Showing the goods' value there would tell a cashier to hand
/// over cash on top of the replacement item.
double refundTotal(
  List<ReturnableLine> lines,
  Map<String, double> quantities,
  String refundMode,
) {
  if (refundMode == 'EXCHANGE') return 0;
  var total = 0.0;
  for (final line in lines) {
    total += (quantities[line.saleItemId] ?? 0) * line.unitPrice;
  }
  return total;
}

/// Why this return cannot be submitted yet, or null when it can.
///
/// Returned as a message rather than a bool so the button can say what is
/// wrong instead of sitting greyed out with no explanation — a cashier with a
/// customer waiting cannot guess.
String? returnBlocker({
  required List<ReturnableLine> lines,
  required Map<String, double> quantities,
  required String refundMode,
  required bool hasCustomer,
}) {
  final chosen =
      quantities.entries.where((e) => e.value > 0).toList(growable: false);
  if (chosen.isEmpty) return 'Choose what is coming back.';

  for (final line in lines) {
    final wanted = quantities[line.saleItemId] ?? 0;
    if (wanted > line.returnable) {
      // The server enforces this too. Catching it here means the cashier is
      // told before the customer is handed anything.
      return '${line.name}: only ${showQuantity(line.returnable)} left to return.';
    }
  }

  if (refundMode == 'KHATA' && !hasCustomer) {
    return 'This bill has no customer, so there is no khata to credit.';
  }
  return null;
}

/// Taking part of a bill back.
///
/// The counter used to offer one action — void the whole sale — which is the
/// wrong tool for what shops actually do. A customer brings one shirt back out
/// of four items, or swaps it for a different size, and voiding destroys the
/// record of what was really sold.
///
/// Everything shown comes from the server rather than the local sale, because
/// a return processed yesterday on the web would be invisible to this device
/// and the phone would cheerfully offer to take the same shirt back twice.
class SaleReturnSheet extends ConsumerStatefulWidget {
  const SaleReturnSheet({
    required this.backendSaleId,
    required this.receiptNumber,
    super.key,
  });

  final String backendSaleId;
  final String receiptNumber;

  @override
  ConsumerState<SaleReturnSheet> createState() => _SaleReturnSheetState();
}

class _SaleReturnSheetState extends ConsumerState<SaleReturnSheet> {
  List<ReturnableLine> _lines = const <ReturnableLine>[];
  final Map<String, double> _quantities = <String, double>{};
  String _mode = 'CASH';
  bool _hasCustomer = false;
  bool _isVoid = false;
  bool _anyReturnable = false;
  String? _receiptNumber;

  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) {
      setState(() {
        _loading = false;
        _error = 'No shop is selected.';
      });
      return;
    }
    try {
      final payload =
          await ref.read(backendApiClientProvider).fetchReturnableSale(
                user: session.user,
                shopId: session.shopId!,
                saleId: widget.backendSaleId,
              );
      if (!mounted) return;
      setState(() {
        _lines = (payload['lines'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(ReturnableLine.fromJson)
            .toList(growable: false);
        _receiptNumber = '${payload['receipt_number'] ?? ''}'.trim();
        _hasCustomer = payload['customer_id'] != null;
        _isVoid = payload['is_void'] == true;
        _anyReturnable = payload['any_returnable'] == true;
        _loading = false;
      });
    } on BackendApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this bill. Check the connection.';
      });
    }
  }

  void _setQuantity(ReturnableLine line, double value) {
    setState(() {
      final clamped = value.clamp(0, line.returnable).toDouble();
      if (clamped <= 0) {
        _quantities.remove(line.saleItemId);
      } else {
        _quantities[line.saleItemId] = clamped;
      }
    });
  }

  Future<void> _submit() async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) return;

    final blocker = returnBlocker(
      lines: _lines,
      quantities: _quantities,
      refundMode: _mode,
      hasCustomer: _hasCustomer,
    );
    if (blocker != null) {
      setState(() => _error = blocker);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(backendApiClientProvider).createSaleReturn(
            user: session.user,
            shopId: session.shopId!,
            saleId: widget.backendSaleId,
            refundMode: _mode,
            lines: _quantities.entries
                .where((e) => e.value > 0)
                .map((e) => <String, dynamic>{
                      'sale_item_id': e.key,
                      'quantity': '${e.value}',
                    })
                .toList(growable: false),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on BackendApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'The return did not go through. Nothing was changed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final total = refundTotal(_lines, _quantities, _mode);
    final blocker = _loading
        ? null
        : returnBlocker(
            lines: _lines,
            quantities: _quantities,
            refundMode: _mode,
            hasCustomer: _hasCustomer,
          );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
              const SizedBox(height: 14),
              Text(
                'Return items',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                'Against ${(_receiptNumber ?? '').isEmpty ? widget.receiptNumber : _receiptNumber}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Flexible(child: _body(colors)),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                _Notice(message: _error!, tone: AppPalette.error),
              ],
              if (!_loading && !_isVoid && _anyReturnable) ...<Widget>[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      _mode == 'EXCHANGE' ? 'Value swapped' : 'Refund',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.textSecondary,
                      ),
                    ),
                    Text(
                      formatCurrency(total),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (_mode == 'EXCHANGE')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'No money leaves the till. Ring up the replacement next.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy || blocker != null ? null : () => _submit(),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _busy
                        ? 'Processing…'
                        : blocker ?? 'Take these back',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(AppColors colors) {
    if (_isVoid) {
      return _Notice(
        message: 'This bill was voided, which already put the stock back.',
        tone: AppPalette.warning,
      );
    }
    if (!_anyReturnable) {
      return _Notice(
        message: 'Everything on this bill has already been returned.',
        tone: AppPalette.warning,
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final line in _lines)
            _LineRow(
              line: line,
              chosen: _quantities[line.saleItemId] ?? 0,
              onChanged: (value) => _setQuantity(line, value),
            ),
          const SizedBox(height: 16),
          Text(
            'HOW IS IT REFUNDED',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final mode in kRefundModes)
                ChoiceChip(
                  selected: _mode == mode.value,
                  // Disabled rather than hidden, with the reason shown on the
                  // button, so it is clear the option exists and why it cannot
                  // be used on this particular bill.
                  onSelected: mode.value == 'KHATA' && !_hasCustomer
                      ? null
                      : (_) => setState(() {
                            _mode = mode.value;
                            _error = null;
                          }),
                  label: Text(mode.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.chosen,
    required this.onChanged,
  });

  final ReturnableLine line;
  final double chosen;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final exhausted = line.returnable <= 0;

    return Opacity(
      opacity: exhausted ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.backgroundSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    line.size.isEmpty ? line.name : '${line.name} · ${line.size}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    exhausted
                        ? 'All ${showQuantity(line.sold)} returned'
                        : '${showQuantity(line.returnable)} of '
                            '${showQuantity(line.sold)} left · '
                            '${formatCurrency(line.unitPrice)} each',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (!exhausted)
              Row(
                children: <Widget>[
                  IconButton(
                    onPressed:
                        chosen <= 0 ? null : () => onChanged(chosen - 1),
                    icon: const Icon(Icons.remove_circle_outline, size: 22),
                    visualDensity: VisualDensity.compact,
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      showQuantity(chosen),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    // Capped at what is left rather than letting the server
                    // reject it after the customer has been told yes.
                    onPressed: chosen >= line.returnable
                        ? null
                        : () => onChanged(chosen + 1),
                    icon: const Icon(Icons.add_circle_outline, size: 22),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.tone});

  final String message;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }
}

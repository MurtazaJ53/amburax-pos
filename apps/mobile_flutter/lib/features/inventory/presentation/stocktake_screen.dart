import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/models/mobile_session.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../pos/presentation/pos_scanner_sheet.dart';
import '../../shell/presentation/mobile_surface.dart';

/// Quantities arrive from DRF as JSON strings.
double parseQuantity(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0;
  return 0;
}

String showCount(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

/// An item as the catalogue lists it, reduced to what a search needs.
class CountableItem {
  const CountableItem({
    required this.id,
    required this.name,
    required this.sku,
    required this.barcode,
  });

  factory CountableItem.fromJson(Map<String, dynamic> json) => CountableItem(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? ''}',
    sku: '${json['sku'] ?? ''}',
    barcode: '${json['barcode'] ?? ''}',
  );

  final String id;
  final String name;
  final String sku;
  final String barcode;
}

/// Items whose name, SKU or barcode contain the query. A blank query matches
/// nothing, so clearing the field does not dump a slice of the catalogue.
List<CountableItem> searchCountable(
  List<CountableItem> items,
  String query, {
  int limit = 8,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const <CountableItem>[];
  return items
      .where(
        (i) =>
            i.name.toLowerCase().contains(q) ||
            i.sku.toLowerCase().contains(q) ||
            i.barcode.toLowerCase().contains(q),
      )
      .take(limit)
      .toList(growable: false);
}

/// What a scan or an Enter press should select.
///
/// An exact barcode or SKU wins outright, even when that same string appears
/// inside another item's name — a scanner produced it, so it is not a guess.
/// Otherwise a single remaining match is taken as unambiguous, and anything
/// else selects nothing.
///
/// Guessing here is expensive. A counter working a shelf does not look up
/// between scans, so a wrong pick records a count against the wrong item and
/// the variance it produces is indistinguishable from real shrinkage.
CountableItem? resolveCountScan(List<CountableItem> items, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return null;
  for (final item in items) {
    if (item.barcode.toLowerCase() == q || item.sku.toLowerCase() == q) {
      return item;
    }
  }
  final matches = searchCountable(items, q);
  return matches.length == 1 ? matches.first : null;
}

/// The one open count, or null. The server allows at most one per shop.
Map<String, dynamic>? openStocktake(List<Map<String, dynamic>> all) {
  for (final row in all) {
    if (row['status'] == 'open') return row;
  }
  return null;
}

final _stocktakesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final session = ref.watch(mobileSessionProvider).asData?.value;
  if (session == null || !session.hasShop) return const <String, dynamic>{};
  return ref
      .read(backendApiClientProvider)
      .fetchStocktakes(user: session.user, shopId: session.shopId!);
});

final _countableItemsProvider = FutureProvider.autoDispose<List<CountableItem>>(
  (ref) async {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) return const <CountableItem>[];
    final rows = await ref
        .read(backendApiClientProvider)
        .fetchInventoryItems(user: session.user, shopId: session.shopId!);
    // Everything is countable, including items the books say are at zero —
    // finding stock that the system does not know about is half the point.
    return rows.map(CountableItem.fromJson).toList(growable: false);
  },
);

/// Counting the shelves.
///
/// This is the screen the whole feature was built for. A stocktake happens
/// standing in front of shelves with a phone in one hand, which is why the
/// counter app matters more here than the web version does: it puts one item
/// in focus at a time and keeps the camera a tap away.
///
/// The expected quantity is deliberately hidden until asked for. Showing it
/// invites the counter to confirm the book figure rather than count the shelf,
/// which produces a stocktake that always agrees and never finds anything.
class StocktakeScreen extends ConsumerStatefulWidget {
  const StocktakeScreen({super.key});

  @override
  ConsumerState<StocktakeScreen> createState() => _StocktakeScreenState();
}

class _StocktakeScreenState extends ConsumerState<StocktakeScreen> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _counted = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _countFocus = FocusNode();

  CountableItem? _selected;
  double? _expected;
  bool _revealExpected = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _counted.dispose();
    _searchFocus.dispose();
    _countFocus.dispose();
    super.dispose();
  }

  bool _canApply(MobileSession session) =>
      session.isOwnerLike || session.isManager;

  void _choose(CountableItem item, Map<String, dynamic>? open) {
    setState(() {
      _selected = item;
      _revealExpected = false;
      _error = null;
      _search.clear();
      _counted.clear();
      _expected = _expectedFor(item.id, open);
    });
    _countFocus.requestFocus();
  }

  /// What the books said the last time this item was counted in this session.
  /// Null when it has not been counted yet, which is the normal case.
  double? _expectedFor(String itemId, Map<String, dynamic>? open) {
    final lines = (open?['lines'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>();
    for (final line in lines) {
      if ('${line['item_id']}' == itemId) {
        return parseQuantity(line['expected']);
      }
    }
    return null;
  }

  Future<void> _run(
    Future<void> Function(BackendApiClient api, MobileSession session) action,
    String failure,
  ) async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(backendApiClientProvider), session);
      ref.invalidate(_stocktakesProvider);
    } on BackendApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _run((api, session) async {
    await api.startStocktake(user: session.user, shopId: session.shopId!);
  }, 'Could not start a count. Check the connection.');

  Future<void> _record(String stocktakeId) async {
    final item = _selected;
    if (item == null) return;
    final typed = _counted.text.trim();
    if (typed.isEmpty) {
      setState(
        () =>
            _error = 'Enter how many are on the shelf. Zero is a real answer.',
      );
      return;
    }
    await _run((api, session) async {
      await api.recordStocktakeCount(
        user: session.user,
        shopId: session.shopId!,
        stocktakeId: stocktakeId,
        itemId: item.id,
        countedQuantity: typed,
      );
    }, 'Could not save that count.');
    if (!mounted || _error != null) return;
    setState(() {
      _selected = null;
      _counted.clear();
    });
    // Straight back to the search field so the next scan needs no tap.
    _searchFocus.requestFocus();
  }

  Future<void> _apply(String stocktakeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apply this count?'),
        content: const Text(
          'Stock will be corrected by the difference each item is out by. '
          'Anything sold while you were counting stays sold.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run((api, session) async {
      await api.applyStocktake(
        user: session.user,
        shopId: session.shopId!,
        stocktakeId: stocktakeId,
      );
    }, 'Could not apply the count.');
  }

  Future<void> _cancel(String stocktakeId) => _run((api, session) async {
    await api.cancelStocktake(
      user: session.user,
      shopId: session.shopId!,
      stocktakeId: stocktakeId,
    );
  }, 'Could not cancel the count.');

  Future<void> _scan(
    List<CountableItem> items,
    Map<String, dynamic>? open,
  ) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PosScannerSheet(),
    );
    if (code == null || !mounted) return;
    final hit = resolveCountScan(items, code);
    if (hit == null) {
      setState(() => _error = 'Nothing in the catalogue matches $code.');
      return;
    }
    _choose(hit, open);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final payload =
        ref.watch(_stocktakesProvider).asData?.value ??
        const <String, dynamic>{};
    final items =
        ref.watch(_countableItemsProvider).asData?.value ??
        const <CountableItem>[];

    final all = (payload['stocktakes'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final open = openStocktake(all);
    final past = all
        .where((r) => r['status'] != 'open')
        .toList(growable: false);

    return MobileStandaloneScaffold(
      title: 'Stocktake',
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_stocktakesProvider);
          ref.invalidate(_countableItemsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            if (_error != null) ...<Widget>[
              _Banner(message: _error!, tone: AppPalette.error),
              const SizedBox(height: 12),
            ],
            if (open == null)
              _StartCard(busy: _busy, onStart: _busy ? null : _start)
            else ...<Widget>[
              _CountCard(
                open: open,
                items: items,
                selected: _selected,
                expected: _expected,
                revealExpected: _revealExpected,
                searchController: _search,
                countController: _counted,
                searchFocus: _searchFocus,
                countFocus: _countFocus,
                busy: _busy,
                onChoose: (item) => _choose(item, open),
                onClear: () => setState(() {
                  _selected = null;
                  _counted.clear();
                }),
                onReveal: () => setState(() => _revealExpected = true),
                onScan: () => _scan(items, open),
                onRecord: () => _record('${open['id']}'),
                onSearchChanged: () => setState(() {}),
                onSearchSubmitted: (value) {
                  final hit = resolveCountScan(items, value);
                  if (hit != null) _choose(hit, open);
                },
              ),
              const SizedBox(height: 12),
              _ProgressCard(
                open: open,
                canApply: session != null && _canApply(session),
                busy: _busy,
                onApply: () => _apply('${open['id']}'),
                onCancel: () => _cancel('${open['id']}'),
              ),
            ],
            if (past.isNotEmpty) ...<Widget>[
              const SizedBox(height: 20),
              Text(
                'EARLIER COUNTS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(height: 8),
              for (final row in past.take(10)) _PastRow(row: row),
            ],
          ],
        ),
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({required this.busy, required this.onStart});

  final bool busy;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Count the shelves',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Walk the shop, scan each item and enter what is actually there. '
            'Nothing changes until you apply the count.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(busy ? 'Starting…' : 'Start a stocktake'),
          ),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.open,
    required this.items,
    required this.selected,
    required this.expected,
    required this.revealExpected,
    required this.searchController,
    required this.countController,
    required this.searchFocus,
    required this.countFocus,
    required this.busy,
    required this.onChoose,
    required this.onClear,
    required this.onReveal,
    required this.onScan,
    required this.onRecord,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
  });

  final Map<String, dynamic> open;
  final List<CountableItem> items;
  final CountableItem? selected;
  final double? expected;
  final bool revealExpected;
  final TextEditingController searchController;
  final TextEditingController countController;
  final FocusNode searchFocus;
  final FocusNode countFocus;
  final bool busy;
  final ValueChanged<CountableItem> onChoose;
  final VoidCallback onClear;
  final VoidCallback onReveal;
  final VoidCallback onScan;
  final VoidCallback onRecord;
  final VoidCallback onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final matches = searchCountable(items, searchController.text);
    final counted = (open['lines'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((l) => '${l['item_id']}')
        .toSet();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '${open['reference']}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${open['counted_lines']} counted',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (selected == null) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: searchController,
                    focusNode: searchFocus,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => onSearchChanged(),
                    onSubmitted: onSearchSubmitted,
                    decoration: const InputDecoration(
                      hintText: 'Scan or search by name, SKU…',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onScan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  tooltip: 'Scan a barcode',
                ),
              ],
            ),
            for (final match in matches)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  match.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                subtitle: match.sku.isEmpty ? null : Text(match.sku),
                trailing: counted.contains(match.id)
                    ? const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: AppPalette.success,
                      )
                    : null,
                onTap: () => onChoose(match),
              ),
          ] else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    selected!.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Choose a different item',
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: countController,
              focusNode: countFocus,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
              onSubmitted: (_) => onRecord(),
              decoration: const InputDecoration(
                labelText: 'How many are on the shelf?',
                hintText: '0',
              ),
            ),
            // Hidden until asked for on purpose: showing the book figure
            // invites confirming it instead of counting the shelf, and a
            // stocktake that always agrees never finds anything.
            if (revealExpected)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  expected == null
                      ? 'Not counted yet in this stocktake.'
                      : 'Last counted against ${showCount(expected!)}.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
              )
            else
              TextButton(
                onPressed: onReveal,
                child: const Text('Show what the books say'),
              ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: busy ? null : onRecord,
              child: Text(busy ? 'Saving…' : 'Record count'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.open,
    required this.canApply,
    required this.busy,
    required this.onApply,
    required this.onCancel,
  });

  final Map<String, dynamic> open;
  final bool canApply;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final lines = (open['lines'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final varianceValue = open['variance_value'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _Tally(
                label: 'Missing',
                value: '${open['missing_count'] ?? 0}',
                tone: AppPalette.error,
              ),
              const SizedBox(width: 10),
              _Tally(
                label: 'Extra',
                value: '${open['extra_count'] ?? 0}',
                tone: AppPalette.warning,
              ),
              const SizedBox(width: 10),
              _Tally(
                label: 'Matched',
                value: '${open['matched_count'] ?? 0}',
                tone: AppPalette.success,
              ),
            ],
          ),
          if (lines.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            for (final line in lines.take(50)) _LineRow(line: line),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Value of the difference',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
                Text(
                  // Null rather than a partial sum: a shrinkage figure that
                  // silently omits items with no cost price understates the
                  // loss, and that is the number somebody acts on.
                  varianceValue == null
                      ? 'Unknown'
                      : formatCurrency(parseQuantity(varianceValue)),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            if (varianceValue == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Some counted items have no cost price recorded.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textTertiary,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 14),
          if (canApply)
            FilledButton.icon(
              onPressed: busy || lines.isEmpty ? null : onApply,
              icon: const Icon(Icons.fact_check_rounded),
              label: Text(busy ? 'Applying…' : 'Apply the count to stock'),
            )
          else
            _Banner(
              message:
                  'Your counting is saved. A manager or owner applies it to stock.',
              tone: AppPalette.warning,
            ),
          TextButton(
            onPressed: busy ? null : onCancel,
            child: const Text('Cancel this count'),
          ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final Map<String, dynamic> line;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final variance = parseQuantity(line['variance']);
    final tone = variance < 0
        ? AppPalette.error
        : variance > 0
        ? AppPalette.warning
        : colors.textTertiary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${line['name']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            '${showCount(parseQuantity(line['expected']))} → '
            '${showCount(parseQuantity(line['counted']))}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          SizedBox(
            width: 54,
            child: Text(
              '${variance > 0 ? '+' : ''}${showCount(variance)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: tone,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PastRow extends StatelessWidget {
  const _PastRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.backgroundSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${row['reference']}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            '${row['counted_lines']} counted · ${row['missing_count']} missing',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${row['status']}'.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: row['status'] == 'applied'
                  ? AppPalette.success
                  : colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: colors.backgroundSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: <Widget>[
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: tone,
              ),
            ),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.tone});

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

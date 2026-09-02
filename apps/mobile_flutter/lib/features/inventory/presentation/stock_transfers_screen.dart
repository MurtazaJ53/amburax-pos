import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/models/mobile_session.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

/// Quantities arrive from DRF as JSON strings.
double _qty(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0;
  return 0;
}

String _showQty(Object? value) {
  final n = _qty(value);
  return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
}

final stockTransfersProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) return const <String, dynamic>{};
    return ref
        .read(backendApiClientProvider)
        .fetchStockTransfers(user: session.user, shopId: session.shopId!);
  },
);

/// Every other shop this account belongs to — a transfer needs somewhere to go.
final transferDestinationsProvider =
    FutureProvider.autoDispose<List<ShopMembershipAccessRecord>>((ref) async {
      final session = ref.watch(mobileSessionProvider).asData?.value;
      if (session == null || !session.hasShop) {
        return const <ShopMembershipAccessRecord>[];
      }
      final all = await ref
          .read(backendApiClientProvider)
          .getShopMemberships(user: session.user);
      return all
          .where((m) => m.shopId != session.shopId)
          .toList(growable: false);
    });

final transferStockItemsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final session = ref.watch(mobileSessionProvider).asData?.value;
      if (session == null || !session.hasShop) {
        return const <Map<String, dynamic>>[];
      }
      final rows = await ref
          .read(backendApiClientProvider)
          .fetchInventoryItems(user: session.user, shopId: session.shopId!);
      // Nothing on the shelf cannot be sent, so keep it out of the picker rather
      // than letting the server reject it after the fact.
      return rows
          .where((r) => _qty(r['stock_on_hand']) > 0)
          .toList(growable: false);
    });

/// Moving stock between the owner's shops.
///
/// Built for the phone because that is where it actually happens: the person
/// receiving a transfer is standing at the back door with cartons, not sitting
/// at a desk. The two pending counts are the point of the screen — stock that
/// has left one shop and not reached the other used to be invisible.
class StockTransfersScreen extends ConsumerStatefulWidget {
  const StockTransfersScreen({super.key});

  @override
  ConsumerState<StockTransfersScreen> createState() =>
      _StockTransfersScreenState();
}

class _StockTransfersScreenState extends ConsumerState<StockTransfersScreen> {
  String? _busyId;

  bool _canMove(MobileSession session) =>
      session.isOwner || session.isAdmin || session.isManager;

  Future<void> _act(
    String transferId,
    Future<Map<String, dynamic>> Function(BackendApiClient, MobileSession) run,
    String failure,
  ) async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) return;

    setState(() => _busyId = transferId);
    try {
      await run(ref.read(backendApiClientProvider), session);
      ref.invalidate(stockTransfersProvider);
    } on BackendApiException catch (error) {
      if (mounted) _toast(error.message);
    } catch (_) {
      if (mounted) _toast(failure);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final async = ref.watch(stockTransfersProvider);
    final payload = async.asData?.value ?? const <String, dynamic>{};
    final transfers = (payload['transfers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final incoming = (payload['incoming_in_transit'] as num?)?.toInt() ?? 0;
    final outgoing = (payload['outgoing_in_transit'] as num?)?.toInt() ?? 0;
    final canMove = session != null && _canMove(session);

    return MobileStandaloneScaffold(
      title: 'Stock transfers',
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(stockTransfersProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: AppMetric(
                    label: 'To receive',
                    value: Text('$incoming'),
                    icon: Icons.call_received_rounded,
                    tone: incoming > 0 ? AppTone.warning : AppTone.info,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppMetric(
                    label: 'Sent, awaiting',
                    value: Text('$outgoing'),
                    icon: Icons.call_made_rounded,
                    tone: AppTone.info,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (canMove)
              FilledButton.icon(
                onPressed: () => _openComposer(context),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Send stock to another shop'),
              ),
            const SizedBox(height: 16),

            if (async.isLoading && transfers.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (async.hasError)
              AppPanel(
                title: 'Could not load transfers',
                child: Text(
                  'Check your connection and pull down to try again.',
                  style: TextStyle(color: colors.textSecondary),
                ),
              )
            else if (transfers.isEmpty)
              const AppPanel(
                title: 'Nothing in transit',
                child: AppEmptyState(
                  icon: Icons.swap_horiz_rounded,
                  title: 'No transfers yet',
                  body:
                      'Transfers move stock between your shops. Nothing '
                      'arrives until the receiving shop confirms it.',
                ),
              )
            else
              ...transfers.map(
                (t) => _TransferCard(
                  transfer: t,
                  activeShopId: session?.shopId ?? '',
                  canMove: canMove,
                  busy: _busyId == (t['id'] ?? '').toString(),
                  onReceive: () => _act(
                    (t['id'] ?? '').toString(),
                    (client, s) => client.receiveStockTransfer(
                      user: s.user,
                      shopId: s.shopId!,
                      transferId: (t['id'] ?? '').toString(),
                    ),
                    'Could not confirm this delivery.',
                  ),
                  onCancel: () => _act(
                    (t['id'] ?? '').toString(),
                    (client, s) => client.cancelStockTransfer(
                      user: s.user,
                      shopId: s.shopId!,
                      transferId: (t['id'] ?? '').toString(),
                    ),
                    'Could not cancel this transfer.',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openComposer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _TransferComposerSheet(),
    ).then((_) => ref.invalidate(stockTransfersProvider));
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.transfer,
    required this.activeShopId,
    required this.canMove,
    required this.busy,
    required this.onReceive,
    required this.onCancel,
  });

  final Map<String, dynamic> transfer;
  final String activeShopId;
  final bool canMove;
  final bool busy;
  final VoidCallback onReceive;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final status = (transfer['status'] ?? '').toString();
    final pending = status == 'in_transit';
    final source = transfer['source_shop'] as Map<String, dynamic>? ?? const {};
    final destination =
        transfer['destination_shop'] as Map<String, dynamic>? ?? const {};
    final isIncoming = (destination['id'] ?? '').toString() == activeShopId;
    final lines = (transfer['lines'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    final (String label, AppTone accent) = switch (status) {
      'in_transit' => ('IN TRANSIT', AppTone.warning),
      'received' => ('RECEIVED', AppTone.success),
      _ => ('CANCELLED', AppTone.danger),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppPanel(
        title: (transfer['reference'] ?? '').toString(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                AppTag(label: label, tone: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${source['name'] ?? ''} → ${destination['name'] ?? ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        (line['name'] ?? '').toString(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${_showQty(line['quantity'])} ${line['unit'] ?? ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (pending && canMove) ...<Widget>[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: isIncoming
                    ? FilledButton.icon(
                        onPressed: busy ? null : onReceive,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(busy ? 'Receiving…' : 'Receive'),
                      )
                    : OutlinedButton.icon(
                        onPressed: busy ? null : onCancel,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: Text(busy ? 'Cancelling…' : 'Cancel transfer'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compose and dispatch: pick a destination shop, then items and quantities.
class _TransferComposerSheet extends ConsumerStatefulWidget {
  const _TransferComposerSheet();

  @override
  ConsumerState<_TransferComposerSheet> createState() =>
      _TransferComposerSheetState();
}

class _TransferComposerSheetState
    extends ConsumerState<_TransferComposerSheet> {
  String? _destinationId;
  final Map<String, TextEditingController> _quantities =
      <String, TextEditingController>{};
  final TextEditingController _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(String itemId) =>
      _quantities.putIfAbsent(itemId, TextEditingController.new);

  Future<void> _send(List<Map<String, dynamic>> items) async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) return;

    if (_destinationId == null || _destinationId!.isEmpty) {
      _toast('Choose which shop the stock is going to.');
      return;
    }

    final lines = <Map<String, dynamic>>[];
    for (final item in items) {
      final id = (item['id'] ?? '').toString();
      final raw = _quantities[id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final quantity = double.tryParse(raw);
      if (quantity == null || quantity <= 0) continue;
      // Catch the common mistake here rather than after a round trip.
      if (quantity > _qty(item['stock_on_hand'])) {
        _toast(
          '${item['name']}: only ${_showQty(item['stock_on_hand'])} in stock.',
        );
        return;
      }
      lines.add(<String, dynamic>{'item_id': id, 'quantity': raw});
    }

    if (lines.isEmpty) {
      _toast('Enter how much of at least one item to send.');
      return;
    }

    setState(() => _sending = true);
    try {
      await ref
          .read(backendApiClientProvider)
          .dispatchStockTransfer(
            user: session.user,
            shopId: session.shopId!,
            destinationShopId: _destinationId!,
            lines: lines,
            note: _note.text,
          );
      if (mounted) Navigator.of(context).pop();
    } on BackendApiException catch (error) {
      if (mounted) _toast(error.message);
    } catch (_) {
      if (mounted) _toast('Could not send the stock.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final destinations =
        ref.watch(transferDestinationsProvider).asData?.value ??
        const <ShopMembershipAccessRecord>[];
    final items =
        ref.watch(transferStockItemsProvider).asData?.value ??
        const <Map<String, dynamic>>[];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: <Widget>[
          const AppSheetHeader(
            title: 'Send stock',
            subtitle:
                'The stock leaves this shop now. It only appears at the '
                'other shop once someone there confirms it arrived.',
            icon: Icons.local_shipping_outlined,
          ),
          const SizedBox(height: 16),

          if (destinations.isEmpty)
            AppPanel(
              title: 'Nowhere to send it',
              child: Text(
                'Transfers move stock between your shops. This account is a '
                'member of only one shop.',
                style: TextStyle(color: colors.textSecondary),
              ),
            )
          else ...<Widget>[
            DropdownButtonFormField<String>(
              initialValue: _destinationId,
              decoration: const InputDecoration(labelText: 'Send to'),
              items: destinations
                  .map(
                    (m) => DropdownMenuItem<String>(
                      value: m.shopId,
                      child: Text(m.shopName),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) => setState(() => _destinationId = value),
            ),
            const SizedBox(height: 16),
            Text(
              'How much of each item',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Text(
                'Nothing in stock to send.',
                style: TextStyle(color: colors.textSecondary),
              )
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              (item['name'] ?? '').toString(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_showQty(item['stock_on_hand'])} in stock',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 84,
                        child: TextField(
                          controller: _controllerFor(
                            (item['id'] ?? '').toString(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(hintText: 'Qty'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Sent with the afternoon van',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _sending ? null : () => _send(items),
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(_sending ? 'Sending…' : 'Send stock'),
            ),
          ],
        ],
      ),
    );
  }
}

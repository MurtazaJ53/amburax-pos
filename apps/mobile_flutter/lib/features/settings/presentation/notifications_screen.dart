import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../shell/presentation/mobile_surface.dart';

/// One alert, as the server records it.
class ShopNotification {
  const ShopNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });

  factory ShopNotification.fromJson(Map<String, dynamic> json) =>
      ShopNotification(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        message: '${json['message'] ?? ''}',
        type: '${json['type'] ?? ''}'.toLowerCase(),
        isRead: json['is_read'] == true,
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      );

  final String id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime? createdAt;
}

/// How long ago, in the words someone says out loud.
///
/// An absolute timestamp on an alert feed makes the reader do arithmetic to
/// answer the only question they have, which is whether this is still current.
String relativeTime(DateTime? when, {DateTime? now}) {
  if (when == null) return '';
  final moment = now ?? DateTime.now();
  final gap = moment.difference(when);
  if (gap.isNegative || gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
  if (gap.inHours < 24) return '${gap.inHours} hr ago';
  if (gap.inDays == 1) return 'yesterday';
  if (gap.inDays < 7) return '${gap.inDays} days ago';
  return '${(gap.inDays / 7).floor()} wk ago';
}

/// The colour an alert carries, by what it is about.
///
/// Semantic rather than decorative: a stock warning and a takings summary are
/// different kinds of news, and a feed where everything looks the same is one
/// nobody scans.
Color toneFor(BuildContext context, String type) {
  switch (type) {
    case 'stock':
    case 'warning':
      return AppPalette.warning;
    case 'error':
    case 'alert':
      return AppPalette.error;
    case 'sales':
    case 'success':
      return AppPalette.success;
    default:
      return AppColors.of(context).textTertiary;
  }
}

/// Unread first, then newest first.
///
/// Straight reverse-chronological buries an unread stock warning under a week
/// of read summaries, which is how a feed stops being read.
List<ShopNotification> sortForReading(List<ShopNotification> rows) {
  final sorted = [...rows];
  sorted.sort((a, b) {
    if (a.isRead != b.isRead) return a.isRead ? 1 : -1;
    final at = a.createdAt;
    final bt = b.createdAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return sorted;
}

final notificationsProvider =
    FutureProvider.autoDispose<List<ShopNotification>>((ref) async {
  final session = ref.watch(mobileSessionProvider).asData?.value;
  if (session == null || !session.hasShop) return const <ShopNotification>[];
  final rows = await ref.read(backendApiClientProvider).fetchNotifications(
        user: session.user,
        shopId: session.shopId!,
      );
  return sortForReading(rows.map(ShopNotification.fromJson).toList());
});

/// Alerts, on the device that is actually in the shopkeeper's hand.
///
/// The backend has been sending a 09:00 low-stock alert and a 21:00 takings
/// summary to owners since they were built, and until now the only place to
/// read one was the web admin. An alert nobody can see is a promise the
/// product was only half keeping.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _markAllRead() async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(backendApiClientProvider).markAllNotificationsRead(
            user: session.user,
            shopId: session.shopId!,
          );
      ref.invalidate(notificationsProvider);
    } on BackendApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update. Check the connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markRead(ShopNotification row) async {
    if (row.isRead) return;
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null) return;
    try {
      await ref.read(backendApiClientProvider).markNotificationRead(
            user: session.user,
            notificationId: row.id,
          );
      ref.invalidate(notificationsProvider);
    } catch (_) {
      // Marking one as read is incidental to reading it. Failing loudly here
      // would interrupt someone for something that costs nothing to retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final async = ref.watch(notificationsProvider);
    final rows = async.asData?.value ?? const <ShopNotification>[];
    final unread = rows.where((r) => !r.isRead).length;

    return MobileStandaloneScaffold(
      title: 'Alerts',
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(notificationsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            if (_error != null) ...<Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppPalette.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.error,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (unread > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '$unread unread',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _markAllRead(),
                    child: Text(_busy ? 'Marking…' : 'Mark all read'),
                  ),
                ],
              ),
            if (async.isLoading && rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 42,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Nothing yet',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Low stock lands here at 9 in the morning, and the day’s '
                      'takings at 9 at night.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final row in rows)
                _NotificationRow(row: row, onTap: () => _markRead(row)),
          ],
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.row, required this.onTap});

  final ShopNotification row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tone = toneFor(context, row.type);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          // Unread sits on the raised surface and keeps its stripe; read fades
          // back so the eye lands on what has not been dealt with.
          color: row.isRead ? colors.backgroundSoft : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: tone, width: row.isRead ? 0 : 3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    row.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: row.isRead ? FontWeight.w600 : FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (row.message.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      row.message,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              relativeTime(row.createdAt),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

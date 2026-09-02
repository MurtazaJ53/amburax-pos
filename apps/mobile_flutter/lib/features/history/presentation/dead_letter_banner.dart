import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart' show CommerceOutboxEntry;
import '../../../core/database/mobile_repository.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Red "needs attention" banner shown when the backend has permanently rejected
/// one or more offline sales (dead-letter queue). Tapping opens a resolution
/// sheet where the owner can force-retry or discard each rejected sale — so a
/// bad command never silently loses a sale without anyone noticing.
class DeadLetterBanner extends ConsumerWidget {
  const DeadLetterBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(deadLetterCountProvider).asData?.value ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: AppPalette.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _openResolution(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppPalette.error.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.error_rounded, color: AppPalette.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$count sale${count == 1 ? '' : 's'} rejected by the server — '
                    'tap to review & resolve.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
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

  void _openResolution(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DeadLetterSheet(),
    );
  }
}

class _DeadLetterSheet extends ConsumerWidget {
  const _DeadLetterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final entries =
        ref.watch(deadLetterEntriesProvider).asData?.value ??
        const <CommerceOutboxEntry>[];
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Rejected sales',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'The backend rejected these permanently (usually a data issue). '
                'Force-retry if the cause is fixed, or discard to stop the alert.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Text('All resolved 🎉'))
                    : ListView.separated(
                        controller: controller,
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) =>
                            _DeadLetterRow(entry: entries[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DeadLetterRow extends ConsumerWidget {
  const _DeadLetterRow({required this.entry});

  final CommerceOutboxEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final repo = ref.read(salesRepositoryProvider);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${entry.commandType} · ${entry.commandId}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            entry.deadLetterReason ?? 'Rejected by the backend.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              TextButton.icon(
                onPressed: () async {
                  await repo.retryDeadLetter(entry.commandId);
                  await ref
                      .read(mobileSyncCoordinatorProvider)
                      .retryCommerceCommand(entry.commandId);
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Force retry'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => repo.discardDeadLetter(entry.commandId),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppPalette.error,
                ),
                label: const Text(
                  'Discard',
                  style: TextStyle(color: AppPalette.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

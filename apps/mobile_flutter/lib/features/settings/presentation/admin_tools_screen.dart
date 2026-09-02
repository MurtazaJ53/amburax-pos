import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

/// Owner/admin-only advanced tooling, kept out of everyday settings.
class AdminToolsScreen extends ConsumerWidget {
  const AdminToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final pending = ref.watch(pendingOutboxCountProvider).asData?.value ?? 0;
    final syncCoordinator = ref.watch(mobileSyncCoordinatorProvider);

    return MobileStandaloneScaffold(
      title: 'Admin tools',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          MobileScreenLead(
            title: 'Admin tools',
            subtitle: 'Advanced operations for owners and admins.',
            icon: Icons.tune_rounded,
            accent: colors.textTertiary,
          ),
          const SizedBox(height: 22),
          MobileListTile(
            title: 'Workspace pulse',
            subtitle: 'Tasks and anomaly signals',
            leadingIcon: Icons.monitor_heart_rounded,
            onTap: () => context.push('/settings/pulse'),
          ),
          MobileListTile(
            title: 'Device sessions',
            subtitle: 'Trusted devices and remote wipe',
            leadingIcon: Icons.devices_rounded,
            onTap: () => context.push('/settings/sessions'),
          ),
          MobileListTile(
            title: 'Advanced ops',
            subtitle: 'Recovery, rollout and technical tools',
            leadingIcon: Icons.settings_suggest_rounded,
            onTap: () => context.push('/settings/advanced'),
          ),
          const SizedBox(height: 22),
          AppPanel(
            title: 'Sync',
            action: MobileTag(
              label: pending > 0 ? '$pending queued' : 'Clear',
              icon: pending > 0
                  ? Icons.cloud_upload_rounded
                  : Icons.check_circle_rounded,
              accent: pending > 0 ? AppPalette.warning : AppPalette.success,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  pending > 0
                      ? '$pending receipt${pending == 1 ? '' : 's'} waiting to sync.'
                      : 'All receipts are synced.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Syncing with cloud...')),
                    );
                    final result = await syncCoordinator.syncNow();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result.message ?? 'Sync complete.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.cloud_sync_rounded),
                  label: const Text('Sync with cloud now'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pushes queued sales and pulls the latest products & '
                  'customers from other devices. Needs the backend reachable '
                  'on your network.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.of(context).textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

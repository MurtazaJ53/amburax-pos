import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/database/mobile_repository.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/models/mobile_session.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/utils/formatters.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

class SettingsSessionsScreen extends ConsumerStatefulWidget {
  const SettingsSessionsScreen({super.key});

  @override
  ConsumerState<SettingsSessionsScreen> createState() =>
      _SettingsSessionsScreenState();
}

class _SettingsSessionsScreenState
    extends ConsumerState<SettingsSessionsScreen> {
  String? _message;
  bool _messageIsError = false;
  String? _busySessionId;
  bool _signingOutAll = false;

  Future<void> _signOutAllOthers(MobileSession session) async {
    setState(() => _signingOutAll = true);
    try {
      final keep = await ref.read(shopRepositoryProvider).ensureAppInstanceId();
      final count = await ref
          .read(backendApiClientProvider)
          .revokeAllWorkspaceSessions(
            user: session.user,
            shopId: session.shopId!,
            keepAppInstanceId: keep,
          );
      await _refreshSessions();
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Signed out $count other device(s).';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = 'Could not sign out all devices. Try again.';
      });
    } finally {
      if (mounted) setState(() => _signingOutAll = false);
    }
  }

  Future<void> _refreshSessions() async {
    ref.invalidate(workspaceAccessSessionsProvider);
    ref.invalidate(workspacePulseProvider);
    ref.invalidate(workspacePulseSignalsProvider);
    await ref.read(workspaceAccessSessionsProvider.future);
  }

  Future<void> _applyAction({
    required MobileSession session,
    required WorkspaceAccessSessionRecord record,
    required String action,
    required String successMessage,
    String note = '',
  }) async {
    if (_busySessionId != null) {
      return;
    }
    // (revoke-all handler lives just below _runSessionAction)
    setState(() {
      _busySessionId = record.id;
      _message = null;
      _messageIsError = false;
    });
    try {
      await ref
          .read(backendApiClientProvider)
          .updateWorkspaceAccessSession(
            user: session.user,
            shopId: session.shopId!,
            sessionId: record.id,
            action: action,
            note: note,
          );
      await _refreshSessions();
      if (!mounted) {
        return;
      }
      setState(() {
        _messageIsError = false;
        _message = successMessage;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messageIsError = true;
        _message = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busySessionId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final verifiedUntil = ref
        .watch(mobileMfaVerifiedUntilProvider)
        .asData
        ?.value;
    final hasFreshSecurityWindow =
        verifiedUntil != null && verifiedUntil.isAfter(DateTime.now());
    final sessionsAsync = ref.watch(workspaceAccessSessionsProvider);
    final sessions =
        sessionsAsync.asData?.value ?? const <WorkspaceAccessSessionRecord>[];
    final trustedCount = sessions
        .where((item) => item.isActive && item.isTrusted && !item.wipeRequested)
        .length;
    final reviewCount = sessions
        .where((item) => item.isActive && item.needsReview)
        .length;
    final riskyCount = sessions
        .where((item) => item.isRisky || item.wipeRequested)
        .length;

    if (session == null) {
      return MobileStandaloneScaffold(
        title: 'Sessions',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            AppPanel(
              title: 'Loading session control',
              child: AppEmptyState(
                icon: Icons.sync_rounded,
                title: 'Checking workspace access',
                body:
                    'Business Hub is loading the signed-in owner/admin account before opening device session controls.',
              ),
            ),
          ],
        ),
      );
    }

    if (!session.isOwnerLike) {
      return MobileStandaloneScaffold(
        title: 'Sessions',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            AppPanel(
              title: 'Owner/admin only',
              child: AppEmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Session control stays elevated',
                body:
                    'Daily operators should stay focused on selling and stock work. Device-session control stays limited to workspace owners and admins.',
              ),
            ),
          ],
        ),
      );
    }

    return MobileStandaloneScaffold(
      title: 'Sessions',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          MobileScreenLead(
            title: 'Review workspace devices',
            subtitle:
                'See which phones are trusted, which need review, and revoke or wipe access when a device should no longer touch this workspace.',
            icon: Icons.devices_rounded,
            accent: AppPalette.primary,
            primaryTag: MobileTag(
              label: '${sessions.length} known',
              icon: Icons.smartphone_rounded,
              accent: AppPalette.primary,
            ),
            secondaryTag: MobileTag(
              label: riskyCount > 0 ? '$riskyCount risky' : 'Trust stable',
              icon: riskyCount > 0
                  ? Icons.crisis_alert_rounded
                  : Icons.verified_rounded,
              accent: riskyCount > 0 ? AppPalette.error : AppPalette.success,
            ),
          ),
          const SizedBox(height: 12),
          if (session.isOwnerLike && sessions.length > 1)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _signingOutAll
                    ? null
                    : () => _signOutAllOthers(session),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.error,
                  side: const BorderSide(color: AppPalette.error),
                ),
                icon: _signingOutAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_rounded),
                label: Text(
                  _signingOutAll
                      ? 'Signing out…'
                      : 'Sign out all other devices',
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (!hasFreshSecurityWindow)
            AppPanel(
              title: 'Security check required',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Verify MFA from Security before revoking, restoring, or remotely wiping mobile device access.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black.withValues(alpha: 0.72),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      context.push('/settings/security');
                    },
                    icon: const Icon(Icons.security_rounded),
                    label: const Text('Open security'),
                  ),
                ],
              ),
            )
          else ...<Widget>[
            if (_message != null) ...<Widget>[
              AppPanel(
                title: _messageIsError
                    ? 'Session action failed'
                    : 'Session updated',
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
            AppPanel(
              title: 'Session posture',
              action: FilledButton.tonalIcon(
                onPressed: _busySessionId == null ? _refreshSessions : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  MobileTag(
                    label: '$trustedCount trusted',
                    icon: Icons.verified_rounded,
                    accent: AppPalette.success,
                  ),
                  MobileTag(
                    label: '$reviewCount review',
                    icon: Icons.visibility_rounded,
                    accent: AppPalette.warning,
                  ),
                  MobileTag(
                    label: '$riskyCount risky',
                    icon: Icons.crisis_alert_rounded,
                    accent: AppPalette.error,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AppPanel(
              title: 'Workspace devices',
              action: MobileTag(
                label: sessions.isEmpty
                    ? 'No sessions'
                    : '${sessions.length} devices',
                icon: Icons.devices_rounded,
                accent: AppPalette.primary,
              ),
              child: sessionsAsync.isLoading
                  ? const AppEmptyState(
                      icon: Icons.sync_rounded,
                      title: 'Refreshing device sessions',
                      body:
                          'Business Hub is loading the latest mobile device access posture for this workspace.',
                    )
                  : sessions.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.smartphone_rounded,
                      title: 'No mobile sessions yet',
                      body:
                          'No mobile device has checked in for this workspace yet.',
                    )
                  : Column(
                      children: sessions
                          .map(
                            (record) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _WorkspaceSessionCard(
                                record: record,
                                busy: _busySessionId == record.id,
                                onRevoke:
                                    record.canManage &&
                                        record.isActive &&
                                        !record.wipeRequested
                                    ? () => _applyAction(
                                        session: session,
                                        record: record,
                                        action: 'revoke',
                                        note: 'Revoked from mobile sessions.',
                                        successMessage:
                                            '${record.deviceLabel} can no longer use this workspace.',
                                      )
                                    : null,
                                onRequestWipe:
                                    record.canManage && !record.wipeRequested
                                    ? () => _applyAction(
                                        session: session,
                                        record: record,
                                        action: 'request_wipe',
                                        note:
                                            'Requested remote wipe from mobile sessions.',
                                        successMessage:
                                            '${record.deviceLabel} will clear local workspace data when it comes online.',
                                      )
                                    : null,
                                onRestore: record.canManage && record.isRevoked
                                    ? () => _applyAction(
                                        session: session,
                                        record: record,
                                        action: 'restore',
                                        note: 'Restored from mobile sessions.',
                                        successMessage:
                                            '${record.deviceLabel} can use the workspace again.',
                                      )
                                    : null,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceSessionCard extends StatelessWidget {
  const _WorkspaceSessionCard({
    required this.record,
    required this.busy,
    this.onRevoke,
    this.onRequestWipe,
    this.onRestore,
  });

  final WorkspaceAccessSessionRecord record;
  final bool busy;
  final VoidCallback? onRevoke;
  final VoidCallback? onRequestWipe;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final subtitle = record.memberEmail.trim().isEmpty
        ? record.roleLabel
        : '${record.memberEmail} | ${record.roleLabel}';
    final lastSeen = record.lastSeenAt == null
        ? 'No recent check-in'
        : 'Last seen ${formatCompactDate(record.lastSeenAt!)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              record.deviceLabel,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '${record.memberName} | $subtitle',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black.withValues(alpha: 0.66),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                MobileTag(
                  label: record.status.toUpperCase(),
                  icon: record.isActive
                      ? Icons.wifi_tethering_rounded
                      : Icons.block_rounded,
                  accent: record.isActive
                      ? AppPalette.success
                      : AppPalette.error,
                ),
                MobileTag(
                  label: record.trustLevel.toUpperCase(),
                  icon: _trustIcon(record.trustLevel),
                  accent: _trustColor(record.trustLevel),
                ),
                MobileTag(
                  label: 'Score ${record.trustScore}',
                  icon: Icons.speed_rounded,
                  accent: AppPalette.primary,
                ),
                if (record.wipeRequested)
                  const MobileTag(
                    label: 'WIPE PENDING',
                    icon: Icons.delete_sweep_rounded,
                    accent: AppPalette.error,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              record.trustSummary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.black.withValues(alpha: 0.76),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              lastSeen,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black.withValues(alpha: 0.56),
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (record.ipAddress.trim().isNotEmpty)
              Text(
                'IP ${record.ipAddress}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black.withValues(alpha: 0.5),
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            if (record.platformName.trim().isNotEmpty ||
                record.appVersion.trim().isNotEmpty ||
                record.releaseChannel.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _deviceMetaLine(record),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black.withValues(alpha: 0.56),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
            if (record.revokeReason?.trim().isNotEmpty == true) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Reason: ${record.revokeReason}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black.withValues(alpha: 0.64),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
            if (record.trustReasons.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              ...record.trustReasons
                  .take(3)
                  .map(
                    (reason) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '- $reason',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 430;
                final actions = <Widget>[
                  if (onRevoke != null)
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onRevoke,
                      icon: const Icon(Icons.block_rounded),
                      label: const Text('Revoke'),
                    ),
                  if (onRequestWipe != null)
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onRequestWipe,
                      icon: const Icon(Icons.delete_sweep_rounded),
                      label: const Text('Revoke and wipe'),
                    ),
                  if (onRestore != null)
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onRestore,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Restore'),
                    ),
                ];

                if (actions.isEmpty) {
                  return Text(
                    'This device is outside your current session-control scope.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black.withValues(alpha: 0.56),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  );
                }

                if (stacked) {
                  return Column(
                    children: actions
                        .expand(
                          (widget) => <Widget>[
                            SizedBox(width: double.infinity, child: widget),
                            if (widget != actions.last)
                              const SizedBox(height: 10),
                          ],
                        )
                        .toList(growable: false),
                  );
                }

                return Row(
                  children: actions
                      .expand(
                        (widget) => <Widget>[
                          Expanded(child: widget),
                          if (widget != actions.last) const SizedBox(width: 10),
                        ],
                      )
                      .toList(growable: false),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _deviceMetaLine(WorkspaceAccessSessionRecord record) {
  final parts = <String>[
    if (record.platformName.trim().isNotEmpty) record.platformName.trim(),
    if (record.appVersion.trim().isNotEmpty) 'v${record.appVersion.trim()}',
    if (record.releaseChannel.trim().isNotEmpty)
      record.releaseChannel.trim().toUpperCase(),
  ];
  if (parts.isEmpty) {
    return 'Device metadata unavailable';
  }
  return parts.join(' | ');
}

Color _trustColor(String level) {
  switch (level.trim().toLowerCase()) {
    case 'trusted':
      return AppPalette.success;
    case 'review':
      return AppPalette.warning;
    case 'risky':
    case 'blocked':
      return AppPalette.error;
    default:
      return AppPalette.primary;
  }
}

IconData _trustIcon(String level) {
  switch (level.trim().toLowerCase()) {
    case 'trusted':
      return Icons.verified_rounded;
    case 'review':
      return Icons.visibility_rounded;
    case 'risky':
      return Icons.report_problem_rounded;
    case 'blocked':
      return Icons.block_rounded;
    default:
      return Icons.devices_rounded;
  }
}

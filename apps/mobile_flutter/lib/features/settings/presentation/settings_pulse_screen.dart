import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/models/mobile_session.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/utils/formatters.dart';
import '../../shell/presentation/mobile_surface.dart';

class SettingsPulseScreen extends ConsumerStatefulWidget {
  const SettingsPulseScreen({super.key});

  @override
  ConsumerState<SettingsPulseScreen> createState() =>
      _SettingsPulseScreenState();
}

class _SettingsPulseScreenState extends ConsumerState<SettingsPulseScreen> {
  String? _message;
  bool _messageIsError = false;
  String? _busySignalId;

  Future<void> _refreshDesk() async {
    ref.invalidate(workspacePulseProvider);
    ref.invalidate(workspacePulseSignalsProvider);
    await ref.read(workspacePulseProvider.future);
  }

  Future<void> _applySignalAction({
    required MobileSession session,
    required WorkspacePulseSignal signal,
    required String action,
    String note = '',
  }) async {
    if (_busySignalId != null) {
      return;
    }
    setState(() {
      _busySignalId = signal.id;
      _message = null;
      _messageIsError = false;
    });
    try {
      await ref
          .read(backendApiClientProvider)
          .updateWorkspacePulseSignal(
            user: session.user,
            shopId: session.shopId!,
            signalId: signal.id,
            action: action,
            note: note,
          );
      await _refreshDesk();
      if (!mounted) {
        return;
      }
      setState(() {
        _messageIsError = false;
        _message = switch (action) {
          'acknowledge' => '${signal.title} acknowledged.',
          'resolve' => '${signal.title} resolved.',
          'reopen' => '${signal.title} reopened.',
          _ => '${signal.title} updated.',
        };
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
          _busySignalId = null;
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
    final pulseAsync = ref.watch(workspacePulseProvider);
    final signalsAsync = ref.watch(workspacePulseSignalsProvider);
    final pulse = pulseAsync.asData?.value;
    final signals =
        signalsAsync.asData?.value ?? const <WorkspacePulseSignal>[];
    final openSignals = signals
        .where((signal) => signal.status != 'resolved')
        .toList(growable: false);
    final resolvedSignals = signals
        .where((signal) => signal.status == 'resolved')
        .take(6)
        .toList(growable: false);

    if (session == null) {
      return MobileStandaloneScaffold(
        title: 'Pulse desk',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            MobilePanel(
              title: 'Loading pulse desk',
              child: MobileEmptyState(
                icon: Icons.sync_rounded,
                title: 'Checking owner access',
                body:
                    'Business Hub is loading the current signed-in owner/admin account before opening the pulse desk.',
              ),
            ),
          ],
        ),
      );
    }

    if (!session.isOwnerLike) {
      return MobileStandaloneScaffold(
        title: 'Pulse desk',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            MobilePanel(
              title: 'Owner/admin only',
              child: MobileEmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Pulse stays with elevated roles',
                body:
                    'Daily operators should stay inside selling and stock work. Workspace pulse is reserved for owner/admin follow-up.',
              ),
            ),
          ],
        ),
      );
    }

    return MobileStandaloneScaffold(
      title: 'Pulse desk',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          MobileScreenLead(
            title: 'Track live owner tasks',
            subtitle:
                'Acknowledge, resolve, or reopen workspace signals before stock, sync, or behavior issues spread into the day.',
            icon: Icons.auto_awesome_rounded,
            accent: AppPalette.primary,
            primaryTag: MobileTag(
              label: openSignals.isEmpty
                  ? 'Desk calm'
                  : '${openSignals.length} open',
              icon: openSignals.isEmpty
                  ? Icons.check_circle_rounded
                  : Icons.notification_important_rounded,
              accent: openSignals.isEmpty
                  ? AppPalette.success
                  : AppPalette.primary,
            ),
            secondaryTag: MobileTag(
              label: pulse == null
                  ? (pulseAsync.isLoading ? 'Refreshing' : 'Unavailable')
                  : pulse.stats.criticalAnomalyCount > 0
                  ? '${pulse.stats.criticalAnomalyCount} critical'
                  : '${pulse.stats.warningAnomalyCount} watch',
              icon: pulse == null
                  ? Icons.sync_rounded
                  : pulse.stats.criticalAnomalyCount > 0
                  ? Icons.crisis_alert_rounded
                  : Icons.monitor_heart_rounded,
              accent: pulse == null
                  ? AppPalette.primary
                  : pulse.stats.criticalAnomalyCount > 0
                  ? AppPalette.error
                  : AppPalette.warning,
            ),
          ),
          const SizedBox(height: 18),
          if (!hasFreshSecurityWindow)
            MobilePanel(
              title: 'Security check required',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Verify MFA from Security before opening pulse controls on mobile. This keeps owner/admin signal control behind a real second factor.',
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
              MobilePanel(
                title: _messageIsError
                    ? 'Pulse control failed'
                    : 'Pulse updated',
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
              title: 'Pulse headline',
              action: FilledButton.tonalIcon(
                onPressed: _busySignalId == null ? _refreshDesk : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
              child: pulse == null
                  ? MobileEmptyState(
                      icon: pulseAsync.isLoading
                          ? Icons.sync_rounded
                          : Icons.wifi_tethering_error_rounded,
                      title: pulseAsync.isLoading
                          ? 'Refreshing workspace pulse'
                          : 'Pulse is unavailable',
                      body: pulseAsync.isLoading
                          ? 'Business Hub is rebuilding the current workspace pulse snapshot.'
                          : 'The backend pulse snapshot could not be loaded right now.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          pulse.headline.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          pulse.headline.body,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.black.withValues(alpha: 0.72),
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            MobileTag(
                              label: '${pulse.stats.openTaskCount} tasks',
                              icon: Icons.assignment_late_rounded,
                              accent: AppPalette.primary,
                            ),
                            MobileTag(
                              label:
                                  '${pulse.stats.criticalAnomalyCount} critical',
                              icon: Icons.crisis_alert_rounded,
                              accent: pulse.stats.criticalAnomalyCount > 0
                                  ? AppPalette.error
                                  : AppPalette.success,
                            ),
                            MobileTag(
                              label:
                                  '${pulse.stats.warningAnomalyCount} warning',
                              icon: Icons.warning_amber_rounded,
                              accent: pulse.stats.warningAnomalyCount > 0
                                  ? AppPalette.warning
                                  : AppPalette.success,
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            MobilePanel(
              title: 'Open pulse desk',
              action: MobileTag(
                label: openSignals.isEmpty
                    ? 'Clear'
                    : '${openSignals.length} active',
                icon: openSignals.isEmpty
                    ? Icons.done_all_rounded
                    : Icons.priority_high_rounded,
                accent: openSignals.isEmpty
                    ? AppPalette.success
                    : AppPalette.primary,
              ),
              child: signalsAsync.isLoading
                  ? const MobileEmptyState(
                      icon: Icons.sync_rounded,
                      title: 'Refreshing pulse signals',
                      body:
                          'Business Hub is loading the latest acknowledged, open, and resolved signals for this workspace.',
                    )
                  : openSignals.isEmpty
                  ? const MobileEmptyState(
                      icon: Icons.verified_rounded,
                      title: 'No open pulse signals',
                      body:
                          'Everything that was previously flagged is either calm or already resolved.',
                    )
                  : Column(
                      children: openSignals
                          .map(
                            (signal) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PulseSignalCard(
                                signal: signal,
                                busy: _busySignalId == signal.id,
                                onAcknowledge: signal.isOpen
                                    ? () => _applySignalAction(
                                        session: session,
                                        signal: signal,
                                        action: 'acknowledge',
                                      )
                                    : null,
                                onResolve: !signal.isResolved
                                    ? () => _applySignalAction(
                                        session: session,
                                        signal: signal,
                                        action: 'resolve',
                                        note:
                                            'Resolved from mobile pulse desk.',
                                      )
                                    : null,
                                onEscalate: !signal.isEscalated
                                    ? () => _applySignalAction(
                                        session: session,
                                        signal: signal,
                                        action: 'escalate',
                                        note:
                                            'Escalated from mobile pulse desk.',
                                      )
                                    : null,
                                onDeescalate: signal.isEscalated
                                    ? () => _applySignalAction(
                                        session: session,
                                        signal: signal,
                                        action: 'deescalate',
                                        note:
                                            'Escalation lowered from mobile pulse desk.',
                                      )
                                    : null,
                                onReopen: signal.isResolved
                                    ? () => _applySignalAction(
                                        session: session,
                                        signal: signal,
                                        action: 'reopen',
                                      )
                                    : null,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
            ),
            const SizedBox(height: 18),
            MobilePanel(
              title: 'Recently resolved',
              action: MobileTag(
                label: '${resolvedSignals.length} shown',
                icon: Icons.task_alt_rounded,
                accent: AppPalette.success,
              ),
              child: resolvedSignals.isEmpty
                  ? const MobileEmptyState(
                      icon: Icons.inbox_rounded,
                      title: 'No resolved signals yet',
                      body:
                          'Resolved pulse items will appear here once owner/admin follow-up begins.',
                    )
                  : Column(
                      children: resolvedSignals
                          .map(
                            (signal) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PulseSignalCard(
                                signal: signal,
                                busy: _busySignalId == signal.id,
                                onAcknowledge: null,
                                onResolve: null,
                                onEscalate: null,
                                onDeescalate: signal.isEscalated
                                    ? () => _applySignalAction(
                                        session: session,
                                        signal: signal,
                                        action: 'deescalate',
                                        note:
                                            'Escalation lowered from mobile pulse desk.',
                                      )
                                    : null,
                                onReopen: () => _applySignalAction(
                                  session: session,
                                  signal: signal,
                                  action: 'reopen',
                                ),
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

class _PulseSignalCard extends StatelessWidget {
  const _PulseSignalCard({
    required this.signal,
    required this.busy,
    this.onAcknowledge,
    this.onResolve,
    this.onEscalate,
    this.onDeescalate,
    this.onReopen,
  });

  final WorkspacePulseSignal signal;
  final bool busy;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onResolve;
  final VoidCallback? onEscalate;
  final VoidCallback? onDeescalate;
  final VoidCallback? onReopen;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        signal.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        signal.body,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black.withValues(alpha: 0.66),
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                MobileTag(
                  label: signal.signalKind.toUpperCase(),
                  icon: signal.signalKind == 'anomaly'
                      ? Icons.crisis_alert_rounded
                      : Icons.assignment_late_rounded,
                  accent: signal.signalKind == 'anomaly'
                      ? _signalLevelColor(signal.signalLevel)
                      : AppPalette.primary,
                ),
                MobileTag(
                  label: signal.status.toUpperCase(),
                  icon: signal.isResolved
                      ? Icons.task_alt_rounded
                      : signal.isAcknowledged
                      ? Icons.visibility_rounded
                      : Icons.priority_high_rounded,
                  accent: signal.isResolved
                      ? AppPalette.success
                      : signal.isAcknowledged
                      ? AppPalette.primary
                      : _signalLevelColor(signal.signalLevel),
                ),
                MobileTag(
                  label: signal.signalLevel.toUpperCase(),
                  icon: Icons.flag_rounded,
                  accent: _signalLevelColor(signal.signalLevel),
                ),
                if (signal.isEscalated)
                  const MobileTag(
                    label: 'ESCALATED',
                    icon: Icons.vertical_align_top_rounded,
                    accent: AppPalette.error,
                  ),
                if (signal.assignedMemberName != null)
                  MobileTag(
                    label:
                        '${signal.assignedMemberName}  ·  ${_roleLabel(signal.assignedMemberRole)}',
                    icon: Icons.person_pin_circle_rounded,
                    accent: AppPalette.primary,
                  ),
                if (signal.metricValue.isNotEmpty)
                  MobileTag(
                    label: signal.metricValue,
                    icon: Icons.speed_rounded,
                    accent: AppPalette.warning,
                  ),
                if (signal.count > 0)
                  MobileTag(
                    label: 'Count ${signal.count}',
                    icon: Icons.format_list_numbered_rounded,
                    accent: AppPalette.info,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _signalMetaLine(signal),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black.withValues(alpha: 0.56),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            if (signal.resolutionNote.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Note: ${signal.resolutionNote}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black.withValues(alpha: 0.64),
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
            if (signal.followUpNote.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Follow-up: ${signal.followUpNote}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black.withValues(alpha: 0.64),
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
            if (signal.escalationNote.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Escalation: ${signal.escalationNote}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black.withValues(alpha: 0.64),
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 430;
                final actions = <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: busy
                        ? null
                        : () {
                            context.go(_resolvePulseRoute(signal.route));
                          },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(signal.ctaLabel),
                  ),
                  if (onAcknowledge != null)
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onAcknowledge,
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('Acknowledge'),
                    ),
                  if (onResolve != null)
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onResolve,
                      icon: const Icon(Icons.task_alt_rounded),
                      label: const Text('Resolve'),
                    ),
                  if (onEscalate != null)
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onEscalate,
                      icon: const Icon(Icons.vertical_align_top_rounded),
                      label: const Text('Escalate'),
                    ),
                  if (onDeescalate != null)
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onDeescalate,
                      icon: const Icon(Icons.vertical_align_bottom_rounded),
                      label: const Text('Lower alert'),
                    ),
                  if (onReopen != null)
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onReopen,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Reopen'),
                    ),
                ];

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

String _signalMetaLine(WorkspacePulseSignal signal) {
  final statusLine = switch (signal.status) {
    'resolved' =>
      'Resolved ${_formatSignalDate(signal.resolvedAt)}${signal.resolvedByName?.isNotEmpty == true ? ' by ${signal.resolvedByName}' : ''}',
    'acknowledged' =>
      'Acknowledged ${_formatSignalDate(signal.acknowledgedAt)}${signal.acknowledgedByName?.isNotEmpty == true ? ' by ${signal.acknowledgedByName}' : ''}',
    _ => 'Last seen ${formatCompactDate(signal.lastDetectedAt)}',
  };
  return '$statusLine  ·  First seen ${formatCompactDate(signal.firstDetectedAt)}';
}

String _formatSignalDate(DateTime? value) {
  if (value == null) {
    return 'recently';
  }
  return formatCompactDate(value);
}

String _resolvePulseRoute(String route) {
  switch (route) {
    case '/sales':
      return '/history';
    case '/plan':
      return '/settings/plan';
    case '/sessions':
      return '/settings/sessions';
    case '/audit':
    case '/migration':
    case '/erpnext':
      return '/settings/security';
    default:
      return route;
  }
}

Color _signalLevelColor(String level) {
  switch (level.trim().toLowerCase()) {
    case 'critical':
    case 'danger':
      return AppPalette.error;
    case 'high':
    case 'warning':
      return AppPalette.warning;
    case 'healthy':
      return AppPalette.success;
    default:
      return AppPalette.primary;
  }
}

String _roleLabel(String? role) {
  switch ((role ?? '').trim().toLowerCase()) {
    case 'owner':
      return 'Owner';
    case 'admin':
      return 'Admin';
    case 'viewer':
      return 'Viewer';
    default:
      return 'Staff';
  }
}



import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/models/mobile_session.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/runtime/app_runtime_info.dart';
import '../../../core/runtime/pilot_diagnostics_snapshot.dart';
import '../../../core/runtime/pilot_evidence_tracker.dart';
import '../../../core/runtime/pilot_evidence_tracker_store.dart';
import '../../../core/runtime/pilot_handoff_report.dart';
import '../../../core/runtime/pilot_incident_escalation_report.dart';
import '../../../core/runtime/pilot_operator_action_plan.dart';
import '../../../core/runtime/pilot_readiness_report.dart';
import '../../../core/runtime/pilot_recovery_report.dart';
import '../../../core/runtime/pilot_rollout_decision_summary.dart';
import '../../../core/runtime/pilot_rollout_evidence_report.dart';
import '../../../core/runtime/pilot_smoke_report.dart';
import '../../../core/runtime/pilot_shift_closeout_report.dart';
import '../../../core/runtime/pilot_wave_archive_pack.dart';
import '../../../core/runtime/pilot_wave_closeout_readiness.dart';
import '../../../core/runtime/pilot_wave_signoff_pack.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/utils/formatters.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

class SettingsOpsScreen extends ConsumerStatefulWidget {
  const SettingsOpsScreen({super.key});

  @override
  ConsumerState<SettingsOpsScreen> createState() => _SettingsOpsScreenState();
}

class _SettingsOpsScreenState extends ConsumerState<SettingsOpsScreen> {
  bool _showAdvancedTools = true;
  bool _queuedEvidenceSessionEnsure = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final shop =
        ref.watch(shopInfoProvider).asData?.value ?? ShopInfo.fallback();
    final verifiedUntil = ref
        .watch(mobileMfaVerifiedUntilProvider)
        .asData
        ?.value;
    final hasFreshSecurityWindow =
        verifiedUntil != null && verifiedUntil.isAfter(DateTime.now());
    if (!shop.supportsAdvancedOps) {
      return MobileStandaloneScaffold(
        title: 'Advanced ops',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: <Widget>[
            MobileScreenLead(
              title: 'Advanced ops locked',
              subtitle:
                  'This workspace stays on the curated Business Hub path. Advanced recovery and rollout tooling only opens on Pro workspaces.',
              icon: Icons.lock_rounded,
              accent: AppPalette.warning,
              primaryTag: AppTag(
                label: '${shop.planLabel} plan',
                icon: Icons.workspace_premium_rounded,
                tone: AppTone.warning,
              ),
            ),
            const SizedBox(height: 18),
            const AppPanel(
              title: 'Upgrade path',
              child: AppEmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Advanced ops stay hidden here',
                body:
                    'Use the normal Settings screen for day-to-day app health. Pro workspaces unlock deeper recovery, rollout, and technical support tools.',
              ),
            ),
          ],
        ),
      );
    }
    if ((session?.isOwnerLike ?? false) && !hasFreshSecurityWindow) {
      return MobileStandaloneScaffold(
        title: 'Advanced ops',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: <Widget>[
            MobileScreenLead(
              title: 'Security verification required',
              subtitle:
                  'Advanced ops now stays behind MFA on mobile. Verify the current owner/admin authenticator code from Security, then return here.',
              icon: Icons.security_rounded,
              accent: AppPalette.primary,
              primaryTag: const AppTag(
                label: 'MFA required',
                icon: Icons.lock_clock_rounded,
                tone: AppTone.warning,
              ),
            ),
            const SizedBox(height: 18),
            AppPanel(
              title: 'Open security first',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Recovery, rollout, and deep support tooling can affect the whole workspace. Business Hub now requires a fresh MFA window before this surface opens.',
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
                    icon: const Icon(Icons.verified_user_rounded),
                    label: const Text('Open security'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final backendApiClient = ref.watch(backendApiClientProvider);
    final syncCoordinator = ref.watch(mobileSyncCoordinatorProvider);
    final syncStatus = ref.watch(syncStatusProvider.select((status) => status));
    final runtimeInfoAsync = ref.watch(appRuntimeInfoProvider);
    final evidenceTrackerAsync = ref.watch(pilotEvidenceTrackerProvider);
    final evidenceTracker =
        evidenceTrackerAsync.asData?.value ?? const PilotEvidenceTrackerState();
    final evidenceTrackerController = ref.watch(
      pilotEvidenceTrackerControllerProvider,
    );
    final history =
        ref.watch(historyOverviewProvider).asData?.value ??
        HistoryOverview.empty();
    final domainStates =
        ref.watch(settingsOpsDomainStatesProvider).asData?.value ??
        <DomainControlState>[
          DomainControlState.legacy('inventory'),
          DomainControlState.legacy('customers'),
          DomainControlState.legacy('sales'),
          DomainControlState.legacy('payments'),
        ];
    final pending = ref.watch(pendingOutboxCountProvider).asData?.value ?? 0;
    final attentionEntries =
        ref.watch(outboxAttentionEntriesProvider).asData?.value ??
        const <CommerceOutboxAttentionEntry>[];
    final runtimeInfo = runtimeInfoAsync.asData?.value;
    final diagnostics = runtimeInfo == null
        ? null
        : PilotDiagnosticsSnapshot(
            runtimeInfo: runtimeInfo,
            shop: shop,
            session: session,
            backendBaseUrl: backendApiClient.baseUrl,
            syncStatus: syncStatus,
            historyOverview: history,
            pendingOutboxCount: pending,
            domainStates: domainStates,
          );
    final suggestedEvidenceSessionLabel = _buildEvidenceSessionLabel(
      shop: shop,
      runtimeInfo: runtimeInfo,
      session: session,
    );
    if (evidenceTrackerAsync.asData != null &&
        !evidenceTracker.hasSessionContext) {
      if (!_queuedEvidenceSessionEnsure) {
        _queuedEvidenceSessionEnsure = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          evidenceTrackerController.ensureSession(
            suggestedEvidenceSessionLabel,
          );
        });
      }
    } else {
      _queuedEvidenceSessionEnsure = false;
    }
    final recoveryReport = diagnostics == null
        ? null
        : PilotRecoveryReport(
            diagnosticsSnapshot: diagnostics,
            attentionEntries: attentionEntries,
          );
    final readinessReport = diagnostics == null
        ? null
        : PilotReadinessReport.evaluate(
            diagnosticsSnapshot: diagnostics,
            attentionEntries: attentionEntries,
          );
    final handoffReport =
        diagnostics == null || readinessReport == null || recoveryReport == null
        ? null
        : PilotHandoffReport(
            diagnosticsSnapshot: diagnostics,
            readinessReport: readinessReport,
            recoveryReport: recoveryReport,
          );
    final actionPlan =
        diagnostics == null || readinessReport == null || recoveryReport == null
        ? null
        : PilotOperatorActionPlan.evaluate(
            diagnosticsSnapshot: diagnostics,
            readinessReport: readinessReport,
            recoveryReport: recoveryReport,
          );
    final rolloutDecisionSummary =
        diagnostics == null ||
            readinessReport == null ||
            recoveryReport == null ||
            actionPlan == null
        ? null
        : PilotRolloutDecisionSummary.evaluate(
            diagnosticsSnapshot: diagnostics,
            readinessReport: readinessReport,
            recoveryReport: recoveryReport,
            actionPlan: actionPlan,
            evidenceTracker: evidenceTracker,
          );
    final waveCloseoutReadiness =
        diagnostics == null ||
            readinessReport == null ||
            recoveryReport == null ||
            actionPlan == null ||
            rolloutDecisionSummary == null
        ? null
        : PilotWaveCloseoutReadiness.evaluate(
            diagnosticsSnapshot: diagnostics,
            readinessReport: readinessReport,
            recoveryReport: recoveryReport,
            actionPlan: actionPlan,
            rolloutDecisionSummary: rolloutDecisionSummary,
            evidenceTracker: evidenceTracker,
          );
    final waveSignoffPack =
        diagnostics == null ||
            readinessReport == null ||
            recoveryReport == null ||
            actionPlan == null ||
            rolloutDecisionSummary == null ||
            waveCloseoutReadiness == null
        ? null
        : PilotWaveSignoffPack.evaluate(
            diagnosticsSnapshot: diagnostics,
            readinessReport: readinessReport,
            recoveryReport: recoveryReport,
            actionPlan: actionPlan,
            rolloutDecisionSummary: rolloutDecisionSummary,
            waveCloseoutReadiness: waveCloseoutReadiness,
            evidenceTracker: evidenceTracker,
          );
    final waveArchivePack = waveSignoffPack == null
        ? null
        : PilotWaveArchivePack.evaluate(
            waveSignoffPack: waveSignoffPack,
            evidenceTracker: evidenceTracker,
          );

    Future<void> markEvidenceCaptured(String artifactId) async {
      await evidenceTrackerController.markCaptured(artifactId);
    }

    return MobileStandaloneScaffold(
      title: 'Advanced ops',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          MobileScreenLead(
            title: 'Advanced ops',
            subtitle:
                'Operator packs, rollout evidence, recovery, and migration-facing tools live here so the daily settings screen stays fast.',
            icon: Icons.settings_rounded,
            accent: AppPalette.info,
            primaryTag: AppTag(
              label: session?.displayRoleLabel ?? 'GUEST',
              icon: Icons.badge_rounded,
              tone: AppTone.info,
            ),
            secondaryTag: AppTag(
              label: syncStatus == MobileSyncStatus.syncing
                  ? 'Syncing config'
                  : 'Config stable',
              icon: syncStatus == MobileSyncStatus.syncing
                  ? Icons.sync_rounded
                  : Icons.verified_rounded,
              tone: syncStatus == MobileSyncStatus.error
                  ? AppTone.danger
                  : AppTone.success,
            ),
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: 'Workspace identity',
            action: AppTag(
              label: session != null && session.isOwnerLike
                  ? 'CONTROL EDIT'
                  : 'VIEW ONLY',
              icon: session != null && session.isOwnerLike
                  ? Icons.edit_rounded
                  : Icons.lock_outline_rounded,
              tone: session != null && session.isOwnerLike
                  ? AppTone.success
                  : AppTone.info,
            ),
            child: Column(
              children: <Widget>[
                _SettingsRow(
                  label: 'Workspace',
                  value: shop.name,
                  icon: Icons.storefront_rounded,
                ),
                _SettingsRow(
                  label: 'Tagline',
                  value: shop.tagline,
                  icon: Icons.auto_awesome_rounded,
                ),
                _SettingsRow(
                  label: 'Operator',
                  value: session != null && session.email.isNotEmpty
                      ? session.email
                      : 'Not signed in',
                  icon: Icons.person_rounded,
                ),
                _SettingsRow(
                  label: 'Shop ID',
                  value: session?.shopId ?? 'No workspace bound',
                  icon: Icons.key_rounded,
                ),
                _SettingsRow(
                  label: 'Backend API',
                  value: backendApiClient.baseUrl,
                  icon: Icons.cloud_outlined,
                ),
                if (session != null && session.isOwnerLike) ...<Widget>[
                  const SizedBox(height: 6),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final changed = await _showWorkspaceSettingsDialog(
                        context,
                        currentShop: shop,
                        session: session,
                        syncCoordinator: syncCoordinator,
                      );
                      if (changed != true || !context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Workspace settings saved and queued to the live shop document.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Edit workspace settings'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: 'Mobile runtime',
            action: AppTag(
              label: pending > 0 ? '$pending queued' : 'Queue clear',
              icon: pending > 0
                  ? Icons.cloud_upload_rounded
                  : Icons.check_circle_rounded,
              tone: pending > 0 ? AppTone.warning : AppTone.success,
            ),
            child: Column(
              children: <Widget>[
                _SettingsRow(
                  label: 'Sync posture',
                  value: syncStatus.name.toUpperCase(),
                  icon: Icons.sync_alt_rounded,
                ),
                _SettingsRow(
                  label: 'Queued commerce commands',
                  value: '$pending',
                  icon: Icons.outbox_rounded,
                ),
                _SettingsRow(
                  label: 'Queued receipt value',
                  value: formatCurrency(history.queuedRevenue),
                  icon: Icons.currency_rupee_rounded,
                ),
                _SettingsRow(
                  label: 'Failed receipts',
                  value: '${history.failedSales}',
                  icon: Icons.error_outline_rounded,
                ),
                _SettingsRow(
                  label: 'Last receipt sync',
                  value: history.lastSyncedAt == null
                      ? 'Unknown'
                      : formatCompactDate(history.lastSyncedAt!),
                  icon: Icons.schedule_rounded,
                ),
                _SettingsRow(
                  label: 'Operator role',
                  value: session?.displayRoleLabel ?? 'UNKNOWN',
                  icon: Icons.admin_panel_settings_rounded,
                ),
                _SettingsRow(
                  label: 'Role focus',
                  value: session?.roleSummary ?? 'Role scope is still loading.',
                  icon: Icons.rule_folder_rounded,
                ),
                _SettingsRow(
                  label: 'Cost visibility',
                  value: session?.canViewCost == true
                      ? 'Enabled'
                      : 'Restricted',
                  icon: Icons.visibility_rounded,
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 430;
                    final buttons = <Widget>[
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            await syncCoordinator.refresh();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Workspace refresh requested.'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh workspace'),
                        ),
                      ),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: pending > 0
                              ? () async {
                                  final result = await syncCoordinator
                                      .flushCommerceOutbox();
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        result.message ??
                                            'Outbox flush requested.',
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.cloud_upload_rounded),
                          label: const Text('Flush outbox'),
                        ),
                      ),
                    ];

                    if (stacked) {
                      return Column(
                        children: <Widget>[
                          buttons[0],
                          const SizedBox(height: 10),
                          buttons[1],
                        ],
                      );
                    }

                    return Row(
                      children: <Widget>[
                        buttons[0],
                        const SizedBox(width: 10),
                        buttons[1],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: 'App and account',
            action: AppTag(
              label: _showAdvancedTools ? 'ADVANCED OPEN' : 'SIMPLE MODE',
              icon: _showAdvancedTools
                  ? Icons.admin_panel_settings_rounded
                  : Icons.favorite_rounded,
              tone: _showAdvancedTools ? AppTone.info : AppTone.success,
            ),
            child: Column(
              children: <Widget>[
                _SettingsRow(
                  label: 'Signed in as',
                  value: session != null && session.email.isNotEmpty
                      ? session.email
                      : 'Unknown operator',
                  icon: Icons.person_rounded,
                ),
                _SettingsRow(
                  label: 'Version',
                  value:
                      runtimeInfoAsync.asData?.value.versionLabel ??
                      'Loading app info',
                  icon: Icons.new_releases_rounded,
                ),
                _SettingsRow(
                  label: 'Release channel',
                  value:
                      runtimeInfoAsync.asData?.value.releaseFingerprint ??
                      'Resolving release data',
                  icon: Icons.flag_rounded,
                ),
                _SettingsRow(
                  label: 'Support mode',
                  value: _showAdvancedTools
                      ? 'Advanced tools visible'
                      : 'Daily-use view only',
                  icon: _showAdvancedTools
                      ? Icons.construction_rounded
                      : Icons.check_circle_rounded,
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 430;
                    final buttons = <Widget>[
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            setState(() {
                              _showAdvancedTools = !_showAdvancedTools;
                            });
                          },
                          icon: Icon(
                            _showAdvancedTools
                                ? Icons.visibility_off_rounded
                                : Icons.tune_rounded,
                          ),
                          label: Text(
                            _showAdvancedTools
                                ? 'Hide advanced tools'
                                : 'Show advanced tools',
                          ),
                        ),
                      ),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            await ref
                                .read(mobileSyncCoordinatorProvider)
                                .refresh();
                            if (!context.mounted) {
                              return;
                            }
                            context.go('/dashboard');
                          },
                          icon: const Icon(Icons.offline_bolt_rounded),
                          label: const Text('Reload workspace'),
                        ),
                      ),
                    ];

                    if (stacked) {
                      return Column(
                        children: <Widget>[
                          buttons[0],
                          const SizedBox(height: 10),
                          buttons[1],
                        ],
                      );
                    }

                    return Row(
                      children: <Widget>[
                        buttons[0],
                        const SizedBox(width: 10),
                        buttons[1],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: 'Advanced operator tools',
            action: AppTag(
              label: _showAdvancedTools ? 'VISIBLE' : 'HIDDEN',
              icon: _showAdvancedTools
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              tone: _showAdvancedTools ? AppTone.info : AppTone.neutral,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'These rollout, evidence, recovery, and migration tools are still here for admin work, but they stay hidden during normal shop use so the screen stays cleaner.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (_showAdvancedTools) ...<Widget>[
            const SizedBox(height: 18),
            AppPanel(
              title: 'Domain cutover map',
              action: AppTag(
                label:
                    '${domainStates.where((state) => state.isPostgresPrimary).length} primary',
                icon: Icons.schema_rounded,
                tone: AppTone.primary,
              ),
              child: Column(
                children: domainStates
                    .map(
                      (state) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _DomainSettingsRow(state: state),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 18),
            AppPanel(
              title: 'Pilot handoff snapshot',
              action: AppTag(
                label: diagnostics == null ? 'Loading' : 'Copy ready',
                icon: diagnostics == null
                    ? Icons.sync_rounded
                    : Icons.assignment_turned_in_rounded,
                tone: diagnostics == null ? AppTone.warning : AppTone.success,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Use this before a pilot handoff or floor smoke run. It captures the installed build identity, workspace, queue health, and domain posture in one copyable block for release notes, QA, or operator chat.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black.withValues(alpha: 0.68),
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SettingsRow(
                    label: 'Release fingerprint',
                    value:
                        runtimeInfo?.releaseFingerprint ??
                        'Loading runtime metadata',
                    icon: Icons.flag_rounded,
                  ),
                  _SettingsRow(
                    label: 'Pilot posture',
                    value:
                        diagnostics?.primaryDomainCountLabel ??
                        'Resolving domain states',
                    icon: Icons.fact_check_rounded,
                  ),
                  _SettingsRow(
                    label: 'Last receipt sync',
                    value: diagnostics?.lastReceiptSyncLabel ?? 'Unknown',
                    icon: Icons.history_toggle_off_rounded,
                  ),
                  FilledButton.tonalIcon(
                    onPressed: diagnostics == null
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: diagnostics.toMultilineText(),
                              ),
                            );
                            await markEvidenceCaptured('pilot_snapshot');
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Pilot launch snapshot copied. Paste it into the rollout thread or QA sheet.',
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.copy_all_rounded),
                    label: const Text('Copy pilot snapshot'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Column(
              children: <Widget>[
                AppPanel(
                  title: 'Operator action center',
                  action: AppTag(
                    label: actionPlan == null
                        ? 'Loading'
                        : actionPlan.actionLabel.toUpperCase(),
                    icon: actionPlan == null
                        ? Icons.sync_rounded
                        : actionPlan.isIncidentAction
                        ? Icons.crisis_alert_rounded
                        : actionPlan.isRecoveryAction
                        ? Icons.build_circle_rounded
                        : actionPlan.isSmokeAction
                        ? Icons.playlist_add_check_circle_rounded
                        : Icons.assignment_turned_in_rounded,
                    tone: actionPlan == null
                        ? AppTone.warning
                        : actionPlan.isIncidentAction
                        ? AppTone.danger
                        : actionPlan.isRecoveryAction
                        ? AppTone.warning
                        : AppTone.success,
                  ),
                  child: actionPlan == null
                      ? const AppEmptyState(
                          icon: Icons.sync_rounded,
                          title: 'Preparing operator action plan',
                          body:
                              'The device is still resolving readiness, recovery, and queue posture.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              actionPlan.summary,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.black.withValues(alpha: 0.68),
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            ...actionPlan.reasons.map(
                              (reason) => _ReadinessNoteRow(
                                message: reason,
                                tone: actionPlan.isIncidentAction
                                    ? AppPalette.error
                                    : actionPlan.isRecoveryAction
                                    ? AppPalette.warning
                                    : AppPalette.success,
                              ),
                            ),
                            const SizedBox(height: 14),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked = constraints.maxWidth < 430;
                                final buttons = <Widget>[
                                  Expanded(
                                    child: FilledButton.tonalIcon(
                                      onPressed: () async {
                                        if (actionPlan.isIncidentAction) {
                                          final report =
                                              await _showPilotIncidentEscalationDialog(
                                                context,
                                                diagnosticsSnapshot:
                                                    diagnostics!,
                                                readinessReport:
                                                    readinessReport!,
                                                recoveryReport: recoveryReport!,
                                              );
                                          if (report == null) {
                                            return;
                                          }
                                          await markEvidenceCaptured(
                                            'incident_escalation',
                                          );
                                          if (!context.mounted) {
                                            return;
                                          }
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Incident escalation pack copied with decision ${report.escalationDecisionLabel}.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        if (actionPlan.isRecoveryAction) {
                                          await Clipboard.setData(
                                            ClipboardData(
                                              text: recoveryReport!
                                                  .toMultilineText(),
                                            ),
                                          );
                                          await markEvidenceCaptured(
                                            'recovery_report',
                                          );
                                          if (!context.mounted) {
                                            return;
                                          }
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Recovery report copied for the next operator action.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        if (actionPlan.isSmokeAction) {
                                          final report =
                                              await _showPilotSmokeChecklistDialog(
                                                context,
                                                diagnosticsSnapshot:
                                                    diagnostics!,
                                                readinessReport:
                                                    readinessReport!,
                                              );
                                          if (report == null) {
                                            return;
                                          }
                                          await markEvidenceCaptured(
                                            'smoke_report',
                                          );
                                          if (!context.mounted) {
                                            return;
                                          }
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Pilot smoke report copied with verdict ${report.verdictLabel}.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        await Clipboard.setData(
                                          ClipboardData(
                                            text: diagnostics!
                                                .toMultilineText(),
                                          ),
                                        );
                                        await markEvidenceCaptured(
                                          'pilot_snapshot',
                                        );
                                        if (!context.mounted) {
                                          return;
                                        }
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Pilot snapshot copied for the next operator step.',
                                            ),
                                          ),
                                        );
                                      },
                                      icon: Icon(
                                        actionPlan.isIncidentAction
                                            ? Icons.crisis_alert_rounded
                                            : actionPlan.isRecoveryAction
                                            ? Icons.health_and_safety_rounded
                                            : actionPlan.isSmokeAction
                                            ? Icons.assignment_turned_in_rounded
                                            : Icons.copy_all_rounded,
                                      ),
                                      label: Text(actionPlan.actionLabel),
                                    ),
                                  ),
                                  Expanded(
                                    child: FilledButton.tonalIcon(
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(
                                            text: actionPlan.toMultilineText(),
                                          ),
                                        );
                                        await markEvidenceCaptured(
                                          'operator_action_brief',
                                        );
                                        if (!context.mounted) {
                                          return;
                                        }
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Operator action brief copied.',
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.copy_all_rounded),
                                      label: const Text('Copy action brief'),
                                    ),
                                  ),
                                ];

                                if (stacked) {
                                  return Column(
                                    children: <Widget>[
                                      buttons[0],
                                      const SizedBox(height: 10),
                                      buttons[1],
                                    ],
                                  );
                                }

                                return Row(
                                  children: <Widget>[
                                    buttons[0],
                                    const SizedBox(width: 10),
                                    buttons[1],
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                AppPanel(
                  title: 'Evidence tracker',
                  action: AppTag(
                    label: evidenceTrackerAsync.asData == null
                        ? 'Loading'
                        : evidenceTracker.statusLabel,
                    icon: evidenceTrackerAsync.asData == null
                        ? Icons.sync_rounded
                        : evidenceTracker.isCoreComplete
                        ? Icons.task_alt_rounded
                        : Icons.assignment_late_rounded,
                    tone: evidenceTrackerAsync.asData == null
                        ? AppTone.warning
                        : evidenceTracker.isCoreComplete
                        ? AppTone.success
                        : AppTone.warning,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'This tracker records which operator evidence exports have already been captured on this device for the current workspace, and it survives app restarts so the team can see what is still missing before handoff.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black.withValues(alpha: 0.68),
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SettingsRow(
                        label: 'Evidence session',
                        value:
                            evidenceTracker.sessionLabel ??
                            suggestedEvidenceSessionLabel,
                        icon: Icons.bookmark_added_rounded,
                      ),
                      _SettingsRow(
                        label: 'Session started',
                        value: evidenceTracker.sessionStartedAt == null
                            ? 'Not started yet'
                            : formatCompactDate(
                                evidenceTracker.sessionStartedAt!,
                              ),
                        icon: Icons.play_circle_rounded,
                      ),
                      _SettingsRow(
                        label: 'Core exports',
                        value: evidenceTracker.completionLabel,
                        icon: Icons.fact_check_rounded,
                      ),
                      _SettingsRow(
                        label: 'Optional exports',
                        value:
                            '${evidenceTracker.capturedOptionalCount} / ${evidenceTracker.totalOptionalCount} captured',
                        icon: Icons.library_add_check_rounded,
                      ),
                      _SettingsRow(
                        label: 'Latest capture',
                        value: evidenceTracker.latestCapturedArtifact == null
                            ? 'No evidence copied yet'
                            : '${evidenceTracker.latestCapturedArtifact!.label} at ${evidenceTracker.latestCapturedAt!.toUtc().toIso8601String()}',
                        icon: Icons.history_edu_rounded,
                      ),
                      _SettingsRow(
                        label: 'Archived sessions',
                        value:
                            '${evidenceTracker.archivedSessions.length} saved',
                        icon: Icons.archive_rounded,
                      ),
                      _SettingsRow(
                        label: 'Archive posture',
                        value: evidenceTracker.archiveTrendLabel,
                        icon: Icons.insights_rounded,
                      ),
                      _SettingsRow(
                        label: 'Archive summary',
                        value: evidenceTracker.archiveInsightSummary,
                        icon: Icons.monitor_heart_rounded,
                      ),
                      Text(
                        evidenceTracker.archiveOperationalGuidance,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: !evidenceTracker.hasArchivedSessions
                              ? AppPalette.primary
                              : evidenceTracker.recentArchiveShowsAttention
                              ? AppPalette.warning
                              : AppPalette.success,
                          fontWeight: FontWeight.w700,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.tonalIcon(
                        onPressed: evidenceTrackerAsync.asData == null
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: evidenceTracker
                                        .toArchiveInsightsText(),
                                  ),
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Archive insights copied for the rollout lead.',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.insights_rounded),
                        label: const Text('Copy archive insights'),
                      ),
                      if (evidenceTracker.hasArchivedSessions) ...<Widget>[
                        const SizedBox(height: 14),
                        Text(
                          'Recent archived sessions:',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: AppPalette.primary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 10),
                        ...evidenceTracker.archivedSessions
                            .take(3)
                            .map(
                              (entry) => _ReadinessNoteRow(
                                message: entry.summaryLine,
                                tone: AppPalette.primary,
                              ),
                            ),
                        const SizedBox(height: 14),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final archived =
                                evidenceTracker.latestArchivedSession;
                            if (archived == null) {
                              return;
                            }
                            await Clipboard.setData(
                              ClipboardData(text: archived.toMultilineText()),
                            );
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Latest archived session copied: ${archived.sessionLabel}.',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.history_toggle_off_rounded),
                          label: const Text('Copy latest archived session'),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: evidenceTracker.toArchivePackText(),
                              ),
                            );
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Full evidence archive pack copied.',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.inventory_2_rounded),
                          label: const Text('Copy full archive pack'),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await evidenceTrackerController.clearArchive();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Archived evidence sessions cleared. Active session kept.',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.auto_delete_rounded),
                          label: const Text('Clear archived sessions'),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (evidenceTracker
                          .missingCoreArtifacts
                          .isNotEmpty) ...<Widget>[
                        Text(
                          'Still missing before handoff:',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: AppPalette.warning,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 10),
                        ...evidenceTracker.missingCoreArtifacts.map(
                          (artifact) => _ReadinessNoteRow(
                            message: artifact.label,
                            tone: AppPalette.warning,
                          ),
                        ),
                      ] else ...<Widget>[
                        Text(
                          'All core handoff artifacts have been captured on this device.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppPalette.success,
                                fontWeight: FontWeight.w700,
                                height: 1.45,
                              ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stacked = constraints.maxWidth < 430;
                          final buttons = <Widget>[
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text: evidenceTracker.toMultilineText(),
                                    ),
                                  );
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Evidence tracker copied for the rollout record.',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_all_rounded),
                                label: const Text('Copy evidence tracker'),
                              ),
                            ),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: evidenceTrackerAsync.asData == null
                                    ? null
                                    : () async {
                                        final sessionLabel =
                                            await _showEvidenceSessionDialog(
                                              context,
                                              currentLabel:
                                                  evidenceTracker.sessionLabel,
                                              suggestedLabel:
                                                  suggestedEvidenceSessionLabel,
                                            );
                                        if (sessionLabel == null) {
                                          return;
                                        }
                                        await evidenceTrackerController
                                            .startFreshSession(sessionLabel);
                                        if (!context.mounted) {
                                          return;
                                        }
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Started a fresh evidence session: $sessionLabel',
                                            ),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.restart_alt_rounded),
                                label: const Text('Fresh session'),
                              ),
                            ),
                          ];

                          if (stacked) {
                            return Column(
                              children: <Widget>[
                                buttons[0],
                                const SizedBox(height: 10),
                                buttons[1],
                              ],
                            );
                          }

                          return Row(
                            children: <Widget>[
                              buttons[0],
                              const SizedBox(width: 10),
                              buttons[1],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                AppPanel(
                  title: 'Pilot readiness signoff',
                  action: AppTag(
                    label: readinessReport == null
                        ? 'Loading'
                        : readinessReport.statusLabel,
                    icon: readinessReport == null
                        ? Icons.sync_rounded
                        : readinessReport.isReadyForShift
                        ? Icons.verified_rounded
                        : readinessReport.shouldMonitor
                        ? Icons.visibility_rounded
                        : Icons.block_rounded,
                    tone: readinessReport == null
                        ? AppTone.warning
                        : readinessReport.isReadyForShift
                        ? AppTone.success
                        : readinessReport.shouldMonitor
                        ? AppTone.warning
                        : AppTone.danger,
                  ),
                  child: readinessReport == null
                      ? const AppEmptyState(
                          icon: Icons.sync_rounded,
                          title: 'Building readiness verdict',
                          body:
                              'The mobile shell is collecting the launch snapshot and queue posture for signoff.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              readinessReport.summary,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.black.withValues(alpha: 0.68),
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                  ),
                            ),
                            if (readinessReport
                                .blockers
                                .isNotEmpty) ...<Widget>[
                              const SizedBox(height: 14),
                              Text(
                                'Blockers',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: AppPalette.error,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              ...readinessReport.blockers.map(
                                (item) => _ReadinessNoteRow(
                                  message: item,
                                  tone: AppPalette.error,
                                ),
                              ),
                            ],
                            if (readinessReport
                                .warnings
                                .isNotEmpty) ...<Widget>[
                              const SizedBox(height: 14),
                              Text(
                                'Warnings',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: AppPalette.warning,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              ...readinessReport.warnings.map(
                                (item) => _ReadinessNoteRow(
                                  message: item,
                                  tone: AppPalette.warning,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: readinessReport.toMultilineText(),
                                  ),
                                );
                                await markEvidenceCaptured('readiness_signoff');
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Pilot readiness signoff copied for rollout approval.',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_all_rounded),
                              label: const Text('Copy readiness signoff'),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.tonalIcon(
                              onPressed: handoffReport == null
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(
                                          text: handoffReport.toMultilineText(),
                                        ),
                                      );
                                      await markEvidenceCaptured(
                                        'handoff_pack',
                                      );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Full pilot handoff pack copied for release evidence.',
                                          ),
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.assignment_rounded),
                              label: const Text('Copy full handoff pack'),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                AppPanel(
                  title: 'Pilot smoke execution',
                  action: AppTag(
                    label: readinessReport == null ? 'Loading' : 'Floor check',
                    icon: readinessReport == null
                        ? Icons.sync_rounded
                        : Icons.playlist_add_check_circle_rounded,
                    tone: readinessReport == null
                        ? AppTone.warning
                        : AppTone.primary,
                  ),
                  child: diagnostics == null || readinessReport == null
                      ? const AppEmptyState(
                          icon: Icons.sync_rounded,
                          title: 'Preparing smoke execution',
                          body:
                              'The launch snapshot and readiness posture are still loading for this device.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Run the floor smoke checklist from the device itself and copy the resulting evidence block into the rollout log. This keeps the final operator decision tied to the exact installed release and workspace binding.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.black.withValues(alpha: 0.68),
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            _SettingsRow(
                              label: 'Release target',
                              value:
                                  '${diagnostics.runtimeInfo.releaseTag} | ${diagnostics.runtimeInfo.rolloutScopeLabel}',
                              icon: Icons.route_rounded,
                            ),
                            _SettingsRow(
                              label: 'Readiness gate',
                              value: readinessReport.statusLabel,
                              icon: Icons.fact_check_rounded,
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                final smokeReport =
                                    await _showPilotSmokeChecklistDialog(
                                      context,
                                      diagnosticsSnapshot: diagnostics,
                                      readinessReport: readinessReport,
                                    );
                                if (smokeReport == null) {
                                  return;
                                }
                                await markEvidenceCaptured('smoke_report');
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Pilot smoke report copied with verdict ${smokeReport.verdictLabel}.',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.assignment_turned_in_rounded,
                              ),
                              label: const Text('Run smoke checklist'),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                AppPanel(
                  title: 'Recovery desk',
                  action: AppTag(
                    label: attentionEntries.isEmpty
                        ? 'Stable'
                        : '${attentionEntries.length} attention',
                    icon: attentionEntries.isEmpty
                        ? Icons.health_and_safety_rounded
                        : Icons.build_circle_rounded,
                    tone: attentionEntries.isEmpty
                        ? AppTone.success
                        : AppTone.danger,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Use this when a pilot device has replay trouble. It shows the highest-risk queued or failed commerce commands, lets you retry one receipt at a time, and creates a recovery report you can hand to support or QA.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black.withValues(alpha: 0.68),
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (attentionEntries.isEmpty)
                        const AppEmptyState(
                          icon: Icons.health_and_safety_rounded,
                          title: 'No recovery work is waiting',
                          body:
                              'Queued and failed commerce commands are clear on this device right now.',
                        )
                      else
                        ...attentionEntries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _OutboxAttentionRow(
                              entry: entry,
                              onRetry: () async {
                                final result = await syncCoordinator
                                    .retryCommerceCommand(entry.commandId);
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      result.message ??
                                          'Retry requested for ${entry.commandId}.',
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stacked = constraints.maxWidth < 430;
                          final buttons = <Widget>[
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: attentionEntries.isEmpty
                                    ? null
                                    : () async {
                                        final result = await syncCoordinator
                                            .flushCommerceOutbox();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              result.message ??
                                                  'Recovery replay requested.',
                                            ),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.cloud_sync_rounded),
                                label: const Text('Retry all attention items'),
                              ),
                            ),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: recoveryReport == null
                                    ? null
                                    : () async {
                                        await Clipboard.setData(
                                          ClipboardData(
                                            text: recoveryReport
                                                .toMultilineText(),
                                          ),
                                        );
                                        await markEvidenceCaptured(
                                          'recovery_report',
                                        );
                                        if (!context.mounted) {
                                          return;
                                        }
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Pilot recovery report copied for support handoff.',
                                            ),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.copy_all_rounded),
                                label: const Text('Copy recovery report'),
                              ),
                            ),
                          ];

                          if (stacked) {
                            return Column(
                              children: <Widget>[
                                buttons[0],
                                const SizedBox(height: 10),
                                buttons[1],
                              ],
                            );
                          }

                          return Row(
                            children: <Widget>[
                              buttons[0],
                              const SizedBox(width: 10),
                              buttons[1],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                AppPanel(
                  title: 'Shift closeout',
                  action: AppTag(
                    label:
                        diagnostics == null ||
                            readinessReport == null ||
                            recoveryReport == null
                        ? 'Loading'
                        : 'End of shift',
                    icon:
                        diagnostics == null ||
                            readinessReport == null ||
                            recoveryReport == null
                        ? Icons.sync_rounded
                        : Icons.assignment_late_rounded,
                    tone:
                        diagnostics == null ||
                            readinessReport == null ||
                            recoveryReport == null
                        ? AppTone.warning
                        : AppTone.info,
                  ),
                  child:
                      diagnostics == null ||
                          readinessReport == null ||
                          recoveryReport == null
                      ? const AppEmptyState(
                          icon: Icons.sync_rounded,
                          title: 'Preparing shift closeout',
                          body:
                              'The device is still resolving readiness and recovery posture for this closeout report.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Use this at the end of a real pilot shift. It captures whether checkout, replay, and customer-ledger behavior stayed healthy, and creates the final operator-side handoff note for the next shift or rollout lead.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.black.withValues(alpha: 0.68),
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            _SettingsRow(
                              label: 'Queue posture',
                              value: diagnostics.pendingOutboxCount > 0
                                  ? '${diagnostics.pendingOutboxCount} command(s) still queued'
                                  : 'Queue clear',
                              icon: Icons.outbox_rounded,
                            ),
                            _SettingsRow(
                              label: 'Recovery attention',
                              value: attentionEntries.isEmpty
                                  ? 'No active recovery items'
                                  : '${attentionEntries.length} attention item(s)',
                              icon: Icons.health_and_safety_rounded,
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                final closeoutReport =
                                    await _showPilotShiftCloseoutDialog(
                                      context,
                                      diagnosticsSnapshot: diagnostics,
                                      readinessReport: readinessReport,
                                      recoveryReport: recoveryReport,
                                    );
                                if (closeoutReport == null) {
                                  return;
                                }
                                await markEvidenceCaptured('shift_closeout');
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Shift closeout copied with decision ${closeoutReport.decisionLabel}.',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.assignment_turned_in_rounded,
                              ),
                              label: const Text('Run shift closeout'),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                AppPanel(
                  title: 'Rollout decision summary',
                  action: AppTag(
                    label: rolloutDecisionSummary == null
                        ? 'Loading'
                        : rolloutDecisionSummary.verdictLabel,
                    icon: rolloutDecisionSummary == null
                        ? Icons.sync_rounded
                        : rolloutDecisionSummary.shouldRollbackAndEscalate
                        ? Icons.crisis_alert_rounded
                        : rolloutDecisionSummary.shouldInvestigateBeforeExpand
                        ? Icons.troubleshoot_rounded
                        : rolloutDecisionSummary.shouldHoldAndMonitor
                        ? Icons.visibility_rounded
                        : Icons.trending_up_rounded,
                    tone: rolloutDecisionSummary == null
                        ? AppTone.warning
                        : rolloutDecisionSummary.shouldRollbackAndEscalate
                        ? AppTone.danger
                        : rolloutDecisionSummary.shouldInvestigateBeforeExpand
                        ? AppTone.warning
                        : rolloutDecisionSummary.shouldHoldAndMonitor
                        ? AppTone.primary
                        : AppTone.success,
                  ),
                  child: rolloutDecisionSummary == null
                      ? const AppEmptyState(
                          icon: Icons.sync_rounded,
                          title: 'Preparing rollout decision summary',
                          body:
                              'The device is still combining readiness, recovery, action, and archive posture into a rollout verdict.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              rolloutDecisionSummary.summary,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.black.withValues(alpha: 0.68),
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            _SettingsRow(
                              label: 'Verdict',
                              value: rolloutDecisionSummary.verdictLabel,
                              icon: Icons.gavel_rounded,
                            ),
                            _SettingsRow(
                              label: 'Recommended next action',
                              value: actionPlan!.actionLabel,
                              icon: Icons.route_rounded,
                            ),
                            _SettingsRow(
                              label: 'Archive posture',
                              value: evidenceTracker.archiveTrendLabel,
                              icon: Icons.insights_rounded,
                            ),
                            ...rolloutDecisionSummary.reasons.map(
                              (reason) => _ReadinessNoteRow(
                                message: reason,
                                tone:
                                    rolloutDecisionSummary
                                        .shouldRollbackAndEscalate
                                    ? AppPalette.error
                                    : rolloutDecisionSummary
                                          .shouldInvestigateBeforeExpand
                                    ? AppPalette.warning
                                    : rolloutDecisionSummary
                                          .shouldHoldAndMonitor
                                    ? AppPalette.primary
                                    : AppPalette.success,
                              ),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: rolloutDecisionSummary
                                        .toMultilineText(),
                                  ),
                                );
                                await markEvidenceCaptured(
                                  'rollout_decision_summary',
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Rollout decision summary copied with verdict ${rolloutDecisionSummary.verdictLabel}.',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.assignment_turned_in_rounded,
                              ),
                              label: const Text('Copy decision summary'),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                AppPanel(
                  title: 'Wave closeout readiness',
                  action: AppTag(
                    label: waveCloseoutReadiness == null
                        ? 'Loading'
                        : waveCloseoutReadiness.statusLabel,
                    icon: waveCloseoutReadiness == null
                        ? Icons.sync_rounded
                        : waveCloseoutReadiness.shouldNotClose
                        ? Icons.block_rounded
                        : waveCloseoutReadiness.shouldCaptureMoreEvidence
                        ? Icons.assignment_late_rounded
                        : waveCloseoutReadiness.isCloseoutWithMonitoring
                        ? Icons.visibility_rounded
                        : Icons.task_alt_rounded,
                    tone: waveCloseoutReadiness == null
                        ? AppTone.warning
                        : waveCloseoutReadiness.shouldNotClose
                        ? AppTone.danger
                        : waveCloseoutReadiness.shouldCaptureMoreEvidence
                        ? AppTone.warning
                        : waveCloseoutReadiness.isCloseoutWithMonitoring
                        ? AppTone.primary
                        : AppTone.success,
                  ),
                  child: waveCloseoutReadiness == null
                      ? const AppEmptyState(
                          icon: Icons.sync_rounded,
                          title: 'Preparing wave closeout readiness',
                          body:
                              'The device is still evaluating whether this rollout wave can be closed cleanly.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              waveCloseoutReadiness.summary,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.black.withValues(alpha: 0.68),
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            _SettingsRow(
                              label: 'Closeout status',
                              value: waveCloseoutReadiness.statusLabel,
                              icon: Icons.playlist_add_check_rounded,
                            ),
                            _SettingsRow(
                              label: 'Required artifacts',
                              value:
                                  waveCloseoutReadiness.closeoutArtifactsLabel,
                              icon: Icons.fact_check_rounded,
                            ),
                            _SettingsRow(
                              label: 'Decision posture',
                              value: rolloutDecisionSummary!.verdictLabel,
                              icon: Icons.gavel_rounded,
                            ),
                            ...waveCloseoutReadiness.reasons.map(
                              (reason) => _ReadinessNoteRow(
                                message: reason,
                                tone: waveCloseoutReadiness.shouldNotClose
                                    ? AppPalette.error
                                    : waveCloseoutReadiness
                                          .shouldCaptureMoreEvidence
                                    ? AppPalette.warning
                                    : waveCloseoutReadiness
                                          .isCloseoutWithMonitoring
                                    ? AppPalette.primary
                                    : AppPalette.success,
                              ),
                            ),
                            if (waveCloseoutReadiness
                                .missingCloseoutArtifacts
                                .isNotEmpty) ...<Widget>[
                              const SizedBox(height: 14),
                              Text(
                                'Still missing for closeout:',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: AppPalette.warning,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              ...waveCloseoutReadiness.missingCloseoutArtifacts
                                  .map(
                                    (artifact) => _ReadinessNoteRow(
                                      message: artifact.label,
                                      tone: AppPalette.warning,
                                    ),
                                  ),
                            ],
                            const SizedBox(height: 14),
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: waveCloseoutReadiness
                                        .toMultilineText(),
                                  ),
                                );
                                await markEvidenceCaptured(
                                  'wave_closeout_readiness',
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Wave closeout readiness copied with status ${waveCloseoutReadiness.statusLabel}.',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.assignment_turned_in_rounded,
                              ),
                              label: const Text('Copy wave closeout readiness'),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                AppPanel(
                  title: 'Wave signoff pack',
                  action: AppTag(
                    label: waveSignoffPack == null
                        ? 'Loading'
                        : waveSignoffPack.signoffStatusLabel,
                    icon: waveSignoffPack == null
                        ? Icons.sync_rounded
                        : waveSignoffPack.isSignoffBlocked
                        ? Icons.block_rounded
                        : waveSignoffPack.isSignoffIncomplete
                        ? Icons.assignment_late_rounded
                        : waveSignoffPack.isSignoffWithMonitoring
                        ? Icons.visibility_rounded
                        : Icons.verified_rounded,
                    tone: waveSignoffPack == null
                        ? AppTone.warning
                        : waveSignoffPack.isSignoffBlocked
                        ? AppTone.danger
                        : waveSignoffPack.isSignoffIncomplete
                        ? AppTone.warning
                        : waveSignoffPack.isSignoffWithMonitoring
                        ? AppTone.primary
                        : AppTone.success,
                  ),
                  child: waveSignoffPack == null
                      ? const AppEmptyState(
                          icon: Icons.sync_rounded,
                          title: 'Preparing wave signoff pack',
                          body:
                              'The device is still combining closeout, decision, and evidence posture into the final wave handoff package.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              waveSignoffPack.summary,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.black.withValues(alpha: 0.68),
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            _SettingsRow(
                              label: 'Signoff status',
                              value: waveSignoffPack.signoffStatusLabel,
                              icon: Icons.verified_user_rounded,
                            ),
                            _SettingsRow(
                              label: 'Closeout posture',
                              value: waveCloseoutReadiness!.statusLabel,
                              icon: Icons.playlist_add_check_rounded,
                            ),
                            _SettingsRow(
                              label: 'Decision posture',
                              value: rolloutDecisionSummary!.verdictLabel,
                              icon: Icons.gavel_rounded,
                            ),
                            ...waveSignoffPack.reasons.map(
                              (reason) => _ReadinessNoteRow(
                                message: reason,
                                tone: waveSignoffPack.isSignoffBlocked
                                    ? AppPalette.error
                                    : waveSignoffPack.isSignoffIncomplete
                                    ? AppPalette.warning
                                    : waveSignoffPack.isSignoffWithMonitoring
                                    ? AppPalette.primary
                                    : AppPalette.success,
                              ),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: waveSignoffPack.toMultilineText(),
                                  ),
                                );
                                await markEvidenceCaptured('wave_signoff_pack');
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Wave signoff pack copied with status ${waveSignoffPack.signoffStatusLabel}.',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.assignment_turned_in_rounded,
                              ),
                              label: const Text('Copy wave signoff pack'),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                AppPanel(
                  title: 'Wave archive pack',
                  action: AppTag(
                    label: waveArchivePack == null
                        ? 'Loading'
                        : waveArchivePack.archiveStatusLabel,
                    icon: waveArchivePack == null
                        ? Icons.sync_rounded
                        : waveArchivePack.isArchiveBlocked
                        ? Icons.block_rounded
                        : waveArchivePack.isArchiveIncomplete
                        ? Icons.assignment_late_rounded
                        : waveArchivePack.isArchiveWithAttention
                        ? Icons.archive_rounded
                        : Icons.inventory_2_rounded,
                    tone: waveArchivePack == null
                        ? AppTone.warning
                        : waveArchivePack.isArchiveBlocked
                        ? AppTone.danger
                        : waveArchivePack.isArchiveIncomplete
                        ? AppTone.warning
                        : waveArchivePack.isArchiveWithAttention
                        ? AppTone.primary
                        : AppTone.success,
                  ),
                  child: waveArchivePack == null
                      ? const AppEmptyState(
                          icon: Icons.sync_rounded,
                          title: 'Preparing wave archive pack',
                          body:
                              'The device is still combining final signoff with the evidence archive for permanent rollout records.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              waveArchivePack.summary,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.black.withValues(alpha: 0.68),
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            _SettingsRow(
                              label: 'Archive status',
                              value: waveArchivePack.archiveStatusLabel,
                              icon: Icons.archive_rounded,
                            ),
                            _SettingsRow(
                              label: 'Signoff posture',
                              value: waveArchivePack
                                  .waveSignoffPack
                                  .signoffStatusLabel,
                              icon: Icons.verified_user_rounded,
                            ),
                            _SettingsRow(
                              label: 'Archived sessions',
                              value:
                                  '${evidenceTracker.archivedSessions.length} saved',
                              icon: Icons.history_edu_rounded,
                            ),
                            ...waveArchivePack.reasons.map(
                              (reason) => _ReadinessNoteRow(
                                message: reason,
                                tone: waveArchivePack.isArchiveBlocked
                                    ? AppPalette.error
                                    : waveArchivePack.isArchiveIncomplete
                                    ? AppPalette.warning
                                    : waveArchivePack.isArchiveWithAttention
                                    ? AppPalette.primary
                                    : AppPalette.success,
                              ),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: waveArchivePack.toMultilineText(),
                                  ),
                                );
                                await markEvidenceCaptured('wave_archive_pack');
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Wave archive pack copied with status ${waveArchivePack.archiveStatusLabel}.',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.inventory_2_rounded),
                              label: const Text('Copy wave archive pack'),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                AppPanel(
                  title: 'Rollout evidence pack',
                  action: AppTag(
                    label:
                        diagnostics == null ||
                            readinessReport == null ||
                            recoveryReport == null
                        ? 'Loading'
                        : 'Wave record',
                    icon:
                        diagnostics == null ||
                            readinessReport == null ||
                            recoveryReport == null
                        ? Icons.sync_rounded
                        : Icons.library_books_rounded,
                    tone:
                        diagnostics == null ||
                            readinessReport == null ||
                            recoveryReport == null
                        ? AppTone.warning
                        : AppTone.primary,
                  ),
                  child:
                      diagnostics == null ||
                          readinessReport == null ||
                          recoveryReport == null
                      ? const AppEmptyState(
                          icon: Icons.sync_rounded,
                          title: 'Preparing rollout evidence',
                          body:
                              'The device is still resolving the core reports needed for the consolidated rollout record.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Use this when a rollout lead wants one final copied pack for the wave record. It consolidates the current readiness, snapshot, and recovery posture, then lets the operator summarize smoke and closeout outcomes in one export.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.black.withValues(alpha: 0.68),
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            _SettingsRow(
                              label: 'Release target',
                              value:
                                  '${diagnostics.runtimeInfo.releaseTag} | ${diagnostics.runtimeInfo.rolloutScopeLabel}',
                              icon: Icons.route_rounded,
                            ),
                            _SettingsRow(
                              label: 'Recovery posture',
                              value:
                                  '${recoveryReport.attentionEntries.length} open attention item(s)',
                              icon: Icons.health_and_safety_rounded,
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                final evidenceReport =
                                    await _showPilotRolloutEvidenceDialog(
                                      context,
                                      diagnosticsSnapshot: diagnostics,
                                      readinessReport: readinessReport,
                                      recoveryReport: recoveryReport,
                                    );
                                if (evidenceReport == null) {
                                  return;
                                }
                                await markEvidenceCaptured('rollout_evidence');
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Rollout evidence pack copied with recommendation ${evidenceReport.recommendationLabel}.',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.assignment_rounded),
                              label: const Text('Build evidence pack'),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                AppPanel(
                  title: 'Incident escalation pack',
                  action: AppTag(
                    label:
                        diagnostics == null ||
                            readinessReport == null ||
                            recoveryReport == null
                        ? 'Loading'
                        : 'Escalation',
                    icon:
                        diagnostics == null ||
                            readinessReport == null ||
                            recoveryReport == null
                        ? Icons.sync_rounded
                        : Icons.crisis_alert_rounded,
                    tone:
                        diagnostics == null ||
                            readinessReport == null ||
                            recoveryReport == null
                        ? AppTone.warning
                        : AppTone.danger,
                  ),
                  child:
                      diagnostics == null ||
                          readinessReport == null ||
                          recoveryReport == null
                      ? const AppEmptyState(
                          icon: Icons.sync_rounded,
                          title: 'Preparing escalation pack',
                          body:
                              'The device is still collecting the reports needed for a structured incident export.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Use this when the rollout lead, support, or engineering needs one structured incident record directly from the affected device. It turns the current readiness, snapshot, and recovery state into a support-ready escalation pack.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.black.withValues(alpha: 0.68),
                                    fontWeight: FontWeight.w600,
                                    height: 1.45,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            _SettingsRow(
                              label: 'Failure posture',
                              value:
                                  '${recoveryReport.attentionEntries.length} recovery item(s) | ${diagnostics.historyOverview.failedSales} failed receipt(s)',
                              icon: Icons.error_outline_rounded,
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                final escalationReport =
                                    await _showPilotIncidentEscalationDialog(
                                      context,
                                      diagnosticsSnapshot: diagnostics,
                                      readinessReport: readinessReport,
                                      recoveryReport: recoveryReport,
                                    );
                                if (escalationReport == null) {
                                  return;
                                }
                                await markEvidenceCaptured(
                                  'incident_escalation',
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Incident escalation pack copied with decision ${escalationReport.escalationDecisionLabel}.',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_all_rounded),
                              label: const Text('Build escalation pack'),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<PilotSmokeReport?> _showPilotSmokeChecklistDialog(
    BuildContext context, {
    required PilotDiagnosticsSnapshot diagnosticsSnapshot,
    required PilotReadinessReport readinessReport,
  }) async {
    final colors = AppColors.of(context);
    final notesController = TextEditingController();
    final outcomes = <String, PilotSmokeCheckOutcome>{
      for (final check in defaultPilotSmokeChecks)
        check.id: PilotSmokeCheckOutcome.pending,
    };

    PilotSmokeReport buildPreview() {
      return PilotSmokeReport(
        diagnosticsSnapshot: diagnosticsSnapshot,
        readinessReport: readinessReport,
        operatorNotes: notesController.text.trim(),
        results: defaultPilotSmokeChecks
            .map(
              (check) => PilotSmokeCheckResult(
                check: check,
                outcome: outcomes[check.id] ?? PilotSmokeCheckOutcome.pending,
              ),
            )
            .toList(growable: false),
      );
    }

    try {
      return await showDialog<PilotSmokeReport>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final preview = buildPreview();
              final verdictTone = switch (preview.verdict) {
                'pass' => AppPalette.success,
                'monitor' => AppPalette.warning,
                'blocked' => AppPalette.error,
                _ => AppPalette.primary,
              };

              return AlertDialog(
                title: const Text('Run pilot smoke checklist'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Mark each floor check from the device you are holding. The copied report becomes the operator-side evidence for the release tag and pilot scope currently installed.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.black.withValues(alpha: 0.68),
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 14),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: verdictTone.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: verdictTone.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  preview.verdictLabel,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: verdictTone,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  preview.summary,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.black.withValues(
                                          alpha: 0.76,
                                        ),
                                        fontWeight: FontWeight.w600,
                                        height: 1.45,
                                      ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Pass ${preview.passedCount} | Fail ${preview.failedCount} | Pending ${preview.pendingCount}',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: colors.textSecondary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...defaultPilotSmokeChecks.map((check) {
                          final outcome =
                              outcomes[check.id] ??
                              PilotSmokeCheckOutcome.pending;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _PilotSmokeCheckCard(
                              check: check,
                              outcome: outcome,
                              onOutcomeChanged: (next) {
                                setDialogState(() {
                                  outcomes[check.id] = next;
                                });
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 6),
                        TextField(
                          textCapitalization: TextCapitalization.sentences,
                          controller: notesController,
                          minLines: 2,
                          maxLines: 4,
                          onChanged: (_) {
                            setDialogState(() {});
                          },
                          decoration: const InputDecoration(
                            labelText: 'Operator notes',
                            hintText:
                                'Optional context for any failure, retry, or floor observation.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final report = buildPreview();
                      await Clipboard.setData(
                        ClipboardData(text: report.toMultilineText()),
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(report);
                      }
                    },
                    child: const Text('Copy smoke report'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      notesController.dispose();
    }
  }

  Future<PilotShiftCloseoutReport?> _showPilotShiftCloseoutDialog(
    BuildContext context, {
    required PilotDiagnosticsSnapshot diagnosticsSnapshot,
    required PilotReadinessReport readinessReport,
    required PilotRecoveryReport recoveryReport,
  }) async {
    final notesController = TextEditingController();
    var checkoutStable = true;
    var replayStable =
        diagnosticsSnapshot.pendingOutboxCount == 0 &&
        !recoveryReport.attentionEntries.any((entry) => entry.isFailed);
    var customerLedgerStable = true;
    var rollbackRequired = false;

    PilotShiftCloseoutReport buildPreview() {
      return PilotShiftCloseoutReport(
        diagnosticsSnapshot: diagnosticsSnapshot,
        readinessReport: readinessReport,
        recoveryReport: recoveryReport,
        answers: PilotShiftCloseoutAnswers(
          checkoutStable: checkoutStable,
          replayStable: replayStable,
          customerLedgerStable: customerLedgerStable,
          rollbackRequired: rollbackRequired,
          notes: notesController.text.trim(),
        ),
      );
    }

    try {
      return await showDialog<PilotShiftCloseoutReport>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final preview = buildPreview();
              final tone = switch (preview.decision) {
                'healthy_handoff' => AppPalette.success,
                'monitor_next_shift' => AppPalette.warning,
                _ => AppPalette.error,
              };

              return AlertDialog(
                title: const Text('Run shift closeout'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Record how the pilot device actually finished the shift. This report is meant for the next operator, the rollout lead, or a support escalation thread.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.black.withValues(alpha: 0.68),
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 14),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: tone.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  preview.decisionLabel,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: tone,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  preview.summary,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.black.withValues(
                                          alpha: 0.76,
                                        ),
                                        fontWeight: FontWeight.w600,
                                        height: 1.45,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _CloseoutToggleCard(
                          label: 'Checkout stayed stable through the shift',
                          value: checkoutStable,
                          onChanged: (value) {
                            setDialogState(() {
                              checkoutStable = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _CloseoutToggleCard(
                          label:
                              'Replay and outbox behavior stayed stable after reconnects',
                          value: replayStable,
                          onChanged: (value) {
                            setDialogState(() {
                              replayStable = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _CloseoutToggleCard(
                          label:
                              'Customer ledger and due-balance behavior stayed correct',
                          value: customerLedgerStable,
                          onChanged: (value) {
                            setDialogState(() {
                              customerLedgerStable = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _CloseoutToggleCard(
                          label: 'Rollback is required before the next shift',
                          value: rollbackRequired,
                          trueLabel: 'YES',
                          falseLabel: 'NO',
                          dangerWhenTrue: true,
                          onChanged: (value) {
                            setDialogState(() {
                              rollbackRequired = value;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          textCapitalization: TextCapitalization.sentences,
                          controller: notesController,
                          minLines: 2,
                          maxLines: 4,
                          onChanged: (_) {
                            setDialogState(() {});
                          },
                          decoration: const InputDecoration(
                            labelText: 'Shift notes',
                            hintText:
                                'Optional closeout context, customer impact, or operator handoff notes.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final report = buildPreview();
                      await Clipboard.setData(
                        ClipboardData(text: report.toMultilineText()),
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(report);
                      }
                    },
                    child: const Text('Copy closeout report'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      notesController.dispose();
    }
  }

  Future<PilotRolloutEvidenceReport?> _showPilotRolloutEvidenceDialog(
    BuildContext context, {
    required PilotDiagnosticsSnapshot diagnosticsSnapshot,
    required PilotReadinessReport readinessReport,
    required PilotRecoveryReport recoveryReport,
  }) async {
    final smokeNotesController = TextEditingController();
    final closeoutNotesController = TextEditingController();
    final rolloutNotesController = TextEditingController();
    var smokeVerdict = readinessReport.isBlocked
        ? 'BLOCKED'
        : readinessReport.shouldMonitor
        ? 'MONITOR'
        : 'PASS';
    var closeoutDecision =
        recoveryReport.attentionEntries.any((entry) => entry.isFailed) ||
            diagnosticsSnapshot.historyOverview.failedSales > 0
        ? 'ESCALATE INCIDENT'
        : diagnosticsSnapshot.pendingOutboxCount > 0
        ? 'MONITOR NEXT SHIFT'
        : 'HEALTHY HANDOFF';
    var rolloutRecommendation =
        closeoutDecision == 'ESCALATE INCIDENT' || smokeVerdict == 'BLOCKED'
        ? 'rollback_wave'
        : smokeVerdict == 'MONITOR' || closeoutDecision == 'MONITOR NEXT SHIFT'
        ? 'hold_wave'
        : 'advance_wave';

    PilotRolloutEvidenceReport buildPreview() {
      return PilotRolloutEvidenceReport(
        diagnosticsSnapshot: diagnosticsSnapshot,
        readinessReport: readinessReport,
        recoveryReport: recoveryReport,
        answers: PilotRolloutEvidenceAnswers(
          smokeVerdict: smokeVerdict,
          closeoutDecision: closeoutDecision,
          rolloutRecommendation: rolloutRecommendation,
          smokeNotes: smokeNotesController.text.trim(),
          closeoutNotes: closeoutNotesController.text.trim(),
          rolloutNotes: rolloutNotesController.text.trim(),
        ),
      );
    }

    try {
      return await showDialog<PilotRolloutEvidenceReport>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final preview = buildPreview();
              final tone = switch (preview.answers.rolloutRecommendation) {
                'advance_wave' => AppPalette.success,
                'hold_wave' => AppPalette.warning,
                'rollback_wave' => AppPalette.error,
                _ => AppPalette.primary,
              };

              return AlertDialog(
                title: const Text('Build rollout evidence pack'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'This pack is meant for the rollout lead or wave record. Summarize the smoke result, the end-of-shift outcome, and the recommendation for the current rollout wave.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.black.withValues(alpha: 0.68),
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 14),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: tone.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  preview.recommendationLabel,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: tone,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  preview.summary,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.black.withValues(
                                          alpha: 0.76,
                                        ),
                                        fontWeight: FontWeight.w600,
                                        height: 1.45,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: smokeVerdict,
                          decoration: const InputDecoration(
                            labelText: 'Smoke verdict',
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'PASS',
                              child: Text('PASS'),
                            ),
                            DropdownMenuItem(
                              value: 'MONITOR',
                              child: Text('MONITOR'),
                            ),
                            DropdownMenuItem(
                              value: 'BLOCKED',
                              child: Text('BLOCKED'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() {
                              smokeVerdict = value;
                              if (value == 'BLOCKED') {
                                rolloutRecommendation = 'rollback_wave';
                              } else if (value == 'MONITOR' &&
                                  rolloutRecommendation == 'advance_wave') {
                                rolloutRecommendation = 'hold_wave';
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          textCapitalization: TextCapitalization.sentences,
                          controller: smokeNotesController,
                          minLines: 2,
                          maxLines: 3,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Smoke notes',
                            hintText:
                                'Optional summary of the smoke result or any notable floor observation.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: closeoutDecision,
                          decoration: const InputDecoration(
                            labelText: 'Shift closeout decision',
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'HEALTHY HANDOFF',
                              child: Text('HEALTHY HANDOFF'),
                            ),
                            DropdownMenuItem(
                              value: 'MONITOR NEXT SHIFT',
                              child: Text('MONITOR NEXT SHIFT'),
                            ),
                            DropdownMenuItem(
                              value: 'ESCALATE INCIDENT',
                              child: Text('ESCALATE INCIDENT'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() {
                              closeoutDecision = value;
                              if (value == 'ESCALATE INCIDENT') {
                                rolloutRecommendation = 'rollback_wave';
                              } else if (value == 'MONITOR NEXT SHIFT' &&
                                  rolloutRecommendation == 'advance_wave') {
                                rolloutRecommendation = 'hold_wave';
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          textCapitalization: TextCapitalization.sentences,
                          controller: closeoutNotesController,
                          minLines: 2,
                          maxLines: 3,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Closeout notes',
                            hintText:
                                'Optional end-of-shift summary for the rollout lead.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: rolloutRecommendation,
                          decoration: const InputDecoration(
                            labelText: 'Rollout recommendation',
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'advance_wave',
                              child: Text('ADVANCE WAVE'),
                            ),
                            DropdownMenuItem(
                              value: 'hold_wave',
                              child: Text('HOLD CURRENT WAVE'),
                            ),
                            DropdownMenuItem(
                              value: 'rollback_wave',
                              child: Text('ROLLBACK CURRENT WAVE'),
                            ),
                            DropdownMenuItem(
                              value: 'manual_review',
                              child: Text('MANUAL REVIEW'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() {
                              rolloutRecommendation = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          textCapitalization: TextCapitalization.sentences,
                          controller: rolloutNotesController,
                          minLines: 2,
                          maxLines: 4,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Rollout lead notes',
                            hintText:
                                'Optional recommendation context, ticket reference, or wave-specific note.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final report = buildPreview();
                      await Clipboard.setData(
                        ClipboardData(text: report.toMultilineText()),
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(report);
                      }
                    },
                    child: const Text('Copy evidence pack'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      smokeNotesController.dispose();
      closeoutNotesController.dispose();
      rolloutNotesController.dispose();
    }
  }

  Future<PilotIncidentEscalationReport?> _showPilotIncidentEscalationDialog(
    BuildContext context, {
    required PilotDiagnosticsSnapshot diagnosticsSnapshot,
    required PilotReadinessReport readinessReport,
    required PilotRecoveryReport recoveryReport,
  }) async {
    final notesController = TextEditingController();
    var severity =
        recoveryReport.attentionEntries.any((entry) => entry.isFailed)
        ? 'sev2'
        : 'sev3';
    var impactScope = 'single_device';
    var checkoutBlocked = diagnosticsSnapshot.historyOverview.failedSales > 0;
    var moneyMovementRisk =
        recoveryReport.attentionEntries.isNotEmpty &&
        recoveryReport.attentionEntries.any((entry) => entry.isFailed);
    var rollbackRequested = readinessReport.isBlocked;

    PilotIncidentEscalationReport buildPreview() {
      return PilotIncidentEscalationReport(
        diagnosticsSnapshot: diagnosticsSnapshot,
        readinessReport: readinessReport,
        recoveryReport: recoveryReport,
        answers: PilotIncidentEscalationAnswers(
          severity: severity,
          impactScope: impactScope,
          checkoutBlocked: checkoutBlocked,
          moneyMovementRisk: moneyMovementRisk,
          rollbackRequested: rollbackRequested,
          notes: notesController.text.trim(),
        ),
      );
    }

    try {
      return await showDialog<PilotIncidentEscalationReport>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final preview = buildPreview();
              final tone = switch (preview.escalationDecision) {
                'immediate_escalation' => AppPalette.error,
                'urgent_review' => AppPalette.warning,
                _ => AppPalette.primary,
              };

              return AlertDialog(
                title: const Text('Build incident escalation pack'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Use this when the device has crossed from normal pilot monitoring into a support or engineering incident. The copied pack is meant to be pasted directly into the escalation thread.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.black.withValues(alpha: 0.68),
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 14),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: tone.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  preview.escalationDecisionLabel,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: tone,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  preview.summary,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.black.withValues(
                                          alpha: 0.76,
                                        ),
                                        fontWeight: FontWeight.w600,
                                        height: 1.45,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: severity,
                          decoration: const InputDecoration(
                            labelText: 'Severity',
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'sev1',
                              child: Text('SEV1'),
                            ),
                            DropdownMenuItem(
                              value: 'sev2',
                              child: Text('SEV2'),
                            ),
                            DropdownMenuItem(
                              value: 'sev3',
                              child: Text('SEV3'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() {
                              severity = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: impactScope,
                          decoration: const InputDecoration(
                            labelText: 'Impact scope',
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'single_device',
                              child: Text('SINGLE DEVICE'),
                            ),
                            DropdownMenuItem(
                              value: 'single_shop',
                              child: Text('SINGLE SHOP'),
                            ),
                            DropdownMenuItem(
                              value: 'wave',
                              child: Text('ROLLOUT WAVE'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setDialogState(() {
                              impactScope = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _CloseoutToggleCard(
                          label: 'Checkout is blocked on this device',
                          value: checkoutBlocked,
                          trueLabel: 'BLOCKED',
                          falseLabel: 'NOT BLOCKED',
                          dangerWhenTrue: true,
                          onChanged: (value) {
                            setDialogState(() {
                              checkoutBlocked = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _CloseoutToggleCard(
                          label: 'Money movement or ledger accuracy is at risk',
                          value: moneyMovementRisk,
                          trueLabel: 'AT RISK',
                          falseLabel: 'NOT AT RISK',
                          dangerWhenTrue: true,
                          onChanged: (value) {
                            setDialogState(() {
                              moneyMovementRisk = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _CloseoutToggleCard(
                          label: 'Rollback is being requested',
                          value: rollbackRequested,
                          trueLabel: 'ROLLBACK',
                          falseLabel: 'NO ROLLBACK',
                          dangerWhenTrue: true,
                          onChanged: (value) {
                            setDialogState(() {
                              rollbackRequested = value;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          textCapitalization: TextCapitalization.sentences,
                          controller: notesController,
                          minLines: 2,
                          maxLines: 4,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Incident notes',
                            hintText:
                                'Operator/support context, shop impact, or escalation instructions.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final report = buildPreview();
                      await Clipboard.setData(
                        ClipboardData(text: report.toMultilineText()),
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(report);
                      }
                    },
                    child: const Text('Copy escalation pack'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      notesController.dispose();
    }
  }

  String _buildEvidenceSessionLabel({
    required ShopInfo shop,
    required AppRuntimeInfo? runtimeInfo,
    required MobileSession? session,
  }) {
    final scope = runtimeInfo?.rolloutScopeLabel.trim();
    final tag = runtimeInfo?.releaseTag.trim();
    final operator = session?.email.trim();
    final dateLabel = DateTime.now().toIso8601String().split('T').first;
    final parts = <String>[
      shop.name.trim().isEmpty ? 'Business Hub' : shop.name.trim(),
      if (scope != null && scope.isNotEmpty) scope,
      if (tag != null && tag.isNotEmpty) tag,
      if (operator != null && operator.isNotEmpty) operator,
      dateLabel,
    ];
    return parts.join(' | ');
  }

  Future<String?> _showEvidenceSessionDialog(
    BuildContext context, {
    required String suggestedLabel,
    String? currentLabel,
  }) async {
    final controller = TextEditingController(
      text: currentLabel?.trim().isNotEmpty == true
          ? currentLabel!.trim()
          : suggestedLabel,
    );

    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Start fresh evidence session'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Use a clear session label for this rollout wave or shift. Starting a fresh session clears the captured evidence list and begins a new tracker window.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black.withValues(alpha: 0.68),
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Session label',
                      hintText: 'Wave or shift label',
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final nextLabel = controller.text.trim();
                  if (nextLabel.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Session label is required.'),
                      ),
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(nextLabel);
                },
                child: const Text('Start session'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<bool?> _showWorkspaceSettingsDialog(
    BuildContext context, {
    required ShopInfo currentShop,
    required MobileSession session,
    required MobileSyncCoordinator syncCoordinator,
  }) async {
    final taglineController = TextEditingController(text: currentShop.tagline);
    final footerController = TextEditingController(text: currentShop.footer);
    final phoneController = TextEditingController(text: currentShop.phone);
    var saving = false;

    try {
      return await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Edit workspace settings'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'These values update the local workspace immediately and then sync back to the live shop document for ${session.shopId}.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black.withValues(alpha: 0.66),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: taglineController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Tagline'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        textCapitalization: TextCapitalization.sentences,
                        controller: footerController,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Receipt footer',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Workspace phone',
                        ),
                      ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            final tagline = taglineController.text.trim();
                            final footer = footerController.text.trim();
                            final phone = phoneController.text.trim();
                            if (tagline.isEmpty || footer.isEmpty) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Tagline and receipt footer are required.',
                                  ),
                                ),
                              );
                              return;
                            }
                            setDialogState(() {
                              saving = true;
                            });
                            try {
                              await syncCoordinator.updateWorkspaceSettings(
                                currentShop: currentShop,
                                tagline: tagline,
                                footer: footer,
                                phone: phone,
                              );
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop(true);
                              }
                            } catch (error) {
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(
                                  dialogContext,
                                ).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Workspace save failed: $error',
                                    ),
                                  ),
                                );
                              }
                              setDialogState(() {
                                saving = false;
                              });
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      taglineController.dispose();
      footerController.dispose();
      phoneController.dispose();
    }
  }
}

class _PilotSmokeCheckCard extends StatelessWidget {
  const _PilotSmokeCheckCard({
    required this.check,
    required this.outcome,
    required this.onOutcomeChanged,
  });

  final PilotSmokeCheckDefinition check;
  final PilotSmokeCheckOutcome outcome;
  final ValueChanged<PilotSmokeCheckOutcome> onOutcomeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tone = switch (outcome) {
      PilotSmokeCheckOutcome.passed => AppPalette.success,
      PilotSmokeCheckOutcome.failed => AppPalette.error,
      PilotSmokeCheckOutcome.pending => AppPalette.primary,
    };

    Widget buildChoice(
      String label,
      PilotSmokeCheckOutcome value,
      IconData icon,
    ) {
      final selected = outcome == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onOutcomeChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? tone.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? tone.withValues(alpha: 0.42)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  size: 16,
                  color: selected ? tone : Colors.black.withValues(alpha: 0.62),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? tone
                        : Colors.black.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    check.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                AppTag(
                  label: check.isCritical ? 'CRITICAL' : 'STANDARD',
                  icon: check.isCritical
                      ? Icons.priority_high_rounded
                      : Icons.rule_rounded,
                  tone: check.isCritical ? AppTone.danger : AppTone.primary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                buildChoice(
                  'Pending',
                  PilotSmokeCheckOutcome.pending,
                  Icons.hourglass_empty_rounded,
                ),
                const SizedBox(width: 8),
                buildChoice(
                  'Pass',
                  PilotSmokeCheckOutcome.passed,
                  Icons.check_circle_rounded,
                ),
                const SizedBox(width: 8),
                buildChoice(
                  'Fail',
                  PilotSmokeCheckOutcome.failed,
                  Icons.cancel_rounded,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseoutToggleCard extends StatelessWidget {
  const _CloseoutToggleCard({
    required this.label,
    required this.value,
    required this.onChanged,
    this.trueLabel = 'STABLE',
    this.falseLabel = 'UNSTABLE',
    this.dangerWhenTrue = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String trueLabel;
  final String falseLabel;
  final bool dangerWhenTrue;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tone = value
        ? (dangerWhenTrue ? AppTone.danger : AppTone.success)
        : (dangerWhenTrue ? AppTone.success : AppTone.warning);
    final toneColors = toneColorsOf(context, tone);

    final labelText = value ? trueLabel : falseLabel;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppTag(
                    label: labelText,
                    icon: value
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    tone: tone,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: toneColors.foreground,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessNoteRow extends StatelessWidget {
  const _ReadinessNoteRow({required this.message, required this.tone});

  final String message;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(Icons.circle, size: 10, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutboxAttentionRow extends StatelessWidget {
  const _OutboxAttentionRow({required this.entry, required this.onRetry});

  final CommerceOutboxAttentionEntry entry;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tone = entry.isFailed
        ? AppTone.danger
        : entry.isSyncing
        ? AppTone.primary
        : AppTone.warning;
    final toneColors = toneColorsOf(context, tone);
    final customerLabel = entry.customerName?.trim().isNotEmpty == true
        ? entry.customerName!.trim()
        : 'Walk-in customer';
    final errorLabel = entry.lastError?.trim().isNotEmpty == true
        ? entry.lastError!.trim()
        : 'No error detail captured';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: toneColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    entry.commandLabel,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                AppTag(
                  label: entry.statusLabel,
                  icon: entry.isFailed
                      ? Icons.error_outline_rounded
                      : entry.isSyncing
                      ? Icons.sync_rounded
                      : Icons.schedule_rounded,
                  tone: tone,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$customerLabel | ${formatCurrency(entry.total)}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Command ${entry.commandId} | attempts ${entry.attemptCount}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black.withValues(alpha: 0.62),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              errorLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: toneColors.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry this receipt'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceStrong,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppPalette.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppPalette.info),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.black.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DomainSettingsRow extends StatelessWidget {
  const _DomainSettingsRow({required this.state});

  final DomainControlState state;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tone = switch (state.pilotSignoffStatus) {
      'production_safe' => AppTone.success,
      'ready_for_cutover' => AppTone.primary,
      'rollback_recommended' => AppTone.danger,
      _ => state.isPostgresPrimary ? AppTone.success : AppTone.warning,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    state.domain.toUpperCase(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                AppTag(
                  label: state.postureLabel.toUpperCase(),
                  icon: state.isPostgresPrimary
                      ? Icons.verified_rounded
                      : Icons.swap_horiz_rounded,
                  tone: tone,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              state.pilotSignoffSummary ??
                  'Write master: ${state.writeMaster} | epoch ${state.currentEpoch}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black.withValues(alpha: 0.62),
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            if (state.pilotRecommendedAction?.isNotEmpty == true) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'Next action: ${state.pilotRecommendedAction}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: toneColorsOf(context, tone).foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

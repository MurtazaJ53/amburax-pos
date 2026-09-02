import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/runtime/app_runtime_info.dart';
import 'package:business_hub_mobile/core/runtime/pilot_diagnostics_snapshot.dart';
import 'package:business_hub_mobile/core/runtime/pilot_evidence_tracker.dart';
import 'package:business_hub_mobile/core/runtime/pilot_operator_action_plan.dart';
import 'package:business_hub_mobile/core/runtime/pilot_readiness_report.dart';
import 'package:business_hub_mobile/core/runtime/pilot_recovery_report.dart';
import 'package:business_hub_mobile/core/runtime/pilot_rollout_decision_summary.dart';
import 'package:business_hub_mobile/core/runtime/pilot_wave_archive_pack.dart';
import 'package:business_hub_mobile/core/runtime/pilot_wave_closeout_readiness.dart';
import 'package:business_hub_mobile/core/runtime/pilot_wave_signoff_pack.dart';
import 'package:business_hub_mobile/core/sync/mobile_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppRuntimeInfo runtimeInfo() {
    return const AppRuntimeInfo(
      appName: 'Business Hub',
      packageName: 'com.example.businesshub',
      version: '1.4.0',
      buildNumber: '12',
      releaseChannel: 'pilot',
      releaseSha: 'abc1234',
      releaseTag: 'mobile-v1.4.0',
      pilotScope: 'wave-2',
    );
  }

  PilotDiagnosticsSnapshot diagnostics({
    int pendingOutboxCount = 0,
    int failedSales = 0,
  }) {
    return PilotDiagnosticsSnapshot(
      runtimeInfo: runtimeInfo(),
      shop: ShopInfo.fallback(),
      session: null,
      backendBaseUrl: 'https://api.example.com/api/v1',
      syncStatus: MobileSyncStatus.idle,
      historyOverview: HistoryOverview(
        totalSales: 12,
        syncedSales: 12 - failedSales,
        queuedSales: pendingOutboxCount,
        failedSales: failedSales,
        totalRevenue: 12000,
        queuedRevenue: pendingOutboxCount * 250,
      ),
      pendingOutboxCount: pendingOutboxCount,
      domainStates: const <DomainControlState>[
        DomainControlState(
          domain: 'inventory',
          currentEpoch: 4,
          cutoverStatus: 'postgres_primary',
          writeMaster: 'postgres',
          controlPresent: true,
          shadowReadsEnabled: true,
          isEnabled: true,
          canWriteOnPostgresSurface: true,
          pilotSignoffStatus: 'production_safe',
        ),
      ],
      operatorEmailOverride: 'pilot@example.com',
      operatorRoleOverride: 'manager',
      workspaceIdOverride: 'shop-1',
      costVisibilityOverride: true,
    );
  }

  PilotWaveArchivePack evaluateForTracker(
    PilotEvidenceTrackerState tracker, {
    int pendingOutboxCount = 0,
    int failedSales = 0,
    List<CommerceOutboxAttentionEntry> attentionEntries =
        const <CommerceOutboxAttentionEntry>[],
  }) {
    final snapshot = diagnostics(
      pendingOutboxCount: pendingOutboxCount,
      failedSales: failedSales,
    );
    final recovery = PilotRecoveryReport(
      diagnosticsSnapshot: snapshot,
      attentionEntries: attentionEntries,
    );
    final readiness = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: snapshot,
      attentionEntries: attentionEntries,
    );
    final actionPlan = PilotOperatorActionPlan.evaluate(
      diagnosticsSnapshot: snapshot,
      readinessReport: readiness,
      recoveryReport: recovery,
    );
    final decision = PilotRolloutDecisionSummary.evaluate(
      diagnosticsSnapshot: snapshot,
      readinessReport: readiness,
      recoveryReport: recovery,
      actionPlan: actionPlan,
      evidenceTracker: tracker,
    );
    final closeout = PilotWaveCloseoutReadiness.evaluate(
      diagnosticsSnapshot: snapshot,
      readinessReport: readiness,
      recoveryReport: recovery,
      actionPlan: actionPlan,
      rolloutDecisionSummary: decision,
      evidenceTracker: tracker,
    );
    final signoff = PilotWaveSignoffPack.evaluate(
      diagnosticsSnapshot: snapshot,
      readinessReport: readiness,
      recoveryReport: recovery,
      actionPlan: actionPlan,
      rolloutDecisionSummary: decision,
      waveCloseoutReadiness: closeout,
      evidenceTracker: tracker,
    );

    return PilotWaveArchivePack.evaluate(
      waveSignoffPack: signoff,
      evidenceTracker: tracker,
    );
  }

  test('ready signoff with captured signoff pack becomes archive ready', () {
    final tracker = const PilotEvidenceTrackerState()
        .ensureSession(
          defaultLabel: 'Wave 2 shift A',
          startedAt: DateTime.utc(2026, 5, 3, 7),
        )
        .markCaptured(
          'pilot_snapshot',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 5),
        )
        .markCaptured(
          'readiness_signoff',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 10),
        )
        .markCaptured(
          'smoke_report',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 15),
        )
        .markCaptured(
          'handoff_pack',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 20),
        )
        .markCaptured(
          'shift_closeout',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 25),
        )
        .markCaptured(
          'rollout_evidence',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 30),
        )
        .markCaptured(
          'rollout_decision_summary',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 31),
        )
        .markCaptured(
          'wave_signoff_pack',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 32),
        )
        .startFreshSession(
          sessionLabel: 'Wave 2 shift B',
          startedAt: DateTime.utc(2026, 5, 3, 12),
        )
        .markCaptured(
          'pilot_snapshot',
          capturedAt: DateTime.utc(2026, 5, 3, 12, 5),
        )
        .markCaptured(
          'readiness_signoff',
          capturedAt: DateTime.utc(2026, 5, 3, 12, 10),
        )
        .markCaptured(
          'smoke_report',
          capturedAt: DateTime.utc(2026, 5, 3, 12, 15),
        )
        .markCaptured(
          'handoff_pack',
          capturedAt: DateTime.utc(2026, 5, 3, 12, 20),
        )
        .markCaptured(
          'shift_closeout',
          capturedAt: DateTime.utc(2026, 5, 3, 12, 25),
        )
        .markCaptured(
          'rollout_evidence',
          capturedAt: DateTime.utc(2026, 5, 3, 12, 30),
        )
        .markCaptured(
          'rollout_decision_summary',
          capturedAt: DateTime.utc(2026, 5, 3, 12, 31),
        )
        .markCaptured(
          'wave_signoff_pack',
          capturedAt: DateTime.utc(2026, 5, 3, 12, 32),
        );

    final report = evaluateForTracker(tracker);

    expect(report.archiveStatusLabel, 'ARCHIVE READY');
    expect(report.summary, contains('ready to archive'));
  });

  test('missing signoff artifact becomes archive incomplete', () {
    final tracker = const PilotEvidenceTrackerState().markCaptured(
      'rollout_decision_summary',
    );

    final report = evaluateForTracker(tracker);

    expect(report.archiveStatusLabel, 'ARCHIVE INCOMPLETE');
    expect(report.summary, contains('not ready yet'));
  });

  test('blocked signoff becomes archive blocked', () {
    final tracker = const PilotEvidenceTrackerState().markCaptured(
      'wave_signoff_pack',
    );
    final report = evaluateForTracker(
      tracker,
      failedSales: 1,
      attentionEntries: const <CommerceOutboxAttentionEntry>[
        CommerceOutboxAttentionEntry(
          commandId: 'cmd-1',
          commandType: 'sale',
          syncStatus: 'failed',
          attemptCount: 2,
          updatedAt: 10,
          total: 300,
        ),
      ],
    );

    expect(report.archiveStatusLabel, 'ARCHIVE BLOCKED');
    expect(report.summary, contains('Do not archive'));
  });
}

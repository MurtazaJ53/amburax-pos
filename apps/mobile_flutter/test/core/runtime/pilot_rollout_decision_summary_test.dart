import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/runtime/app_runtime_info.dart';
import 'package:business_hub_mobile/core/runtime/pilot_diagnostics_snapshot.dart';
import 'package:business_hub_mobile/core/runtime/pilot_evidence_tracker.dart';
import 'package:business_hub_mobile/core/runtime/pilot_operator_action_plan.dart';
import 'package:business_hub_mobile/core/runtime/pilot_readiness_report.dart';
import 'package:business_hub_mobile/core/runtime/pilot_recovery_report.dart';
import 'package:business_hub_mobile/core/runtime/pilot_rollout_decision_summary.dart';
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
    String syncStatus = 'idle',
    List<DomainControlState> domainStates = const <DomainControlState>[
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
      DomainControlState(
        domain: 'customers',
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
  }) {
    return PilotDiagnosticsSnapshot(
      runtimeInfo: runtimeInfo(),
      shop: ShopInfo.fallback(),
      session: null,
      backendBaseUrl: 'https://api.example.com/api/v1',
      syncStatus: MobileSyncStatus.values.firstWhere(
        (value) => value.name == syncStatus,
      ),
      historyOverview: HistoryOverview(
        totalSales: 12,
        syncedSales: 12 - failedSales,
        queuedSales: pendingOutboxCount,
        failedSales: failedSales,
        totalRevenue: 12000,
        queuedRevenue: pendingOutboxCount * 250,
      ),
      pendingOutboxCount: pendingOutboxCount,
      domainStates: domainStates,
      operatorEmailOverride: 'pilot@example.com',
      operatorRoleOverride: 'manager',
      workspaceIdOverride: 'shop-1',
      costVisibilityOverride: true,
    );
  }

  test('ready device with healthy archive becomes ready to expand', () {
    final snapshot = diagnostics();
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
        );
    final recovery = PilotRecoveryReport(
      diagnosticsSnapshot: snapshot,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );
    final readiness = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: snapshot,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );
    final actionPlan = PilotOperatorActionPlan.evaluate(
      diagnosticsSnapshot: snapshot,
      readinessReport: readiness,
      recoveryReport: recovery,
    );

    final report = PilotRolloutDecisionSummary.evaluate(
      diagnosticsSnapshot: snapshot,
      readinessReport: readiness,
      recoveryReport: recovery,
      actionPlan: actionPlan,
      evidenceTracker: tracker,
    );

    expect(report.verdictLabel, 'READY TO EXPAND');
    expect(report.summary, contains('strong posture'));
  });

  test('recent archive attention becomes investigate before expand', () {
    final snapshot = diagnostics();
    final tracker = const PilotEvidenceTrackerState()
        .ensureSession(
          defaultLabel: 'Wave 2 shift A',
          startedAt: DateTime.utc(2026, 5, 3, 7),
        )
        .markCaptured(
          'pilot_snapshot',
          capturedAt: DateTime.utc(2026, 5, 3, 7, 5),
        )
        .startFreshSession(
          sessionLabel: 'Wave 2 shift B',
          startedAt: DateTime.utc(2026, 5, 3, 12),
        );
    final recovery = PilotRecoveryReport(
      diagnosticsSnapshot: snapshot,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );
    final readiness = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: snapshot,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );
    final actionPlan = PilotOperatorActionPlan.evaluate(
      diagnosticsSnapshot: snapshot,
      readinessReport: readiness,
      recoveryReport: recovery,
    );

    final report = PilotRolloutDecisionSummary.evaluate(
      diagnosticsSnapshot: snapshot,
      readinessReport: readiness,
      recoveryReport: recovery,
      actionPlan: actionPlan,
      evidenceTracker: tracker,
    );

    expect(report.verdictLabel, 'INVESTIGATE BEFORE EXPAND');
    expect(
      report.reasons.join(' '),
      contains(
        'Recent archived sessions still show attention-needed closeouts',
      ),
    );
  });

  test('blocked readiness becomes rollback and escalate', () {
    final snapshot = diagnostics(failedSales: 1);
    const tracker = PilotEvidenceTrackerState();
    final attentionEntries = <CommerceOutboxAttentionEntry>[
      const CommerceOutboxAttentionEntry(
        commandId: 'cmd-1',
        commandType: 'sale',
        syncStatus: 'failed',
        attemptCount: 3,
        updatedAt: 1000,
        total: 550,
      ),
    ];
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

    final report = PilotRolloutDecisionSummary.evaluate(
      diagnosticsSnapshot: snapshot,
      readinessReport: readiness,
      recoveryReport: recovery,
      actionPlan: actionPlan,
      evidenceTracker: tracker,
    );

    expect(report.verdictLabel, 'ROLLBACK AND ESCALATE');
    expect(report.summary, contains('Freeze rollout expansion'));
  });
}

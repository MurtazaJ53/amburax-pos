import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/runtime/app_runtime_info.dart';
import 'package:business_hub_mobile/core/runtime/pilot_diagnostics_snapshot.dart';
import 'package:business_hub_mobile/core/runtime/pilot_readiness_report.dart';
import 'package:business_hub_mobile/core/runtime/pilot_recovery_report.dart';
import 'package:business_hub_mobile/core/runtime/pilot_shift_closeout_report.dart';
import 'package:business_hub_mobile/core/sync/mobile_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PilotDiagnosticsSnapshot buildDiagnostics({
    MobileSyncStatus syncStatus = MobileSyncStatus.idle,
    int pendingOutboxCount = 0,
    int failedSales = 0,
  }) {
    const runtime = AppRuntimeInfo(
      appName: 'Business Hub',
      packageName: 'com.example.businesshub',
      version: '1.4.0',
      buildNumber: '14',
      releaseChannel: 'pilot',
      releaseSha: 'abc1234',
      releaseTag: 'mobile-v1.4.0',
      pilotScope: 'limbdi-wave-2',
    );

    return PilotDiagnosticsSnapshot(
      runtimeInfo: runtime,
      shop: const ShopInfo(
        name: 'Pilot Shop',
        tagline: 'Fast retail',
        footer: 'Thanks',
        currency: 'INR',
        phone: '',
      ),
      session: null,
      backendBaseUrl: 'https://api.business-hub.test/api/v1',
      syncStatus: syncStatus,
      historyOverview: HistoryOverview(
        totalSales: 22,
        syncedSales: 22,
        queuedSales: pendingOutboxCount,
        failedSales: failedSales,
        totalRevenue: 12500,
        queuedRevenue: pendingOutboxCount > 0 ? 850 : 0,
        lastSyncedAt: null,
      ),
      operatorEmailOverride: 'owner@pilot.test',
      operatorRoleOverride: 'owner',
      workspaceIdOverride: 'shop-pilot-2',
      pendingOutboxCount: pendingOutboxCount,
      domainStates: const <DomainControlState>[
        DomainControlState(
          domain: 'sales',
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
      generatedAt: DateTime.utc(2026, 5, 2, 22, 0),
    );
  }

  test('closeout report is healthy when shift ended cleanly', () {
    final diagnostics = buildDiagnostics();
    final readiness = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );
    final recovery = PilotRecoveryReport(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
      generatedAt: DateTime.utc(2026, 5, 2, 22, 10),
    );
    final report = PilotShiftCloseoutReport(
      diagnosticsSnapshot: diagnostics,
      readinessReport: readiness,
      recoveryReport: recovery,
      answers: const PilotShiftCloseoutAnswers(
        checkoutStable: true,
        replayStable: true,
        customerLedgerStable: true,
        rollbackRequired: false,
        notes: 'Shift closed cleanly.',
      ),
      generatedAt: DateTime.utc(2026, 5, 2, 22, 20),
    );

    expect(report.decisionLabel, 'HEALTHY HANDOFF');
    expect(report.summary, contains('finished the shift cleanly'));
  });

  test(
    'closeout report monitors when queue work remains but no incident is declared',
    () {
      final diagnostics = buildDiagnostics(
        syncStatus: MobileSyncStatus.offline,
        pendingOutboxCount: 2,
      );
      final readiness = PilotReadinessReport.evaluate(
        diagnosticsSnapshot: diagnostics,
        attentionEntries: const <CommerceOutboxAttentionEntry>[],
      );
      final recovery = PilotRecoveryReport(
        diagnosticsSnapshot: diagnostics,
        attentionEntries: const <CommerceOutboxAttentionEntry>[],
        generatedAt: DateTime.utc(2026, 5, 2, 22, 10),
      );
      final report = PilotShiftCloseoutReport(
        diagnosticsSnapshot: diagnostics,
        readinessReport: readiness,
        recoveryReport: recovery,
        answers: const PilotShiftCloseoutAnswers(
          checkoutStable: true,
          replayStable: true,
          customerLedgerStable: true,
          rollbackRequired: false,
        ),
      );

      expect(report.decisionLabel, 'MONITOR NEXT SHIFT');
    },
  );

  test('closeout report escalates when rollback is required', () {
    final diagnostics = buildDiagnostics();
    final readiness = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );
    final recovery = PilotRecoveryReport(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );
    final report = PilotShiftCloseoutReport(
      diagnosticsSnapshot: diagnostics,
      readinessReport: readiness,
      recoveryReport: recovery,
      answers: const PilotShiftCloseoutAnswers(
        checkoutStable: true,
        replayStable: true,
        customerLedgerStable: true,
        rollbackRequired: true,
        notes: 'Rollback before morning shift.',
      ),
    );

    final text = report.toMultilineText();

    expect(report.decisionLabel, 'ESCALATE INCIDENT');
    expect(text, contains('Business Hub pilot shift closeout report'));
    expect(text, contains('Release tag: mobile-v1.4.0'));
    expect(text, contains('Pilot scope: limbdi-wave-2'));
    expect(text, contains('- Rollback required: YES'));
    expect(text, contains('Rollback before morning shift.'));
  });
}

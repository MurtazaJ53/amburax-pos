import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/runtime/app_runtime_info.dart';
import 'package:business_hub_mobile/core/runtime/pilot_diagnostics_snapshot.dart';
import 'package:business_hub_mobile/core/runtime/pilot_readiness_report.dart';
import 'package:business_hub_mobile/core/runtime/pilot_smoke_report.dart';
import 'package:business_hub_mobile/core/sync/mobile_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PilotDiagnosticsSnapshot buildDiagnostics() {
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
      syncStatus: MobileSyncStatus.idle,
      historyOverview: const HistoryOverview(
        totalSales: 22,
        syncedSales: 22,
        queuedSales: 0,
        failedSales: 0,
        totalRevenue: 12500,
        queuedRevenue: 0,
        lastSyncedAt: null,
      ),
      operatorEmailOverride: 'owner@pilot.test',
      operatorRoleOverride: 'owner',
      workspaceIdOverride: 'shop-pilot-2',
      pendingOutboxCount: 0,
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
      generatedAt: DateTime.utc(2026, 5, 2, 20, 0),
    );
  }

  test(
    'smoke report returns pass when all checks pass and readiness is clear',
    () {
      final diagnostics = buildDiagnostics();
      final readiness = PilotReadinessReport.evaluate(
        diagnosticsSnapshot: diagnostics,
        attentionEntries: const <CommerceOutboxAttentionEntry>[],
      );
      final report = PilotSmokeReport(
        diagnosticsSnapshot: diagnostics,
        readinessReport: readiness,
        results: defaultPilotSmokeChecks
            .map(
              (check) => PilotSmokeCheckResult(
                check: check,
                outcome: PilotSmokeCheckOutcome.passed,
              ),
            )
            .toList(growable: false),
        operatorNotes: 'Floor run completed cleanly.',
        generatedAt: DateTime.utc(2026, 5, 2, 20, 30),
      );

      expect(readiness.statusLabel, 'READY FOR SHIFT');
      expect(report.verdictLabel, 'PASS');
      expect(report.passedCount, defaultPilotSmokeChecks.length);
      expect(report.failedCount, 0);
      expect(report.pendingCount, 0);
    },
  );

  test('smoke report blocks when a critical smoke check fails', () {
    final diagnostics = buildDiagnostics();
    final readiness = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );
    final report = PilotSmokeReport(
      diagnosticsSnapshot: diagnostics,
      readinessReport: readiness,
      results: <PilotSmokeCheckResult>[
        for (final check in defaultPilotSmokeChecks)
          PilotSmokeCheckResult(
            check: check,
            outcome: check.id == 'cash_sale'
                ? PilotSmokeCheckOutcome.failed
                : PilotSmokeCheckOutcome.passed,
          ),
      ],
      generatedAt: DateTime.utc(2026, 5, 2, 20, 45),
    );

    expect(report.hasCriticalFailure, isTrue);
    expect(report.verdictLabel, 'BLOCKED');
    expect(report.summary, contains('Critical smoke failures'));
  });

  test('smoke report export includes release scope and result lines', () {
    final diagnostics = buildDiagnostics();
    final readiness = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );
    final report = PilotSmokeReport(
      diagnosticsSnapshot: diagnostics,
      readinessReport: readiness,
      results: <PilotSmokeCheckResult>[
        for (final check in defaultPilotSmokeChecks)
          PilotSmokeCheckResult(
            check: check,
            outcome: check.id == 'scanner'
                ? PilotSmokeCheckOutcome.failed
                : PilotSmokeCheckOutcome.passed,
          ),
      ],
      operatorNotes: 'Scanner lagged during first scan.',
      generatedAt: DateTime.utc(2026, 5, 2, 21, 0),
    );

    final text = report.toMultilineText();

    expect(text, contains('Business Hub pilot smoke execution report'));
    expect(text, contains('Release tag: mobile-v1.4.0'));
    expect(text, contains('Pilot scope: limbdi-wave-2'));
    expect(text, contains('Verdict: BLOCKED'));
    expect(
      text,
      contains('- Barcode / scanner flow works: FAIL | priority=critical'),
    );
    expect(text, contains('Operator notes:'));
    expect(text, contains('Scanner lagged during first scan.'));
  });
}

import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/runtime/app_runtime_info.dart';
import 'package:business_hub_mobile/core/runtime/pilot_diagnostics_snapshot.dart';
import 'package:business_hub_mobile/core/runtime/pilot_incident_escalation_report.dart';
import 'package:business_hub_mobile/core/runtime/pilot_readiness_report.dart';
import 'package:business_hub_mobile/core/runtime/pilot_recovery_report.dart';
import 'package:business_hub_mobile/core/sync/mobile_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PilotDiagnosticsSnapshot buildDiagnostics({int failedSales = 0}) {
    const runtime = AppRuntimeInfo(
      appName: 'Business Hub',
      packageName: 'com.example.businesshub',
      version: '1.4.2',
      buildNumber: '16',
      releaseChannel: 'pilot',
      releaseSha: 'fedc321',
      releaseTag: 'mobile-v1.4.2',
      pilotScope: 'surat-wave-1',
    );

    return PilotDiagnosticsSnapshot(
      runtimeInfo: runtime,
      shop: const ShopInfo(
        name: 'Surat Pilot',
        tagline: 'Fast retail',
        footer: 'Thanks',
        currency: 'INR',
        phone: '',
      ),
      session: null,
      backendBaseUrl: 'https://api.business-hub.test/api/v1',
      syncStatus: MobileSyncStatus.error,
      historyOverview: HistoryOverview(
        totalSales: 12,
        syncedSales: 10,
        queuedSales: 2,
        failedSales: failedSales,
        totalRevenue: 6400,
        queuedRevenue: 700,
        lastSyncedAt: null,
      ),
      operatorEmailOverride: 'owner@surat.test',
      operatorRoleOverride: 'owner',
      workspaceIdOverride: 'shop-surat-1',
      pendingOutboxCount: 2,
      domainStates: const <DomainControlState>[],
      generatedAt: DateTime.utc(2026, 5, 3, 0, 0),
    );
  }

  test(
    'incident escalation report marks immediate escalation for rollback risk',
    () {
      final diagnostics = buildDiagnostics(failedSales: 1);
      final readiness = PilotReadinessReport.evaluate(
        diagnosticsSnapshot: diagnostics,
        attentionEntries: const <CommerceOutboxAttentionEntry>[
          CommerceOutboxAttentionEntry(
            commandId: 'sale-1',
            commandType: 'sale_create',
            syncStatus: 'failed',
            attemptCount: 3,
            updatedAt: 1714694400,
            total: 700,
          ),
        ],
      );
      final recovery = PilotRecoveryReport(
        diagnosticsSnapshot: diagnostics,
        attentionEntries: const <CommerceOutboxAttentionEntry>[
          CommerceOutboxAttentionEntry(
            commandId: 'sale-1',
            commandType: 'sale_create',
            syncStatus: 'failed',
            attemptCount: 3,
            updatedAt: 1714694400,
            total: 700,
            lastError: 'Balance mismatch',
          ),
        ],
      );

      final report = PilotIncidentEscalationReport(
        diagnosticsSnapshot: diagnostics,
        readinessReport: readiness,
        recoveryReport: recovery,
        answers: const PilotIncidentEscalationAnswers(
          severity: 'sev1',
          impactScope: 'single_shop',
          checkoutBlocked: true,
          moneyMovementRisk: true,
          rollbackRequested: true,
          notes: 'Checkout blocked and payment totals look unsafe.',
        ),
      );

      expect(report.escalationDecisionLabel, 'IMMEDIATE ESCALATION');
      expect(report.summary, contains('immediate escalation'));
    },
  );

  test(
    'incident escalation export includes severity and embedded sections',
    () {
      final diagnostics = buildDiagnostics();
      final readiness = PilotReadinessReport.evaluate(
        diagnosticsSnapshot: diagnostics,
        attentionEntries: const <CommerceOutboxAttentionEntry>[],
      );
      final recovery = PilotRecoveryReport(
        diagnosticsSnapshot: diagnostics,
        attentionEntries: const <CommerceOutboxAttentionEntry>[],
      );
      final report = PilotIncidentEscalationReport(
        diagnosticsSnapshot: diagnostics,
        readinessReport: readiness,
        recoveryReport: recovery,
        answers: const PilotIncidentEscalationAnswers(
          severity: 'sev2',
          impactScope: 'wave',
          checkoutBlocked: false,
          moneyMovementRisk: false,
          rollbackRequested: false,
          notes: 'Support should watch this wave closely.',
        ),
      );

      final text = report.toMultilineText();

      expect(text, contains('Business Hub pilot incident escalation pack'));
      expect(text, contains('Severity: SEV2'));
      expect(text, contains('Impact scope: ROLLOUT WAVE'));
      expect(text, contains('Pilot scope: surat-wave-1'));
      expect(text, contains('=== READINESS SIGNOFF ==='));
      expect(text, contains('=== LAUNCH SNAPSHOT ==='));
      expect(text, contains('=== RECOVERY REPORT ==='));
    },
  );
}

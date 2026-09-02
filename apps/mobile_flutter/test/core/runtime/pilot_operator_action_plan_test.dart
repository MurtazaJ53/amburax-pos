import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/runtime/app_runtime_info.dart';
import 'package:business_hub_mobile/core/runtime/pilot_diagnostics_snapshot.dart';
import 'package:business_hub_mobile/core/runtime/pilot_operator_action_plan.dart';
import 'package:business_hub_mobile/core/runtime/pilot_readiness_report.dart';
import 'package:business_hub_mobile/core/runtime/pilot_recovery_report.dart';
import 'package:business_hub_mobile/core/sync/mobile_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PilotDiagnosticsSnapshot buildDiagnostics({
    MobileSyncStatus syncStatus = MobileSyncStatus.idle,
    int pendingOutboxCount = 0,
    int failedSales = 0,
    int rejectedSales = 0,
    String? operatorEmail,
    String? workspaceId,
  }) {
    const runtime = AppRuntimeInfo(
      appName: 'Business Hub',
      packageName: 'com.example.businesshub',
      version: '1.4.3',
      buildNumber: '17',
      releaseChannel: 'pilot',
      releaseSha: '1122abc',
      releaseTag: 'mobile-v1.4.3',
      pilotScope: 'bhavnagar-wave-1',
    );

    return PilotDiagnosticsSnapshot(
      runtimeInfo: runtime,
      shop: const ShopInfo(
        name: 'Bhavnagar Pilot',
        tagline: 'Fast retail',
        footer: 'Thanks',
        currency: 'INR',
        phone: '',
      ),
      session: null,
      backendBaseUrl: 'https://api.business-hub.test/api/v1',
      syncStatus: syncStatus,
      historyOverview: HistoryOverview(
        totalSales: 9,
        syncedSales: 9,
        queuedSales: pendingOutboxCount,
        failedSales: failedSales,
        rejectedSales: rejectedSales,
        totalRevenue: 5200,
        queuedRevenue: pendingOutboxCount > 0 ? 500 : 0,
        lastSyncedAt: null,
      ),
      operatorEmailOverride: operatorEmail,
      operatorRoleOverride: operatorEmail == null ? null : 'owner',
      workspaceIdOverride: workspaceId,
      pendingOutboxCount: pendingOutboxCount,
      domainStates: const <DomainControlState>[],
      generatedAt: DateTime.utc(2026, 5, 3, 0, 30),
    );
  }

  test('action plan escalates when failures are present', () {
    final diagnostics = buildDiagnostics(
      syncStatus: MobileSyncStatus.error,
      failedSales: 1,
      rejectedSales: 1,
      operatorEmail: 'owner@pilot.test',
      workspaceId: 'shop-bhavnagar-1',
    );
    final readiness = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[
        CommerceOutboxAttentionEntry(
          commandId: 'sale-1',
          commandType: 'sale_create',
          syncStatus: 'failed',
          attemptCount: 2,
          updatedAt: 1714696200,
          total: 500,
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
          attemptCount: 2,
          updatedAt: 1714696200,
          total: 500,
        ),
      ],
    );

    final plan = PilotOperatorActionPlan.evaluate(
      diagnosticsSnapshot: diagnostics,
      readinessReport: readiness,
      recoveryReport: recovery,
    );

    expect(plan.actionId, 'incident_escalation');
  });

  test('action plan points to recovery desk for queued work', () {
    final diagnostics = buildDiagnostics(
      pendingOutboxCount: 2,
      operatorEmail: 'owner@pilot.test',
      workspaceId: 'shop-bhavnagar-1',
    );
    final readiness = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[
        CommerceOutboxAttentionEntry(
          commandId: 'sale-2',
          commandType: 'sale_create',
          syncStatus: 'pending',
          attemptCount: 0,
          updatedAt: 1714696200,
          total: 250,
        ),
      ],
    );
    final recovery = PilotRecoveryReport(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[
        CommerceOutboxAttentionEntry(
          commandId: 'sale-2',
          commandType: 'sale_create',
          syncStatus: 'pending',
          attemptCount: 0,
          updatedAt: 1714696200,
          total: 250,
        ),
      ],
    );

    final plan = PilotOperatorActionPlan.evaluate(
      diagnosticsSnapshot: diagnostics,
      readinessReport: readiness,
      recoveryReport: recovery,
    );

    expect(plan.actionId, 'recovery_desk');
  });

  test('action plan points to smoke checklist when posture is clean', () {
    final diagnostics = buildDiagnostics(
      operatorEmail: 'owner@pilot.test',
      workspaceId: 'shop-bhavnagar-1',
    );
    final readiness = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );
    final recovery = PilotRecoveryReport(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );

    final plan = PilotOperatorActionPlan.evaluate(
      diagnosticsSnapshot: diagnostics,
      readinessReport: readiness,
      recoveryReport: recovery,
    );

    expect(plan.actionId, 'smoke_checklist');
    expect(
      plan.toMultilineText(),
      contains('Recommended action: Run smoke checklist'),
    );
  });
}

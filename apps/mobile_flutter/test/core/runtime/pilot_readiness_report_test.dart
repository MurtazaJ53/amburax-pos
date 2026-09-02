import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/runtime/app_runtime_info.dart';
import 'package:business_hub_mobile/core/runtime/pilot_diagnostics_snapshot.dart';
import 'package:business_hub_mobile/core/runtime/pilot_readiness_report.dart';
import 'package:business_hub_mobile/core/sync/mobile_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readiness becomes blocked when build is local and failures exist', () {
    const runtime = AppRuntimeInfo(
      appName: 'Business Hub',
      packageName: 'com.example.businesshub',
      version: '1.3.9',
      buildNumber: '9',
      releaseChannel: 'local',
      releaseSha: '',
      releaseTag: 'dev-build',
      pilotScope: 'unspecified',
    );

    final diagnostics = PilotDiagnosticsSnapshot(
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
      syncStatus: MobileSyncStatus.error,
      historyOverview: const HistoryOverview(
        totalSales: 10,
        syncedSales: 8,
        queuedSales: 1,
        failedSales: 1,
        rejectedSales: 1,
        totalRevenue: 10000,
        queuedRevenue: 500,
        lastSyncedAt: null,
      ),
      pendingOutboxCount: 1,
      domainStates: <DomainControlState>[DomainControlState.legacy('sales')],
    );

    final report = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[
        CommerceOutboxAttentionEntry(
          commandId: 'sale-cmd-1',
          commandType: 'sale_create',
          syncStatus: 'failed',
          attemptCount: 3,
          updatedAt: 1,
        ),
      ],
    );

    expect(report.isBlocked, isTrue);
    expect(report.blockers, isNotEmpty);
    expect(report.statusLabel, 'BLOCKED STARTUP');
    expect(
      report.toMultilineText(),
      contains('This build is still marked as local'),
    );
  });

  test('readiness becomes monitor state for queued or offline posture', () {
    const runtime = AppRuntimeInfo(
      appName: 'Business Hub',
      packageName: 'com.example.businesshub',
      version: '1.3.9',
      buildNumber: '9',
      releaseChannel: 'pilot',
      releaseSha: 'abc1234',
      releaseTag: 'mobile-v1.3.9',
      pilotScope: 'limbdi-wave-1',
    );

    final diagnostics = PilotDiagnosticsSnapshot(
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
      syncStatus: MobileSyncStatus.offline,
      historyOverview: const HistoryOverview(
        totalSales: 10,
        syncedSales: 10,
        queuedSales: 0,
        failedSales: 0,
        totalRevenue: 10000,
        queuedRevenue: 0,
        lastSyncedAt: null,
      ),
      operatorEmailOverride: 'pilot@shop.test',
      operatorRoleOverride: 'staff',
      workspaceIdOverride: 'shop-pilot-1',
      pendingOutboxCount: 1,
      domainStates: const <DomainControlState>[],
    );

    final report = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );

    expect(report.shouldMonitor, isTrue);
    expect(report.warnings, isNotEmpty);
    expect(report.statusLabel, 'MONITOR BEFORE SHIFT');
  });

  /// Builds an otherwise-healthy device so the sales gating can be tested on
  /// its own. The pre-existing fixtures all had session: null, which blocks by
  /// itself - so nothing actually proved what failed/rejected sales do.
  PilotDiagnosticsSnapshot healthyDeviceWith({
    int failedSales = 0,
    int rejectedSales = 0,
  }) {
    const runtime = AppRuntimeInfo(
      appName: 'Business Hub',
      packageName: 'com.example.businesshub',
      version: '1.3.9',
      buildNumber: '9',
      releaseChannel: 'pilot',
      releaseSha: 'abc1234',
      releaseTag: 'mobile-v1.3.9',
      pilotScope: 'limbdi-wave-1',
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
      historyOverview: HistoryOverview(
        totalSales: 10,
        syncedSales: 10,
        queuedSales: 0,
        failedSales: failedSales,
        rejectedSales: rejectedSales,
        totalRevenue: 10000,
        queuedRevenue: 0,
        lastSyncedAt: DateTime.utc(2026, 5, 3),
      ),
      operatorEmailOverride: 'pilot@shop.test',
      operatorRoleOverride: 'staff',
      workspaceIdOverride: 'shop-pilot-1',
      pendingOutboxCount: 0,
      domainStates: const <DomainControlState>[],
    );
  }

  test('a transient push failure does not block the shift', () {
    // These retry themselves on the next flush. Blocking here meant a till
    // that briefly lost signal could not open.
    final report = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: healthyDeviceWith(failedSales: 3),
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );
    expect(report.isBlocked, isFalse);
  });

  test('a server rejection does block the shift', () {
    final report = PilotReadinessReport.evaluate(
      diagnosticsSnapshot: healthyDeviceWith(rejectedSales: 1),
      attentionEntries: const <CommerceOutboxAttentionEntry>[],
    );
    expect(report.isBlocked, isTrue);
    expect(report.blockers.join(' '), contains('rejected'));
  });
}

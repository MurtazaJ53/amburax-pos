import 'package:business_hub_mobile/core/models/mobile_models.dart';
import 'package:business_hub_mobile/core/runtime/app_runtime_info.dart';
import 'package:business_hub_mobile/core/runtime/pilot_diagnostics_snapshot.dart';
import 'package:business_hub_mobile/core/runtime/pilot_recovery_report.dart';
import 'package:business_hub_mobile/core/sync/mobile_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recovery report includes attention entries and runtime identity', () {
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
      syncStatus: MobileSyncStatus.error,
      historyOverview: const HistoryOverview(
        totalSales: 50,
        syncedSales: 46,
        queuedSales: 3,
        failedSales: 1,
        totalRevenue: 100000,
        queuedRevenue: 2400,
        lastSyncedAt: null,
      ),
      pendingOutboxCount: 3,
      domainStates: <DomainControlState>[DomainControlState.legacy('sales')],
      generatedAt: DateTime.utc(2026, 5, 2, 13),
    );

    final report = PilotRecoveryReport(
      diagnosticsSnapshot: diagnostics,
      attentionEntries: const <CommerceOutboxAttentionEntry>[
        CommerceOutboxAttentionEntry(
          commandId: 'sale-cmd-1',
          commandType: 'sale_create',
          syncStatus: 'failed',
          attemptCount: 4,
          updatedAt: 1,
          customerName: 'Ayaan',
          total: 1999,
          lastError: '409 stale domain epoch',
        ),
      ],
      generatedAt: DateTime.utc(2026, 5, 2, 13, 15),
    );

    final text = report.toMultilineText();

    expect(text, contains('Business Hub pilot recovery report'));
    expect(text, contains('Release fingerprint: pilot | abc1234'));
    expect(text, contains('Release tag: mobile-v1.3.9'));
    expect(text, contains('Pilot scope: limbdi-wave-1'));
    expect(text, contains('Workspace: Pilot Shop'));
    expect(text, contains('Queued commerce commands: 3'));
    expect(text, contains('Failed receipts: 1'));
    expect(text, contains('Sale replay: FAILED | command=sale-cmd-1'));
    expect(text, contains('customer=Ayaan'));
    expect(text, contains('last_error=409 stale domain epoch'));
  });
}

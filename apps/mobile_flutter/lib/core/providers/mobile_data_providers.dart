import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/local_database.dart' show CommerceOutboxEntry;
import '../database/mobile_repository.dart';
import '../backend/backend_api_client.dart';
import '../models/mobile_models.dart';
import '../models/mobile_session.dart';
import '../runtime/mobile_runtime_config.dart';
import '../session/mobile_session_controller.dart';

/// Server-computed sales totals across ALL sales ({total_sales, gross_revenue}),
/// so revenue is correct even when the phone only holds a recent window of
/// receipts. Returns null on error → callers fall back to local figures.
final salesServerSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
      final session = ref.watch(mobileSessionProvider).asData?.value;
      if (session == null || !session.hasShop) return null;
      try {
        return await ref
            .read(backendApiClientProvider)
            .fetchSalesSummary(user: session.user, shopId: session.shopId!);
      } catch (_) {
        return null;
      }
    });

/// Server-side customer search — queries ALL customers on the backend (not just
/// the recent window on the phone), so you can find anyone by name or phone.
final customerSearchProvider = FutureProvider.autoDispose
    .family<List<BackendCustomerSummary>, String>((ref, query) async {
      final q = query.trim();
      if (q.length < 2) return const <BackendCustomerSummary>[];
      final session = ref.watch(mobileSessionProvider).asData?.value;
      if (session == null || !session.hasShop) {
        return const <BackendCustomerSummary>[];
      }
      try {
        return await ref
            .read(backendApiClientProvider)
            .fetchCustomers(
              user: session.user,
              shopId: session.shopId!,
              query: q,
            );
      } catch (_) {
        return const <BackendCustomerSummary>[];
      }
    });

final shopInfoProvider = StreamProvider<ShopInfo>((ref) {
  final shopRepository = ref.watch(shopRepositoryProvider);
  return shopRepository.watchShopInfo();
});

final historyOverviewProvider = StreamProvider<HistoryOverview>((ref) {
  final salesRepository = ref.watch(salesRepositoryProvider);
  return salesRepository.watchHistoryOverview();
});

final pendingOutboxCountProvider = StreamProvider<int>((ref) {
  final salesRepository = ref.watch(salesRepositoryProvider);
  return salesRepository.watchPendingOutboxCount();
});

/// Count of sales the backend permanently rejected (dead-letter) — drives the
/// "needs attention" badge.
final deadLetterCountProvider = StreamProvider<int>((ref) {
  return ref.watch(salesRepositoryProvider).watchDeadLetterCount();
});

/// The dead-lettered commands themselves, for the resolution screen.
final deadLetterEntriesProvider = StreamProvider<List<CommerceOutboxEntry>>((
  ref,
) {
  return ref.watch(salesRepositoryProvider).watchDeadLetterEntries();
});

final customersProvider = StreamProvider<List<BackendCustomerSummary>>((ref) {
  final customerRepository = ref.watch(customerRepositoryProvider);
  return customerRepository.watchLegacyCustomers();
});

final mobileMfaVerifiedUntilProvider = StreamProvider<DateTime?>((ref) {
  final shopRepository = ref.watch(shopRepositoryProvider);
  return shopRepository.watchMfaVerifiedUntil();
});

final shopMembershipsProvider =
    FutureProvider<List<ShopMembershipAccessRecord>>((ref) async {
      final session = await ref.watch(mobileSessionProvider.future);
      if (session == null) {
        return const <ShopMembershipAccessRecord>[];
      }
      if (!MobileRuntimeConfig.backendSyncEnabled) {
        return _localMemberships(session);
      }

      return ref
          .read(backendApiClientProvider)
          .getShopMemberships(user: session.user);
    });

final workspacePulseProvider = FutureProvider<WorkspacePulseSnapshot?>((
  ref,
) async {
  final session = await ref.watch(mobileSessionProvider.future);
  if (session == null || !session.isOwnerLike || !session.hasShop) {
    return null;
  }
  if (!MobileRuntimeConfig.backendSyncEnabled) {
    return _localPulseSnapshot();
  }

  return ref
      .read(backendApiClientProvider)
      .getWorkspacePulse(user: session.user, shopId: session.shopId!);
});

final workspacePulseSignalsProvider =
    FutureProvider<List<WorkspacePulseSignal>>((ref) async {
      final session = await ref.watch(mobileSessionProvider.future);
      if (session == null || !session.isOwnerLike || !session.hasShop) {
        return const <WorkspacePulseSignal>[];
      }
      if (!MobileRuntimeConfig.backendSyncEnabled) {
        return const <WorkspacePulseSignal>[];
      }

      return ref
          .read(backendApiClientProvider)
          .getWorkspacePulseSignals(
            user: session.user,
            shopId: session.shopId!,
          );
    });

final workspaceAccessSessionsProvider =
    FutureProvider<List<WorkspaceAccessSessionRecord>>((ref) async {
      final session = await ref.watch(mobileSessionProvider.future);
      if (session == null || !session.isOwnerLike || !session.hasShop) {
        return const <WorkspaceAccessSessionRecord>[];
      }
      if (!MobileRuntimeConfig.backendSyncEnabled) {
        return _localAccessSessions(session);
      }

      return ref
          .read(backendApiClientProvider)
          .getWorkspaceAccessSessions(
            user: session.user,
            shopId: session.shopId!,
          );
    });

final workspaceTeamMembersProvider =
    FutureProvider<List<WorkspaceTeamMemberRecord>>((ref) async {
      final session = await ref.watch(mobileSessionProvider.future);
      if (session == null || !session.isOwnerLike || !session.hasShop) {
        return const <WorkspaceTeamMemberRecord>[];
      }
      if (!MobileRuntimeConfig.backendSyncEnabled) {
        return _localTeamMembers(session);
      }

      return ref
          .read(backendApiClientProvider)
          .getWorkspaceTeamMembers(user: session.user, shopId: session.shopId!);
    });

final attendanceSummaryProvider = FutureProvider<AttendanceSummarySnapshot?>((
  ref,
) async {
  final session = await ref.watch(mobileSessionProvider.future);
  final memberships = await ref.watch(shopMembershipsProvider.future);
  if (session == null || !session.hasShop) {
    return null;
  }
  if (!MobileRuntimeConfig.backendSyncEnabled) {
    return const AttendanceSummarySnapshot(
      totalSessions: 0,
      presentCount: 0,
      leaveCount: 0,
      activeWorkersToday: 0,
    );
  }

  final scopedMembershipId = session.isOwnerLike
      ? null
      : memberships
            .where((item) => item.shopId == session.shopId && item.isActive)
            .map((item) => item.id)
            .cast<String?>()
            .firstWhere(
              (item) => item != null && item.isNotEmpty,
              orElse: () => session.membershipId,
            );
  return ref
      .read(backendApiClientProvider)
      .getAttendanceSummary(
        user: session.user,
        shopId: session.shopId!,
        membershipId: scopedMembershipId,
      );
});

final attendanceSessionsProvider =
    FutureProvider<List<AttendanceSessionRecord>>((ref) async {
      final session = await ref.watch(mobileSessionProvider.future);
      final memberships = await ref.watch(shopMembershipsProvider.future);
      if (session == null || !session.hasShop) {
        return const <AttendanceSessionRecord>[];
      }
      if (!MobileRuntimeConfig.backendSyncEnabled) {
        return const <AttendanceSessionRecord>[];
      }

      final scopedMembershipId = session.isOwnerLike
          ? null
          : memberships
                .where((item) => item.shopId == session.shopId && item.isActive)
                .map((item) => item.id)
                .cast<String?>()
                .firstWhere(
                  (item) => item != null && item.isNotEmpty,
                  orElse: () => session.membershipId,
                );
      return ref
          .read(backendApiClientProvider)
          .getAttendanceSessions(
            user: session.user,
            shopId: session.shopId!,
            membershipId: scopedMembershipId,
          );
    });

// Expenses are stored locally (local-first) so they work with or without the
// backend, like sales / inventory / customers.
final expensesProvider = StreamProvider<List<ExpenseRecord>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchExpenses();
});

final expenseSummaryProvider = StreamProvider<ExpenseSummarySnapshot?>((ref) {
  return ref.watch(expenseRepositoryProvider).watchExpenses().map((list) {
    final total = list.fold<double>(0, (sum, e) => sum + e.amount);
    final byCategory = <String, double>{};
    for (final e in list) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
    }
    String? biggest;
    var max = -1.0;
    byCategory.forEach((k, v) {
      if (v > max) {
        max = v;
        biggest = k;
      }
    });
    return ExpenseSummarySnapshot(
      totalEntries: list.length,
      totalAmount: total,
      uniqueCategories: byCategory.length,
      biggestCategory: biggest,
    );
  });
});

// P&L / financial reporting for a period. Sales + expenses stream separately
// and the screen folds them with the pure computeProfitAndLoss, so both a new
// sale and a new expense update the report live.
final reportSalesProvider =
    StreamProvider.family<List<ReportSale>, HistoryDateWindow>((ref, window) {
      return ref.watch(reportsRepositoryProvider).watchReportSales(window);
    });

final reportExpensesProvider = StreamProvider.family<double, HistoryDateWindow>(
  (ref, window) {
    return ref.watch(reportsRepositoryProvider).watchPeriodExpenses(window);
  },
);

// End-of-day Z-report figures (default: today).
final zReportProvider =
    StreamProvider.family<ZReportSnapshot, HistoryDateWindow>((ref, window) {
      return ref.watch(reportsRepositoryProvider).watchZReport(window);
    });

// POS quick-keys: the shop's favourite items, persisted as a setting.
final favouriteIdsProvider =
    AsyncNotifierProvider<FavouriteIdsController, List<String>>(
      FavouriteIdsController.new,
    );

class FavouriteIdsController extends AsyncNotifier<List<String>> {
  static const String _key = 'pos_favourites';

  @override
  Future<List<String>> build() async {
    final raw = await ref.read(shopRepositoryProvider).readSetting(_key);
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List
          ? decoded.map((e) => e.toString()).toList(growable: false)
          : const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  bool isFavourite(String id) =>
      (state.asData?.value ?? const <String>[]).contains(id);

  Future<void> toggle(String id) async {
    final current = <String>[...(state.asData?.value ?? const <String>[])];
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }
    state = AsyncData<List<String>>(current);
    await ref
        .read(shopRepositoryProvider)
        .writeSetting(_key, jsonEncode(current));
  }
}

// Resolve the favourite ids to full items for the POS quick-key strip.
final favouriteItemsProvider = StreamProvider<List<InventoryCatalogItem>>((
  ref,
) {
  final ids = ref.watch(favouriteIdsProvider).asData?.value ?? const <String>[];
  return ref.watch(inventoryRepositoryProvider).watchItemsByIds(ids);
});

/// The shop's actual top sellers, used to fill the POS quick-add strip when the
/// cashier hasn't pinned anything. A favourites row that starts empty stays
/// empty — nobody discovers a long-press — so it earns its space from day one.
final autoTopSellersProvider =
    FutureProvider.autoDispose<List<InventoryCatalogItem>>((ref) async {
      final pinned =
          ref.watch(favouriteIdsProvider).asData?.value ?? const <String>[];
      if (pinned.isNotEmpty) return const <InventoryCatalogItem>[];

      final top = await ref
          .watch(reportsRepositoryProvider)
          .bestSellers(days: 30, limit: 8);
      if (top.isEmpty) return const <InventoryCatalogItem>[];

      // bestSellers groups by name (movements record a name snapshot), so map back
      // to live catalog rows to get current price and stock.
      final catalog = await ref
          .watch(inventoryRepositoryProvider)
          .watchCatalogPage(page: 1, pageSize: 500)
          .first;
      final byName = <String, InventoryCatalogItem>{
        for (final item in catalog) item.name.toLowerCase(): item,
      };
      return top
          .map((t) => byName[t.name.toLowerCase()])
          .whereType<InventoryCatalogItem>()
          .toList(growable: false);
    });

// Customer khata timeline (credit sales + payments).
final customerLedgerProvider =
    StreamProvider.family<List<CustomerLedgerRecord>, String>((
      ref,
      customerId,
    ) {
      return ref.watch(customerRepositoryProvider).watchLedger(customerId);
    });

// Per-item stock audit trail (sold / received / returned / adjusted).
final stockMovementsProvider =
    StreamProvider.family<List<StockMovement>, String>((ref, itemId) {
      return ref
          .watch(inventoryRepositoryProvider)
          .watchStockMovements(itemId: itemId);
    });

// Stock buying (money-out to suppliers) is local-first, same as expenses.
final purchasesProvider = StreamProvider<List<PurchaseRecord>>((ref) {
  return ref.watch(purchaseRepositoryProvider).watchPurchases();
});

final supplierDuesProvider = StreamProvider<List<SupplierDue>>((ref) {
  return ref.watch(purchaseRepositoryProvider).watchSuppliers();
});

final purchaseSummaryProvider = StreamProvider<PurchaseSummarySnapshot>((ref) {
  return ref.watch(purchaseRepositoryProvider).watchSummary();
});

final dashboardOverviewProvider =
    StreamProvider.family<DashboardOverview, bool>((ref, includeCost) {
      final inventoryRepository = ref.watch(inventoryRepositoryProvider);
      return inventoryRepository.watchDashboardOverview(
        includeCost: includeCost,
      );
    });

final dashboardLowStockPreviewProvider = StreamProvider<List<LowStockItem>>((
  ref,
) {
  final inventoryRepository = ref.watch(inventoryRepositoryProvider);
  return inventoryRepository.watchLowStockPreview();
});

final dashboardRecentSalesProvider = StreamProvider<List<RecentSaleSummary>>((
  ref,
) {
  final salesRepository = ref.watch(salesRepositoryProvider);
  return salesRepository.watchRecentSales(limit: 4);
});

final historySalesProvider =
    StreamProvider.family<List<RecentSaleSummary>, HistoryFilter>((
      ref,
      filter,
    ) {
      final salesRepository = ref.watch(salesRepositoryProvider);
      return salesRepository.watchRecentSales(filter: filter);
    });

final historyDomainStatesProvider = StreamProvider<List<DomainControlState>>((
  ref,
) {
  final shopRepository = ref.watch(shopRepositoryProvider);
  return shopRepository.watchTrackedDomainStates(const <String>[
    'sales',
    'payments',
  ]);
});

final settingsOpsDomainStatesProvider =
    StreamProvider<List<DomainControlState>>((ref) {
      final shopRepository = ref.watch(shopRepositoryProvider);
      return shopRepository.watchTrackedDomainStates(const <String>[
        'inventory',
        'customers',
        'sales',
        'payments',
      ]);
    });

List<ShopMembershipAccessRecord> _localMemberships(MobileSession session) {
  return <ShopMembershipAccessRecord>[
    ShopMembershipAccessRecord(
      id: session.membershipId ?? 'local-owner-membership',
      role: session.normalizedRole.isEmpty ? 'owner' : session.normalizedRole,
      roleLabel: session.displayRoleLabel,
      roleSummary: session.roleSummary,
      roleProfile: session.roleProfileKey,
      status: 'active',
      shopId: session.shopId ?? MobileRuntimeConfig.localShopId,
      shopName: MobileRuntimeConfig.localShopName,
      shopSlug: 'local-business-hub',
      shopCurrencyCode: 'INR',
      shopTimezone: 'Asia/Kolkata',
      shopPlanTier: 'growth',
      shopEnabledFeatures: const <String, bool>{
        'inventory': true,
        'pos': true,
        'customers': true,
        'history': true,
        'team': true,
        'attendance': true,
        'expenses': true,
        'advanced_ops': true,
      },
    ),
  ];
}

List<WorkspaceTeamMemberRecord> _localTeamMembers(MobileSession session) {
  final now = DateTime.now();
  return <WorkspaceTeamMemberRecord>[
    WorkspaceTeamMemberRecord(
      id: session.membershipId ?? 'local-owner-membership',
      memberName: session.user.displayName.isEmpty
          ? 'Business Hub Owner'
          : session.user.displayName,
      memberEmail: session.email,
      phone: '',
      role: session.normalizedRole.isEmpty ? 'owner' : session.normalizedRole,
      roleLabel: session.displayRoleLabel,
      roleSummary: session.roleSummary,
      roleProfile: session.roleProfileKey,
      status: 'active',
      permissionsVersion: 1,
      permissions: session.permissions ?? const <String, dynamic>{},
      isCurrentUser: true,
      canManage: true,
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

List<WorkspaceAccessSessionRecord> _localAccessSessions(MobileSession session) {
  final now = DateTime.now();
  return <WorkspaceAccessSessionRecord>[
    WorkspaceAccessSessionRecord(
      id: 'local-device-session',
      memberName: session.user.displayName.isEmpty
          ? 'Business Hub Owner'
          : session.user.displayName,
      memberEmail: session.email,
      membershipRoleSnapshot: session.normalizedRole.isEmpty
          ? 'owner'
          : session.normalizedRole,
      roleLabel: session.displayRoleLabel,
      status: 'active',
      deviceLabel: 'Local device',
      platformName: 'android',
      packageName: 'business_hub_mobile',
      appVersion: 'local',
      buildNumber: 'local',
      releaseChannel: 'local-first',
      releaseTag: 'local-first',
      lastSeenAt: now,
      revokedAt: null,
      revokeReason: null,
      wipeRequested: false,
      wipeRequestedAt: null,
      wipeAcknowledgedAt: null,
      trustScore: 100,
      trustLevel: 'trusted',
      trustSummary: 'Local owner session. Backend session governance is off.',
      trustReasons: const <String>['Local-first build'],
      metadata: const <String, dynamic>{'mode': 'local_first'},
      canManage: true,
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

WorkspacePulseSnapshot _localPulseSnapshot() {
  return WorkspacePulseSnapshot(
    refreshedAt: DateTime.now(),
    headline: const WorkspacePulseHeadline(
      title: 'Local workspace is ready',
      body:
          'Inventory, POS, customers, and history run from the device vault. Live backend sync is paused for this build.',
      route: '/inventory',
      ctaLabel: 'Open inventory',
      tone: 'success',
    ),
    stats: const WorkspacePulseStats(
      openTaskCount: 0,
      criticalAnomalyCount: 0,
      warningAnomalyCount: 0,
      staleSessionCount: 0,
      wipePendingCount: 0,
      openPlanRequestCount: 0,
      lowStockCount: 0,
    ),
    tasks: const <WorkspacePulseTask>[],
    anomalies: const <WorkspacePulseAnomaly>[],
  );
}

final outboxAttentionEntriesProvider =
    StreamProvider<List<CommerceOutboxAttentionEntry>>((ref) {
      final salesRepository = ref.watch(salesRepositoryProvider);
      return salesRepository.watchOutboxAttentionEntries();
    });

final domainStateProvider = StreamProvider.family<DomainControlState, String>((
  ref,
  domain,
) {
  final shopRepository = ref.watch(shopRepositoryProvider);
  return shopRepository.watchDomainState(domain);
});

final inventoryCategoriesProvider =
    StreamProvider<List<InventoryCategorySummary>>((ref) {
      final inventoryRepository = ref.watch(inventoryRepositoryProvider);
      return inventoryRepository.watchCategories();
    });

final inventoryOverviewProvider =
    StreamProvider.family<DashboardOverview, bool>((ref, includeCost) {
      final inventoryRepository = ref.watch(inventoryRepositoryProvider);
      return inventoryRepository.watchDashboardOverview(
        includeCost: includeCost,
      );
    });

final inventoryCatalogPageProvider =
    StreamProvider.family<List<InventoryCatalogItem>, InventoryCatalogFilter>((
      ref,
      filter,
    ) {
      final inventoryRepository = ref.watch(inventoryRepositoryProvider);
      return inventoryRepository.watchCatalogPage(
        search: filter.search,
        category: filter.category,
        page: filter.page,
        pageSize: filter.pageSize,
        includeCost: filter.includeCost,
        lowStockOnly: filter.lowStockOnly,
      );
    });

final inventoryCatalogCountProvider =
    StreamProvider.family<int, InventoryCatalogFilter>((ref, filter) {
      final inventoryRepository = ref.watch(inventoryRepositoryProvider);
      return inventoryRepository.watchCatalogCount(
        search: filter.search,
        category: filter.category,
        lowStockOnly: filter.lowStockOnly,
      );
    });

final posCatalogPageProvider =
    StreamProvider.family<List<InventoryCatalogItem>, PosCatalogFilter>((
      ref,
      filter,
    ) {
      final inventoryRepository = ref.watch(inventoryRepositoryProvider);
      return inventoryRepository.watchCatalogPage(
        search: filter.search,
        category: filter.category,
        page: filter.page,
        pageSize: filter.pageSize,
        includeCost: filter.includeCost,
        lowStockOnly: filter.lowStockOnly,
      );
    });

final posCatalogCountProvider = StreamProvider.family<int, PosCatalogFilter>((
  ref,
  filter,
) {
  final inventoryRepository = ref.watch(inventoryRepositoryProvider);
  return inventoryRepository.watchCatalogCount(
    search: filter.search,
    category: filter.category,
    lowStockOnly: filter.lowStockOnly,
  );
});

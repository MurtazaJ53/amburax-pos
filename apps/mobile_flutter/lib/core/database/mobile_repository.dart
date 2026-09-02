import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../images/product_image_store.dart';
import '../models/mobile_models.dart';
import '../runtime/pilot_evidence_tracker.dart';
import 'local_database.dart';

final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  return ShopRepository(ref.watch(localDatabaseProvider));
});

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(ref.watch(localDatabaseProvider));
});

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(ref.watch(localDatabaseProvider));
});

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(ref.watch(localDatabaseProvider));
});

class ShopRepository {
  ShopRepository(this._db);

  final BusinessHubDatabase _db;
  static const String _pilotEvidenceTrackerKey = 'pilot_evidence_tracker';
  static const String _appInstanceIdKey = 'app_instance_id';
  static const String _mfaVerifiedUntilKey = 'mfa_verified_until';

  Stream<ShopInfo> watchShopInfo() {
    final query = (_db.select(
      _db.shopSettingsEntries,
    )..where((tbl) => tbl.key.equals('settings'))).watchSingleOrNull();

    return query.map((row) {
      if (row == null) {
        return ShopInfo.fallback();
      }

      try {
        final decoded = jsonDecode(row.value) as Map<String, dynamic>;
        return ShopInfo(
          name: (decoded['name'] ?? 'Business Hub Pro').toString(),
          tagline: (decoded['tagline'] ?? 'ZARRA ECOSYSTEM').toString(),
          footer: (decoded['footer'] ?? 'Thank you for your business!')
              .toString(),
          currency: (decoded['currency'] ?? 'INR').toString(),
          phone: (decoded['business_phone'] ?? decoded['phone'] ?? '')
              .toString(),
          gstin: (decoded['gstin'] ?? '').toString(),
          upiVpa: (decoded['upi_vpa'] ?? '').toString(),
          planTier: (decoded['plan_tier'] ?? 'growth').toString(),
          enabledFeatures: _coerceEnabledFeatures(
            decoded['enabled_features'],
            fallbackPlanTier: (decoded['plan_tier'] ?? 'growth').toString(),
          ),
        );
      } catch (_) {
        return ShopInfo.fallback();
      }
    });
  }

  Future<void> saveShopDocument(Map<String, dynamic> rawData) async {
    final settings = Map<String, dynamic>.from(
      rawData['settings'] is Map ? rawData['settings'] as Map : const {},
    );
    settings['name'] =
        rawData['name'] ?? settings['name'] ?? 'Business Hub Pro';
    settings['tagline'] =
        settings['tagline'] ??
        rawData['tagline'] ??
        rawData['ecosystem'] ??
        'ZARRA ECOSYSTEM';
    settings['footer'] =
        settings['footer'] ??
        rawData['footer'] ??
        'Thank you for your business!';
    settings['currency'] = settings['currency'] ?? rawData['currency'] ?? 'INR';
    settings['business_phone'] =
        rawData['business_phone'] ??
        rawData['phone'] ??
        settings['business_phone'] ??
        settings['phone'] ??
        '';
    settings['gstin'] = rawData['gstin'] ?? settings['gstin'] ?? '';
    settings['upi_vpa'] = rawData['upi_vpa'] ?? settings['upi_vpa'] ?? '';
    settings['plan_tier'] =
        rawData['plan_tier'] ?? settings['plan_tier'] ?? 'growth';
    settings['enabled_features'] = _coerceEnabledFeatures(
      rawData['enabled_features'] ?? settings['enabled_features'],
      fallbackPlanTier: settings['plan_tier'].toString(),
    );

    await _db
        .into(_db.shopSettingsEntries)
        .insertOnConflictUpdate(
          ShopSettingsEntriesCompanion.insert(
            key: 'settings',
            value: jsonEncode(settings),
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<String?> readSetting(String key) async {
    final row = await (_db.select(
      _db.shopSettingsEntries,
    )..where((tbl) => tbl.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeSetting(String key, String value) async {
    await _db
        .into(_db.shopSettingsEntries)
        .insertOnConflictUpdate(
          ShopSettingsEntriesCompanion.insert(
            key: key,
            value: value,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> saveDomainState({required DomainControlState state}) async {
    await _db
        .into(_db.shopSettingsEntries)
        .insertOnConflictUpdate(
          ShopSettingsEntriesCompanion.insert(
            key: 'domain_state_${state.domain}',
            value: jsonEncode(state.toJson()),
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Stream<DomainControlState> watchDomainState(String domain) {
    final query =
        (_db.select(_db.shopSettingsEntries)
              ..where((tbl) => tbl.key.equals('domain_state_$domain')))
            .watchSingleOrNull();

    return query.map((row) {
      if (row == null) {
        return DomainControlState.legacy(domain);
      }

      try {
        final decoded = jsonDecode(row.value) as Map<String, dynamic>;
        return DomainControlState.fromJson(decoded, fallbackDomain: domain);
      } catch (_) {
        return DomainControlState.legacy(domain);
      }
    });
  }

  Stream<List<DomainControlState>> watchTrackedDomainStates(
    List<String> domains,
  ) {
    if (domains.isEmpty) {
      return Stream.value(const <DomainControlState>[]);
    }

    final keys = domains.map((domain) => 'domain_state_$domain').toList();
    return (_db.select(
      _db.shopSettingsEntries,
    )..where((tbl) => tbl.key.isIn(keys))).watch().map((rows) {
      final decodedByDomain = <String, DomainControlState>{};
      for (final row in rows) {
        try {
          final decoded = jsonDecode(row.value) as Map<String, dynamic>;
          final domain =
              (decoded['domain'] ?? row.key.replaceFirst('domain_state_', ''))
                  .toString();
          decodedByDomain[domain] = DomainControlState.fromJson(
            decoded,
            fallbackDomain: domain,
          );
        } catch (_) {
          continue;
        }
      }

      return domains
          .map(
            (domain) =>
                decodedByDomain[domain] ?? DomainControlState.legacy(domain),
          )
          .toList(growable: false);
    });
  }

  Future<int> getDomainEpoch(String domain) async {
    final row =
        await (_db.select(_db.shopSettingsEntries)
              ..where((tbl) => tbl.key.equals('domain_state_$domain')))
            .getSingleOrNull();

    if (row == null) {
      return 1;
    }

    try {
      final decoded = jsonDecode(row.value) as Map<String, dynamic>;
      final epoch = decoded['current_epoch'];
      if (epoch is int) {
        return epoch;
      }
      if (epoch is num) {
        return epoch.toInt();
      }
      if (epoch is String) {
        return int.tryParse(epoch) ?? 1;
      }
      return 1;
    } catch (_) {
      return 1;
    }
  }

  Stream<PilotEvidenceTrackerState> watchPilotEvidenceTracker() {
    final query =
        (_db.select(_db.shopSettingsEntries)
              ..where((tbl) => tbl.key.equals(_pilotEvidenceTrackerKey)))
            .watchSingleOrNull();

    return query.map((row) {
      if (row == null) {
        return const PilotEvidenceTrackerState();
      }
      return _decodePilotEvidenceTracker(row.value);
    });
  }

  Future<PilotEvidenceTrackerState> getPilotEvidenceTracker() async {
    final row =
        await (_db.select(_db.shopSettingsEntries)
              ..where((tbl) => tbl.key.equals(_pilotEvidenceTrackerKey)))
            .getSingleOrNull();

    if (row == null) {
      return const PilotEvidenceTrackerState();
    }
    return _decodePilotEvidenceTracker(row.value);
  }

  Future<void> savePilotEvidenceTracker(PilotEvidenceTrackerState state) async {
    if (!state.hasStoredState) {
      await (_db.delete(
        _db.shopSettingsEntries,
      )..where((tbl) => tbl.key.equals(_pilotEvidenceTrackerKey))).go();
      return;
    }

    await _db
        .into(_db.shopSettingsEntries)
        .insertOnConflictUpdate(
          ShopSettingsEntriesCompanion.insert(
            key: _pilotEvidenceTrackerKey,
            value: jsonEncode(state.toJson()),
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> markPilotEvidenceCaptured(
    String artifactId, {
    DateTime? capturedAt,
  }) async {
    final current = await getPilotEvidenceTracker();
    final next = current.markCaptured(artifactId, capturedAt: capturedAt);
    await savePilotEvidenceTracker(next);
  }

  Future<void> ensurePilotEvidenceSession(String defaultLabel) async {
    final current = await getPilotEvidenceTracker();
    final next = current.ensureSession(defaultLabel: defaultLabel);
    if (identical(next, current)) {
      return;
    }
    await savePilotEvidenceTracker(next);
  }

  Future<void> startFreshPilotEvidenceSession(String sessionLabel) async {
    final next = const PilotEvidenceTrackerState().startFreshSession(
      sessionLabel: sessionLabel,
    );
    await savePilotEvidenceTracker(next);
  }

  Future<void> resetPilotEvidenceTracker() async {
    await savePilotEvidenceTracker(const PilotEvidenceTrackerState());
  }

  Future<void> clearPilotEvidenceArchive() async {
    final current = await getPilotEvidenceTracker();
    final next = current.withoutArchivedSessions();
    await savePilotEvidenceTracker(next);
  }

  Stream<DateTime?> watchMfaVerifiedUntil() {
    final query =
        (_db.select(_db.shopSettingsEntries)
              ..where((tbl) => tbl.key.equals(_mfaVerifiedUntilKey)))
            .watchSingleOrNull();
    return query.map((row) => _decodeStoredDateTime(row?.value));
  }

  Future<void> saveMfaVerifiedUntil(DateTime? value) async {
    if (value == null) {
      await (_db.delete(
        _db.shopSettingsEntries,
      )..where((tbl) => tbl.key.equals(_mfaVerifiedUntilKey))).go();
      return;
    }

    await _saveShopSetting(_mfaVerifiedUntilKey, value.toIso8601String());
  }

  Future<String> ensureAppInstanceId() async {
    final existing = await _readShopSetting(_appInstanceIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }

    final random = Random.secure();
    final next =
        'mobile-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
        '${List<String>.generate(6, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    await _saveShopSetting(_appInstanceIdKey, next);
    return next;
  }

  Future<void> clearWorkspace({bool preserveAppInstanceId = true}) async {
    final preservedAppInstanceId = preserveAppInstanceId
        ? await _readShopSetting(_appInstanceIdKey)
        : null;

    await _db.delete(_db.shopSettingsEntries).go();

    if (preservedAppInstanceId != null &&
        preservedAppInstanceId.trim().isNotEmpty) {
      await _saveShopSetting(_appInstanceIdKey, preservedAppInstanceId.trim());
    }
  }

  /// Wipe EVERY shop-scoped local data table. Called when the active shop
  /// changes (login/register/accept into a different workspace) so a new
  /// tenant never sees the previous tenant's cached data. This is the local
  /// half of tenant isolation - the backend is already row-level isolated.
  ///
  /// Deliberately clears all data tables directly (not the per-repository
  /// clearWorkspace helpers) so nothing is ever missed - expenses and
  /// purchases had no clear helper at all. Shop settings (tokens, shop
  /// document, app-instance id) are left intact; the caller re-seeds the shop
  /// document for the new workspace.
  Future<void> clearAllWorkspaceData() async {
    await _db.transaction(() async {
      await _db.delete(_db.inventoryPrivateEntries).go();
      await _db.delete(_db.inventoryEntries).go();
      await _db.delete(_db.stockMovementEntries).go();
      await _db.delete(_db.customerLedgerEntries).go();
      await _db.delete(_db.customerEntries).go();
      await _db.delete(_db.commerceOutboxEntries).go();
      await _db.delete(_db.salesEntries).go();
      await _db.delete(_db.expenseEntries).go();
      await _db.delete(_db.purchaseEntries).go();
    });
    // Drop the previous shop's document so the new workspace's name/settings
    // replace it rather than lingering.
    await _saveShopSetting('settings', '');
  }

  PilotEvidenceTrackerState _decodePilotEvidenceTracker(String rawValue) {
    try {
      final decoded = jsonDecode(rawValue) as Map<String, dynamic>;
      return PilotEvidenceTrackerState.fromJson(decoded);
    } catch (_) {
      return const PilotEvidenceTrackerState();
    }
  }

  Future<String?> _readShopSetting(String key) async {
    final row = await (_db.select(
      _db.shopSettingsEntries,
    )..where((tbl) => tbl.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _saveShopSetting(String key, String value) async {
    await _db
        .into(_db.shopSettingsEntries)
        .insertOnConflictUpdate(
          ShopSettingsEntriesCompanion.insert(
            key: key,
            value: value,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  DateTime? _decodeStoredDateTime(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(rawValue.trim())?.toLocal();
  }
}

Map<String, bool> _coerceEnabledFeatures(
  dynamic rawValue, {
  required String fallbackPlanTier,
}) {
  final normalizedPlan = fallbackPlanTier.trim().toLowerCase();
  final features = <String, bool>{
    'expenses': normalizedPlan != 'starter',
    'attendance': normalizedPlan != 'starter',
    'supplier_directory': normalizedPlan != 'starter',
    'purchase_workflow': normalizedPlan == 'pro',
    'advanced_reports': normalizedPlan == 'pro',
    'finance_summary': normalizedPlan == 'pro',
    'advanced_ops': normalizedPlan == 'pro',
  };

  if (rawValue is Map) {
    for (final entry in rawValue.entries) {
      features[entry.key.toString()] = entry.value == true;
    }
  }

  return features;
}

class InventoryRepository {
  InventoryRepository(this._db);

  final BusinessHubDatabase _db;

  /// Run [action] inside a single DB transaction. All repos share this database
  /// connection, so bulk imports (products, customers, …) wrapped here commit as
  /// one fast batch instead of hundreds of individual writes.
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

  Stream<DashboardOverview> watchDashboardOverview({
    required bool includeCost,
  }) {
    final today = DateTime.now().toIso8601String().split('T').first;
    final sql =
        '''
      SELECT
        COUNT(i.id) AS total_items,
        COALESCE(SUM(i.stock), 0) AS total_stock,
        COALESCE(SUM(i.price * i.stock), 0) AS inventory_value,
        COALESCE(SUM((i.price - ${includeCost ? 'COALESCE(ip.cost_price, 0)' : '0'}) * i.stock), 0) AS potential_profit,
        COALESCE(SUM(CASE WHEN i.stock <= COALESCE(i.reorder_level, 5) THEN 1 ELSE 0 END), 0) AS low_stock,
        COALESCE((SELECT COUNT(*) FROM sales s WHERE s.tombstone = 0 AND s.date = ?), 0) AS today_sales,
        COALESCE((SELECT SUM(s.total) FROM sales s WHERE s.tombstone = 0 AND s.date = ?), 0) AS today_revenue
      FROM inventory i
      LEFT JOIN inventory_private ip ON ip.id = i.id AND ip.tombstone = 0
      WHERE i.tombstone = 0;
    ''';

    return _db
        .customSelect(
          sql,
          variables: [Variable<String>(today), Variable<String>(today)],
          readsFrom: {
            _db.inventoryEntries,
            _db.inventoryPrivateEntries,
            _db.salesEntries,
          },
        )
        .watchSingle()
        .map((row) {
          final metrics = InventoryMetrics(
            totalItems: row.readNullable<int>('total_items') ?? 0,
            totalStock: row.readNullable<double>('total_stock') ?? 0,
            inventoryValue: row.readNullable<double>('inventory_value') ?? 0,
            potentialProfit: row.readNullable<double>('potential_profit') ?? 0,
            lowStock: row.readNullable<int>('low_stock') ?? 0,
          );

          return DashboardOverview(
            metrics: metrics,
            todaySalesCount: row.readNullable<int>('today_sales') ?? 0,
            todayRevenue: row.readNullable<double>('today_revenue') ?? 0,
          );
        });
  }

  /// Stock that hasn't sold in [days], worst first by money tied up.
  ///
  /// Uses the stock-movement log rather than parsing every sale's item JSON —
  /// with tens of thousands of bills that would be far too slow to open a
  /// screen with. Items that have NEVER sold are included: they're the worst
  /// case, not an absence of data.
  Stream<List<DeadStockItem>> watchDeadStock({int days = 90}) {
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    return _db
        .customSelect(
          """
            SELECT i.id, i.name, COALESCE(i.category, 'General') AS category,
                   i.stock, i.price, p.cost_price,
                   (SELECT MAX(m.created_at) FROM stock_movements m
                     WHERE m.item_id = i.id AND m.reason = 'SALE')
                     AS last_sold_at
            FROM inventory i
            LEFT JOIN inventory_private p ON p.id = i.id
            WHERE i.tombstone = 0
              AND i.stock > 0
              AND (last_sold_at IS NULL OR last_sold_at < ?)
            -- NULLIF so a stored 0.00 cost falls back to the sell price like
            -- a missing one does. Without it those items value at zero and
            -- sort to the bottom, hiding the biggest problems on the shelf.
            ORDER BY (i.stock * COALESCE(NULLIF(p.cost_price, 0), i.price)) DESC;
          """,
          variables: [Variable<int>(cutoff)],
          readsFrom: {
            _db.inventoryEntries,
            _db.inventoryPrivateEntries,
            _db.stockMovementEntries,
          },
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => DeadStockItem(
                  id: row.readNullable<String>('id') ?? '',
                  name: row.readNullable<String>('name') ?? 'Unnamed item',
                  category: row.readNullable<String>('category') ?? 'General',
                  stock: row.readNullable<double>('stock') ?? 0,
                  price: row.readNullable<double>('price') ?? 0,
                  costPrice: row.readNullable<double>('cost_price'),
                  lastSoldAt: row.readNullable<int>('last_sold_at') == null
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(
                          row.readNullable<int>('last_sold_at') ?? 0,
                        ),
                ),
              )
              .toList(growable: false),
        );
  }

  /// Everything at or below its reorder level — the full buying list, worst
  /// first. Unlike watchLowStockPreview this isn't capped, because a purchase
  /// run needs every item, not a dashboard teaser.
  Stream<List<ReorderItem>> watchReorderList() {
    return _db
        .customSelect(
          """
            SELECT i.id, i.name, COALESCE(i.category, 'General') AS category,
                   i.stock, COALESCE(i.reorder_level, 5) AS reorder_level,
                   i.unit, i.sku, p.cost_price
            FROM inventory i
            LEFT JOIN inventory_private p ON p.id = i.id
            WHERE i.tombstone = 0
              AND i.stock <= COALESCE(i.reorder_level, 5)
            ORDER BY (i.stock <= 0) DESC, i.stock ASC, LOWER(i.name) ASC;
          """,
          readsFrom: {_db.inventoryEntries, _db.inventoryPrivateEntries},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => ReorderItem(
                  id: row.readNullable<String>('id') ?? '',
                  name: row.readNullable<String>('name') ?? 'Unnamed item',
                  category: row.readNullable<String>('category') ?? 'General',
                  stock: row.readNullable<double>('stock') ?? 0,
                  reorderLevel: row.readNullable<int>('reorder_level') ?? 5,
                  unit: row.readNullable<String>('unit'),
                  sku: row.readNullable<String>('sku'),
                  costPrice: row.readNullable<double>('cost_price'),
                ),
              )
              .toList(growable: false),
        );
  }

  Stream<List<LowStockItem>> watchLowStockPreview({int limit = 8}) {
    return _db
        .customSelect(
          '''
            SELECT id, name, COALESCE(category, 'General') AS category, stock, size
            FROM inventory
            WHERE tombstone = 0 AND stock <= COALESCE(reorder_level, 5)
            ORDER BY stock ASC, LOWER(name) ASC
            LIMIT ?;
          ''',
          variables: [Variable<int>(limit)],
          readsFrom: {_db.inventoryEntries},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => LowStockItem(
                  id: row.readNullable<String>('id') ?? '',
                  name: row.readNullable<String>('name') ?? '',
                  category: row.readNullable<String>('category') ?? '',
                  stock: row.readNullable<double>('stock') ?? 0,
                  size: row.readNullable<String>('size'),
                ),
              )
              .toList(growable: false),
        );
  }

  Stream<List<InventoryCategorySummary>> watchCategories() {
    return _db
        .customSelect(
          '''
            SELECT COALESCE(category, 'General') AS category, COUNT(*) AS product_count
            FROM inventory
            WHERE tombstone = 0
            GROUP BY COALESCE(category, 'General')
            ORDER BY LOWER(COALESCE(category, 'General')) ASC;
          ''',
          readsFrom: {_db.inventoryEntries},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => InventoryCategorySummary(
                  category: row.readNullable<String>('category') ?? '',
                  productCount: row.readNullable<int>('product_count') ?? 0,
                ),
              )
              .toList(growable: false),
        );
  }

  Stream<int> watchCatalogCount({
    String search = '',
    String? category,
    bool lowStockOnly = false,
  }) {
    final normalized = search.trim().toLowerCase();
    final where = <String>['tombstone = 0'];
    final variables = <Variable<Object>>[];

    if (category != null && category.isNotEmpty) {
      where.add("COALESCE(category, 'General') = ?");
      variables.add(Variable<String>(category));
    }
    if (lowStockOnly) {
      where.add('stock <= COALESCE(reorder_level, 5)');
    }
    if (normalized.isNotEmpty) {
      where.add(
        "(LOWER(name) LIKE ? OR LOWER(COALESCE(sku, '')) LIKE ? OR LOWER(COALESCE(size, '')) LIKE ?)",
      );
      final like = '%$normalized%';
      variables
        ..add(Variable<String>(like))
        ..add(Variable<String>(like))
        ..add(Variable<String>(like));
    }

    return _db
        .customSelect(
          'SELECT COUNT(*) AS total FROM inventory WHERE ${where.join(' AND ')};',
          variables: variables,
          readsFrom: {_db.inventoryEntries},
        )
        .watchSingle()
        .map((row) => row.readNullable<int>('total') ?? 0);
  }

  Stream<List<InventoryCatalogItem>> watchCatalogPage({
    String search = '',
    String? category,
    int page = 1,
    int pageSize = 40,
    bool includeCost = false,
    bool lowStockOnly = false,
  }) {
    final normalized = search.trim().toLowerCase();
    final safePage = page < 1 ? 1 : page;
    final offset = (safePage - 1) * pageSize;
    final where = <String>['i.tombstone = 0'];
    final variables = <Variable<Object>>[];

    if (category != null && category.isNotEmpty) {
      where.add("COALESCE(i.category, 'General') = ?");
      variables.add(Variable<String>(category));
    }
    if (lowStockOnly) {
      where.add('i.stock <= COALESCE(i.reorder_level, 5)');
    }
    if (normalized.isNotEmpty) {
      where.add(
        "(LOWER(i.name) LIKE ? OR LOWER(COALESCE(i.sku, '')) LIKE ? OR LOWER(COALESCE(i.size, '')) LIKE ?)",
      );
      final like = '%$normalized%';
      variables
        ..add(Variable<String>(like))
        ..add(Variable<String>(like))
        ..add(Variable<String>(like));
    }

    final sql =
        '''
      SELECT
        i.id,
        i.name,
        i.price,
        i.sku,
        COALESCE(i.category, 'General') AS category,
        i.subcategory,
        i.size,
        i.description,
        i.hsn_code,
        COALESCE(i.gst_rate, 0) AS gst_rate,
        COALESCE(i.price_includes_tax, 1) AS price_includes_tax,
        i.stock,
        i.source_meta,
        i.image_path,
        i.unit,
        i.reorder_level,
        i.variant_group_id,
        i.variant_label,
        i.created_at,
        ${includeCost ? 'COALESCE(ip.cost_price, 0)' : 'NULL'} AS cost_price,
        ip.supplier_id,
        ip.last_purchase_date
      FROM inventory i
      LEFT JOIN inventory_private ip ON ip.id = i.id AND ip.tombstone = 0
      WHERE ${where.join(' AND ')}
      ORDER BY LOWER(i.name) ASC, LOWER(COALESCE(i.size, '')) ASC
      LIMIT ? OFFSET ?;
    ''';

    variables
      ..add(Variable<int>(pageSize))
      ..add(Variable<int>(offset));

    return _db
        .customSelect(
          sql,
          variables: variables,
          readsFrom: {_db.inventoryEntries, _db.inventoryPrivateEntries},
        )
        .watch()
        .map((rows) => rows.map(_mapCatalogRow).toList(growable: false));
  }

  Future<InventoryCatalogItem?> findByExactLookup(
    String lookup, {
    required bool includeCost,
  }) async {
    final value = lookup.trim().toLowerCase();
    if (value.isEmpty) return null;

    final rows = await _db
        .customSelect(
          '''
        SELECT
          i.id,
          i.name,
          i.price,
          i.sku,
          COALESCE(i.category, 'General') AS category,
          i.subcategory,
          i.size,
          i.description,
          i.hsn_code,
          COALESCE(i.gst_rate, 0) AS gst_rate,
          COALESCE(i.price_includes_tax, 1) AS price_includes_tax,
          i.stock,
          i.source_meta,
          i.image_path,
          i.unit,
          i.reorder_level,
          i.variant_group_id,
          i.variant_label,
          i.created_at,
          ${includeCost ? 'COALESCE(ip.cost_price, 0)' : 'NULL'} AS cost_price,
          ip.supplier_id,
          ip.last_purchase_date
        FROM inventory i
        LEFT JOIN inventory_private ip ON ip.id = i.id AND ip.tombstone = 0
        WHERE i.tombstone = 0
          AND (
            LOWER(i.id) = ?
            OR LOWER(COALESCE(i.sku, '')) = ?
          )
        LIMIT 1;
      ''',
          variables: [Variable<String>(value), Variable<String>(value)],
          readsFrom: {_db.inventoryEntries, _db.inventoryPrivateEntries},
        )
        .get();

    if (rows.isEmpty) return null;
    return _mapCatalogRow(rows.first);
  }

  /// Resolve a set of item ids to full catalog items (for POS quick-keys).
  Stream<List<InventoryCatalogItem>> watchItemsByIds(List<String> ids) {
    if (ids.isEmpty) {
      return Stream<List<InventoryCatalogItem>>.value(
        const <InventoryCatalogItem>[],
      );
    }
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    return _db
        .customSelect(
          '''
        SELECT
          i.id, i.name, i.price, i.sku,
          COALESCE(i.category, 'General') AS category,
          i.subcategory, i.size, i.description, i.hsn_code,
          COALESCE(i.gst_rate, 0) AS gst_rate,
          COALESCE(i.price_includes_tax, 1) AS price_includes_tax,
          i.stock, i.source_meta, i.image_path, i.unit, i.reorder_level,
          i.variant_group_id, i.variant_label, i.created_at,
          NULL AS cost_price, NULL AS supplier_id, NULL AS last_purchase_date
        FROM inventory i
        WHERE i.tombstone = 0 AND i.id IN ($placeholders);
      ''',
          variables: ids.map((id) => Variable<String>(id)).toList(),
          readsFrom: {_db.inventoryEntries},
        )
        .watch()
        .map((rows) => rows.map(_mapCatalogRow).toList(growable: false));
  }

  /// Rename a category across every item that carries it. Returns the number
  /// of items updated.
  Future<int> renameCategory(String from, String to) async {
    final normalized = to.trim().isEmpty ? 'General' : to.trim();
    return (_db.update(
      _db.inventoryEntries,
    )..where((tbl) => tbl.category.equals(from))).write(
      InventoryEntriesCompanion(
        category: Value(normalized),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> mergeInventoryDocument(
    String id,
    Map<String, dynamic> data, {
    required int updatedAt,
  }) async {
    final createdAt = _asEpoch(data['createdAt']) ?? updatedAt;
    await _db
        .into(_db.inventoryEntries)
        .insertOnConflictUpdate(
          InventoryEntriesCompanion.insert(
            id: id,
            name: (data['name'] ?? 'Unnamed item').toString(),
            price: _asDouble(data['price']),
            sku: Value(_asStringOrNull(data['sku'])),
            category: Value(
              _asStringOrNull(data['category'])?.trim().isNotEmpty == true
                  ? _asStringOrNull(data['category'])!
                  : 'General',
            ),
            subcategory: Value(_asStringOrNull(data['subcategory'])),
            size: Value(_asStringOrNull(data['size'])),
            description: Value(_asStringOrNull(data['description'])),
            hsnCode: Value(
              _asStringOrNull(data['hsnCode'] ?? data['hsn_code']),
            ),
            gstRate: Value(_asDouble(data['gstRate'] ?? data['gst_rate'])),
            priceIncludesTax: Value(
              _asBool(
                data['priceIncludesTax'] ?? data['price_includes_tax'],
                fallback: true,
              ),
            ),
            stock: Value(_asDouble(data['stock'])),
            sourceMeta: Value(_encodeNullableJson(data['sourceMeta'])),
            // Only touch the photo when the caller supplies one, so imports and
            // sync merges that don't carry an image never wipe an existing one.
            imagePath:
                (data.containsKey('imagePath') ||
                    data.containsKey('image_path'))
                ? Value(
                    _asStringOrNull(data['imagePath'] ?? data['image_path']),
                  )
                : const Value.absent(),
            unit: (data.containsKey('unit'))
                ? Value(_asStringOrNull(data['unit']))
                : const Value.absent(),
            reorderLevel:
                (data.containsKey('reorderLevel') ||
                    data.containsKey('reorder_level'))
                ? Value(
                    _asIntOrNull(data['reorderLevel'] ?? data['reorder_level']),
                  )
                : const Value.absent(),
            // Absent rather than null when the payload is silent: an import or
            // a partial merge that does not mention stock history must not
            // erase what a full sync already established.
            hasStockHistory:
                (data.containsKey('hasStockHistory') ||
                    data.containsKey('has_stock_history'))
                ? Value(
                    _asBoolOrNull(
                      data['hasStockHistory'] ?? data['has_stock_history'],
                    ),
                  )
                : const Value.absent(),
            variantGroupId:
                (data.containsKey('variantGroupId') ||
                    data.containsKey('variant_group_id'))
                ? Value(
                    _asStringOrNull(
                      data['variantGroupId'] ?? data['variant_group_id'],
                    ),
                  )
                : const Value.absent(),
            variantLabel:
                (data.containsKey('variantLabel') ||
                    data.containsKey('variant_label'))
                ? Value(
                    _asStringOrNull(
                      data['variantLabel'] ?? data['variant_label'],
                    ),
                  )
                : const Value.absent(),
            createdAt: createdAt,
            updatedAt: Value(updatedAt),
            tombstone: Value(data['tombstone'] == true),
          ),
        );
  }

  Future<void> mergeInventoryPrivateDocument(
    String id,
    Map<String, dynamic> data, {
    required int updatedAt,
  }) async {
    await _db
        .into(_db.inventoryPrivateEntries)
        .insertOnConflictUpdate(
          InventoryPrivateEntriesCompanion.insert(
            id: id,
            costPrice: Value(_asDouble(data['costPrice'])),
            supplierId: Value(_asStringOrNull(data['supplierId'])),
            lastPurchaseDate: Value(_asStringOrNull(data['lastPurchaseDate'])),
            updatedAt: Value(updatedAt),
            tombstone: Value(data['tombstone'] == true),
          ),
        );
  }

  Future<void> mergeBackendInventoryItem(
    Map<String, dynamic> row, {
    int? updatedAt,

    /// Fetches this product's photo, when the row says there is one.
    ///
    /// Injected rather than called from here: the repository talks to the
    /// database, and giving it an HTTP client to reach for would make every
    /// merge a network operation.
    Future<({List<int> bytes, String? contentType})?> Function()? fetchImage,
  }) async {
    final id = _asStringOrNull(row['id']);
    if (id == null) {
      return;
    }
    final resolvedUpdatedAt =
        updatedAt ??
        _asEpoch(row['updated_at'] ?? row['created_at']) ??
        DateTime.now().millisecondsSinceEpoch;

    // Rehydrate the product photo pulled from the server into a local file so
    // the existing file-based display code works and images survive a data
    // clear. Only when we don't already have a local copy.
    String? hydratedImagePath;
    // The list no longer carries the picture - it was base64 on every row, so
    // one sync pulled every photo in the shop whether it had changed or not.
    // It carries a flag now, and the picture is fetched from its own address.
    //
    // image_data is still read first so this keeps working against a server
    // that has not been updated yet.
    final remoteImage = _asStringOrNull(row['image_data']);
    final serverHasImage = remoteImage != null || row['has_image'] == true;
    if (serverHasImage) {
      final existing = await (_db.select(
        _db.inventoryEntries,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      final hasLocal =
          existing?.imagePath != null &&
          existing!.imagePath!.isNotEmpty &&
          File(existing.imagePath!).existsSync();
      if (!hasLocal) {
        if (remoteImage != null) {
          hydratedImagePath = await ProductImageStore().storeFromDataUri(
            remoteImage,
          );
        } else if (fetchImage != null) {
          final fetched = await fetchImage();
          if (fetched != null) {
            hydratedImagePath = await ProductImageStore().storeFromBytes(
              fetched.bytes,
              contentType: fetched.contentType,
            );
          }
        }
      }
    }

    await mergeInventoryDocument(id, <String, dynamic>{
      'name': row['name'],
      'imagePath': ?hydratedImagePath,
      'price': row['sell_price'] ?? row['price'],
      'sku': row['sku'],
      'category': row['category'],
      'subcategory': row['subcategory'],
      'size': row['size'],
      'description': row['description'],
      'hsn_code': row['hsn_code'],
      'gst_rate': row['gst_rate'],
      'price_includes_tax': row['price_includes_tax'],
      'stock': row['stock_on_hand'] ?? row['stock'],
      // These used to be device-only, so a reinstall lost every reorder level
      // the shop had set. They now round-trip through the API.
      'unit': row['unit'],
      'reorderLevel': row['reorder_level'] ?? row['reorderLevel'],
      'sourceMeta': row['source_meta_json'] ?? row['sourceMeta'],
      'createdAt': row['created_at'] ?? resolvedUpdatedAt,
      'updatedAt': row['updated_at'] ?? resolvedUpdatedAt,
      'tombstone': row['tombstone'] == true || row['status'] == 'archived',
    }, updatedAt: resolvedUpdatedAt);

    if (row.containsKey('cost_price') ||
        row.containsKey('supplier_id') ||
        row.containsKey('last_purchase_date')) {
      await mergeInventoryPrivateDocument(id, <String, dynamic>{
        'costPrice': row['cost_price'],
        'supplierId': row['supplier_id'],
        'lastPurchaseDate': row['last_purchase_date'],
        'updatedAt': row['updated_at'] ?? resolvedUpdatedAt,
        'tombstone': row['tombstone'] == true,
      }, updatedAt: resolvedUpdatedAt);
    }
  }

  InventoryCatalogItem _mapCatalogRow(QueryRow row) {
    // Use nullable reads with defaults everywhere: Drift's read<T>() for a
    // non-null column ends in a `!`, so a single NULL in any column (e.g. a
    // legacy/imported row missing gst_rate or created_at) would crash the whole
    // catalog stream with "Null check operator used on a null value" — which
    // surfaced as "Add item failed" when the list rebuilt after an insert.
    return InventoryCatalogItem(
      id: row.readNullable<String>('id') ?? '',
      name: row.readNullable<String>('name') ?? 'Unnamed item',
      price: row.readNullable<double>('price') ?? 0,
      sku: row.readNullable<String>('sku'),
      category: row.readNullable<String>('category') ?? 'General',
      subcategory: row.readNullable<String>('subcategory'),
      size: row.readNullable<String>('size'),
      description: row.readNullable<String>('description'),
      hsnCode: row.readNullable<String>('hsn_code'),
      gstRate: row.readNullable<double>('gst_rate') ?? 0,
      priceIncludesTax: row.readNullable<bool>('price_includes_tax') ?? true,
      stock: row.readNullable<double>('stock') ?? 0,
      sourceMeta: row.readNullable<String>('source_meta'),
      imagePath: row.readNullable<String>('image_path'),
      unit: row.readNullable<String>('unit'),
      reorderLevel: row.readNullable<int>('reorder_level'),
      variantGroupId: row.readNullable<String>('variant_group_id'),
      variantLabel: row.readNullable<String>('variant_label'),
      hasStockHistory: row.readNullable<bool>('has_stock_history'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.readNullable<int>('created_at') ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      costPrice: row.readNullable<double>('cost_price'),
      supplierId: row.readNullable<String>('supplier_id'),
      lastPurchaseDate: row.readNullable<String>('last_purchase_date'),
    );
  }

  /// Receive stock into an item (used by purchases). Increments stock, updates
  /// the last cost when supplied, and logs a movement — all in one transaction.
  Future<void> applyStockIn({
    required String itemId,
    required double quantity,
    double? unitCost,
    bool updateCost = true,
    String reason = 'PURCHASE',
    String? refId,
    String? actorName,
    String note = '',
  }) async {
    if (quantity == 0) return;
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.inventoryEntries,
      )..where((t) => t.id.equals(itemId))).getSingleOrNull();
      if (row == null) return;
      final newStock = row.stock + quantity;
      await (_db.update(
        _db.inventoryEntries,
      )..where((t) => t.id.equals(itemId))).write(
        InventoryEntriesCompanion(
          stock: Value(newStock),
          updatedAt: Value(nowMillis),
        ),
      );
      if (updateCost && unitCost != null && unitCost > 0) {
        await _db
            .into(_db.inventoryPrivateEntries)
            .insertOnConflictUpdate(
              InventoryPrivateEntriesCompanion.insert(
                id: itemId,
                costPrice: Value(unitCost),
                lastPurchaseDate: Value(
                  DateTime.now().toIso8601String().split('T').first,
                ),
                updatedAt: Value(nowMillis),
              ),
            );
      }
      await _writeStockMovement(
        _db,
        itemId: itemId,
        itemName: row.name,
        delta: quantity,
        reason: reason,
        balanceAfter: newStock,
        refId: refId,
        actorName: actorName,
        note: note,
      );
    });
  }

  /// Log a manual stock correction (the delta between the old and new counts)
  /// so the audit trail explains every change, not just automated ones.
  Future<void> logStockAdjustment({
    required String itemId,
    required String itemName,
    required double oldStock,
    required double newStock,
    String? actorName,
    String note = 'Manual adjustment',
  }) async {
    final delta = newStock - oldStock;
    if (delta.abs() < 0.0001) return;
    await _writeStockMovement(
      _db,
      itemId: itemId,
      itemName: itemName,
      delta: delta,
      reason: 'ADJUST',
      balanceAfter: newStock,
      note: note,
      actorName: actorName,
    );
  }

  Stream<List<StockMovement>> watchStockMovements({
    String? itemId,
    int limit = 200,
  }) {
    final where = <String>[];
    final vars = <Variable<Object>>[];
    if (itemId != null && itemId.isNotEmpty) {
      where.add('item_id = ?');
      vars.add(Variable<String>(itemId));
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} ';
    return _db
        .customSelect(
          'SELECT * FROM stock_movements ${whereSql}ORDER BY created_at DESC '
          'LIMIT ?;',
          variables: [...vars, Variable<int>(limit)],
          readsFrom: {_db.stockMovementEntries},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => StockMovement(
                  id: row.readNullable<String>('id') ?? '',
                  itemId: row.readNullable<String>('item_id') ?? '',
                  itemName: row.readNullable<String>('item_name') ?? '',
                  delta: row.readNullable<double>('delta') ?? 0,
                  balanceAfter: row.readNullable<double>('balance_after'),
                  reason: row.readNullable<String>('reason') ?? '',
                  refId: row.readNullable<String>('ref_id'),
                  note: row.readNullable<String>('note') ?? '',
                  actorName: _asStringOrNull(
                    row.readNullable<String>('actor_name'),
                  ),
                  createdAt: DateTime.fromMillisecondsSinceEpoch(
                    row.readNullable<int>('created_at') ?? 0,
                  ),
                ),
              )
              .toList(growable: false),
        );
  }

  Future<void> clearWorkspace() async {
    await _db.transaction(() async {
      await _db.delete(_db.inventoryPrivateEntries).go();
      await _db.delete(_db.inventoryEntries).go();
      await _db.delete(_db.stockMovementEntries).go();
    });
  }
}

class CustomerRepository {
  CustomerRepository(this._db);

  final BusinessHubDatabase _db;

  /// Everyone who owes money, biggest debt first — the order a shopkeeper
  /// actually works through when collecting udhaar.
  Stream<List<KhataDebtor>> watchDebtors() {
    final query = _db.select(_db.customerEntries)
      ..where((t) => t.tombstone.equals(false) & t.balance.isBiggerThanValue(0))
      ..orderBy([(t) => OrderingTerm.desc(t.balance)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => KhataDebtor(
              id: row.id,
              name: row.name,
              phone: row.phone ?? '',
              balance: row.balance,
              lastRemindedAt: row.lastRemindedAt == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(row.lastRemindedAt!),
              lastSeenAt: row.lastSeenAt == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(row.lastSeenAt!),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Record that a reminder was sent, so the same customer isn't chased twice
  /// in a day and the list can show who is genuinely overdue.
  Future<void> markReminded(String customerId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(
      _db.customerEntries,
    )..where((t) => t.id.equals(customerId))).write(
      CustomerEntriesCompanion(
        lastRemindedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Stream<List<BackendCustomerSummary>> watchLegacyCustomers({
    String search = '',
  }) {
    final normalized = search.trim().toLowerCase();
    final where = <String>['tombstone = 0'];
    final variables = <Variable<Object>>[];

    if (normalized.isNotEmpty) {
      where.add(
        "(LOWER(name) LIKE ? OR LOWER(COALESCE(phone, '')) LIKE ? OR LOWER(COALESCE(email, '')) LIKE ?)",
      );
      final like = '%$normalized%';
      variables
        ..add(Variable<String>(like))
        ..add(Variable<String>(like))
        ..add(Variable<String>(like));
    }

    final sql =
        '''
      SELECT
        id,
        name,
        phone,
        email,
        notes,
        status,
        total_spent,
        balance
      FROM customers
      WHERE ${where.join(' AND ')}
      ORDER BY
        CASE WHEN balance > 0 THEN 0 ELSE 1 END,
        balance DESC,
        LOWER(name) ASC;
    ''';

    return _db
        .customSelect(
          sql,
          variables: variables,
          readsFrom: {_db.customerEntries},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => BackendCustomerSummary(
                  id: row.readNullable<String>('id') ?? '',
                  name: row.readNullable<String>('name') ?? '',
                  phone: _asStringOrNull(row.readNullable<String>('phone')),
                  email: _asStringOrNull(row.readNullable<String>('email')),
                  notes: _asStringOrNull(row.readNullable<String>('notes')),
                  status: row.readNullable<String>('status') ?? '',
                  totalSpent: row.readNullable<double>('total_spent') ?? 0,
                  balance: row.readNullable<double>('balance') ?? 0,
                ),
              )
              .toList(growable: false),
        );
  }

  Future<void> mergeRemoteCustomerDocument(
    String id,
    Map<String, dynamic> data, {
    required int updatedAt,
  }) async {
    final createdAt =
        _asEpoch(data['createdAt'] ?? data['created_at']) ?? updatedAt;
    final lastSeenAt =
        _asEpoch(data['lastSeenAt'] ?? data['last_seen_at']) ??
        _asEpoch(data['updatedAt'] ?? data['updated_at']) ??
        updatedAt;

    await _db
        .into(_db.customerEntries)
        .insertOnConflictUpdate(
          CustomerEntriesCompanion.insert(
            id: id,
            name: (data['name'] ?? data['customerName'] ?? 'Unnamed customer')
                .toString(),
            phone: Value(
              _asStringOrNull(
                data['phone'] ?? data['mobile'] ?? data['mobileNumber'],
              ),
            ),
            email: Value(_asStringOrNull(data['email'])),
            notes: Value(
              _asStringOrNull(data['notes'] ?? data['note'] ?? data['remark']),
            ),
            status: Value(
              _asStringOrNull(data['status']) ??
                  (data['tombstone'] == true ? 'archived' : 'active'),
            ),
            totalSpent: Value(
              _asDouble(
                data['totalSpent'] ??
                    data['total_spent'] ??
                    data['lifetimeSpend'] ??
                    data['lifetime_spend'],
              ),
            ),
            balance: Value(
              _asDouble(
                data['balance'] ??
                    data['currentBalance'] ??
                    data['current_balance'] ??
                    data['dueAmount'] ??
                    data['due_amount'],
              ),
            ),
            createdAt: createdAt,
            updatedAt: Value(updatedAt),
            lastSeenAt: Value(lastSeenAt),
            // Shared across devices so the owner on the web and the cashier
            // here never chase the same customer on the same day.
            lastRemindedAt: Value(
              _asEpoch(data['lastRemindedAt'] ?? data['last_reminded_at']),
            ),
            tombstone: Value(data['tombstone'] == true),
          ),
        );
  }

  /// Record a payment against a customer's due: reduce the balance (never below
  /// zero) and append a PAYMENT entry to their khata — atomically.
  Future<double> recordPayment({
    required String customerId,
    required double amount,
    String? actorName,
    String note = 'Payment received',
  }) async {
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    var newBalance = 0.0;
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.customerEntries,
      )..where((t) => t.id.equals(customerId))).getSingleOrNull();
      if (row == null) return;
      final applied = amount < 0 ? 0.0 : amount;
      newBalance = (row.balance - applied).clamp(0, double.infinity).toDouble();
      await (_db.update(
        _db.customerEntries,
      )..where((t) => t.id.equals(customerId))).write(
        CustomerEntriesCompanion(
          balance: Value(newBalance),
          updatedAt: Value(nowMillis),
        ),
      );
      await _writeCustomerLedger(
        _db,
        customerId: customerId,
        type: 'PAYMENT',
        amount: -applied,
        balanceAfter: newBalance,
        note: note,
        actorName: actorName,
      );
    });
    return newBalance;
  }

  /// Record where an imported/brought-forward balance came from.
  ///
  /// Setting `balance` on its own leaves a customer showing a due with an
  /// empty khata - the owner cannot tell the customer what the money is for,
  /// which is exactly when they need the ledger. The id is derived from the
  /// customer so re-importing the same sheet corrects the opening row instead
  /// of stacking duplicates on top of it.
  Future<void> recordOpeningBalance({
    required String customerId,
    required double balance,
    DateTime? occurredAt,
    String note = 'Opening balance (imported)',
  }) async {
    if (balance == 0) return;
    final at = (occurredAt ?? DateTime.now()).millisecondsSinceEpoch;
    await _db
        .into(_db.customerLedgerEntries)
        .insertOnConflictUpdate(
          CustomerLedgerEntriesCompanion.insert(
            id: 'led-opening-$customerId',
            customerId: customerId,
            type: 'OPENING',
            amount: balance,
            balanceAfter: balance,
            note: Value(note),
            createdAt: at,
          ),
        );
  }

  /// How many customers carry a balance with nothing in their khata to explain
  /// it - the fallout of imports that set a balance and wrote no ledger row.
  Future<int> countUnexplainedBalances() async {
    final rows = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM customers c WHERE c.balance != 0 '
          'AND c.tombstone = 0 AND NOT EXISTS ('
          'SELECT 1 FROM customer_ledger l WHERE l.customer_id = c.id);',
          readsFrom: {_db.customerEntries, _db.customerLedgerEntries},
        )
        .get();
    return rows.first.readNullable<int>('c') ?? 0;
  }

  /// Give those balances an origin row, dated to when the customer was added.
  ///
  /// This records the balance that is already there rather than inventing an
  /// amount, and labels it "carried over" so nobody mistakes it for a real
  /// sale. Customers who already have any ledger history are left alone, so it
  /// cannot double-count, and re-running it is a no-op.
  Future<int> backfillOpeningBalances() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.transaction(() async {
      // customUpdate, not customInsert: drift's customInsert returns the new
      // rowid, which for an INSERT...SELECT is meaningless as a count and
      // silently reads as "1 row written" even when nothing was.
      return _db.customUpdate(
        'INSERT INTO customer_ledger '
        '(id, customer_id, type, amount, balance_after, note, created_at) '
        "SELECT 'led-opening-' || c.id, c.id, 'OPENING', c.balance, c.balance, "
        "'Opening balance (carried over)', "
        'CASE WHEN c.created_at > 0 THEN c.created_at ELSE ? END '
        'FROM customers c WHERE c.balance != 0 AND c.tombstone = 0 '
        'AND NOT EXISTS ('
        'SELECT 1 FROM customer_ledger l WHERE l.customer_id = c.id);',
        variables: [Variable<int>(now)],
        updates: {_db.customerLedgerEntries},
      );
    });
  }

  Stream<List<CustomerLedgerRecord>> watchLedger(String customerId) {
    return _db
        .customSelect(
          'SELECT * FROM customer_ledger WHERE customer_id = ? '
          'ORDER BY created_at DESC;',
          variables: [Variable<String>(customerId)],
          readsFrom: {_db.customerLedgerEntries},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => CustomerLedgerRecord(
                  id: row.readNullable<String>('id') ?? '',
                  customerId: row.readNullable<String>('customer_id') ?? '',
                  type: row.readNullable<String>('type') ?? '',
                  amount: row.readNullable<double>('amount') ?? 0,
                  balanceAfter: row.readNullable<double>('balance_after') ?? 0,
                  refId: _asStringOrNull(row.readNullable<String>('ref_id')),
                  note: row.readNullable<String>('note') ?? '',
                  actorName: _asStringOrNull(
                    row.readNullable<String>('actor_name'),
                  ),
                  createdAt: DateTime.fromMillisecondsSinceEpoch(
                    row.readNullable<int>('created_at') ?? 0,
                  ),
                ),
              )
              .toList(growable: false),
        );
  }

  Future<void> clearWorkspace() async {
    await _db.transaction(() async {
      await _db.delete(_db.customerEntries).go();
      await _db.delete(_db.customerLedgerEntries).go();
    });
  }
}

class SalesRepository {
  SalesRepository(this._db);

  final BusinessHubDatabase _db;

  Stream<HistoryOverview> watchHistoryOverview() {
    return _db
        .customSelect(
          '''
            SELECT
              COUNT(*) AS total_sales,
              COALESCE(SUM(total), 0.0) AS total_revenue,
              COALESCE(SUM(CASE WHEN sync_status IN ('synced_backend', 'synced') THEN 1 ELSE 0 END), 0) AS synced_sales,
              COALESCE(SUM(CASE WHEN sync_status IN ('queued', 'syncing') THEN 1 ELSE 0 END), 0) AS queued_sales,
              COALESCE(SUM(CASE WHEN sync_status IN ('queued', 'syncing') THEN total ELSE 0 END), 0.0) AS queued_revenue,
              COALESCE(SUM(CASE WHEN sync_status IN ('failed_backend', 'failed') THEN 1 ELSE 0 END), 0) AS failed_sales,
              COALESCE(SUM(CASE WHEN sync_status = 'rejected' THEN 1 ELSE 0 END), 0) AS rejected_sales,
              MAX(last_synced_at) AS last_synced_at
            FROM sales
            WHERE tombstone = 0 AND sync_status NOT IN ('refunded', 'void');
          ''',
          readsFrom: {_db.salesEntries},
        )
        .watchSingle()
        .map(
          (row) => HistoryOverview(
            totalSales: row.readNullable<int>('total_sales') ?? 0,
            syncedSales: row.readNullable<int>('synced_sales') ?? 0,
            queuedSales: row.readNullable<int>('queued_sales') ?? 0,
            failedSales: row.readNullable<int>('failed_sales') ?? 0,
            rejectedSales: row.readNullable<int>('rejected_sales') ?? 0,
            totalRevenue: row.readNullable<double>('total_revenue') ?? 0,
            queuedRevenue: row.readNullable<double>('queued_revenue') ?? 0,
            lastSyncedAt: row.readNullable<int>('last_synced_at') == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    row.readNullable<int>('last_synced_at') ?? 0,
                  ),
          ),
        );
  }

  Stream<List<RecentSaleSummary>> watchRecentSales({
    int limit = 8,
    String search = '',
    String? paymentMode,
    CommerceSyncState? syncState,
    HistoryFilter? filter,
  }) {
    final effectiveLimit = filter?.limit ?? limit;
    final normalized = (filter?.search ?? search).trim().toLowerCase();
    final effectivePaymentMode = filter?.paymentMode ?? paymentMode;
    final effectiveSyncState = filter?.syncState ?? syncState;
    final query = _db.select(_db.salesEntries)
      ..where((tbl) => tbl.tombstone.equals(false));

    if (normalized.isNotEmpty) {
      query.where(
        (tbl) =>
            tbl.customerName.lower().like('%$normalized%') |
            tbl.customerPhone.lower().like('%$normalized%') |
            tbl.id.lower().like('%$normalized%'),
      );
    }

    if (effectivePaymentMode != null && effectivePaymentMode.isNotEmpty) {
      query.where((tbl) => tbl.paymentMode.equals(effectivePaymentMode));
    }

    if (effectiveSyncState != null) {
      final statuses = switch (effectiveSyncState) {
        CommerceSyncState.localOnly => const ['local_only'],
        CommerceSyncState.queued => const ['queued'],
        CommerceSyncState.syncing => const ['syncing'],
        CommerceSyncState.synced => const ['synced_backend', 'synced'],
        CommerceSyncState.failed => const ['failed_backend', 'failed'],
        CommerceSyncState.refunded => const ['refunded', 'void'],
      };
      query.where((tbl) => tbl.syncStatus.isIn(statuses));
    }

    final dateWindow = filter?.dateWindow ?? HistoryDateWindow.all;
    final exactDate = _historyExactDate(dateWindow);
    final sinceDate = _historySinceDate(dateWindow);
    if (exactDate != null) {
      query.where((tbl) => tbl.date.equals(exactDate));
    } else if (sinceDate != null) {
      query.where((tbl) => tbl.date.isBiggerOrEqualValue(sinceDate));
    }

    query
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)])
      ..limit(effectiveLimit);

    return query.watch().map(
      (rows) => rows
          .map((row) {
            final payments = _parseSalePayments(row.paymentsJson);
            final amountReceived = payments.fold<double>(
              0,
              (sum, payment) => sum + payment.amount,
            );
            final amountDue = row.total - amountReceived;
            return RecentSaleSummary(
              id: row.id,
              total: row.total,
              amountReceived: amountReceived,
              amountDue: amountDue > 0 ? amountDue : 0,
              date: row.date,
              paymentMode: row.paymentMode,
              customerName: row.customerName,
              itemSummary: _summariseItems(row.itemsJson),
              syncState: _parseSyncState(row.syncStatus),
            );
          })
          .where(
            (sale) =>
                !(filter?.onlyDueSales ?? false) || sale.hasOutstandingDue,
          )
          .toList(growable: false),
    );
  }

  /// Insert a historical sale (e.g. imported from another POS). Idempotent by
  /// [id]; does NOT touch inventory stock or the sync outbox — it is treated
  /// as settled past history.
  /// SQL grouping that defines "the same imported receipt". Kept in one place
  /// so the preview and the cleanup can never drift apart and delete something
  /// the preview did not show.
  static const String _importedDuplicateGrouping =
      'GROUP BY date, total, discount, payment_mode, '
      "IFNULL(customer_name, ''), IFNULL(customer_phone, '')";

  static const String _importedDuplicateScope =
      "WHERE id LIKE 'import-sale-%' AND tombstone = 0";

  /// Preview duplicate imported receipts, worst offenders first.
  ///
  /// Scoped to `import-sale-%` so real POS sales are never considered. Note
  /// this cannot distinguish a file imported twice from a shop that genuinely
  /// rang up two identical sales in a day - the caller must show the user what
  /// would go before removing anything.
  Future<List<ImportedDuplicateGroup>> findImportedSaleDuplicates() async {
    final rows = await _db
        .customSelect(
          'SELECT date, total, COUNT(*) AS copies, '
          "IFNULL(customer_name, '') AS who FROM sales "
          '$_importedDuplicateScope $_importedDuplicateGrouping '
          'HAVING COUNT(*) > 1 ORDER BY COUNT(*) DESC, total DESC;',
          readsFrom: {_db.salesEntries},
        )
        .get();
    return rows
        .map(
          (row) => ImportedDuplicateGroup(
            date: row.readNullable<String>('date') ?? '',
            total: row.readNullable<double>('total') ?? 0,
            customerName: row.readNullable<String>('who') ?? '',
            copies: row.readNullable<int>('copies') ?? 0,
          ),
        )
        .toList();
  }

  /// Collapse duplicate imported receipts to one copy each.
  ///
  /// Tombstones rather than deletes, so a wrong call is recoverable and the
  /// rows stay auditable. Imported sales touch no stock ledger and no customer
  /// balance, so this only affects History and Reports. Returns how many rows
  /// were retired.
  Future<int> removeImportedSaleDuplicates() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.transaction(() async {
      // Keep the lexicographically first id in each group; deterministic, so
      // re-running is a no-op rather than eating another copy.
      return _db.customUpdate(
        'UPDATE sales SET tombstone = 1, updated_at = ? '
        '$_importedDuplicateScope AND id NOT IN ('
        'SELECT MIN(id) FROM sales $_importedDuplicateScope '
        '$_importedDuplicateGrouping);',
        variables: [Variable<int>(now)],
        updates: {_db.salesEntries},
      );
    });
  }

  /// Ids of sales already stored, so an importer can tell the user how many
  /// rows a re-import will overwrite rather than silently reprocessing them.
  Future<Set<String>> existingSaleIds() async {
    final rows =
        await (_db.selectOnly(_db.salesEntries)
              ..addColumns([_db.salesEntries.id]))
            .map((row) => row.read(_db.salesEntries.id))
            .get();
    return rows.whereType<String>().toSet();
  }

  Future<void> importHistoricalSale({
    required String id,
    required String date,
    required int createdAtMillis,
    required double total,
    required double discount,
    required String paymentMode,
    required String? customerName,
    required String? customerPhone,
    required String footerNote,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> payments,
  }) async {
    await _db
        .into(_db.salesEntries)
        .insertOnConflictUpdate(
          SalesEntriesCompanion.insert(
            id: id,
            total: total,
            discount: Value(discount),
            discountType: const Value('fixed'),
            paymentMode: Value(paymentMode),
            date: date,
            createdAt: createdAtMillis,
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
            customerName: Value(customerName),
            customerPhone: Value(customerPhone),
            footerNote: Value(footerNote),
            itemsJson: jsonEncode(items),
            paymentsJson: jsonEncode(payments),
            commandId: Value('zobaze-import-$id'),
            syncStatus: const Value('synced'),
            backendSaleId: const Value(null),
          ),
        );
  }

  Future<SaleRecordDetail?> getSaleDetail(String saleId) async {
    final row = await (_db.select(
      _db.salesEntries,
    )..where((tbl) => tbl.id.equals(saleId))).getSingleOrNull();
    if (row == null) {
      return null;
    }

    return SaleRecordDetail(
      id: row.id,
      total: row.total,
      discount: row.discount,
      discountType: row.discountType,
      paymentMode: row.paymentMode,
      date: row.date,
      syncState: _parseSyncState(row.syncStatus),
      items: _parseSaleItems(row.itemsJson),
      payments: _parseSalePayments(row.paymentsJson),
      customerName: row.customerName,
      customerPhone: row.customerPhone,
      footerNote: row.footerNote,
      commandId: row.commandId,
      backendSaleId: row.backendSaleId,
      lastSyncError: row.lastSyncError,
    );
  }

  Stream<List<CustomerPulseSummary>> watchCustomerPulse({
    String search = '',
    int limit = 18,
  }) {
    final normalized = search.trim().toLowerCase();
    final variables = <Variable<Object>>[];
    final where = <String>[
      'tombstone = 0',
      "(TRIM(COALESCE(customer_name, '')) <> '' OR TRIM(COALESCE(customer_phone, '')) <> '')",
    ];

    if (normalized.isNotEmpty) {
      where.add(
        "(LOWER(COALESCE(customer_name, '')) LIKE ? OR LOWER(COALESCE(customer_phone, '')) LIKE ?)",
      );
      final like = '%$normalized%';
      variables
        ..add(Variable<String>(like))
        ..add(Variable<String>(like));
    }

    variables.add(Variable<int>(limit));

    return _db
        .customSelect(
          '''
            SELECT
              COALESCE(NULLIF(TRIM(customer_name), ''), 'Walk-in customer') AS customer_name,
              NULLIF(TRIM(customer_phone), '') AS customer_phone,
              COUNT(*) AS visit_count,
              COALESCE(SUM(total), 0.0) AS lifetime_spend,
              COALESCE(SUM(CASE WHEN sync_status IN ('queued', 'syncing', 'failed_backend', 'failed') THEN 1 ELSE 0 END), 0) AS pending_sales,
              MAX(created_at) AS last_seen_at
            FROM sales
            WHERE ${where.join(' AND ')}
            GROUP BY customer_name, customer_phone
            ORDER BY last_seen_at DESC, lifetime_spend DESC
            LIMIT ?;
          ''',
          variables: variables,
          readsFrom: {_db.salesEntries},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => CustomerPulseSummary(
                  name: row.readNullable<String>('customer_name') ?? '',
                  phone: row.readNullable<String>('customer_phone'),
                  visitCount: row.readNullable<int>('visit_count') ?? 0,
                  lifetimeSpend:
                      row.readNullable<double>('lifetime_spend') ?? 0,
                  pendingSales: row.readNullable<int>('pending_sales') ?? 0,
                  lastSeenAt: DateTime.fromMillisecondsSinceEpoch(
                    row.readNullable<int>('last_seen_at') ?? 0,
                  ),
                ),
              )
              .toList(growable: false),
        );
  }

  Stream<int> watchPendingOutboxCount() {
    return _db
        .customSelect(
          '''
            SELECT COUNT(*) AS total
            FROM commerce_outbox
            WHERE sync_status IN ('pending', 'failed', 'syncing');
          ''',
          readsFrom: {_db.commerceOutboxEntries},
        )
        .watchSingle()
        .map((row) => row.readNullable<int>('total') ?? 0);
  }

  Stream<List<CommerceOutboxAttentionEntry>> watchOutboxAttentionEntries({
    int limit = 6,
  }) {
    return _db
        .customSelect(
          '''
            SELECT
              o.command_id,
              o.command_type,
              o.sync_status,
              o.attempt_count,
              o.last_attempt_at,
              o.updated_at,
              o.last_error,
              s.id AS sale_id,
              COALESCE(s.customer_name, '') AS customer_name,
              COALESCE(s.total, 0.0) AS total,
              s.date AS sale_date
            FROM commerce_outbox o
            LEFT JOIN sales s ON s.command_id = o.command_id
            WHERE o.sync_status IN ('pending', 'failed', 'syncing')
            ORDER BY
              CASE o.sync_status
                WHEN 'failed' THEN 0
                WHEN 'syncing' THEN 1
                ELSE 2
              END,
              COALESCE(o.last_attempt_at, o.updated_at, o.created_at) DESC
            LIMIT ?;
          ''',
          variables: [Variable<int>(limit)],
          readsFrom: {_db.commerceOutboxEntries, _db.salesEntries},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => CommerceOutboxAttentionEntry(
                  commandId: row.readNullable<String>('command_id') ?? '',
                  commandType: row.readNullable<String>('command_type') ?? '',
                  syncStatus: row.readNullable<String>('sync_status') ?? '',
                  attemptCount: row.readNullable<int>('attempt_count') ?? 0,
                  updatedAt: row.readNullable<int>('updated_at') ?? 0,
                  lastAttemptAt: row.readNullable<int>('last_attempt_at'),
                  lastError: _asStringOrNull(
                    row.readNullable<String>('last_error'),
                  ),
                  saleId: _asStringOrNull(row.readNullable<String>('sale_id')),
                  customerName: _asStringOrNull(
                    row.readNullable<String>('customer_name'),
                  ),
                  total: row.readNullable<double>('total') ?? 0,
                  saleDate: _asStringOrNull(
                    row.readNullable<String>('sale_date'),
                  ),
                ),
              )
              .toList(growable: false),
        );
  }

  Future<void> mergeRemoteSaleDocument(
    String id,
    Map<String, dynamic> data, {
    required int updatedAt,
  }) async {
    final createdAt = _asEpoch(data['createdAt']) ?? updatedAt;
    final payments = data['payments'] is List
        ? jsonEncode(data['payments'])
        : jsonEncode(const []);
    final items = data['items'] is List
        ? jsonEncode(data['items'])
        : jsonEncode(const []);

    await _db
        .into(_db.salesEntries)
        .insertOnConflictUpdate(
          SalesEntriesCompanion.insert(
            id: id,
            total: _asDouble(data['total']),
            discount: Value(_asDouble(data['discount'])),
            discountType: Value((data['discountType'] ?? 'fixed').toString()),
            paymentMode: Value((data['paymentMode'] ?? 'CASH').toString()),
            date:
                (data['date'] ??
                        DateTime.now().toIso8601String().split('T').first)
                    .toString(),
            createdAt: createdAt,
            updatedAt: Value(updatedAt),
            customerName: Value(_asStringOrNull(data['customerName'])),
            customerPhone: Value(_asStringOrNull(data['customerPhone'])),
            customerId: Value(_asStringOrNull(data['customerId'])),
            footerNote: Value(_asStringOrNull(data['footerNote'])),
            itemsJson: items,
            paymentsJson: payments,
            tombstone: Value(data['tombstone'] == true),
          ),
        );
  }

  Future<void> mergeBackendSaleDocument(
    Map<String, dynamic> data, {
    required int updatedAt,
  }) async {
    final backendSaleId = (data['id'] ?? '').toString().trim();
    if (backendSaleId.isEmpty) {
      return;
    }

    final sourceMeta = data['source_meta_json'] is Map
        ? Map<String, dynamic>.from(data['source_meta_json'] as Map)
        : const <String, dynamic>{};
    final commandId = _asStringOrNull(sourceMeta['command_id']);
    final storageId = await _resolveSaleStorageId(
      backendSaleId: backendSaleId,
      commandId: commandId,
    );
    final createdAt =
        _asEpoch(
          data['occurred_at'] ?? data['created_at'] ?? data['createdAt'],
        ) ??
        updatedAt;
    final items = data['items'] is List
        ? jsonEncode(
            (data['items'] as List)
                .map(
                  (item) => {
                    'itemId': item['inventory_item_id'],
                    'name': item['name'],
                    'sku': item['sku'],
                    'size': item['size'],
                    'quantity': item['quantity'],
                    'price': _asDouble(item['unit_price']),
                    'costPrice': item['unit_cost'] == null
                        ? null
                        : _asDouble(item['unit_cost']),
                    'hsnCode': item['hsn_snapshot'],
                    'gstRate': _asDouble(item['gst_rate']),
                    'taxableAmount': _asDouble(item['taxable_amount']),
                    'taxAmount': _asDouble(item['tax_amount']),
                    'cgstAmount': _asDouble(item['cgst_amount']),
                    'sgstAmount': _asDouble(item['sgst_amount']),
                    'igstAmount': _asDouble(item['igst_amount']),
                  },
                )
                .toList(growable: false),
          )
        : jsonEncode(const []);
    final payments = data['payments'] is List
        ? jsonEncode(
            (data['payments'] as List)
                .map(
                  (payment) => {
                    'mode': payment['payment_method'],
                    'amount': _asDouble(payment['amount']),
                  },
                )
                .toList(growable: false),
          )
        : jsonEncode(const []);

    final combinedFooter =
        (data['buyer_gstin'] != null &&
            data['buyer_gstin'].toString().trim().isNotEmpty)
        ? '${data['footer_note'] ?? ''}\n\nBuyer GSTIN: ${data['buyer_gstin']}'
              .trim()
        : _asStringOrNull(data['footer_note']);

    await _db
        .into(_db.salesEntries)
        .insertOnConflictUpdate(
          SalesEntriesCompanion.insert(
            id: storageId,
            total: _asDouble(data['total_amount'] ?? data['total']),
            discount: Value(
              _asDouble(data['discount_amount'] ?? data['discount']),
            ),
            discountType: Value((data['discount_type'] ?? 'fixed').toString()),
            paymentMode: Value((data['payment_mode'] ?? 'CASH').toString()),
            date:
                (data['sale_date'] ??
                        data['date'] ??
                        DateTime.now().toIso8601String().split('T').first)
                    .toString(),
            createdAt: createdAt,
            updatedAt: Value(updatedAt),
            customerName: Value(_asStringOrNull(data['customer_name'])),
            customerPhone: Value(_asStringOrNull(data['customer_phone'])),
            customerId: Value(_asStringOrNull(data['customer_id'])),
            footerNote: Value(combinedFooter),
            itemsJson: items,
            paymentsJson: payments,
            commandId: Value(commandId),
            // A voided (refunded) sale from the server keeps its REFUNDED marker
            // so it doesn't reappear in revenue/counts after a re-sync.
            syncStatus: Value(
              (data['status'] ?? '').toString().toLowerCase() == 'void'
                  ? 'refunded'
                  : 'synced_backend',
            ),
            backendSaleId: Value(backendSaleId),
            lastSyncError: const Value(null),
            lastSyncedAt: Value(updatedAt),
            tombstone: Value(data['tombstone'] == true),
          ),
        );
  }

  Future<LocalSaleCommit> recordLocalSale({
    required String shopId,
    required List<PosCartItem> items,
    required List<PosPayment> payments,
    required String paymentMode,
    required String footerNote,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? buyerGstin,
    double discount = 0,
    int redeemPoints = 0,
    DateTime? saleDate,
  }) async {
    if (shopId.trim().isEmpty) {
      throw ArgumentError('A valid shopId is required to queue a mobile sale.');
    }

    final saleId = 'sale-${DateTime.now().millisecondsSinceEpoch}';
    final commandId = 'sale-cmd-${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now();
    // Business timestamp for the sale (allows backdating); record ids and
    // updatedAt stay at the real current time.
    final effectiveAt = saleDate ?? now;
    final createdAt = effectiveAt.toIso8601String();
    final date = createdAt.split('T').first;
    final baseDomainEpoch = await _readDomainEpoch('sales');
    final inventoryDeltas = <String, double>{};
    final totalBeforeDiscount = items.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );
    final total = totalBeforeDiscount - discount;
    final encodedItems = items
        .map((item) => item.toSaleJson())
        .toList(growable: false);
    final encodedPayments = payments
        .map((payment) => payment.toJson())
        .toList(growable: false);

    for (final item in items) {
      inventoryDeltas[item.id] =
          (inventoryDeltas[item.id] ?? 0) - item.quantity;
    }

    await _db.transaction(() async {
      await _db
          .into(_db.salesEntries)
          .insert(
            SalesEntriesCompanion.insert(
              id: saleId,
              total: total,
              discount: Value(discount),
              discountType: const Value('fixed'),
              paymentMode: Value(paymentMode),
              date: date,
              createdAt: effectiveAt.millisecondsSinceEpoch,
              updatedAt: Value(now.millisecondsSinceEpoch),
              customerName: Value(customerName),
              customerPhone: Value(customerPhone),
              customerId: Value(customerId),
              footerNote: Value(
                (buyerGstin != null && buyerGstin.trim().isNotEmpty)
                    ? '$footerNote\n\nBuyer GSTIN: $buyerGstin'.trim()
                    : footerNote,
              ),
              itemsJson: jsonEncode(encodedItems),
              paymentsJson: jsonEncode(encodedPayments),
              commandId: Value(commandId),
              syncStatus: const Value('queued'),
              backendSaleId: const Value(null),
            ),
          );

      await _db
          .into(_db.commerceOutboxEntries)
          .insert(
            CommerceOutboxEntriesCompanion.insert(
              commandId: commandId,
              shopId: shopId,
              commandType: 'sale_create',
              domain: 'sales',
              baseDomainEpoch: Value(baseDomainEpoch),
              payloadJson: jsonEncode(
                LocalSaleCommit(
                  commandId: commandId,
                  saleId: saleId,
                  shopId: shopId,
                  baseDomainEpoch: baseDomainEpoch,
                  date: date,
                  createdAt: createdAt,
                  total: total,
                  discount: discount,
                  discountType: 'fixed',
                  paymentMode: paymentMode,
                  items: encodedItems,
                  payments: encodedPayments,
                  customerId: customerId,
                  customerName: customerName,
                  customerPhone: customerPhone,
                  footerNote: footerNote,
                  buyerGstin: buyerGstin,
                  redeemPoints: redeemPoints,
                  inventoryDeltas: inventoryDeltas,
                ).toBackendCommandPayload(),
              ),
              createdAt: now.millisecondsSinceEpoch,
              updatedAt: Value(now.millisecondsSinceEpoch),
            ),
          );

      for (final item in items) {
        await (_db.update(
          _db.inventoryEntries,
        )..where((tbl) => tbl.id.equals(item.id))).write(
          InventoryEntriesCompanion(
            stock: Value(item.stock - item.quantity),
            updatedAt: Value(now.millisecondsSinceEpoch),
          ),
        );
        // Skip custom/weighed lines — they aren't inventory rows, so there is
        // no real stock to move.
        if (!item.id.startsWith('custom-') && !item.id.startsWith('weigh-')) {
          await _writeStockMovement(
            _db,
            itemId: item.id,
            itemName: item.name,
            delta: -item.quantity,
            reason: 'SALE',
            balanceAfter: item.stock - item.quantity,
            refId: saleId,
          );
        }
      }

      // Credit sale: push the unpaid balance onto the customer's khata so the
      // due shows up in the Clients list. Done inside the sale transaction so
      // the ledger stays consistent with the recorded sale.
      if (customerId != null && customerId.isNotEmpty) {
        final received = payments.fold<double>(
          0,
          (sum, payment) => sum + payment.amount,
        );
        final saleDue = total - received;
        if (saleDue > 0.009) {
          final customerRow = await (_db.select(
            _db.customerEntries,
          )..where((tbl) => tbl.id.equals(customerId))).getSingleOrNull();
          if (customerRow != null) {
            final newBalance = customerRow.balance + saleDue;
            await (_db.update(
              _db.customerEntries,
            )..where((tbl) => tbl.id.equals(customerId))).write(
              CustomerEntriesCompanion(
                balance: Value(newBalance),
                updatedAt: Value(now.millisecondsSinceEpoch),
              ),
            );
            await _writeCustomerLedger(
              _db,
              customerId: customerId,
              type: 'SALE_CREDIT',
              amount: saleDue,
              balanceAfter: newBalance,
              refId: saleId,
              note: 'Credit sale',
            );
          }
        }
      }
    });

    return LocalSaleCommit(
      commandId: commandId,
      saleId: saleId,
      shopId: shopId,
      baseDomainEpoch: baseDomainEpoch,
      date: date,
      createdAt: createdAt,
      total: total,
      discount: discount,
      discountType: 'fixed',
      paymentMode: paymentMode,
      items: encodedItems,
      payments: encodedPayments,
      customerName: customerName,
      customerPhone: customerPhone,
      customerId: customerId,
      footerNote: footerNote,
      inventoryDeltas: inventoryDeltas,
    );
  }

  /// Record a full return/refund of a past sale: a reversing (negative) sale
  /// for history + reporting, and — if [restock] — put the items back on the
  /// shelf (matched by SKU, else name). All in one transaction.
  /// Void/refund a sale. The server void (called by the caller) reverses the
  /// sale + stock + customer ledger there; here we mark the original sale
  /// REFUNDED locally (so it stays visible in History with a badge but drops
  /// out of revenue/counts), and put the items back in local stock.
  Future<void> recordReturn({
    required String shopId,
    required SaleRecordDetail original,
    required bool restock,
  }) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(
        _db.salesEntries,
      )..where((t) => t.id.equals(original.id))).write(
        SalesEntriesCompanion(
          syncStatus: const Value('refunded'),
          updatedAt: Value(now.millisecondsSinceEpoch),
        ),
      );

      if (restock) {
        for (final it in original.items) {
          final hasSku = it.sku != null && it.sku!.trim().isNotEmpty;
          final row =
              await (_db.select(_db.inventoryEntries)
                    ..where(
                      (t) => hasSku
                          ? t.sku.equals(it.sku!)
                          : t.name.equals(it.name),
                    )
                    ..limit(1))
                  .getSingleOrNull();
          if (row != null) {
            await (_db.update(
              _db.inventoryEntries,
            )..where((t) => t.id.equals(row.id))).write(
              InventoryEntriesCompanion(
                stock: Value(row.stock + it.quantity),
                updatedAt: Value(now.millisecondsSinceEpoch),
              ),
            );
            await _writeStockMovement(
              _db,
              itemId: row.id,
              itemName: row.name,
              delta: it.quantity,
              reason: 'RETURN',
              balanceAfter: row.stock + it.quantity,
              refId: 'return-${original.id}',
            );
          }
        }
      }
    });
  }

  /// Pending/failed outbox entries ready to send. The automatic loop honours
  /// exponential backoff and a max-attempt ceiling so one poison command can't
  /// hammer the backend forever; a manual retry passes [ignoreBackoff] to force
  /// every waiting entry (including exhausted ones) through immediately.
  Future<List<CommerceOutboxEntryModel>> getPendingOutboxEntries({
    bool ignoreBackoff = false,
  }) async {
    final rows =
        await (_db.select(_db.commerceOutboxEntries)
              ..where(
                (tbl) =>
                    (tbl.syncStatus.equals('pending') |
                        tbl.syncStatus.equals('failed')) &
                    tbl.isDeadLetter.equals(false),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)]))
            .get();

    final now = DateTime.now().millisecondsSinceEpoch;
    final ready = ignoreBackoff
        ? rows
        : rows
              .where((row) {
                if (row.attemptCount >= kOutboxMaxAttempts) return false;
                final lastAt = row.lastAttemptAt;
                if (lastAt == null) return true;
                return now - lastAt >= outboxBackoffMs(row.attemptCount);
              })
              .toList(growable: false);

    return ready
        .map(
          (row) => CommerceOutboxEntryModel(
            commandId: row.commandId,
            shopId: row.shopId,
            commandType: row.commandType,
            domain: row.domain,
            baseDomainEpoch: row.baseDomainEpoch,
            payloadJson: row.payloadJson,
            syncStatus: row.syncStatus,
            attemptCount: row.attemptCount,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            lastAttemptAt: row.lastAttemptAt,
            completedAt: row.completedAt,
            lastError: row.lastError,
          ),
        )
        .toList(growable: false);
  }

  /// Move a command to the dead-letter queue: the server permanently rejected
  /// it (4xx), so it stops retrying and surfaces for a human to resolve. The
  /// linked local sale is flagged so the UI can show it needs attention.
  Future<void> markOutboxDeadLetter(String commandId, String reason) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final trimmed = reason.length > 2000 ? reason.substring(0, 2000) : reason;
    await (_db.update(
      _db.commerceOutboxEntries,
    )..where((tbl) => tbl.commandId.equals(commandId))).write(
      CommerceOutboxEntriesCompanion(
        syncStatus: const Value('dead_letter'),
        isDeadLetter: const Value(true),
        deadLetterReason: Value(trimmed),
        lastError: Value('Moved to DLQ: $trimmed'),
        updatedAt: Value(now),
      ),
    );
    await (_db.update(
      _db.salesEntries,
    )..where((tbl) => tbl.commandId.equals(commandId))).write(
      SalesEntriesCompanion(
        syncStatus: const Value('rejected'),
        lastSyncError: Value(trimmed),
        updatedAt: Value(now),
      ),
    );
  }

  /// Live count of dead-lettered commands, for a "needs attention" badge.
  Stream<int> watchDeadLetterCount() {
    final query = _db.selectOnly(_db.commerceOutboxEntries)
      ..addColumns([_db.commerceOutboxEntries.commandId.count()])
      ..where(_db.commerceOutboxEntries.isDeadLetter.equals(true));
    return query
        .map(
          (row) => row.read(_db.commerceOutboxEntries.commandId.count()) ?? 0,
        )
        .watchSingle();
  }

  /// Live list of dead-lettered commands for the resolution screen.
  Stream<List<CommerceOutboxEntry>> watchDeadLetterEntries() {
    return (_db.select(_db.commerceOutboxEntries)
          ..where((tbl) => tbl.isDeadLetter.equals(true))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]))
        .watch();
  }

  /// Discard a dead-lettered command: drop the queue entry so it stops nagging.
  /// The local sale row stays (flagged 'rejected') for the owner's records.
  Future<void> discardDeadLetter(String commandId) async {
    await (_db.delete(
      _db.commerceOutboxEntries,
    )..where((tbl) => tbl.commandId.equals(commandId))).go();
  }

  /// "Force retry" a dead-lettered command (e.g. after the backend was fixed):
  /// clear the terminal flags and reset attempts so the next flush picks it up.
  Future<void> retryDeadLetter(String commandId) async {
    await (_db.update(
      _db.commerceOutboxEntries,
    )..where((tbl) => tbl.commandId.equals(commandId))).write(
      CommerceOutboxEntriesCompanion(
        syncStatus: const Value('pending'),
        isDeadLetter: const Value(false),
        deadLetterReason: const Value(null),
        attemptCount: const Value(0),
        lastAttemptAt: const Value(null),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> markOutboxSyncing(String commandId) async {
    await (_db.update(
      _db.commerceOutboxEntries,
    )..where((tbl) => tbl.commandId.equals(commandId))).write(
      CommerceOutboxEntriesCompanion(
        syncStatus: const Value('syncing'),
        attemptCount: const Value.absent(),
        lastAttemptAt: Value(DateTime.now().millisecondsSinceEpoch),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );

    await (_db.update(
      _db.salesEntries,
    )..where((tbl) => tbl.commandId.equals(commandId))).write(
      SalesEntriesCompanion(
        syncStatus: const Value('syncing'),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> registerOutboxAttempt(String commandId) async {
    final row = await (_db.select(
      _db.commerceOutboxEntries,
    )..where((tbl) => tbl.commandId.equals(commandId))).getSingleOrNull();
    final nextAttempts = (row?.attemptCount ?? 0) + 1;
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(
      _db.commerceOutboxEntries,
    )..where((tbl) => tbl.commandId.equals(commandId))).write(
      CommerceOutboxEntriesCompanion(
        attemptCount: Value(nextAttempts),
        lastAttemptAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> markCommandSynced({
    required String commandId,
    required String receiptId,
    String? backendSaleId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.update(
        _db.commerceOutboxEntries,
      )..where((tbl) => tbl.commandId.equals(commandId))).write(
        CommerceOutboxEntriesCompanion(
          syncStatus: const Value('synced'),
          lastError: const Value(null),
          completedAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      await (_db.update(
        _db.salesEntries,
      )..where((tbl) => tbl.commandId.equals(commandId))).write(
        SalesEntriesCompanion(
          syncStatus: const Value('synced_backend'),
          backendReceiptId: Value(receiptId),
          backendSaleId: Value(backendSaleId),
          lastSyncError: const Value(null),
          lastSyncedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<void> markCommandFailed({
    required String commandId,
    required String error,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.update(
        _db.commerceOutboxEntries,
      )..where((tbl) => tbl.commandId.equals(commandId))).write(
        CommerceOutboxEntriesCompanion(
          syncStatus: const Value('failed'),
          lastError: Value(error),
          updatedAt: Value(now),
        ),
      );

      await (_db.update(
        _db.salesEntries,
      )..where((tbl) => tbl.commandId.equals(commandId))).write(
        SalesEntriesCompanion(
          syncStatus: const Value('failed_backend'),
          lastSyncError: Value(error),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<void> markCommandQueued(String commandId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(
      _db.commerceOutboxEntries,
    )..where((tbl) => tbl.commandId.equals(commandId))).write(
      CommerceOutboxEntriesCompanion(
        syncStatus: const Value('pending'),
        updatedAt: Value(now),
      ),
    );

    await (_db.update(
      _db.salesEntries,
    )..where((tbl) => tbl.commandId.equals(commandId))).write(
      SalesEntriesCompanion(
        syncStatus: const Value('queued'),
        updatedAt: Value(now),
      ),
    );
  }

  Future<int> _readDomainEpoch(String domain) async {
    final row =
        await (_db.select(_db.shopSettingsEntries)
              ..where((tbl) => tbl.key.equals('domain_state_$domain')))
            .getSingleOrNull();
    if (row == null) {
      return 1;
    }

    try {
      final decoded = jsonDecode(row.value) as Map<String, dynamic>;
      final epoch = decoded['current_epoch'];
      if (epoch is int) return epoch;
      if (epoch is num) return epoch.toInt();
      if (epoch is String) return int.tryParse(epoch) ?? 1;
    } catch (_) {
      return 1;
    }
    return 1;
  }

  Future<String> _resolveSaleStorageId({
    required String backendSaleId,
    required String? commandId,
  }) async {
    if (commandId != null) {
      final existingByCommand = await (_db.select(
        _db.salesEntries,
      )..where((tbl) => tbl.commandId.equals(commandId))).getSingleOrNull();
      if (existingByCommand != null) {
        return existingByCommand.id;
      }
    }

    final existingByBackendId =
        await (_db.select(_db.salesEntries)
              ..where((tbl) => tbl.backendSaleId.equals(backendSaleId)))
            .getSingleOrNull();
    if (existingByBackendId != null) {
      return existingByBackendId.id;
    }

    return backendSaleId;
  }

  Future<void> clearWorkspace() async {
    await _db.transaction(() async {
      await _db.delete(_db.commerceOutboxEntries).go();
      await _db.delete(_db.salesEntries).go();
    });
  }
}

String? _historyExactDate(HistoryDateWindow window) {
  if (window != HistoryDateWindow.today) {
    return null;
  }
  return _historyDateOnly(DateTime.now());
}

String? _historySinceDate(HistoryDateWindow window) {
  final today = DateTime.now();
  return switch (window) {
    HistoryDateWindow.all => null,
    HistoryDateWindow.today => null,
    HistoryDateWindow.sevenDays => _historyDateOnly(
      today.subtract(const Duration(days: 6)),
    ),
    HistoryDateWindow.thirtyDays => _historyDateOnly(
      today.subtract(const Duration(days: 29)),
    ),
    HistoryDateWindow.ninetyDays => _historyDateOnly(
      today.subtract(const Duration(days: 89)),
    ),
  };
}

String _historyDateOnly(DateTime value) =>
    value.toIso8601String().split('T').first;

CommerceSyncState _parseSyncState(String raw) {
  switch (raw) {
    case 'queued':
      return CommerceSyncState.queued;
    case 'syncing':
      return CommerceSyncState.syncing;
    case 'synced_backend':
    case 'synced':
      return CommerceSyncState.synced;
    case 'failed_backend':
    case 'failed':
      return CommerceSyncState.failed;
    case 'refunded':
    case 'void':
      return CommerceSyncState.refunded;
    default:
      return CommerceSyncState.localOnly;
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

double? _asDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    final t = value.trim();
    return t.isEmpty ? null : double.tryParse(t);
  }
  return null;
}

bool _asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (const {'1', 'true', 'yes', 'y', 'on'}.contains(normalized)) {
      return true;
    }
    if (const {'0', 'false', 'no', 'n', 'off'}.contains(normalized)) {
      return false;
    }
  }
  return fallback;
}

/// Like [_asBool] but keeps "the payload did not say" as null instead of
/// folding it into false. Used where unknown and false mean different things —
/// stock history being the case that matters, since false there would claim an
/// item was never stocked.
bool? _asBoolOrNull(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (const {'1', 'true', 'yes', 'y', 'on'}.contains(normalized)) return true;
    if (const {'0', 'false', 'no', 'n', 'off'}.contains(normalized)) {
      return false;
    }
  }
  return null;
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }
  return null;
}

/// After this many automatic attempts a command stops auto-retrying and waits
/// in the "needs attention" list for a manual retry.
const int kOutboxMaxAttempts = 8;
const int _kOutboxBaseBackoffMs = 30000; // 30s
const int _kOutboxMaxBackoffMs = 3600000; // 1h ceiling

/// Exponential backoff between automatic retries: 30s, 60s, 120s, … capped 1h.
int outboxBackoffMs(int attemptCount) {
  if (attemptCount <= 0) return 0;
  final shift = (attemptCount - 1).clamp(0, 20);
  final ms = _kOutboxBaseBackoffMs * (1 << shift);
  return ms > _kOutboxMaxBackoffMs ? _kOutboxMaxBackoffMs : ms;
}

var _ledgerSeq = 0;

/// Append one entry to a customer's khata. Safe inside a transaction.
Future<void> _writeCustomerLedger(
  BusinessHubDatabase db, {
  required String customerId,
  required String type,
  required double amount,
  required double balanceAfter,
  String? refId,
  String note = '',
  String? actorName,
}) async {
  final seq = _ledgerSeq++;
  await db
      .into(db.customerLedgerEntries)
      .insert(
        CustomerLedgerEntriesCompanion.insert(
          id: 'led-${DateTime.now().microsecondsSinceEpoch}-$seq',
          customerId: customerId,
          type: type,
          amount: amount,
          balanceAfter: balanceAfter,
          refId: Value(refId),
          note: Value(note),
          actorName: Value(actorName),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

var _movementSeq = 0;

/// Append one row to the stock audit trail. Safe to call inside a transaction;
/// the id blends time, item and a process-lifetime counter so tight loops never
/// collide.
Future<void> _writeStockMovement(
  BusinessHubDatabase db, {
  required String itemId,
  required String itemName,
  required double delta,
  required String reason,
  double? balanceAfter,
  String? refId,
  String note = '',
  String? actorName,
}) async {
  final seq = _movementSeq++;
  await db
      .into(db.stockMovementEntries)
      .insert(
        StockMovementEntriesCompanion.insert(
          id: 'mv-${DateTime.now().microsecondsSinceEpoch}-$seq',
          itemId: itemId,
          itemName: itemName,
          delta: delta,
          reason: reason,
          balanceAfter: Value(balanceAfter),
          refId: Value(refId),
          note: Value(note),
          actorName: Value(actorName),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

int? _asEpoch(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsedDate = DateTime.tryParse(value);
    if (parsedDate != null) return parsedDate.millisecondsSinceEpoch;
    return int.tryParse(value);
  }
  return null;
}

String? _asStringOrNull(Object? value) {
  if (value == null) return null;
  final next = value.toString().trim();
  return next.isEmpty ? null : next;
}

String? _encodeNullableJson(Object? value) {
  if (value == null) return null;
  try {
    return jsonEncode(value);
  } catch (_) {
    return null;
  }
}

/// Build a short, human-friendly line-item summary for a receipt title, e.g.
/// "Rice" or "Rice + 2 more". Cheap: only reads item names, no full parse.
String? _summariseItems(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.isEmpty) {
      return null;
    }
    final names = decoded
        .whereType<Map>()
        .map((item) => (item['name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) {
      return null;
    }
    if (names.length == 1) {
      return names.first;
    }
    return '${names.first} + ${names.length - 1} more';
  } catch (_) {
    return null;
  }
}

List<SaleDetailItem> _parseSaleItems(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <SaleDetailItem>[];
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) => SaleDetailItem(
            name: (item['name'] ?? 'Unknown item').toString(),
            quantity: _asDouble(item['quantity']),
            unitPrice: _asDouble(item['price'] ?? item['unit_price']),
            size: _asStringOrNull(item['size']),
            sku: _asStringOrNull(item['sku']),
            unitCost: item['costPrice'] == null && item['unit_cost'] == null
                ? null
                : _asDouble(item['costPrice'] ?? item['unit_cost']),
            hsnCode: _asStringOrNull(
              item['hsnCode'] ?? item['hsn_code'] ?? item['hsn_snapshot'],
            ),
            gstRate: _asDouble(item['gstRate'] ?? item['gst_rate']),
            lineDiscount: _asDouble(
              item['discount'] ?? item['lineDiscount'] ?? item['line_discount'],
            ),
            taxableAmount: _asDouble(
              item['taxableAmount'] ?? item['taxable_amount'],
            ),
            taxAmount: _asDouble(item['taxAmount'] ?? item['tax_amount']),
            cgstAmount: _asDouble(item['cgstAmount'] ?? item['cgst_amount']),
            sgstAmount: _asDouble(item['sgstAmount'] ?? item['sgst_amount']),
            igstAmount: _asDouble(item['igstAmount'] ?? item['igst_amount']),
            priceIncludesTax: _asBool(
              item['priceIncludesTax'] ?? item['price_includes_tax'],
              fallback: true,
            ),
          ),
        )
        .toList(growable: false);
  } catch (_) {
    return const <SaleDetailItem>[];
  }
}

List<SaleDetailPayment> _parseSalePayments(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <SaleDetailPayment>[];
    }
    return decoded
        .whereType<Map>()
        .map(
          (payment) => SaleDetailPayment(
            mode: (payment['mode'] ?? payment['payment_method'] ?? 'CASH')
                .toString(),
            amount: _asDouble(payment['amount']),
            referenceCode: _asStringOrNull(payment['reference_code']),
            note: _asStringOrNull(payment['note']),
          ),
        )
        .toList(growable: false);
  } catch (_) {
    return const <SaleDetailPayment>[];
  }
}

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(ref.watch(localDatabaseProvider));
});

class ExpenseRepository {
  ExpenseRepository(this._db);

  final BusinessHubDatabase _db;

  Future<void> recordExpense({
    required String category,
    required double amount,
    required DateTime expenseDate,
    String description = '',
    String paymentMethod = 'CASH',
    String paymentReference = '',
    String? actorName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.expenseEntries)
        .insert(
          ExpenseEntriesCompanion.insert(
            id: 'expense-${DateTime.now().microsecondsSinceEpoch}',
            category: Value(
              category.trim().isEmpty ? 'General' : category.trim(),
            ),
            amount: Value(amount),
            description: Value(description.trim()),
            paymentMethod: Value(paymentMethod),
            paymentReference: Value(paymentReference.trim()),
            expenseDate: expenseDate.toIso8601String().split('T').first,
            actorName: Value(actorName),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
  }

  /// Insert-or-replace an expense with an explicit id — used to store the
  /// server's copy (its UUID) after a push, and to hydrate expenses pulled from
  /// the backend on login so they survive a data clear.
  Future<void> upsertExpense({
    required String id,
    required String category,
    required double amount,
    required DateTime expenseDate,
    String description = '',
    String paymentMethod = 'CASH',
    String paymentReference = '',
    String? actorName,
    bool tombstone = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.expenseEntries)
        .insertOnConflictUpdate(
          ExpenseEntriesCompanion.insert(
            id: id,
            category: Value(
              category.trim().isEmpty ? 'General' : category.trim(),
            ),
            amount: Value(amount),
            description: Value(description.trim()),
            paymentMethod: Value(paymentMethod),
            paymentReference: Value(paymentReference.trim()),
            expenseDate: expenseDate.toIso8601String().split('T').first,
            actorName: Value(actorName),
            createdAt: now,
            updatedAt: Value(now),
            tombstone: Value(tombstone),
          ),
        );
  }

  Stream<List<ExpenseRecord>> watchExpenses({
    String query = '',
    String category = '',
  }) {
    final where = <String>['tombstone = 0'];
    final vars = <Variable<Object>>[];
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      where.add('(LOWER(category) LIKE ? OR LOWER(description) LIKE ?)');
      vars
        ..add(Variable<String>('%$q%'))
        ..add(Variable<String>('%$q%'));
    }
    if (category.trim().isNotEmpty) {
      where.add('LOWER(category) = ?');
      vars.add(Variable<String>(category.trim().toLowerCase()));
    }
    final sql =
        'SELECT * FROM expenses WHERE ${where.join(' AND ')} '
        'ORDER BY expense_date DESC, created_at DESC;';
    return _db
        .customSelect(sql, variables: vars, readsFrom: {_db.expenseEntries})
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => ExpenseRecord(
                  id: row.readNullable<String>('id') ?? '',
                  category: row.readNullable<String>('category') ?? 'General',
                  amount: row.readNullable<double>('amount') ?? 0,
                  description: row.readNullable<String>('description') ?? '',
                  paymentMethod:
                      row.readNullable<String>('payment_method') ?? 'CASH',
                  paymentReference:
                      row.readNullable<String>('payment_reference') ?? '',
                  expenseDate:
                      DateTime.tryParse(
                        row.readNullable<String>('expense_date') ?? '',
                      ) ??
                      DateTime.now(),
                  actorName: _asStringOrNull(
                    row.readNullable<String>('actor_name'),
                  ),
                  tombstone: (row.readNullable<int>('tombstone') ?? 0) == 1,
                ),
              )
              .toList(growable: false),
        );
  }

  Future<ExpenseSummarySnapshot> summary() async {
    final rows = await (_db.select(
      _db.expenseEntries,
    )..where((t) => t.tombstone.equals(false))).get();
    final total = rows.fold<double>(0, (sum, r) => sum + r.amount);
    final byCategory = <String, double>{};
    for (final r in rows) {
      byCategory[r.category] = (byCategory[r.category] ?? 0) + r.amount;
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
      totalEntries: rows.length,
      totalAmount: total,
      uniqueCategories: byCategory.length,
      biggestCategory: biggest,
    );
  }
}

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  return PurchaseRepository(ref.watch(localDatabaseProvider));
});

/// Stock buying + supplier dues, local-first. Purchases are money-out with a
/// running payable; suppliers and their outstanding balances are derived by
/// grouping purchases, so there's no separate supplier entity to keep in sync.
class PurchaseRepository {
  PurchaseRepository(this._db);

  final BusinessHubDatabase _db;

  /// Records the purchase and returns its id (so the caller can link any
  /// auto stock-in movements back to this purchase).
  Future<String> recordPurchase({
    required String supplierName,
    required double total,
    required DateTime purchaseDate,
    double amountPaid = 0,
    String supplierPhone = '',
    String reference = '',
    String paymentMethod = 'CASH',
    String notes = '',
    String? actorName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'purchase-${DateTime.now().microsecondsSinceEpoch}';
    // A payment can never exceed the bill, and neither value can be negative.
    final safeTotal = total < 0 ? 0.0 : total;
    final safePaid = amountPaid < 0
        ? 0.0
        : (amountPaid > safeTotal ? safeTotal : amountPaid);
    await _db
        .into(_db.purchaseEntries)
        .insert(
          PurchaseEntriesCompanion.insert(
            id: id,
            supplierName: supplierName.trim().isEmpty
                ? 'Unnamed supplier'
                : supplierName.trim(),
            supplierPhone: Value(supplierPhone.trim()),
            reference: Value(reference.trim()),
            total: Value(safeTotal),
            amountPaid: Value(safePaid),
            paymentMethod: Value(paymentMethod),
            notes: Value(notes.trim()),
            purchaseDate: purchaseDate.toIso8601String().split('T').first,
            actorName: Value(actorName),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  /// Insert-or-replace a purchase with an explicit id — used to store the
  /// server's copy after a push, and to hydrate purchases pulled from the
  /// backend on login so they (and the suppliers rolled up from them) survive a
  /// data clear.
  Future<void> upsertPurchase({
    required String id,
    required String supplierName,
    required double total,
    required DateTime purchaseDate,
    double amountPaid = 0,
    String supplierPhone = '',
    String reference = '',
    String paymentMethod = 'CASH',
    String notes = '',
    String? actorName,
    bool tombstone = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final safeTotal = total < 0 ? 0.0 : total;
    final safePaid = amountPaid < 0
        ? 0.0
        : (amountPaid > safeTotal ? safeTotal : amountPaid);
    await _db
        .into(_db.purchaseEntries)
        .insertOnConflictUpdate(
          PurchaseEntriesCompanion.insert(
            id: id,
            supplierName: supplierName.trim().isEmpty
                ? 'Unnamed supplier'
                : supplierName.trim(),
            supplierPhone: Value(supplierPhone.trim()),
            reference: Value(reference.trim()),
            total: Value(safeTotal),
            amountPaid: Value(safePaid),
            paymentMethod: Value(paymentMethod),
            notes: Value(notes.trim()),
            purchaseDate: purchaseDate.toIso8601String().split('T').first,
            actorName: Value(actorName),
            createdAt: now,
            updatedAt: Value(now),
            tombstone: Value(tombstone),
          ),
        );
  }

  /// Add a payment against an existing purchase, capped at its outstanding
  /// balance. Returns the new outstanding balance.
  Future<double> settlePurchase({
    required String purchaseId,
    required double amount,
  }) async {
    final row = await (_db.select(
      _db.purchaseEntries,
    )..where((t) => t.id.equals(purchaseId))).getSingleOrNull();
    if (row == null) return 0;
    final due = row.total - row.amountPaid;
    final applied = amount < 0 ? 0.0 : (amount > due ? due : amount);
    final newPaid = row.amountPaid + applied;
    await (_db.update(
      _db.purchaseEntries,
    )..where((t) => t.id.equals(purchaseId))).write(
      PurchaseEntriesCompanion(
        amountPaid: Value(newPaid),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    final remaining = row.total - newPaid;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> deletePurchase(String id) async {
    await (_db.update(
      _db.purchaseEntries,
    )..where((t) => t.id.equals(id))).write(
      PurchaseEntriesCompanion(
        tombstone: const Value(true),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Stream<List<PurchaseRecord>> watchPurchases({String query = ''}) {
    final where = <String>['tombstone = 0'];
    final vars = <Variable<Object>>[];
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      where.add(
        '(LOWER(supplier_name) LIKE ? OR LOWER(reference) LIKE ? '
        'OR LOWER(notes) LIKE ?)',
      );
      vars
        ..add(Variable<String>('%$q%'))
        ..add(Variable<String>('%$q%'))
        ..add(Variable<String>('%$q%'));
    }
    final sql =
        'SELECT * FROM purchases WHERE ${where.join(' AND ')} '
        'ORDER BY purchase_date DESC, created_at DESC;';
    return _db
        .customSelect(sql, variables: vars, readsFrom: {_db.purchaseEntries})
        .watch()
        .map((rows) => rows.map(_mapPurchaseRow).toList(growable: false));
  }

  /// Suppliers rolled up from their purchases, ordered by who you owe most.
  Stream<List<SupplierDue>> watchSuppliers() {
    const sql = '''
      SELECT
        supplier_name AS name,
        MAX(supplier_phone) AS phone,
        COUNT(*) AS purchase_count,
        COALESCE(SUM(total), 0) AS total_purchased,
        COALESCE(SUM(total - amount_paid), 0) AS payable
      FROM purchases
      WHERE tombstone = 0
      GROUP BY LOWER(supplier_name)
      ORDER BY payable DESC, total_purchased DESC;
    ''';
    return _db
        .customSelect(sql, readsFrom: {_db.purchaseEntries})
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => SupplierDue(
                  name: row.readNullable<String>('name') ?? '',
                  phone:
                      _asStringOrNull(row.readNullable<String>('phone')) ?? '',
                  purchaseCount: row.readNullable<int>('purchase_count') ?? 0,
                  totalPurchased:
                      row.readNullable<double>('total_purchased') ?? 0,
                  payable: row.readNullable<double>('payable') ?? 0,
                ),
              )
              .toList(growable: false),
        );
  }

  Stream<PurchaseSummarySnapshot> watchSummary() {
    const sql = '''
      SELECT
        COUNT(*) AS total_purchases,
        COALESCE(SUM(total), 0) AS total_spent,
        COALESCE(SUM(total - amount_paid), 0) AS total_payable,
        COUNT(DISTINCT LOWER(supplier_name)) AS supplier_count
      FROM purchases
      WHERE tombstone = 0;
    ''';
    return _db
        .customSelect(sql, readsFrom: {_db.purchaseEntries})
        .watchSingle()
        .map(
          (row) => PurchaseSummarySnapshot(
            totalPurchases: row.readNullable<int>('total_purchases') ?? 0,
            totalSpent: row.readNullable<double>('total_spent') ?? 0,
            totalPayable: row.readNullable<double>('total_payable') ?? 0,
            supplierCount: row.readNullable<int>('supplier_count') ?? 0,
          ),
        );
  }

  PurchaseRecord _mapPurchaseRow(QueryRow row) {
    return PurchaseRecord(
      id: row.readNullable<String>('id') ?? '',
      supplierName:
          row.readNullable<String>('supplier_name') ?? 'Unnamed supplier',
      supplierPhone: row.readNullable<String>('supplier_phone') ?? '',
      reference: row.readNullable<String>('reference') ?? '',
      total: row.readNullable<double>('total') ?? 0,
      amountPaid: row.readNullable<double>('amount_paid') ?? 0,
      paymentMethod: row.readNullable<String>('payment_method') ?? 'CASH',
      notes: row.readNullable<String>('notes') ?? '',
      purchaseDate:
          DateTime.tryParse(row.readNullable<String>('purchase_date') ?? '') ??
          DateTime.now(),
      actorName: _asStringOrNull(row.readNullable<String>('actor_name')),
      tombstone: (row.readNullable<int>('tombstone') ?? 0) == 1,
    );
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(localDatabaseProvider));
});

/// Read side for financial reporting. Parses stored sale rows into the shape
/// [computeProfitAndLoss] expects; expenses for the same window come through a
/// sibling stream so the pure P&L math stays in one place.
class ReportsRepository {
  ReportsRepository(this._db);

  final BusinessHubDatabase _db;

  /// Best sellers over the last [days], by quantity moved.
  ///
  /// Reads the stock-movement log rather than parsing every bill's item JSON:
  /// with tens of thousands of sales, JSON parsing would make this unusable.
  Future<List<BestSellerItem>> bestSellers({
    int days = 30,
    int limit = 20,
  }) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    final rows = await _db
        .customSelect(
          """
        SELECT m.item_name AS name,
               SUM(-m.delta) AS qty,
               SUM(-m.delta * COALESCE(i.price, 0)) AS revenue,
               SUM(-m.delta * (COALESCE(i.price, 0) - COALESCE(p.cost_price, 0)))
                 AS profit,
               MAX(CASE WHEN p.cost_price IS NULL THEN 1 ELSE 0 END) AS cost_missing
        FROM stock_movements m
        LEFT JOIN inventory i ON i.id = m.item_id
        LEFT JOIN inventory_private p ON p.id = m.item_id
        WHERE m.reason = 'SALE' AND m.created_at >= ? AND m.delta < 0
        GROUP BY LOWER(m.item_name)
        ORDER BY qty DESC
        LIMIT ?;
      """,
          variables: [Variable<int>(cutoff), Variable<int>(limit)],
          readsFrom: {
            _db.stockMovementEntries,
            _db.inventoryEntries,
            _db.inventoryPrivateEntries,
          },
        )
        .get();

    return rows
        .map(
          (row) => BestSellerItem(
            name: row.readNullable<String>('name') ?? 'Unknown item',
            quantitySold: row.readNullable<double>('qty') ?? 0,
            revenue: row.readNullable<double>('revenue') ?? 0,
            // Don't report a profit we can't stand behind.
            profit: (row.readNullable<int>('cost_missing') ?? 1) == 1
                ? null
                : row.readNullable<double>('profit'),
          ),
        )
        .toList(growable: false);
  }

  /// Money in vs money out over the last [days].
  Future<CashFlowSnapshot> cashFlow({int days = 30}) async {
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .split('T')
        .first;

    final row = await _db
        .customSelect(
          """
        SELECT
          (SELECT COALESCE(SUM(total), 0) FROM sales
            WHERE tombstone = 0
              AND sync_status NOT IN ('refunded', 'void')
              AND date >= ?) AS sales_total,
          (SELECT COALESCE(SUM(amount_paid), 0) FROM purchases
            WHERE tombstone = 0 AND purchase_date >= ?) AS purchases_paid,
          (SELECT COALESCE(SUM(amount), 0) FROM expenses
            WHERE tombstone = 0 AND expense_date >= ?) AS expenses_total;
      """,
          variables: [
            Variable<String>(since),
            Variable<String>(since),
            Variable<String>(since),
          ],
          readsFrom: {
            _db.salesEntries,
            _db.purchaseEntries,
            _db.expenseEntries,
          },
        )
        .getSingle();

    return CashFlowSnapshot(
      salesCollected: row.readNullable<double>('sales_total') ?? 0,
      purchases: row.readNullable<double>('purchases_paid') ?? 0,
      expenses: row.readNullable<double>('expenses_total') ?? 0,
    );
  }

  Stream<List<ReportSale>> watchReportSales(HistoryDateWindow window) {
    final exactDate = _historyExactDate(window);
    final sinceDate = _historySinceDate(window);
    final where = <String>['tombstone = 0'];
    final vars = <Variable<Object>>[];
    if (exactDate != null) {
      where.add('date = ?');
      vars.add(Variable<String>(exactDate));
    } else if (sinceDate != null) {
      where.add('date >= ?');
      vars.add(Variable<String>(sinceDate));
    }
    return _db
        .customSelect(
          'SELECT total, customer_name, items_json FROM sales '
          'WHERE ${where.join(' AND ')};',
          variables: vars,
          readsFrom: {_db.salesEntries},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => ReportSale(
                  total: row.readNullable<double>('total') ?? 0,
                  customerName: _asStringOrNull(
                    row.readNullable<String>('customer_name'),
                  ),
                  lines: _parseReportLines(
                    row.readNullable<String>('items_json') ?? '',
                  ),
                ),
              )
              .toList(growable: false),
        );
  }

  /// Aggregate a single day's takings into a Z-report: gross, discounts, tax,
  /// tender split (from actual payment lines), and first/last bill times.
  Stream<ZReportSnapshot> watchZReport(HistoryDateWindow window) {
    final exactDate = _historyExactDate(window);
    final sinceDate = _historySinceDate(window);
    final where = <String>['tombstone = 0'];
    final vars = <Variable<Object>>[];
    if (exactDate != null) {
      where.add('date = ?');
      vars.add(Variable<String>(exactDate));
    } else if (sinceDate != null) {
      where.add('date >= ?');
      vars.add(Variable<String>(sinceDate));
    }
    return _db
        .customSelect(
          'SELECT total, discount, items_json, payments_json, created_at '
          'FROM sales WHERE ${where.join(' AND ')};',
          variables: vars,
          readsFrom: {_db.salesEntries},
        )
        .watch()
        .map((rows) {
          var gross = 0.0;
          var discount = 0.0;
          var tax = 0.0;
          var collected = 0.0;
          final tender = <String, double>{};
          DateTime? firstAt;
          DateTime? lastAt;
          for (final row in rows) {
            gross += row.readNullable<double>('total') ?? 0;
            discount += row.readNullable<double>('discount') ?? 0;
            for (final line in _parseReportLines(
              row.readNullable<String>('items_json') ?? '',
            )) {
              final lineTotal = line.price * line.quantity;
              if (line.gstRate > 0) {
                tax += line.priceIncludesTax
                    ? lineTotal * line.gstRate / (100 + line.gstRate)
                    : lineTotal * line.gstRate / 100;
              }
            }
            for (final p in _parseZPayments(
              row.readNullable<String>('payments_json') ?? '',
            )) {
              final mode = p.key.isEmpty ? 'OTHER' : p.key;
              tender[mode] = (tender[mode] ?? 0) + p.value;
              collected += p.value;
            }
            final createdAt = DateTime.fromMillisecondsSinceEpoch(
              row.readNullable<int>('created_at') ?? 0,
            );
            if (firstAt == null || createdAt.isBefore(firstAt)) {
              firstAt = createdAt;
            }
            if (lastAt == null || createdAt.isAfter(lastAt)) lastAt = createdAt;
          }
          return ZReportSnapshot(
            salesCount: rows.length,
            grossSales: gross,
            discountTotal: discount,
            taxCollected: tax,
            collected: collected,
            due: (gross - collected) > 0 ? gross - collected : 0,
            tenderBreakdown: tender,
            firstBillAt: firstAt,
            lastBillAt: lastAt,
          );
        });
  }

  List<MapEntry<String, double>> _parseZPayments(String paymentsJson) {
    if (paymentsJson.trim().isEmpty) return const <MapEntry<String, double>>[];
    try {
      final decoded = jsonDecode(paymentsJson);
      if (decoded is! List) return const <MapEntry<String, double>>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((p) {
            final mode = (p['mode'] ?? p['type'] ?? 'OTHER')
                .toString()
                .toUpperCase();
            return MapEntry(mode, _asDouble(p['amount']));
          })
          .toList(growable: false);
    } catch (_) {
      return const <MapEntry<String, double>>[];
    }
  }

  Stream<double> watchPeriodExpenses(HistoryDateWindow window) {
    final exactDate = _historyExactDate(window);
    final sinceDate = _historySinceDate(window);
    final where = <String>['tombstone = 0'];
    final vars = <Variable<Object>>[];
    if (exactDate != null) {
      where.add('expense_date = ?');
      vars.add(Variable<String>(exactDate));
    } else if (sinceDate != null) {
      where.add('expense_date >= ?');
      vars.add(Variable<String>(sinceDate));
    }
    return _db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0) AS total FROM expenses '
          'WHERE ${where.join(' AND ')};',
          variables: vars,
          readsFrom: {_db.expenseEntries},
        )
        .watchSingle()
        .map((row) => row.readNullable<double>('total') ?? 0);
  }

  List<ReportSaleLine> _parseReportLines(String itemsJson) {
    if (itemsJson.trim().isEmpty) return const <ReportSaleLine>[];
    try {
      final decoded = jsonDecode(itemsJson);
      if (decoded is! List) return const <ReportSaleLine>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) {
            return ReportSaleLine(
              name: (item['name'] ?? 'Item').toString(),
              quantity: _asDouble(item['quantity']),
              price: _asDouble(item['price'] ?? item['unitPrice']),
              costPrice: _asDoubleOrNull(
                item['costPrice'] ?? item['unit_cost'],
              ),
              gstRate: _asDouble(item['gstRate'] ?? item['gst_rate']),
              priceIncludesTax: _asBool(
                item['priceIncludesTax'] ?? item['price_includes_tax'],
                fallback: true,
              ),
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const <ReportSaleLine>[];
    }
  }
}

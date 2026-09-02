import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/backend_api_client.dart';
import '../database/mobile_repository.dart';
import '../images/product_image_store.dart';
import '../models/mobile_models.dart';
import '../models/mobile_session.dart';
import '../runtime/app_runtime_info.dart';
import 'outbox_error.dart';
import '../runtime/mobile_runtime_config.dart';
import '../session/mobile_session_controller.dart';

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, MobileSyncStatus>(
      SyncStatusNotifier.new,
    );

class SyncStatusNotifier extends Notifier<MobileSyncStatus> {
  @override
  MobileSyncStatus build() => MobileSyncStatus.idle;

  void setStatus(MobileSyncStatus next) {
    if (state == next) {
      return;
    }
    state = next;
  }
}

final mobileSyncCoordinatorProvider = Provider<MobileSyncCoordinator>((ref) {
  final coordinator = MobileSyncCoordinator(
    backendApiClient: ref.read(backendApiClientProvider),
    shopRepository: ref.read(shopRepositoryProvider),
    inventoryRepository: ref.read(inventoryRepositoryProvider),
    customerRepository: ref.read(customerRepositoryProvider),
    salesRepository: ref.read(salesRepositoryProvider),
    expenseRepository: ref.read(expenseRepositoryProvider),
    purchaseRepository: ref.read(purchaseRepositoryProvider),
    setStatus: ref.read(syncStatusProvider.notifier).setStatus,
  );

  ref.listen<AsyncValue<MobileSession?>>(
    mobileSessionProvider,
    (_, next) => coordinator.handleSession(next.asData?.value),
    fireImmediately: true,
  );

  ref.onDispose(coordinator.dispose);
  return coordinator;
});

enum MobileSyncStatus { idle, syncing, offline, error }

class MobileSyncCoordinator {
  MobileSyncCoordinator({
    required BackendApiClient backendApiClient,
    required ShopRepository shopRepository,
    required InventoryRepository inventoryRepository,
    required CustomerRepository customerRepository,
    required SalesRepository salesRepository,
    required ExpenseRepository expenseRepository,
    required PurchaseRepository purchaseRepository,
    required this.setStatus,
  }) : _backendApiClient = backendApiClient,
       _shopRepository = shopRepository,
       _inventoryRepository = inventoryRepository,
       _customerRepository = customerRepository,
       _salesRepository = salesRepository,
       _expenseRepository = expenseRepository,
       _purchaseRepository = purchaseRepository;

  final BackendApiClient _backendApiClient;
  final ShopRepository _shopRepository;
  final InventoryRepository _inventoryRepository;
  final CustomerRepository _customerRepository;
  final SalesRepository _salesRepository;
  final ExpenseRepository _expenseRepository;
  final PurchaseRepository _purchaseRepository;
  final void Function(MobileSyncStatus status) setStatus;

  MobileSession? _session;

  /// Set when the server rejected our token (401). Sync stays paused — and no
  /// local data is touched — until the user signs in again.
  bool _needsReauth = false;
  bool _salesReadsUseBackend = false;
  bool _isFlushingOutbox = false;
  Timer? _outboxRetryTimer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<AppRuntimeInfo>? _runtimeInfoFuture;

  Future<void> handleSession(
    MobileSession? session, {
    bool force = false,
  }) async {
    final previousShopId = _session?.shopId;
    if (!force &&
        session?.shopId == _session?.shopId &&
        session?.role == _session?.role) {
      return;
    }

    await _cancelSubscriptions();

    final isSwitchingWorkspace =
        previousShopId != null &&
        session != null &&
        previousShopId != session.shopId;

    // Only a real workspace switch clears the cache. A null session is NOT a
    // reliable sign-out signal: the session provider emits AsyncLoading (and so
    // a null value) on every login / staff-PIN / shop-switch transition, and
    // wiping there destroyed the local shop — including unsynced outbox work —
    // on a transient state change. Cross-tenant isolation is already enforced
    // by _wipeIfShopChanged() in the session controller, which wipes whenever
    // the device attaches to a different shop.
    if (isSwitchingWorkspace) {
      await _clearWorkspaceCache(clearSales: true);
    }

    _session = session;

    if (session == null || !session.hasShop) {
      _salesReadsUseBackend = false;
      setStatus(MobileSyncStatus.idle);
      return;
    }
    // A fresh signed-in session clears any earlier "token rejected" pause.
    _needsReauth = false;

    setStatus(MobileSyncStatus.syncing);
    final shopId = session.shopId!;
    await _ensureLocalWorkspace(session, shopId);
    if (!MobileRuntimeConfig.backendSyncEnabled) {
      _salesReadsUseBackend = false;
      setStatus(MobileSyncStatus.idle);
      return;
    }

    final hasAccess = await _syncWorkspaceAccessSession(session);
    if (!hasAccess) {
      return;
    }
    final domainStates = await _refreshBackendDomainEpochs(session, shopId);
    final salesState = domainStates['sales'];
    // Default to Postgres-primary when the probe was inconclusive (a slow /
    // free-tier backend can drop a domain-state request). Native self-serve
    // shops are always Postgres-primary, so assuming so is safe and avoids
    // disabling backend reads on a transient hiccup.
    _salesReadsUseBackend = salesState?.isPostgresPrimary ?? true;

    // Always hydrate local from the backend snapshot on login/refresh. Merges
    // are upserts, so a pull can never lose local data — but it guarantees the
    // shop is populated even if the domain-state probe flaked, which is what
    // was intermittently leaving a freshly-signed-in shop empty.
    await _syncBackendInventorySnapshot(session, shopId);
    await _syncBackendSalesSnapshot(session, shopId);
    // Customers were previously only pulled by a manual sync, so a fresh
    // login (which clears the cache) showed zero customers until the user hit
    // refresh. Pull them on login too.
    await _syncBackendCustomersSnapshot(session, shopId);
    // Expenses and purchases (and the suppliers rolled up from purchases) were
    // local-only, so they vanished on every clear+login. Pull them too.
    await _syncBackendExpensesSnapshot(session, shopId);
    await _syncBackendPurchasesSnapshot(session, shopId);

    setStatus(MobileSyncStatus.idle);
    _startOutboxRetryLoop();
    await flushCommerceOutbox(checkAccess: false);
  }

  Future<void> refresh() => handleSession(_session, force: true);

  Future<void> updateWorkspaceSettings({
    required ShopInfo currentShop,
    required String tagline,
    required String footer,
    required String phone,
  }) async {
    final session = _session;
    if (session == null || !session.hasShop) {
      throw StateError(
        'No active workspace is attached to this mobile session.',
      );
    }
    if (!session.isOwnerLike) {
      throw StateError(
        'Only workspace owners and admins can change mobile workspace settings.',
      );
    }

    setStatus(MobileSyncStatus.syncing);
    final payload = <String, dynamic>{
      'name': currentShop.name,
      'tagline': tagline,
      'footer': footer,
      'phone': phone,
      'currency': currentShop.currency,
      'plan_tier': currentShop.planTier,
      'enabled_features': currentShop.enabledFeatures,
      'settings': <String, dynamic>{
        'name': currentShop.name,
        'tagline': tagline,
        'footer': footer,
        'phone': phone,
        'currency': currentShop.currency,
        'plan_tier': currentShop.planTier,
        'enabled_features': currentShop.enabledFeatures,
      },
    };

    try {
      await _shopRepository.saveShopDocument(payload);
      setStatus(MobileSyncStatus.idle);
    } catch (error) {
      debugPrint('Workspace settings update failed: $error');
      setStatus(MobileSyncStatus.error);
      rethrow;
    }
  }

  Future<void> createInventoryItem({
    required String name,
    required double sellPrice,
    required double openingStock,
    String sku = '',
    String barcode = '',
    String category = 'General',
    String subcategory = '',
    String size = '',
    String description = '',
    double? costPrice,
    String hsnCode = '',
    double gstRate = 0,
    bool priceIncludesTax = true,
    String? imagePath,
    String? unit,
    int? reorderLevel,
    String? variantGroupId,
    String? variantLabel,
  }) async {
    final session = _session;
    if (session == null || !session.hasShop) {
      throw StateError('Sign in to a workspace before adding inventory.');
    }
    if (session.isReadOnly) {
      throw StateError('Viewer access cannot add inventory items.');
    }

    setStatus(MobileSyncStatus.syncing);
    final now = DateTime.now();
    final updatedAt = now.millisecondsSinceEpoch;
    final normalizedCategory = category.trim().isEmpty
        ? 'General'
        : category.trim();

    if (!MobileRuntimeConfig.backendSyncEnabled) {
      await _createInventoryItemLocally(
        session: session,
        name: name.trim(),
        sellPrice: sellPrice,
        openingStock: openingStock,
        sku: sku.trim(),
        barcode: barcode.trim(),
        category: normalizedCategory,
        subcategory: subcategory.trim(),
        size: size.trim(),
        description: description.trim(),
        costPrice: session.canViewCost ? costPrice : null,
        hsnCode: hsnCode.trim(),
        gstRate: gstRate,
        priceIncludesTax: priceIncludesTax,
        imagePath: imagePath,
        unit: unit,
        reorderLevel: reorderLevel,
        variantGroupId: variantGroupId,
        variantLabel: variantLabel,
        timestamp: now,
      );
      setStatus(MobileSyncStatus.idle);
      return;
    }

    try {
      final created = await _backendApiClient.createInventoryItem(
        user: session.user,
        shopId: session.shopId!,
        imageData: await ProductImageStore.encodeForUpload(imagePath),
        name: name.trim(),
        sellPrice: sellPrice,
        openingStock: openingStock,
        sku: sku.trim(),
        barcode: barcode.trim(),
        category: normalizedCategory,
        subcategory: subcategory.trim(),
        size: size.trim(),
        description: description.trim(),
        costPrice: session.canViewCost ? costPrice : null,
        hsnCode: hsnCode.trim(),
        gstRate: gstRate,
        priceIncludesTax: priceIncludesTax,
        unit: unit,
        reorderLevel: reorderLevel,
      );
      await _inventoryRepository.mergeBackendInventoryItem(
        created,
        updatedAt: updatedAt,
      );
      // Unit and reorder level now round-trip through the API, but the local
      // image path is still device-only, so re-merge it onto the synced row.
      final createdId = created['id']?.toString();
      final localOnly = <String, dynamic>{};
      if (imagePath != null) localOnly['imagePath'] = imagePath;
      if (localOnly.isNotEmpty && createdId != null && createdId.isNotEmpty) {
        await _inventoryRepository.mergeInventoryDocument(
          createdId,
          localOnly,
          updatedAt: updatedAt,
        );
      }
      setStatus(MobileSyncStatus.idle);
    } on BackendApiException catch (error) {
      final canUseLocalFallback =
          error.statusCode == null || error.statusCode == 409;
      if (!canUseLocalFallback) {
        setStatus(MobileSyncStatus.error);
        rethrow;
      }
      await _createInventoryItemLocally(
        session: session,
        name: name.trim(),
        sellPrice: sellPrice,
        openingStock: openingStock,
        sku: sku.trim(),
        barcode: barcode.trim(),
        category: normalizedCategory,
        subcategory: subcategory.trim(),
        size: size.trim(),
        description: description.trim(),
        costPrice: session.canViewCost ? costPrice : null,
        hsnCode: hsnCode.trim(),
        gstRate: gstRate,
        priceIncludesTax: priceIncludesTax,
        imagePath: imagePath,
        unit: unit,
        reorderLevel: reorderLevel,
        variantGroupId: variantGroupId,
        variantLabel: variantLabel,
        timestamp: now,
      );
      setStatus(MobileSyncStatus.idle);
    } on IOException catch (error) {
      debugPrint('Inventory backend unavailable, using local fallback: $error');
      await _createInventoryItemLocally(
        session: session,
        name: name.trim(),
        sellPrice: sellPrice,
        openingStock: openingStock,
        sku: sku.trim(),
        barcode: barcode.trim(),
        category: normalizedCategory,
        subcategory: subcategory.trim(),
        size: size.trim(),
        description: description.trim(),
        costPrice: session.canViewCost ? costPrice : null,
        hsnCode: hsnCode.trim(),
        gstRate: gstRate,
        priceIncludesTax: priceIncludesTax,
        imagePath: imagePath,
        unit: unit,
        reorderLevel: reorderLevel,
        variantGroupId: variantGroupId,
        variantLabel: variantLabel,
        timestamp: now,
      );
      setStatus(MobileSyncStatus.idle);
    } catch (_) {
      setStatus(MobileSyncStatus.error);
      rethrow;
    }
  }

  /// Create a product with multiple size/colour variants. Each variant becomes
  /// its own inventory row (own price / stock / SKU / cost) sharing one
  /// [variantGroupId], so stock, sales and reporting work per variant while the
  /// POS can group them behind a single tile. Local-first, like single items.
  Future<void> createVariantGroup({
    required String baseName,
    required List<VariantDraft> variants,
    String category = 'General',
    String hsnCode = '',
    double gstRate = 0,
    bool priceIncludesTax = true,
    String? unit,
    String? imagePath,
  }) async {
    final session = _session;
    if (session == null || !session.hasShop) {
      throw StateError('Sign in to a workspace before adding inventory.');
    }
    if (session.isReadOnly) {
      throw StateError('Viewer access cannot add inventory items.');
    }
    final drafts = variants
        .where((v) => v.label.trim().isNotEmpty)
        .toList(growable: false);
    if (drafts.isEmpty) {
      throw StateError('Add at least one variant with a label.');
    }

    setStatus(MobileSyncStatus.syncing);
    final normalizedCategory = category.trim().isEmpty
        ? 'General'
        : category.trim();
    final groupId = 'vg-${DateTime.now().microsecondsSinceEpoch}';
    // A single base time; per-variant microsecond offsets keep row ids unique.
    final base = DateTime.now();
    try {
      for (var i = 0; i < drafts.length; i++) {
        final v = drafts[i];
        await _createInventoryItemLocally(
          session: session,
          name: '${baseName.trim()} (${v.label.trim()})',
          sellPrice: v.sellPrice,
          openingStock: v.openingStock,
          sku: v.sku.trim(),
          barcode: '',
          category: normalizedCategory,
          subcategory: '',
          size: v.label.trim(),
          description: '',
          costPrice: session.canViewCost ? v.costPrice : null,
          hsnCode: hsnCode.trim(),
          gstRate: gstRate,
          priceIncludesTax: priceIncludesTax,
          timestamp: base.add(Duration(microseconds: i)),
          imagePath: imagePath,
          unit: unit,
          reorderLevel: v.reorderLevel,
          variantGroupId: groupId,
          variantLabel: v.label.trim(),
        );
      }
      setStatus(MobileSyncStatus.idle);
    } catch (_) {
      setStatus(MobileSyncStatus.error);
      rethrow;
    }
  }

  /// Update an existing inventory item locally (edit + restock).
  ///
  /// The local merge is a full upsert, so callers must pass the complete set
  /// of fields (using the item's current values for anything unchanged) or the
  /// missing fields reset to defaults.
  Future<void> updateInventoryItem({
    required String itemId,
    required String name,
    required double sellPrice,
    required double stock,
    String sku = '',
    String barcode = '',
    String category = 'General',
    String subcategory = '',
    String size = '',
    String description = '',
    double? costPrice,
    String hsnCode = '',
    double gstRate = 0,
    bool priceIncludesTax = true,
    DateTime? createdAt,
    String? imagePath,
    String? unit,
    int? reorderLevel,
  }) async {
    final session = _session;
    if (session == null || !session.hasShop) {
      throw StateError('Sign in to a workspace before editing inventory.');
    }
    if (session.isReadOnly) {
      throw StateError('Viewer access cannot edit inventory items.');
    }

    setStatus(MobileSyncStatus.syncing);
    final now = DateTime.now();
    final iso = now.toIso8601String();
    // Push the edit to the server (was local-only). Only for items that carry
    // a real server id; local-only items sync via their create instead.
    if (MobileRuntimeConfig.backendSyncEnabled &&
        _uuidPattern.hasMatch(itemId)) {
      try {
        await _backendApiClient.updateInventoryItem(
          user: session.user,
          shopId: session.shopId!,
          itemId: itemId,
          imageData: await ProductImageStore.encodeForUpload(imagePath),
          name: name.trim(),
          sellPrice: sellPrice,
          category: category,
          sku: sku,
          hsnCode: hsnCode,
          gstRate: gstRate,
          priceIncludesTax: priceIncludesTax,
          costPrice: session.canViewCost ? costPrice : null,
          description: description,
          unit: unit,
          reorderLevel: reorderLevel,
        );
      } catch (error) {
        debugPrint('Backend inventory update failed: $error');
      }
    }
    final normalizedCategory = category.trim().isEmpty
        ? 'General'
        : category.trim();
    final payload = <String, dynamic>{
      'name': name.trim(),
      'price': sellPrice,
      'sell_price': sellPrice,
      'sku': sku.trim(),
      'barcode': barcode.trim(),
      'category': normalizedCategory,
      'subcategory': subcategory.trim(),
      'size': size.trim(),
      'description': description.trim(),
      'hsnCode': hsnCode.trim(),
      'gstRate': gstRate,
      'priceIncludesTax': priceIncludesTax,
      'stock': stock,
      'status': 'active',
      'tombstone': false,
      // Always present on edit so the form fully owns these (set / replace
      // / clear); null clears them.
      'imagePath': imagePath,
      'unit': unit,
      'reorderLevel': reorderLevel,
      'createdAt': (createdAt ?? now).toIso8601String(),
      'updatedAt': iso,
    };
    await _inventoryRepository.mergeInventoryDocument(
      itemId,
      payload,
      updatedAt: now.millisecondsSinceEpoch,
    );
    if (costPrice != null && session.canViewCost) {
      await _inventoryRepository.mergeInventoryPrivateDocument(
        itemId,
        <String, dynamic>{
          'costPrice': costPrice,
          'updatedAt': iso,
          'tombstone': false,
        },
        updatedAt: now.millisecondsSinceEpoch,
      );
    }
    setStatus(MobileSyncStatus.idle);
  }

  /// Archive (soft-delete) an inventory item locally. Tombstoned items are
  /// filtered out of every catalog query.
  Future<void> deleteInventoryItem({
    required String itemId,
    required String name,
  }) async {
    final session = _session;
    if (session == null || !session.hasShop) {
      throw StateError('Sign in to a workspace before removing inventory.');
    }
    if (session.isReadOnly) {
      throw StateError('Viewer access cannot remove inventory items.');
    }
    setStatus(MobileSyncStatus.syncing);
    final now = DateTime.now();
    // Push the delete to the server (was previously local-only, so deleted
    // items reappeared after a fresh login). A non-UUID id is a local-only
    // item that never synced, so there's nothing to delete on the server.
    if (MobileRuntimeConfig.backendSyncEnabled &&
        _uuidPattern.hasMatch(itemId)) {
      try {
        await _backendApiClient.deleteInventoryItem(
          user: session.user,
          shopId: session.shopId!,
          itemId: itemId,
        );
      } catch (error) {
        debugPrint('Backend inventory delete failed: $error');
      }
    }
    await _inventoryRepository.mergeInventoryDocument(itemId, <String, dynamic>{
      'name': name,
      'status': 'archived',
      'tombstone': true,
      'updatedAt': now.toIso8601String(),
    }, updatedAt: now.millisecondsSinceEpoch);
    setStatus(MobileSyncStatus.idle);
  }

  /// Pull the latest inventory + customers from the backend and merge them
  /// locally. Merges are upserts, so a pull can never lose local data. Paired
  /// with the outbox push this gives two-way, multi-device sync.
  /// Refresh the shop's business details from the server.
  ///
  /// Best-effort: a shop that cannot reach the server should still sync its
  /// sales, and the locally stored details stay usable meanwhile.
  Future<void> _pullShopSettings(MobileSession session) async {
    try {
      final remote = await _backendApiClient.fetchShopSettings(
        user: session.user,
        shopId: session.shopId!,
      );
      final name = (remote['name'] ?? '').toString().trim();
      // An empty name would blank the receipt header; treat it as no answer.
      if (name.isEmpty) return;

      // saveShopDocument overwrites the whole record, so carry through the
      // fields the settings endpoint does not own (plan tier and features).
      final current = await _shopRepository.watchShopInfo().first;
      await _shopRepository.saveShopDocument(<String, dynamic>{
        'name': name,
        'tagline': (remote['tagline'] ?? current.tagline).toString(),
        'footer': (remote['footer'] ?? current.footer).toString(),
        'currency': (remote['currency_code'] ?? current.currency).toString(),
        'business_phone': (remote['business_phone'] ?? current.phone)
            .toString(),
        'gstin': (remote['gstin'] ?? current.gstin).toString(),
        'upi_vpa': (remote['upi_vpa'] ?? current.upiVpa).toString(),
        'plan_tier': current.planTier,
        'enabled_features': current.enabledFeatures,
      });
    } catch (error) {
      debugPrint('Shop settings pull failed: $error');
    }
  }

  Future<CommerceSyncResult> pullFromCloud() async {
    if (!MobileRuntimeConfig.backendSyncEnabled) {
      return const CommerceSyncResult(
        commandId: 'pull',
        state: CommerceSyncState.queued,
        message: 'Live backend sync is disabled for this build.',
      );
    }
    final session = _session;
    if (session == null || !session.hasShop) {
      return const CommerceSyncResult(
        commandId: 'pull',
        state: CommerceSyncState.queued,
        message: 'Sign in to a workspace before syncing.',
      );
    }

    setStatus(MobileSyncStatus.syncing);
    final now = DateTime.now().millisecondsSinceEpoch;
    // Shop details first: on a fresh install the receipt header, GSTIN and UPI
    // id would otherwise stay at their defaults until someone re-typed them.
    await _pullShopSettings(session);
    try {
      final shopId = session.shopId!;
      final user = session.user;

      final items = await _backendApiClient.fetchInventoryItems(
        user: user,
        shopId: shopId,
      );
      for (final row in items) {
        await _inventoryRepository.mergeBackendInventoryItem(
          row,
          updatedAt: now,
          // Fetched only when the row says there is a photo and no local copy
          // exists, so a repeat sync costs nothing.
          fetchImage: () => _backendApiClient.fetchInventoryImage(
            user: user,
            shopId: shopId,
            itemId: row['id'].toString(),
          ),
        );
      }

      final customers = await _backendApiClient.fetchCustomers(
        user: user,
        shopId: shopId,
      );
      final iso = DateTime.now().toIso8601String();
      for (final c in customers) {
        await _customerRepository
            .mergeRemoteCustomerDocument(c.id, <String, dynamic>{
              'name': c.name,
              'phone': c.phone ?? '',
              'email': c.email ?? '',
              'notes': c.notes ?? '',
              'status': c.status,
              'balance': c.balance,
              'total_spent': c.totalSpent,
              'tombstone': false,
              'updatedAt': iso,
            }, updatedAt: now);
      }

      setStatus(MobileSyncStatus.idle);
      return CommerceSyncResult(
        commandId: 'pull',
        state: CommerceSyncState.synced,
        message:
            'Pulled ${items.length} products and ${customers.length} customers.',
      );
    } on BackendApiException catch (error) {
      setStatus(MobileSyncStatus.error);
      return CommerceSyncResult(
        commandId: 'pull',
        state: CommerceSyncState.failed,
        message: 'Cloud pull failed: ${error.message}',
      );
    } on IOException catch (error) {
      setStatus(MobileSyncStatus.offline);
      return CommerceSyncResult(
        commandId: 'pull',
        state: CommerceSyncState.failed,
        message: 'Cloud unreachable: $error',
      );
    }
  }

  /// Save the shop's business details locally and push them to the server.
  ///
  /// These used to be device-only: a reinstall lost the shop's GSTIN and UPI
  /// id, and the website had no way to read them. Local write first so the
  /// receipt is correct immediately even with no signal; the push is
  /// best-effort and re-runs on the next save.
  Future<void> saveBusinessDetails(Map<String, dynamic> document) async {
    await _shopRepository.saveShopDocument(document);

    final session = _session;
    if (session == null ||
        !session.hasShop ||
        !MobileRuntimeConfig.backendSyncEnabled) {
      return;
    }
    try {
      await _backendApiClient.updateShopSettings(
        user: session.user,
        shopId: session.shopId!,
        changes: <String, dynamic>{
          'name': document['name'],
          'tagline': document['tagline'],
          'footer': document['footer'],
          'currency_code': document['currency'],
          'business_phone': document['business_phone'],
          'gstin': document['gstin'],
          'upi_vpa': document['upi_vpa'],
        },
      );
    } catch (error) {
      debugPrint('Backend shop settings push failed: $error');
    }
  }

  /// Record that a payment reminder went out.
  ///
  /// Written locally first so the list updates instantly and an offline shop
  /// still doesn't chase the same person twice on this device. The push is
  /// best-effort: failing to tell the server is not a reason to make the owner
  /// think the reminder never happened.
  Future<void> markCustomerReminded(String customerId) async {
    await _customerRepository.markReminded(customerId);

    final session = _session;
    if (session == null ||
        !session.hasShop ||
        !MobileRuntimeConfig.backendSyncEnabled ||
        !_uuidPattern.hasMatch(customerId)) {
      return;
    }
    try {
      await _backendApiClient.markCustomerReminded(
        user: session.user,
        shopId: session.shopId!,
        customerId: customerId,
      );
    } catch (error) {
      debugPrint('Backend reminder mark failed: $error');
    }
  }

  /// Full two-way sync: push queued sales/payments, then pull the latest
  /// catalog + customers. Safe to trigger manually.
  Future<CommerceSyncResult> syncNow() async {
    final push = await flushCommerceOutbox(force: true);
    final pull = await pullFromCloud();
    if (pull.state == CommerceSyncState.failed) return pull;
    return CommerceSyncResult(
      commandId: 'sync-now',
      state: pull.state,
      message: 'Synced. ${pull.message} ${push.message ?? ''}'.trim(),
    );
  }

  Future<CommerceSyncResult> submitSale(LocalSaleCommit commit) async {
    final session = _session;
    if (session == null || !session.hasShop) {
      return CommerceSyncResult(
        commandId: commit.commandId,
        state: CommerceSyncState.queued,
        message: 'Sale saved locally. Sign in again to sync it.',
      );
    }

    return flushCommerceOutbox(triggerCommandId: commit.commandId);
  }

  Future<void> dispose() => _cancelSubscriptions();

  Future<CommerceSyncResult> retryCommerceCommand(String commandId) async {
    await _salesRepository.markCommandQueued(commandId);
    return flushCommerceOutbox(triggerCommandId: commandId);
  }

  Future<CommerceSyncResult> flushCommerceOutbox({
    String? triggerCommandId,
    bool checkAccess = true,
    bool force = false,
  }) async {
    if (!MobileRuntimeConfig.backendSyncEnabled) {
      return CommerceSyncResult(
        commandId: triggerCommandId ?? 'local-only',
        state: CommerceSyncState.queued,
        message:
            'Sale saved locally. Live backend sync is disabled for this build.',
      );
    }

    if (_isFlushingOutbox) {
      return CommerceSyncResult(
        commandId: triggerCommandId ?? 'pending',
        state: CommerceSyncState.syncing,
        message: 'Commerce outbox sync is already in progress.',
      );
    }

    final session = _session;
    if (session == null || !session.hasShop) {
      return CommerceSyncResult(
        commandId: triggerCommandId ?? 'unknown',
        state: CommerceSyncState.queued,
        message: 'Outbox is waiting for an authenticated workspace.',
      );
    }

    if (checkAccess) {
      final hasAccess = await _syncWorkspaceAccessSession(session);
      if (!hasAccess) {
        return CommerceSyncResult(
          commandId: triggerCommandId ?? 'unknown',
          state: CommerceSyncState.queued,
          message:
              'Workspace access ended on this device. Sign in again if access is restored.',
        );
      }
    }

    _isFlushingOutbox = true;
    // A manual retry (or an explicit trigger) forces every waiting entry
    // through, ignoring backoff and the attempt ceiling.
    final entries = await _salesRepository.getPendingOutboxEntries(
      ignoreBackoff: force || triggerCommandId != null,
    );
    if (entries.isEmpty) {
      _isFlushingOutbox = false;
      return CommerceSyncResult(
        commandId: triggerCommandId ?? 'none',
        state: CommerceSyncState.synced,
        message: 'Nothing is waiting in the mobile outbox.',
      );
    }

    final foregroundSync = triggerCommandId != null;
    if (foregroundSync) {
      setStatus(MobileSyncStatus.syncing);
    }
    CommerceSyncResult? targetResult;
    var hadFailure = false;

    try {
      for (final entry in entries) {
        await _salesRepository.registerOutboxAttempt(entry.commandId);
        await _salesRepository.markOutboxSyncing(entry.commandId);
        try {
          final payload = Map<String, dynamic>.from(
            jsonDecode(entry.payloadJson) as Map<String, dynamic>,
          );
          if (entry.commandType == 'sale_create') {
            // Safety net for already-queued payloads: the backend requires a
            // UUID or null for inventory_item_id, so null out any non-UUID
            // local id (custom/weighed/offline items) before sending. This lets
            // a previously-rejected sale succeed on retry instead of looping.
            _sanitizeSaleItemIds(payload);
          }
          late BackendCommandResponse response;
          switch (entry.commandType) {
            case 'sale_create':
              response = await _backendApiClient.submitSaleCommand(
                user: session.user,
                shopId: entry.shopId,
                payload: payload,
              );
              break;
            case 'payment_create':
              response = await _backendApiClient.submitPaymentCommand(
                user: session.user,
                shopId: entry.shopId,
                payload: payload,
              );
              break;
            default:
              throw BackendApiException(
                'Unknown mobile commerce command type: ${entry.commandType}',
              );
          }

          await _salesRepository.markCommandSynced(
            commandId: entry.commandId,
            receiptId: response.receiptId,
            backendSaleId: entry.commandType == 'sale_create'
                ? response.entityId
                : null,
          );
          if (entry.commandId == triggerCommandId) {
            targetResult = CommerceSyncResult(
              commandId: entry.commandId,
              state: CommerceSyncState.synced,
              backendEntityId: response.entityId,
              message: response.duplicate
                  ? 'Sale was already accepted by the backend earlier.'
                  : 'Sale saved locally and synced to the backend.',
            );
          }
        } catch (error) {
          final status = error is BackendApiException ? error.statusCode : null;
          if (isPermanentOutboxRejection(status)) {
            // The server permanently rejected this payload (4xx validation).
            // Dead-letter it and CONTINUE so valid sales behind it still sync —
            // one bad command can never block the whole offline queue.
            await _salesRepository.markOutboxDeadLetter(
              entry.commandId,
              error.toString(),
            );
            if (entry.commandId == triggerCommandId) {
              targetResult = CommerceSyncResult(
                commandId: entry.commandId,
                state: CommerceSyncState.failed,
                message:
                    'This sale was rejected by the backend and needs attention.',
              );
            }
            continue;
          }
          debugPrint('Commerce outbox sync failed: $error');
          hadFailure = true;
          await _salesRepository.markCommandFailed(
            commandId: entry.commandId,
            error: error.toString(),
          );
          if (entry.commandId == triggerCommandId) {
            targetResult = CommerceSyncResult(
              commandId: entry.commandId,
              state: CommerceSyncState.queued,
              message:
                  'Sale saved locally. Backend sync is pending and will retry later.',
            );
          }
        }
      }

      if (_salesReadsUseBackend) {
        await _syncBackendSalesSnapshot(
          session,
          session.shopId!,
          updateStatus: foregroundSync,
        );
      }

      if (foregroundSync) {
        setStatus(hadFailure ? MobileSyncStatus.error : MobileSyncStatus.idle);
      }
      return targetResult ??
          CommerceSyncResult(
            commandId: triggerCommandId ?? entries.first.commandId,
            state: hadFailure
                ? CommerceSyncState.queued
                : CommerceSyncState.synced,
            message: hadFailure
                ? 'Some commerce commands are still queued for retry.'
                : 'Pending commerce commands were flushed.',
          );
    } finally {
      _isFlushingOutbox = false;
    }
  }

  Future<void> _clearWorkspaceCache({required bool clearSales}) async {
    final futures = <Future<void>>[
      _shopRepository.clearWorkspace(),
      _inventoryRepository.clearWorkspace(),
      _customerRepository.clearWorkspace(),
    ];
    if (clearSales) {
      futures.add(_salesRepository.clearWorkspace());
    }
    await Future.wait<void>(futures);
  }

  Future<void> _ensureLocalWorkspace(
    MobileSession session,
    String shopId,
  ) async {
    // Only seed a placeholder when there is no shop doc yet. This used to run
    // unconditionally and OVERWRITE the real shop the register/login flow just
    // saved — wiping the shop name and phone number on every session refresh.
    final existing = await _shopRepository.readSetting('settings');
    if (existing != null && existing.isNotEmpty) {
      return;
    }
    await _shopRepository.saveShopDocument(<String, dynamic>{
      'name': MobileRuntimeConfig.localShopName,
      'tagline': 'LOCAL-FIRST COMMAND CENTER',
      'footer': 'Thank you for your business!',
      'currency': 'INR',
      'plan_tier': 'growth',
      'enabled_features': <String, bool>{
        'inventory': true,
        'pos': true,
        'customers': true,
        'history': true,
        'team': true,
        'attendance': true,
        'expenses': true,
        'advanced_ops': true,
      },
      'settings': <String, dynamic>{
        'name': MobileRuntimeConfig.localShopName,
        'tagline': 'LOCAL-FIRST COMMAND CENTER',
        'footer': 'Thank you for your business!',
        'currency': 'INR',
        'plan_tier': 'growth',
      },
      'sourceMeta': <String, dynamic>{
        'shop_id': shopId,
        'session_uid': session.uid,
        'mode': MobileRuntimeConfig.backendSyncEnabled
            ? 'backend_sync'
            : 'local_first',
      },
    });
  }

  Future<bool> _syncWorkspaceAccessSession(MobileSession session) async {
    if (!MobileRuntimeConfig.backendSyncEnabled) {
      return true;
    }
    if (!session.hasShop) {
      return true;
    }

    try {
      final runtimeInfo = await _loadRuntimeInfo();
      final appInstanceId = await _shopRepository.ensureAppInstanceId();
      final heartbeat = await _backendApiClient.sendWorkspaceSessionHeartbeat(
        user: session.user,
        shopId: session.shopId!,
        payload: WorkspaceSessionHeartbeatPayload(
          appInstanceId: appInstanceId,
          deviceLabel:
              '${runtimeInfo.appName} ${runtimeInfo.versionLabel} (${Platform.operatingSystem})',
          platformName: Platform.operatingSystem,
          packageName: runtimeInfo.packageName,
          appVersion: runtimeInfo.version,
          buildNumber: runtimeInfo.buildNumber,
          releaseChannel: runtimeInfo.releaseChannel,
          releaseTag: runtimeInfo.releaseTag,
          metadata: <String, dynamic>{
            'role': session.normalizedRole,
            'role_profile_key': session.roleProfileKey,
            'release_sha': runtimeInfo.releaseSha,
            'pilot_scope': runtimeInfo.pilotScope,
          },
        ),
      );

      if (!heartbeat.shouldSignOut && !heartbeat.shouldWipeLocalData) {
        return true;
      }

      await _enforceWorkspaceSessionInstruction(session, heartbeat: heartbeat);
      return false;
    } on BackendApiException catch (error) {
      // An auth failure means "we can't talk to the server right now" — it must
      // never destroy local data. Previously a single 401/403 on the background
      // heartbeat wiped the whole local workspace while the UI stayed signed in,
      // so the shop silently emptied mid-session and only came back on re-login.
      // A 403 is a permission/plan gate, not an expired session, so it doesn't
      // even stop syncing.
      if (error.statusCode == 401) {
        await _pauseSyncForReauth();
        return false;
      }
      debugPrint('Workspace session heartbeat skipped: $error');
      return true;
    } catch (error) {
      debugPrint('Workspace session heartbeat skipped: $error');
      return true;
    }
  }

  Future<void> _enforceWorkspaceSessionInstruction(
    MobileSession session, {
    required WorkspaceAccessSessionHeartbeatResult heartbeat,
  }) async {
    await _cancelSubscriptions();
    // Only destroy local data when the server explicitly asks for a remote wipe
    // (the lost/stolen-device feature). A plain "sign out" instruction should
    // end the session, not erase the shop's records from this device.
    if (heartbeat.shouldWipeLocalData) {
      await _clearWorkspaceCache(clearSales: true);
    }

    if (heartbeat.shouldWipeLocalData) {
      try {
        await _backendApiClient.acknowledgeWorkspaceSessionWipe(
          user: session.user,
          shopId: session.shopId!,
          sessionId: heartbeat.sessionId,
        );
      } catch (error) {
        debugPrint('Workspace session wipe acknowledge skipped: $error');
      }
    }

    await _finalizeLocalSignOut();
  }

  /// The access token is no longer accepted. Stop background syncing and flag
  /// the session as needing re-authentication, but keep every local record —
  /// re-signing in re-attaches to the same shop and the data is still there
  /// (and any unsynced local work isn't thrown away).
  Future<void> _pauseSyncForReauth() async {
    await _cancelSubscriptions();
    _outboxRetryTimer?.cancel();
    _outboxRetryTimer = null;
    _needsReauth = true;
    setStatus(MobileSyncStatus.error);
  }

  Future<void> _finalizeLocalSignOut() async {
    _session = null;
    _salesReadsUseBackend = false;
    setStatus(MobileSyncStatus.idle);
  }

  Future<AppRuntimeInfo> _loadRuntimeInfo() {
    return _runtimeInfoFuture ??= AppRuntimeInfo.load();
  }

  Future<Map<String, DomainControlState>> _refreshBackendDomainEpochs(
    MobileSession session,
    String shopId,
  ) async {
    if (!MobileRuntimeConfig.backendSyncEnabled) {
      return const <String, DomainControlState>{};
    }

    final domains = <String>[
      'inventory',
      'customers',
      'customer_ledger',
      'sales',
      'payments',
    ];

    final stateEntries = await Future.wait(
      domains.map((domain) async {
        try {
          final state = await _backendApiClient.getDomainState(
            user: session.user,
            shopId: shopId,
            domain: domain,
          );
          await _shopRepository.saveDomainState(state: state);
          return MapEntry(domain, state);
        } catch (error) {
          debugPrint('$domain domain state refresh skipped: $error');
          return null;
        }
      }),
    );

    return Map<String, DomainControlState>.fromEntries(
      stateEntries.whereType<MapEntry<String, DomainControlState>>(),
    );
  }

  Future<void> _cancelSubscriptions() async {
    _outboxRetryTimer?.cancel();
    _outboxRetryTimer = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  void _startOutboxRetryLoop() {
    _outboxRetryTimer?.cancel();
    _outboxRetryTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      final session = _session;
      if (session == null || !session.hasShop || _needsReauth) {
        return;
      }
      unawaited(_runBackgroundSyncTick(session));
    });
  }

  Future<void> _runBackgroundSyncTick(MobileSession session) async {
    final stillAllowed = await _syncWorkspaceAccessSession(session);
    if (!stillAllowed) {
      return;
    }

    await flushCommerceOutbox(checkAccess: false);
    if (_salesReadsUseBackend) {
      await _syncBackendSalesSnapshot(
        session,
        session.shopId!,
        updateStatus: false,
      );
    }
  }

  Future<void> _syncBackendSalesSnapshot(
    MobileSession session,
    String shopId, {
    bool updateStatus = true,
  }) async {
    try {
      final backendSales = await _backendApiClient.fetchRecentSales(
        user: session.user,
        shopId: shopId,
        limit: 200,
      );
      for (final sale in backendSales) {
        final updatedAt = _toEpoch(
          sale['occurred_at'] ?? sale['updated_at'] ?? sale['sale_date'],
        );
        await _salesRepository.mergeBackendSaleDocument(
          sale,
          updatedAt: updatedAt,
        );
      }
      if (updateStatus) {
        setStatus(MobileSyncStatus.idle);
      }
    } catch (error) {
      debugPrint('Backend sales snapshot sync failed: $error');
      if (updateStatus) {
        setStatus(MobileSyncStatus.error);
      }
    }
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Null out any non-UUID `inventory_item_id` in a queued sale payload so the
  /// backend (which requires a UUID or null) accepts it as a named line rather
  /// than rejecting the whole sale.
  void _sanitizeSaleItemIds(Map<String, dynamic> payload) {
    final sale = payload['sale'];
    if (sale is! Map) return;
    final customerId = (sale['customer_id'] ?? '').toString().trim();
    if (!_uuidPattern.hasMatch(customerId)) {
      sale['customer_id'] = null;
    }
    final items = sale['items'];
    if (items is! List) return;
    for (final item in items) {
      if (item is Map) {
        final id = (item['inventory_item_id'] ?? '').toString().trim();
        if (!_uuidPattern.hasMatch(id)) {
          item['inventory_item_id'] = null;
        }
      }
    }
  }

  Future<void> _syncBackendCustomersSnapshot(
    MobileSession session,
    String shopId, {
    bool updateStatus = false,
  }) async {
    try {
      final customers = await _backendApiClient.fetchCustomers(
        user: session.user,
        shopId: shopId,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final iso = DateTime.now().toIso8601String();
      for (final c in customers) {
        await _customerRepository
            .mergeRemoteCustomerDocument(c.id, <String, dynamic>{
              'name': c.name,
              'phone': c.phone ?? '',
              'email': c.email ?? '',
              'notes': c.notes ?? '',
              'status': c.status,
              'balance': c.balance,
              'total_spent': c.totalSpent,
              'tombstone': false,
              'updatedAt': iso,
            }, updatedAt: now);
      }
      if (updateStatus) setStatus(MobileSyncStatus.idle);
    } catch (error) {
      debugPrint('Backend customers snapshot sync failed: $error');
      if (updateStatus) setStatus(MobileSyncStatus.error);
    }
  }

  Future<void> _syncBackendExpensesSnapshot(
    MobileSession session,
    String shopId, {
    bool updateStatus = false,
  }) async {
    try {
      final expenses = await _backendApiClient.getExpenses(
        user: session.user,
        shopId: shopId,
      );
      for (final e in expenses) {
        if (e.id.isEmpty) continue;
        await _expenseRepository.upsertExpense(
          id: e.id,
          category: e.category,
          amount: e.amount,
          expenseDate: e.expenseDate,
          description: e.description,
          paymentMethod: e.paymentMethod,
          paymentReference: e.paymentReference,
          actorName: e.actorName,
          tombstone: e.tombstone,
        );
      }
      if (updateStatus) setStatus(MobileSyncStatus.idle);
    } catch (error) {
      debugPrint('Backend expenses snapshot sync failed: $error');
      if (updateStatus) setStatus(MobileSyncStatus.error);
    }
  }

  Future<void> _syncBackendPurchasesSnapshot(
    MobileSession session,
    String shopId, {
    bool updateStatus = false,
  }) async {
    try {
      final purchases = await _backendApiClient.getPurchases(
        user: session.user,
        shopId: shopId,
      );
      for (final p in purchases) {
        if (p.id.isEmpty) continue;
        await _purchaseRepository.upsertPurchase(
          id: p.id,
          supplierName: p.supplierName,
          total: p.total,
          purchaseDate: p.purchaseDate,
          amountPaid: p.amountPaid,
          supplierPhone: p.supplierPhone,
          reference: p.reference,
          paymentMethod: p.paymentMethod,
          notes: p.notes,
          actorName: p.actorName,
          tombstone: p.tombstone,
        );
      }
      if (updateStatus) setStatus(MobileSyncStatus.idle);
    } catch (error) {
      debugPrint('Backend purchases snapshot sync failed: $error');
      if (updateStatus) setStatus(MobileSyncStatus.error);
    }
  }

  /// Record an expense: push to the server first so it survives a data clear,
  /// then store the server's copy locally (keyed by its id). Falls back to a
  /// local-only row when the backend is unreachable.
  Future<void> recordExpense({
    required String category,
    required double amount,
    required DateTime expenseDate,
    String description = '',
    String paymentMethod = 'CASH',
    String paymentReference = '',
    String? actorName,
  }) async {
    final session = _session;
    if (session == null || !session.hasShop) {
      throw StateError('Sign in to a workspace before adding expenses.');
    }
    if (session.isReadOnly) {
      throw StateError('Viewer access cannot add expenses.');
    }

    setStatus(MobileSyncStatus.syncing);
    try {
      if (MobileRuntimeConfig.backendSyncEnabled) {
        try {
          final created = await _backendApiClient.createExpense(
            user: session.user,
            shopId: session.shopId!,
            category: category,
            amount: amount,
            expenseDate: expenseDate,
            description: description,
            paymentMethod: paymentMethod,
            paymentReference: paymentReference,
          );
          if (created.id.isNotEmpty) {
            await _expenseRepository.upsertExpense(
              id: created.id,
              category: created.category,
              amount: created.amount,
              expenseDate: created.expenseDate,
              description: created.description,
              paymentMethod: created.paymentMethod,
              paymentReference: created.paymentReference,
              actorName: created.actorName ?? actorName,
            );
            setStatus(MobileSyncStatus.idle);
            return;
          }
        } catch (error) {
          debugPrint('Backend expense push failed, saving locally: $error');
        }
      }
      await _expenseRepository.recordExpense(
        category: category,
        amount: amount,
        expenseDate: expenseDate,
        description: description,
        paymentMethod: paymentMethod,
        paymentReference: paymentReference,
        actorName: actorName,
      );
      setStatus(MobileSyncStatus.idle);
    } catch (error) {
      setStatus(MobileSyncStatus.error);
      rethrow;
    }
  }

  /// Record a purchase (and its supplier due) on the server, then locally.
  /// Returns the local row id so callers can link stock-in movements to it.
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
    final session = _session;
    if (session == null || !session.hasShop) {
      throw StateError('Sign in to a workspace before adding purchases.');
    }
    if (session.isReadOnly) {
      throw StateError('Viewer access cannot add purchases.');
    }

    setStatus(MobileSyncStatus.syncing);
    try {
      if (MobileRuntimeConfig.backendSyncEnabled) {
        try {
          final created = await _backendApiClient.createPurchase(
            user: session.user,
            shopId: session.shopId!,
            supplierName: supplierName,
            total: total,
            purchaseDate: purchaseDate,
            amountPaid: amountPaid,
            reference: reference,
            paymentMode: paymentMethod,
            note: notes,
          );
          if (created.id.isNotEmpty) {
            await _purchaseRepository.upsertPurchase(
              id: created.id,
              supplierName: created.supplierName,
              total: created.total,
              purchaseDate: created.purchaseDate,
              amountPaid: created.amountPaid,
              // The server has no phone on a purchase; keep what was entered.
              supplierPhone: supplierPhone,
              reference: created.reference,
              paymentMethod: created.paymentMethod,
              notes: created.notes,
              actorName: created.actorName ?? actorName,
            );
            setStatus(MobileSyncStatus.idle);
            return created.id;
          }
        } catch (error) {
          debugPrint('Backend purchase push failed, saving locally: $error');
        }
      }
      final localId = await _purchaseRepository.recordPurchase(
        supplierName: supplierName,
        total: total,
        purchaseDate: purchaseDate,
        amountPaid: amountPaid,
        supplierPhone: supplierPhone,
        reference: reference,
        paymentMethod: paymentMethod,
        notes: notes,
        actorName: actorName,
      );
      setStatus(MobileSyncStatus.idle);
      return localId;
    } catch (error) {
      setStatus(MobileSyncStatus.error);
      rethrow;
    }
  }

  /// Search inventory on the server and cache matches locally so the catalog
  /// (which reads local) can show items beyond the recent window. Reuses the
  /// backend->local merge, so no separate mapping is needed.
  Future<void> searchInventoryFromServer(String query) async {
    final session = _session;
    if (session == null ||
        !session.hasShop ||
        !MobileRuntimeConfig.backendSyncEnabled ||
        query.trim().length < 2) {
      return;
    }
    try {
      final items = await _backendApiClient.fetchInventoryItems(
        user: session.user,
        shopId: session.shopId!,
        query: query.trim(),
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final item in items) {
        await _inventoryRepository.mergeBackendInventoryItem(
          item,
          updatedAt: now,
          fetchImage: () => _backendApiClient.fetchInventoryImage(
            user: session.user,
            shopId: session.shopId!,
            itemId: item['id'].toString(),
          ),
        );
      }
    } catch (error) {
      debugPrint('Inventory server search failed: $error');
    }
  }

  /// Search sales on the server and cache matches locally so History can show
  /// receipts beyond the recent window.
  Future<void> searchSalesFromServer(String query) async {
    final session = _session;
    if (session == null ||
        !session.hasShop ||
        !MobileRuntimeConfig.backendSyncEnabled ||
        query.trim().length < 2) {
      return;
    }
    try {
      final sales = await _backendApiClient.fetchRecentSales(
        user: session.user,
        shopId: session.shopId!,
        query: query.trim(),
        limit: 200,
      );
      for (final sale in sales) {
        final updatedAt = _toEpoch(
          sale['occurred_at'] ?? sale['updated_at'] ?? sale['sale_date'],
        );
        await _salesRepository.mergeBackendSaleDocument(
          sale,
          updatedAt: updatedAt,
        );
      }
    } catch (error) {
      debugPrint('Sales server search failed: $error');
    }
  }

  Future<void> _syncBackendInventorySnapshot(
    MobileSession session,
    String shopId, {
    bool updateStatus = true,
  }) async {
    try {
      final backendItems = await _backendApiClient.fetchInventoryItems(
        user: session.user,
        shopId: shopId,
      );
      final updatedAt = DateTime.now().millisecondsSinceEpoch;
      for (final item in backendItems) {
        await _inventoryRepository.mergeBackendInventoryItem(
          item,
          updatedAt: updatedAt,
          fetchImage: () => _backendApiClient.fetchInventoryImage(
            user: session.user,
            shopId: shopId,
            itemId: item['id'].toString(),
          ),
        );
      }
      if (updateStatus) {
        setStatus(MobileSyncStatus.idle);
      }
    } catch (error) {
      debugPrint('Backend inventory snapshot sync failed: $error');
      if (updateStatus) {
        setStatus(MobileSyncStatus.error);
      }
    }
  }

  Future<void> _createInventoryItemLocally({
    required MobileSession session,
    required String name,
    required double sellPrice,
    required double openingStock,
    required String sku,
    required String barcode,
    required String category,
    required String subcategory,
    required String size,
    required String description,
    required double? costPrice,
    required String hsnCode,
    required double gstRate,
    required bool priceIncludesTax,
    required DateTime timestamp,
    String? imagePath,
    String? unit,
    int? reorderLevel,
    String? variantGroupId,
    String? variantLabel,
  }) async {
    final itemId = 'local-${timestamp.microsecondsSinceEpoch}';
    final isoTimestamp = timestamp.toIso8601String();
    final payload = <String, dynamic>{
      'name': name,
      'price': sellPrice,
      'sell_price': sellPrice,
      'sku': sku,
      'barcode': barcode,
      'category': category,
      'subcategory': subcategory,
      'size': size,
      'description': description,
      'hsnCode': hsnCode,
      'gstRate': gstRate,
      'priceIncludesTax': priceIncludesTax,
      'stock': openingStock,
      'status': 'active',
      'tombstone': false,
      'sourceMeta': <String, dynamic>{
        'created_from': 'mobile_inventory',
        'actor_uid': session.uid,
      },
      'imagePath': imagePath,
      'unit': unit,
      'reorderLevel': reorderLevel,
      'variantGroupId': variantGroupId,
      'variantLabel': variantLabel,
      'createdAt': isoTimestamp,
      'updatedAt': isoTimestamp,
    };

    await _inventoryRepository.mergeInventoryDocument(
      itemId,
      payload,
      updatedAt: timestamp.millisecondsSinceEpoch,
    );

    if (costPrice != null) {
      final privatePayload = <String, dynamic>{
        'costPrice': costPrice,
        'updatedAt': isoTimestamp,
        'tombstone': false,
      };
      await _inventoryRepository.mergeInventoryPrivateDocument(
        itemId,
        privatePayload,
        updatedAt: timestamp.millisecondsSinceEpoch,
      );
    }
  }

  int _toEpoch(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsedDate = DateTime.tryParse(value);
      if (parsedDate != null) return parsedDate.millisecondsSinceEpoch;
      return int.tryParse(value) ?? DateTime.now().millisecondsSinceEpoch;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }
}

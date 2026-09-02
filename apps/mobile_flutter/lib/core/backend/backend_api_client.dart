import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/mobile_repository.dart';
import '../models/mobile_auth_user.dart';
import '../models/mobile_models.dart';
import '../runtime/mobile_runtime_config.dart';

/// Storage keys shared with the session controller. Duplicated deliberately
/// rather than imported: the session controller depends on this file, and
/// importing it back would make the cycle real.
const String _storedAccessKey = 'jwt_access';
const String _storedRefreshKey = 'jwt_refresh';

final backendApiClientProvider = Provider<BackendApiClient>((ref) {
  return BackendApiClient(
    baseUrl: const String.fromEnvironment(
      'BUSINESS_HUB_API_BASE_URL',
      defaultValue: 'https://api.indianwasteportal.com/api/v1',
    ),
    readRefreshToken: () async =>
        ref.read(shopRepositoryProvider).readSetting(_storedRefreshKey),
    onTokensRefreshed: (access, refresh) async {
      final repo = ref.read(shopRepositoryProvider);
      await repo.writeSetting(_storedAccessKey, access);
      await repo.writeSetting(_storedRefreshKey, refresh);
    },
  );
});

class BackendApiException implements Exception {
  BackendApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class BackendCommandResponse {
  const BackendCommandResponse({
    required this.commandId,
    required this.receiptId,
    required this.duplicate,
    required this.resultStatus,
    this.entityId,
  });

  final String commandId;
  final String receiptId;
  final bool duplicate;
  final String resultStatus;
  final String? entityId;
}

class WorkspaceSessionHeartbeatPayload {
  const WorkspaceSessionHeartbeatPayload({
    required this.appInstanceId,
    required this.deviceLabel,
    required this.platformName,
    required this.packageName,
    required this.appVersion,
    required this.buildNumber,
    required this.releaseChannel,
    required this.releaseTag,
    this.metadata = const <String, dynamic>{},
  });

  final String appInstanceId;
  final String deviceLabel;
  final String platformName;
  final String packageName;
  final String appVersion;
  final String buildNumber;
  final String releaseChannel;
  final String releaseTag;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'app_instance_id': appInstanceId,
    'device_label': deviceLabel,
    'platform_name': platformName,
    'package_name': packageName,
    'app_version': appVersion,
    'build_number': buildNumber,
    'release_channel': releaseChannel,
    'release_tag': releaseTag,
    'metadata_json': metadata,
  };
}

class UserMfaVerifyPayload {
  const UserMfaVerifyPayload({required this.purpose, required this.code});

  final String purpose;
  final String code;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'purpose': purpose,
    'code': code,
  };
}

/// One page of a list endpoint, and where the next one starts.
///
/// The body of these endpoints is a bare JSON array - deliberately, because
/// this client throws on anything else - so the cursor for the next page
/// travels in the X-Next-Cursor header instead. A caller that reads only the
/// body sees one page and has no way to know there were more.
class _ListPage {
  const _ListPage(this.rows, this.nextCursor);

  final List<Map<String, dynamic>> rows;

  /// Null when this was the last page.
  final String? nextCursor;
}

class BackendApiClient {
  BackendApiClient({
    required this.baseUrl,
    this.readRefreshToken,
    this.onTokensRefreshed,
  });

  final String baseUrl;

  /// Reads the stored refresh token. Injected rather than imported so the API
  /// client keeps no dependency on session storage.
  final Future<String?> Function()? readRefreshToken;

  /// Persists a newly minted pair. Both are stored: the server rotates the
  /// refresh token on every exchange, so keeping only the access token would
  /// leave the next refresh presenting one that has already been spent.
  final Future<void> Function(String access, String refresh)? onTokensRefreshed;

  /// A single in-flight refresh, shared by every request waiting on one.
  ///
  /// A screen that opens with five parallel requests produces five 401s at
  /// once. Without this each would refresh independently, and with rotating
  /// refresh tokens four of those five exchanges would be spending a token
  /// another had already replaced.
  Future<String?>? _inFlightRefresh;
  static const Duration _requestTimeout = Duration(
    milliseconds: MobileRuntimeConfig.backendTimeoutMs,
  );

  Future<DomainControlState> getDomainState({
    required User user,
    required String shopId,
    required String domain,
  }) async {
    final decoded = await _request(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/domain-state/$domain/',
    );

    return DomainControlState.fromJson(decoded, fallbackDomain: domain);
  }

  Future<List<ShopMembershipAccessRecord>> getShopMemberships({
    required User user,
  }) async {
    final decoded = await _requestList(
      user: user,
      method: 'GET',
      path: '/shops/',
    );
    return decoded
        .map(
          (row) => ShopMembershipAccessRecord(
            id: (row['id'] ?? '').toString(),
            role: (row['role'] ?? 'staff').toString(),
            roleLabel: (row['role_label'] ?? 'Staff').toString(),
            roleSummary: (row['role_summary'] ?? '').toString(),
            roleProfile: (row['role_profile'] ?? '').toString(),
            status: (row['status'] ?? 'active').toString(),
            shopId: (row['shop_id'] ?? '').toString(),
            shopName: (row['shop_name'] ?? '').toString(),
            shopSlug: (row['shop_slug'] ?? '').toString(),
            shopCurrencyCode: (row['shop_currency_code'] ?? 'INR').toString(),
            shopTimezone: (row['shop_timezone'] ?? 'Asia/Kolkata').toString(),
            shopPlanTier: (row['shop_plan_tier'] ?? 'growth').toString(),
            shopPhone: (row['shop_phone'] ?? '').toString(),
            shopEnabledFeatures: row['shop_enabled_features'] is Map
                ? Map<String, bool>.from(
                    (row['shop_enabled_features'] as Map).map(
                      (key, value) => MapEntry(key.toString(), value == true),
                    ),
                  )
                : const <String, bool>{},
            permissions: row['permissions_json'] is Map
                ? Map<String, dynamic>.from(row['permissions_json'] as Map)
                : const <String, dynamic>{},
            permissionsVersion: _asInt(row['permissions_version']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<WorkspaceTeamMemberRecord>> getWorkspaceTeamMembers({
    required User user,
    required String shopId,
  }) async {
    final decoded = await _requestList(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/team/',
    );
    return decoded.map(_mapWorkspaceTeamMember).toList(growable: false);
  }

  Future<WorkspaceTeamMemberRecord> createWorkspaceTeamMember({
    required User user,
    required String shopId,
    required String email,
    String fullName = '',
    String phone = '',
    String role = 'staff',
  }) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/team/',
      body: <String, dynamic>{
        'email': email,
        'full_name': fullName,
        'phone': phone,
        'role': role,
      },
    );
    return _mapWorkspaceTeamMember(decoded);
  }

  Future<WorkspaceTeamMemberRecord> updateWorkspaceTeamMember({
    required User user,
    required String shopId,
    required String membershipId,
    String? role,
    String? status,
    Map<String, dynamic>? permissions,
  }) async {
    final body = <String, dynamic>{};
    if (role != null) {
      body['role'] = role;
    }
    if (status != null) {
      body['status'] = status;
    }
    if (permissions != null) {
      body['permissions_json'] = permissions;
    }
    final decoded = await _request(
      user: user,
      method: 'PATCH',
      path: '/shops/$shopId/team/$membershipId/',
      body: body,
    );
    return _mapWorkspaceTeamMember(decoded);
  }

  /// Sign out all active sessions for a shop, keeping the current device.
  /// Returns the number of devices signed out.
  Future<int> revokeAllWorkspaceSessions({
    required User user,
    required String shopId,
    String keepAppInstanceId = '',
  }) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/sessions/revoke-all/',
      body: <String, dynamic>{'keep_app_instance_id': keepAppInstanceId},
    );
    return _asInt(decoded['revoked']);
  }

  /// The module/action permission catalog for the editor UI.
  Future<Map<String, dynamic>> getPermissionCatalog({
    required User user,
    required String shopId,
  }) async {
    return _request(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/permission-catalog/',
    );
  }

  Future<AttendanceSummarySnapshot> getAttendanceSummary({
    required User user,
    required String shopId,
    String? membershipId,
  }) async {
    final query = membershipId == null || membershipId.trim().isEmpty
        ? ''
        : '?membership_id=${Uri.encodeQueryComponent(membershipId.trim())}';
    final decoded = await _request(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/attendance/summary/$query',
    );
    return AttendanceSummarySnapshot(
      totalSessions: _asInt(decoded['total_sessions']),
      presentCount: _asInt(decoded['present_count']),
      leaveCount: _asInt(decoded['leave_count']),
      activeWorkersToday: _asInt(decoded['active_workers_today']),
    );
  }

  Future<List<AttendanceSessionRecord>> getAttendanceSessions({
    required User user,
    required String shopId,
    String? membershipId,
  }) async {
    final query = membershipId == null || membershipId.trim().isEmpty
        ? ''
        : '?membership_id=${Uri.encodeQueryComponent(membershipId.trim())}';
    final decoded = await _requestList(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/attendance/$query',
    );
    return decoded.map(_mapAttendanceSession).toList(growable: false);
  }

  Future<AttendanceSessionRecord> createAttendanceSession({
    required User user,
    required String shopId,
    required String membershipId,
    required DateTime sessionDate,
    required String status,
    DateTime? clockInAt,
    DateTime? clockOutAt,
    String note = '',
  }) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/attendance/',
      body: <String, dynamic>{
        'membership_id': membershipId,
        'session_date': sessionDate.toIso8601String().split('T').first,
        'status': status,
        'clock_in_at': clockInAt?.toIso8601String(),
        'clock_out_at': clockOutAt?.toIso8601String(),
        'note': note,
      },
    );
    return _mapAttendanceSession(decoded);
  }

  Future<List<ExpenseRecord>> getExpenses({
    required User user,
    required String shopId,
    String query = '',
    String category = '',
  }) async {
    final queryParts = <String>[];
    if (query.trim().isNotEmpty) {
      queryParts.add('q=${Uri.encodeQueryComponent(query.trim())}');
    }
    if (category.trim().isNotEmpty) {
      queryParts.add('category=${Uri.encodeQueryComponent(category.trim())}');
    }
    final path = queryParts.isEmpty
        ? '/shops/$shopId/expenses/'
        : '/shops/$shopId/expenses/?${queryParts.join('&')}';
    final decoded = await _requestList(user: user, method: 'GET', path: path);
    return decoded.map(_mapExpense).toList(growable: false);
  }

  Future<ExpenseRecord> createExpense({
    required User user,
    required String shopId,
    required String category,
    required double amount,
    required DateTime expenseDate,
    String description = '',
    String paymentMethod = 'CASH',
    String paymentReference = '',
  }) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/expenses/',
      body: <String, dynamic>{
        'category': category,
        'amount': amount.toStringAsFixed(2),
        'description': description,
        'payment_method': paymentMethod,
        'payment_reference': paymentReference,
        'expense_date': expenseDate.toIso8601String().split('T').first,
      },
    );
    return _mapExpense(decoded);
  }

  /// Current subscription state + the plan catalogue (prices/durations).
  Future<Map<String, dynamic>> fetchSubscription({
    required User user,
    required String shopId,
  }) async {
    return _request(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/subscription/',
    );
  }

  /// Re-evaluate the subscription server-side ("I've paid, check again").
  Future<Map<String, dynamic>> refreshSubscription({
    required User user,
    required String shopId,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/subscription/refresh/',
      body: const <String, dynamic>{},
    );
  }

  /// Open a payment for a billing period. Returns the hosted payment URL to
  /// launch; access is granted by the webhook, not by the app.
  Future<Map<String, dynamic>> startSubscriptionCheckout({
    required User user,
    required String shopId,
    required String billingPeriod,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/subscription/checkout/',
      body: <String, dynamic>{'billing_period': billingPeriod},
    );
  }

  /// Who sold how much, over an optional date window.
  Future<List<Map<String, dynamic>>> fetchStaffPerformance({
    required User user,
    required String shopId,
    String dateFrom = '',
    String dateTo = '',
  }) async {
    final parts = <String>[];
    if (dateFrom.isNotEmpty) parts.add('date_from=$dateFrom');
    if (dateTo.isNotEmpty) parts.add('date_to=$dateTo');
    final query = parts.isEmpty ? '' : '?${parts.join('&')}';
    return _requestList(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/sales/staff-performance/$query',
    );
  }

  /// Ask the platform to move this workspace onto another plan. Lands in the
  /// admin queue as a ShopPlanRequest instead of being lost in a clipboard copy.
  Future<void> requestPlanUpgrade({
    required User user,
    required String shopId,
    required String requestedPlanTier,
    String note = '',
  }) async {
    await _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/plan-requests/',
      body: <String, dynamic>{
        'requested_plan_tier': requestedPlanTier,
        'request_note': note,
      },
    );
  }

  /// Purchases (stock buying + supplier dues). The mobile app rolls suppliers
  /// up from their purchases, so syncing purchases also restores the supplier
  /// list and outstanding payables after a data clear.
  Future<List<PurchaseRecord>> getPurchases({
    required User user,
    required String shopId,
    String query = '',
  }) async {
    final path = query.trim().isEmpty
        ? '/shops/$shopId/purchases/'
        : '/shops/$shopId/purchases/?q=${Uri.encodeQueryComponent(query.trim())}';
    final decoded = await _requestList(user: user, method: 'GET', path: path);
    return decoded.map(_mapPurchase).toList(growable: false);
  }

  Future<PurchaseRecord> createPurchase({
    required User user,
    required String shopId,
    required String supplierName,
    required double total,
    required DateTime purchaseDate,
    double amountPaid = 0,
    String reference = '',
    String paymentMode = 'CASH',
    String note = '',
  }) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/purchases/',
      body: <String, dynamic>{
        'supplier_name': supplierName,
        'reference': reference,
        'amount_paid': amountPaid.toStringAsFixed(2),
        'payment_mode': paymentMode,
        'note': note,
        'purchase_date': purchaseDate.toIso8601String().split('T').first,
        // The server derives subtotal/total from the line items, so send the
        // purchase as a single consolidated line matching the entered total.
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': reference.trim().isEmpty
                ? 'Stock purchase'
                : reference.trim(),
            'quantity': '1',
            'unit_cost': total.toStringAsFixed(2),
          },
        ],
      },
    );
    return _mapPurchase(decoded);
  }

  Future<Map<String, dynamic>> createInventoryItem({
    required User user,
    required String shopId,
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
    String? imageData,
    String? unit,
    int? reorderLevel,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'sell_price': sellPrice.toStringAsFixed(2),
      'opening_stock': openingStock,
      // Product photo travels as a base64 data URI so it survives a reinstall.
      'image_data': imageData ?? '',
      'sku': sku,
      'barcode': barcode,
      'category': category.trim().isEmpty ? 'General' : category.trim(),
      'subcategory': subcategory,
      'size': size,
      'description': description,
      'hsn_code': hsnCode.trim(),
      'gst_rate': gstRate.toStringAsFixed(2),
      'price_includes_tax': priceIncludesTax,
      'unit': unit ?? '',
      'reorder_level': reorderLevel,
      'status': 'active',
    };
    if (costPrice != null) {
      body['private_cost_price'] = costPrice.toStringAsFixed(2);
    }

    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/inventory/',
      body: body,
    );
  }

  /// Bulk-create inventory items (spreadsheet import). Returns the server's
  /// {created, skipped, errors} summary. Each entry uses the same field names
  /// as createInventoryItem's body.
  Future<Map<String, dynamic>> bulkCreateInventory({
    required User user,
    required String shopId,
    required List<Map<String, dynamic>> items,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/inventory/bulk/',
      body: <String, dynamic>{'items': items},
    );
  }

  Future<Map<String, dynamic>> bulkCreateCustomers({
    required User user,
    required String shopId,
    required List<Map<String, dynamic>> customers,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/customers/bulk/',
      body: <String, dynamic>{'customers': customers},
    );
  }

  /// Bulk-import flat historical sales (past bills) as records — no stock
  /// effects, idempotent by each row's `id`.
  Future<Map<String, dynamic>> bulkImportSalesHistory({
    required User user,
    required String shopId,
    required List<Map<String, dynamic>> sales,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/sales/history-import/',
      body: <String, dynamic>{'sales': sales},
    );
  }

  Future<Map<String, dynamic>> updateInventoryItem({
    required User user,
    required String shopId,
    required String itemId,
    required String name,
    required double sellPrice,
    String category = 'General',
    String sku = '',
    String hsnCode = '',
    double gstRate = 0,
    bool priceIncludesTax = true,
    double? costPrice,
    String description = '',
    String? imageData,
    String? unit,
    int? reorderLevel,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'sell_price': sellPrice.toStringAsFixed(2),
      'category': category.trim().isEmpty ? 'General' : category.trim(),
      'sku': sku,
      'hsn_code': hsnCode.trim(),
      'gst_rate': gstRate.toStringAsFixed(2),
      'price_includes_tax': priceIncludesTax,
      'description': description,
      // The edit form owns both fields outright, so send them every time:
      // null genuinely means "cleared", not "unchanged".
      'unit': unit ?? '',
      'reorder_level': reorderLevel,
    };
    if (costPrice != null) {
      body['private_cost_price'] = costPrice.toStringAsFixed(2);
    }
    // Only send the photo when the caller resolved one, so an edit that didn't
    // touch the image never blanks the stored copy.
    if (imageData != null) {
      body['image_data'] = imageData;
    }
    return _request(
      user: user,
      method: 'PATCH',
      path: '/shops/$shopId/inventory/$itemId/',
      body: body,
    );
  }

  Future<void> deleteInventoryItem({
    required User user,
    required String shopId,
    required String itemId,
  }) async {
    await _request(
      user: user,
      method: 'DELETE',
      path: '/shops/$shopId/inventory/$itemId/',
    );
  }

  // ---------------------------------------------------------------------
  //  Returns
  // ---------------------------------------------------------------------

  /// What is still returnable on a bill, after any earlier returns.
  ///
  /// The counter cannot work this out on its own. Local sale lines carry no
  /// server-side `sale_item_id`, and an earlier return processed on the web or
  /// from another device would be invisible here — so the remaining quantity
  /// has to come from the server or the phone will happily offer to take back
  /// goods that already came back once.
  Future<Map<String, dynamic>> fetchReturnableSale({
    required User user,
    required String shopId,
    required String saleId,
  }) async {
    return _request(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/sales/$saleId/returnable/',
    );
  }

  /// Take part of a bill back: stock returns, money is refunded or credited.
  ///
  /// Each line is `{'sale_item_id': ..., 'quantity': ...}`. [refundMode] is one
  /// of CASH, UPI, BANK, CARD, KHATA or EXCHANGE; the server rejects KHATA on a
  /// bill with no customer, and EXCHANGE records a zero refund because the
  /// value carries into the replacement bill.
  Future<Map<String, dynamic>> createSaleReturn({
    required User user,
    required String shopId,
    required String saleId,
    required List<Map<String, dynamic>> lines,
    String refundMode = 'CASH',
    String note = '',
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/sales/$saleId/return/',
      body: <String, dynamic>{
        'lines': lines,
        'refund_mode': refundMode,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }

  // Deliberately absent: voidSale, deleteCustomer, getExpenseSummary and
  // createCustomerLedgerEntry. The counter app is offline-first — it writes to
  // the local database and lets the sync coordinator reconcile — so a REST
  // call that bypasses that produces a change the device does not know it
  // made. Expense summaries are computed locally from the same data. Returns
  // go through the partial-return sheet, which is what left voidSale without
  // a caller.

  /// Every product in the shop, following the server's paging to the end.
  ///
  /// This used to make one request and take what it was given. The server
  /// returns 200 rows by default and names the next page in an X-Next-Cursor
  /// header, so a shop with more than 200 products simply did not have the
  /// rest on the phone - no error, no empty state, no way to tell. Scanning a
  /// barcode for a product past the cut said the item did not exist.
  ///
  /// [limit] is a ceiling on the whole walk rather than a page size, so it
  /// keeps meaning what its callers already assume it means.
  Future<List<Map<String, dynamic>>> fetchInventoryItems({
    required User user,
    required String shopId,
    int limit = 5000,
    String query = '',
  }) async {
    final q = query.trim();
    final base = q.isEmpty
        ? '/shops/$shopId/inventory/'
        : '/shops/$shopId/inventory/?q=${Uri.encodeQueryComponent(q)}';

    final items = <Map<String, dynamic>>[];
    String? cursor;

    // Bounded rather than "until the cursor stops". A server that kept
    // returning the same cursor would otherwise spin here forever, on a phone,
    // on someone's mobile data.
    for (var page = 0; page < _maxListPages; page++) {
      final path = cursor == null
          ? base
          : '$base${base.contains('?') ? '&' : '?'}'
                'cursor=${Uri.encodeQueryComponent(cursor)}';

      final result = await _requestListPage(
        user: user,
        method: 'GET',
        path: path,
      );
      items.addAll(result.rows);

      if (result.nextCursor == null || items.length >= limit) break;
      // The same cursor twice means no progress. Stopping with what we have
      // beats looping; the alternative failure is silent and expensive.
      if (result.nextCursor == cursor) break;
      cursor = result.nextCursor;
    }

    return items.take(limit).toList(growable: false);
  }

  Future<BackendCommandResponse> submitSaleCommand({
    required User user,
    required String shopId,
    required Map<String, dynamic> payload,
  }) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/sales/commands/',
      body: payload,
    );

    return BackendCommandResponse(
      commandId: (decoded['command_id'] ?? '').toString(),
      receiptId: (decoded['receipt_id'] ?? '').toString(),
      duplicate: decoded['duplicate'] == true,
      resultStatus: (decoded['result_status'] ?? '').toString(),
      entityId: decoded['sale'] is Map
          ? (decoded['sale']['id'] ?? '').toString()
          : null,
    );
  }

  Future<BackendCommandResponse> submitPaymentCommand({
    required User user,
    required String shopId,
    required Map<String, dynamic> payload,
  }) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/payments/commands/',
      body: payload,
    );

    return BackendCommandResponse(
      commandId: (decoded['command_id'] ?? '').toString(),
      receiptId: (decoded['receipt_id'] ?? '').toString(),
      duplicate: decoded['duplicate'] == true,
      resultStatus: (decoded['result_status'] ?? '').toString(),
      entityId: decoded['payment'] is Map
          ? (decoded['payment']['id'] ?? '').toString()
          : null,
    );
  }

  /// Server-computed sales totals across ALL sales (not just the pulled
  /// window): {total_sales, gross_revenue, ...}. Used so revenue is accurate on
  /// shops with more sales than the phone pulls locally.
  Future<Map<String, dynamic>> fetchSalesSummary({
    required User user,
    required String shopId,
    String? dateFrom,
    String? dateTo,
  }) async {
    final params = <String>[
      if (dateFrom != null && dateFrom.isNotEmpty) 'date_from=$dateFrom',
      if (dateTo != null && dateTo.isNotEmpty) 'date_to=$dateTo',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    return _request(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/sales/summary/$query',
    );
  }

  Future<List<Map<String, dynamic>>> fetchRecentSales({
    required User user,
    required String shopId,
    int limit = 40,
    String query = '',
  }) async {
    final q = query.trim();
    final path = q.isEmpty
        ? '/shops/$shopId/sales/'
        : '/shops/$shopId/sales/?q=${Uri.encodeQueryComponent(q)}';
    final decoded = await _requestList(user: user, method: 'GET', path: path);

    if (decoded.length <= limit) {
      return decoded;
    }
    return decoded.take(limit).toList(growable: false);
  }

  Future<List<BackendCustomerSummary>> fetchCustomers({
    required User user,
    required String shopId,
    String query = '',
  }) async {
    final normalized = query.trim();
    final path = normalized.isEmpty
        ? '/shops/$shopId/customers/'
        : '/shops/$shopId/customers/?q=${Uri.encodeQueryComponent(normalized)}';
    final decoded = await _requestList(user: user, method: 'GET', path: path);
    return decoded.map(_mapCustomerSummary).toList(growable: false);
  }

  Future<BackendCustomerSummary> createCustomer({
    required User user,
    required String shopId,
    required String name,
    String? phone,
    String? email,
    String? notes,
    double openingBalance = 0,
  }) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/customers/',
      body: <String, dynamic>{
        'name': name,
        'phone': phone ?? '',
        'email': email ?? '',
        'notes': notes ?? '',
        'opening_balance': openingBalance.toStringAsFixed(2),
      },
    );
    return _mapCustomerSummary(decoded);
  }

  Future<BackendCustomerSummary> updateCustomer({
    required User user,
    required String shopId,
    required String customerId,
    required String name,
    String? phone,
    String? email,
    String? notes,
    String status = 'active',
  }) async {
    final decoded = await _request(
      user: user,
      method: 'PUT',
      path: '/shops/$shopId/customers/$customerId/',
      body: <String, dynamic>{
        'name': name,
        'phone': phone ?? '',
        'email': email ?? '',
        'notes': notes ?? '',
        'status': status,
      },
    );
    return _mapCustomerSummary(decoded);
  }

  /// Fetch the shop's own details (name, GSTIN, UPI id, receipt lines).
  Future<Map<String, dynamic>> fetchShopSettings({
    required User user,
    required String shopId,
  }) async {
    return _request(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/settings/',
    );
  }

  /// Push the shop's details so every device and the website agree. Only the
  /// keys supplied are changed.
  Future<Map<String, dynamic>> updateShopSettings({
    required User user,
    required String shopId,
    required Map<String, dynamic> changes,
  }) async {
    return _request(
      user: user,
      method: 'PATCH',
      path: '/shops/$shopId/settings/',
      body: changes,
    );
  }

  /// Record that a payment reminder went out, so every other device shows the
  /// customer as already chased today.
  Future<void> markCustomerReminded({
    required User user,
    required String shopId,
    required String customerId,
  }) async {
    await _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/customers/$customerId/remind/',
      body: const <String, dynamic>{},
    );
  }

  Future<List<CustomerLedgerPreviewEntry>> fetchCustomerLedger({
    required User user,
    required String shopId,
    required String customerId,
  }) async {
    final decoded = await _requestList(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/customers/$customerId/ledger/',
    );
    return decoded
        .map(
          (row) => CustomerLedgerPreviewEntry(
            id: (row['id'] ?? '').toString(),
            eventType: (row['event_type'] ?? 'adjustment').toString(),
            amountDelta: _asDouble(row['amount_delta']),
            occurredAt: _asDateTime(row['occurred_at']),
            note: _nullableText(row['note']),
            actorName: _nullableText(row['actor_name']),
          ),
        )
        .toList(growable: false);
  }

  Future<WorkspaceAccessSessionHeartbeatResult> sendWorkspaceSessionHeartbeat({
    required User user,
    required String shopId,
    required WorkspaceSessionHeartbeatPayload payload,
  }) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/sessions/mobile/heartbeat/',
      body: payload.toJson(),
    );

    return WorkspaceAccessSessionHeartbeatResult(
      sessionId: (decoded['session_id'] ?? '').toString(),
      status: (decoded['status'] ?? '').toString(),
      deviceLabel: (decoded['device_label'] ?? payload.deviceLabel).toString(),
      shouldSignOut: decoded['should_sign_out'] == true,
      shouldWipeLocalData: decoded['should_wipe_local_data'] == true,
      revokeReason: _nullableText(decoded['revoke_reason']),
      revokedAt: _asNullableDateTime(decoded['revoked_at']),
      wipeRequestedAt: _asNullableDateTime(decoded['wipe_requested_at']),
      wipeAcknowledgedAt: _asNullableDateTime(decoded['wipe_acknowledged_at']),
    );
  }

  Future<UserMfaStatus> getUserMfaStatus({required User user}) async {
    final decoded = await _request(
      user: user,
      method: 'GET',
      path: '/session/mfa/',
    );
    return _mapUserMfaStatus(decoded);
  }

  Future<UserMfaStatus> beginUserMfaEnrollment({required User user}) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/session/mfa/enroll/',
      body: const <String, dynamic>{},
    );
    return _mapUserMfaStatus(decoded);
  }

  Future<UserMfaVerifyResult> verifyUserMfaCode({
    required User user,
    required UserMfaVerifyPayload payload,
  }) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/session/mfa/verify/',
      body: payload.toJson(),
    );
    return UserMfaVerifyResult(
      status: _mapUserMfaStatus(
        Map<String, dynamic>.from(decoded['status'] as Map<String, dynamic>),
      ),
      verifiedAt: _asDateTime(decoded['verified_at']),
      verifiedUntil: _asDateTime(decoded['verified_until']),
    );
  }

  Future<UserMfaStatus> disableUserMfa({
    required User user,
    required String code,
  }) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/session/mfa/disable/',
      body: <String, dynamic>{'code': code},
    );
    return _mapUserMfaStatus(decoded);
  }

  Future<WorkspacePulseSnapshot> getWorkspacePulse({
    required User user,
    required String shopId,
  }) async {
    final decoded = await _request(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/projections/pulse/',
    );

    return WorkspacePulseSnapshot(
      refreshedAt: _asDateTime(decoded['refreshed_at']),
      headline: WorkspacePulseHeadline(
        title: (decoded['headline']?['title'] ?? '').toString(),
        body: (decoded['headline']?['body'] ?? '').toString(),
        route: (decoded['headline']?['route'] ?? '/history').toString(),
        ctaLabel: (decoded['headline']?['cta_label'] ?? 'Open').toString(),
        tone: (decoded['headline']?['tone'] ?? 'info').toString(),
      ),
      stats: WorkspacePulseStats(
        openTaskCount: _asInt(decoded['stats']?['open_task_count']),
        criticalAnomalyCount: _asInt(
          decoded['stats']?['critical_anomaly_count'],
        ),
        warningAnomalyCount: _asInt(decoded['stats']?['warning_anomaly_count']),
        staleSessionCount: _asInt(decoded['stats']?['stale_session_count']),
        wipePendingCount: _asInt(decoded['stats']?['wipe_pending_count']),
        openPlanRequestCount: _asInt(
          decoded['stats']?['open_plan_request_count'],
        ),
        lowStockCount: _asInt(decoded['stats']?['low_stock_count']),
      ),
      tasks: ((decoded['tasks'] ?? const <dynamic>[]) as List<dynamic>)
          .whereType<Map>()
          .map(
            (row) => WorkspacePulseTask(
              code: (row['code'] ?? '').toString(),
              priority: (row['priority'] ?? 'medium').toString(),
              tone: (row['tone'] ?? 'info').toString(),
              title: (row['title'] ?? '').toString(),
              body: (row['body'] ?? '').toString(),
              route: (row['route'] ?? '/history').toString(),
              ctaLabel: (row['cta_label'] ?? 'Open').toString(),
              count: _asInt(row['count']),
              metadata: row['metadata_json'] is Map
                  ? Map<String, dynamic>.from(row['metadata_json'] as Map)
                  : const <String, dynamic>{},
            ),
          )
          .toList(growable: false),
      anomalies: ((decoded['anomalies'] ?? const <dynamic>[]) as List<dynamic>)
          .whereType<Map>()
          .map(
            (row) => WorkspacePulseAnomaly(
              code: (row['code'] ?? '').toString(),
              severity: (row['severity'] ?? 'info').toString(),
              title: (row['title'] ?? '').toString(),
              body: (row['body'] ?? '').toString(),
              route: (row['route'] ?? '/history').toString(),
              ctaLabel: (row['cta_label'] ?? 'Open').toString(),
              metricValue: (row['metric_value'] ?? '').toString(),
              metadata: row['metadata_json'] is Map
                  ? Map<String, dynamic>.from(row['metadata_json'] as Map)
                  : const <String, dynamic>{},
            ),
          )
          .toList(growable: false),
    );
  }

  Future<List<WorkspacePulseSignal>> getWorkspacePulseSignals({
    required User user,
    required String shopId,
    String? status,
  }) async {
    final path = status == null || status.trim().isEmpty
        ? '/shops/$shopId/projections/pulse/signals/'
        : '/shops/$shopId/projections/pulse/signals/?status=${Uri.encodeQueryComponent(status.trim())}';
    final decoded = await _requestList(user: user, method: 'GET', path: path);
    return decoded
        .map(
          (row) => WorkspacePulseSignal(
            id: (row['id'] ?? '').toString(),
            signalKind: (row['signal_kind'] ?? '').toString(),
            code: (row['code'] ?? '').toString(),
            status: (row['status'] ?? 'open').toString(),
            signalLevel: (row['signal_level'] ?? '').toString(),
            signalRank: _asInt(row['signal_rank']),
            tone: (row['tone'] ?? '').toString(),
            title: (row['title'] ?? '').toString(),
            body: (row['body'] ?? '').toString(),
            route: (row['route'] ?? '/history').toString(),
            ctaLabel: (row['cta_label'] ?? 'Open').toString(),
            metricValue: (row['metric_value'] ?? '').toString(),
            count: _asInt(row['count']),
            firstDetectedAt: _asDateTime(row['first_detected_at']),
            lastDetectedAt: _asDateTime(row['last_detected_at']),
            lastSnapshotRefreshedAt: _asDateTime(
              row['last_snapshot_refreshed_at'],
            ),
            assignedMembershipId: _nullableText(row['assigned_membership_id']),
            assignedMemberName: _nullableText(row['assigned_member_name']),
            assignedMemberRole: _nullableText(row['assigned_member_role']),
            assignedAt: _asNullableDateTime(row['assigned_at']),
            assignedByName: _nullableText(row['assigned_by_name']),
            acknowledgedAt: _asNullableDateTime(row['acknowledged_at']),
            acknowledgedByName: _nullableText(row['acknowledged_by_name']),
            isEscalated: row['is_escalated'] == true,
            escalatedAt: _asNullableDateTime(row['escalated_at']),
            escalatedByName: _nullableText(row['escalated_by_name']),
            escalationNote: (row['escalation_note'] ?? '').toString(),
            followUpNote: (row['follow_up_note'] ?? '').toString(),
            resolvedAt: _asNullableDateTime(row['resolved_at']),
            resolvedByName: _nullableText(row['resolved_by_name']),
            resolutionNote: (row['resolution_note'] ?? '').toString(),
            metadata: row['metadata_json'] is Map
                ? Map<String, dynamic>.from(row['metadata_json'] as Map)
                : const <String, dynamic>{},
          ),
        )
        .toList(growable: false);
  }

  Future<WorkspacePulseSignal> updateWorkspacePulseSignal({
    required User user,
    required String shopId,
    required String signalId,
    required String action,
    String note = '',
    String? assigneeMembershipId,
  }) async {
    final decoded = await _request(
      user: user,
      method: 'PATCH',
      path: '/shops/$shopId/projections/pulse/signals/$signalId/',
      body: <String, dynamic>{
        'action': action,
        'note': note,
        if (assigneeMembershipId != null &&
            assigneeMembershipId.trim().isNotEmpty)
          'assignee_membership_id': assigneeMembershipId,
      },
    );

    return WorkspacePulseSignal(
      id: (decoded['id'] ?? '').toString(),
      signalKind: (decoded['signal_kind'] ?? '').toString(),
      code: (decoded['code'] ?? '').toString(),
      status: (decoded['status'] ?? 'open').toString(),
      signalLevel: (decoded['signal_level'] ?? '').toString(),
      signalRank: _asInt(decoded['signal_rank']),
      tone: (decoded['tone'] ?? '').toString(),
      title: (decoded['title'] ?? '').toString(),
      body: (decoded['body'] ?? '').toString(),
      route: (decoded['route'] ?? '/history').toString(),
      ctaLabel: (decoded['cta_label'] ?? 'Open').toString(),
      metricValue: (decoded['metric_value'] ?? '').toString(),
      count: _asInt(decoded['count']),
      firstDetectedAt: _asDateTime(decoded['first_detected_at']),
      lastDetectedAt: _asDateTime(decoded['last_detected_at']),
      lastSnapshotRefreshedAt: _asDateTime(
        decoded['last_snapshot_refreshed_at'],
      ),
      assignedMembershipId: _nullableText(decoded['assigned_membership_id']),
      assignedMemberName: _nullableText(decoded['assigned_member_name']),
      assignedMemberRole: _nullableText(decoded['assigned_member_role']),
      assignedAt: _asNullableDateTime(decoded['assigned_at']),
      assignedByName: _nullableText(decoded['assigned_by_name']),
      acknowledgedAt: _asNullableDateTime(decoded['acknowledged_at']),
      acknowledgedByName: _nullableText(decoded['acknowledged_by_name']),
      isEscalated: decoded['is_escalated'] == true,
      escalatedAt: _asNullableDateTime(decoded['escalated_at']),
      escalatedByName: _nullableText(decoded['escalated_by_name']),
      escalationNote: (decoded['escalation_note'] ?? '').toString(),
      followUpNote: (decoded['follow_up_note'] ?? '').toString(),
      resolvedAt: _asNullableDateTime(decoded['resolved_at']),
      resolvedByName: _nullableText(decoded['resolved_by_name']),
      resolutionNote: (decoded['resolution_note'] ?? '').toString(),
      metadata: decoded['metadata_json'] is Map
          ? Map<String, dynamic>.from(decoded['metadata_json'] as Map)
          : const <String, dynamic>{},
    );
  }

  Future<List<WorkspaceAccessSessionRecord>> getWorkspaceAccessSessions({
    required User user,
    required String shopId,
  }) async {
    final decoded = await _requestList(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/sessions/',
    );
    return decoded
        .map(
          (row) => WorkspaceAccessSessionRecord(
            id: (row['id'] ?? '').toString(),
            memberName: (row['member_name'] ?? '').toString(),
            memberEmail: (row['member_email'] ?? '').toString(),
            membershipRoleSnapshot: (row['membership_role_snapshot'] ?? 'staff')
                .toString(),
            roleLabel: (row['role_label'] ?? 'Staff').toString(),
            status: (row['status'] ?? 'active').toString(),
            deviceLabel: (row['device_label'] ?? '').toString(),
            platformName: (row['platform_name'] ?? '').toString(),
            packageName: (row['package_name'] ?? '').toString(),
            appVersion: (row['app_version'] ?? '').toString(),
            buildNumber: (row['build_number'] ?? '').toString(),
            releaseChannel: (row['release_channel'] ?? '').toString(),
            releaseTag: (row['release_tag'] ?? '').toString(),
            lastSeenAt: _asNullableDateTime(row['last_seen_at']),
            ipAddress: (row['ip_address'] ?? '').toString(),
            userAgent: (row['user_agent'] ?? '').toString(),
            revokedAt: _asNullableDateTime(row['revoked_at']),
            revokeReason: _nullableText(row['revoke_reason']),
            wipeRequested: row['wipe_requested'] == true,
            wipeRequestedAt: _asNullableDateTime(row['wipe_requested_at']),
            wipeAcknowledgedAt: _asNullableDateTime(
              row['wipe_acknowledged_at'],
            ),
            trustScore: _asInt(row['trust_score']),
            trustLevel: (row['trust_level'] ?? 'review').toString(),
            trustSummary: (row['trust_summary'] ?? '').toString(),
            trustReasons:
                ((row['trust_reasons'] ?? const <dynamic>[]) as List<dynamic>)
                    .map((item) => item.toString())
                    .where((item) => item.trim().isNotEmpty)
                    .toList(growable: false),
            metadata: row['metadata_json'] is Map
                ? Map<String, dynamic>.from(row['metadata_json'] as Map)
                : const <String, dynamic>{},
            canManage: row['can_manage'] == true,
            createdAt: _asDateTime(row['created_at']),
            updatedAt: _asDateTime(row['updated_at']),
          ),
        )
        .toList(growable: false);
  }

  Future<WorkspaceAccessSessionRecord> updateWorkspaceAccessSession({
    required User user,
    required String shopId,
    required String sessionId,
    required String action,
    String note = '',
  }) async {
    final decoded = await _request(
      user: user,
      method: 'PATCH',
      path: '/shops/$shopId/sessions/$sessionId/',
      body: <String, dynamic>{'action': action, 'note': note},
    );

    return WorkspaceAccessSessionRecord(
      id: (decoded['id'] ?? '').toString(),
      memberName: (decoded['member_name'] ?? '').toString(),
      memberEmail: (decoded['member_email'] ?? '').toString(),
      membershipRoleSnapshot: (decoded['membership_role_snapshot'] ?? 'staff')
          .toString(),
      roleLabel: (decoded['role_label'] ?? 'Staff').toString(),
      status: (decoded['status'] ?? 'active').toString(),
      deviceLabel: (decoded['device_label'] ?? '').toString(),
      platformName: (decoded['platform_name'] ?? '').toString(),
      packageName: (decoded['package_name'] ?? '').toString(),
      appVersion: (decoded['app_version'] ?? '').toString(),
      buildNumber: (decoded['build_number'] ?? '').toString(),
      releaseChannel: (decoded['release_channel'] ?? '').toString(),
      releaseTag: (decoded['release_tag'] ?? '').toString(),
      lastSeenAt: _asNullableDateTime(decoded['last_seen_at']),
      revokedAt: _asNullableDateTime(decoded['revoked_at']),
      revokeReason: _nullableText(decoded['revoke_reason']),
      wipeRequested: decoded['wipe_requested'] == true,
      wipeRequestedAt: _asNullableDateTime(decoded['wipe_requested_at']),
      wipeAcknowledgedAt: _asNullableDateTime(decoded['wipe_acknowledged_at']),
      trustScore: _asInt(decoded['trust_score']),
      trustLevel: (decoded['trust_level'] ?? 'review').toString(),
      trustSummary: (decoded['trust_summary'] ?? '').toString(),
      trustReasons:
          ((decoded['trust_reasons'] ?? const <dynamic>[]) as List<dynamic>)
              .map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList(growable: false),
      metadata: decoded['metadata_json'] is Map
          ? Map<String, dynamic>.from(decoded['metadata_json'] as Map)
          : const <String, dynamic>{},
      canManage: decoded['can_manage'] == true,
      createdAt: _asDateTime(decoded['created_at']),
      updatedAt: _asDateTime(decoded['updated_at']),
    );
  }

  Future<void> acknowledgeWorkspaceSessionWipe({
    required User user,
    required String shopId,
    required String sessionId,
  }) async {
    await _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/sessions/$sessionId/wipe-ack/',
    );
  }

  // ---------------------------------------------------------------------
  //  Stock transfers between the owner's shops
  // ---------------------------------------------------------------------

  /// Transfers touching this shop, in either direction.
  ///
  /// Returns the raw payload rather than a typed record because the counter
  /// screen needs the incoming/outgoing pending counts that sit alongside the
  /// list, and inventing a wrapper class for two integers earns nothing.
  Future<Map<String, dynamic>> fetchStockTransfers({
    required User user,
    required String shopId,
  }) async {
    return _request(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/inventory/transfers/',
    );
  }

  /// Send stock to another shop. The stock leaves immediately; it only
  /// arrives once the destination confirms.
  Future<Map<String, dynamic>> dispatchStockTransfer({
    required User user,
    required String shopId,
    required String destinationShopId,
    required List<Map<String, dynamic>> lines,
    String note = '',
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/inventory/transfers/',
      body: <String, dynamic>{
        'destination_shop_id': destinationShopId,
        'lines': lines,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }

  /// Confirm a delivery arrived. [shopId] must be the destination.
  Future<Map<String, dynamic>> receiveStockTransfer({
    required User user,
    required String shopId,
    required String transferId,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/inventory/transfers/$transferId/receive/',
    );
  }

  /// Call off a transfer that never left. [shopId] must be the source.
  Future<Map<String, dynamic>> cancelStockTransfer({
    required User user,
    required String shopId,
    required String transferId,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/inventory/transfers/$transferId/cancel/',
    );
  }

  /// The day's Roj Mel: money in on one side, credit given on the other.
  ///
  /// [date] is an ISO date; omitted means today in the shop's own timezone,
  /// which is the server's job to know rather than the phone's.
  Future<Map<String, dynamic>> fetchDayBook({
    required User user,
    required String shopId,
    String date = '',
  }) async {
    final suffix = date.trim().isEmpty ? '' : '?date=${date.trim()}';
    return _request(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/reports/day-book/$suffix',
    );
  }

  // ---------------------------------------------------------------------
  //  Notifications
  // ---------------------------------------------------------------------

  /// The alert feed for the signed-in user.
  ///
  /// User-scoped rather than shop-scoped on the server, with the shop as a
  /// filter, because one person can hold memberships in several shops and the
  /// 09:00 stock alert is addressed to them rather than to a shop.
  Future<List<Map<String, dynamic>>> fetchNotifications({
    required User user,
    required String shopId,
  }) async {
    return _requestList(
      user: user,
      method: 'GET',
      path: '/notifications/?shop_id=$shopId',
    );
  }

  Future<void> markNotificationRead({
    required User user,
    required String notificationId,
  }) async {
    await _request(
      user: user,
      method: 'POST',
      path: '/notifications/$notificationId/read/',
    );
  }

  Future<int> markAllNotificationsRead({
    required User user,
    required String shopId,
  }) async {
    final decoded = await _request(
      user: user,
      method: 'POST',
      path: '/notifications/read-all/',
      body: <String, dynamic>{'shop_id': shopId},
    );
    return _asInt(decoded['updated_count']);
  }

  // ---------------------------------------------------------------------
  //  Stocktakes
  // ---------------------------------------------------------------------

  /// Counts for this shop, newest first. At most one is open.
  Future<Map<String, dynamic>> fetchStocktakes({
    required User user,
    required String shopId,
  }) async {
    return _request(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/inventory/stocktakes/',
    );
  }

  /// Begin a count. The server refuses a second open one, because two counts
  /// measuring against the same books would double every correction.
  Future<Map<String, dynamic>> startStocktake({
    required User user,
    required String shopId,
    String note = '',
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/inventory/stocktakes/',
      body: <String, dynamic>{if (note.trim().isNotEmpty) 'note': note.trim()},
    );
  }

  /// Record what is on the shelf for one item. Counting the same item again
  /// replaces the earlier figure rather than adding to it.
  Future<Map<String, dynamic>> recordStocktakeCount({
    required User user,
    required String shopId,
    required String stocktakeId,
    required String itemId,
    required String countedQuantity,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/inventory/stocktakes/$stocktakeId/count/',
      body: <String, dynamic>{
        'item_id': itemId,
        'counted_quantity': countedQuantity,
      },
    );
  }

  /// Post the corrections and close the count. Manager or above.
  Future<Map<String, dynamic>> applyStocktake({
    required User user,
    required String shopId,
    required String stocktakeId,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/inventory/stocktakes/$stocktakeId/apply/',
    );
  }

  /// Abandon a count without touching stock.
  Future<Map<String, dynamic>> cancelStocktake({
    required User user,
    required String shopId,
    required String stocktakeId,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/inventory/stocktakes/$stocktakeId/cancel/',
    );
  }

  // ---------------------------------------------------------------------
  //  Purchase orders
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> fetchPurchaseOrders({
    required User user,
    required String shopId,
    bool openOnly = false,
  }) async {
    return _request(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/purchase-orders/${openOnly ? '?open=1' : ''}',
    );
  }

  Future<Map<String, dynamic>> createPurchaseOrder({
    required User user,
    required String shopId,
    required List<Map<String, dynamic>> lines,
    String? supplierId,
    String? expectedDate,
    String note = '',
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/purchase-orders/',
      body: <String, dynamic>{
        'lines': lines,
        if (supplierId != null && supplierId.isNotEmpty)
          'supplier_id': supplierId,
        if (expectedDate != null && expectedDate.isNotEmpty)
          'expected_date': expectedDate,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }

  /// Book in what actually arrived. Partial is the normal case.
  Future<Map<String, dynamic>> receivePurchaseOrder({
    required User user,
    required String shopId,
    required String orderId,
    required List<Map<String, dynamic>> lines,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/purchase-orders/$orderId/receive/',
      body: <String, dynamic>{'lines': lines},
    );
  }

  Future<Map<String, dynamic>> cancelPurchaseOrder({
    required User user,
    required String shopId,
    required String orderId,
  }) async {
    return _request(
      user: user,
      method: 'DELETE',
      path: '/shops/$shopId/purchase-orders/$orderId/',
    );
  }

  Future<List<Map<String, dynamic>>> fetchSuppliers({
    required User user,
    required String shopId,
  }) async {
    return _requestList(
      user: user,
      method: 'GET',
      path: '/shops/$shopId/suppliers/',
    );
  }

  // ---------------------------------------------------------------------
  //  Customer khata statement links
  // ---------------------------------------------------------------------

  /// Mint a private statement link for one customer, retiring any earlier one.
  ///
  /// The plaintext token comes back exactly once and is never stored, so the
  /// caller must use it immediately or ask for a new one.
  Future<Map<String, dynamic>> createCustomerStatementLink({
    required User user,
    required String shopId,
    required String customerId,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/customers/$customerId/statement-link/',
    );
  }

  /// Gateway/unavailable statuses that mean "the server is waking up or
  /// redeploying" on a free-tier host — worth waiting for and retrying rather
  /// than surfacing as a failure (which used to make writes silently fall back
  /// to local and then be lost).
  static const Set<int> _coldStartStatuses = <int>{502, 503, 504};

  /// How many pages one list walk may fetch. 25 x 200 rows is 5,000
  /// products - past any single shop this app is built for, and short
  /// enough that a server looping on its own cursor stops being a phone
  /// stuck downloading on mobile data.
  static const int _maxListPages = 25;

  static const int _maxAttempts = 5;

  Future<Map<String, dynamic>> _request({
    required User user,
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    if (baseUrl.trim().isEmpty) {
      throw BackendApiException(
        'BUSINESS_HUB_API_BASE_URL is not configured for Flutter mobile.',
      );
    }

    // One refresh attempt per call. A second 401 after refreshing means the
    // session is genuinely gone, and retrying again would loop.
    var refreshed = false;
    String? freshToken;

    for (var attempt = 1; ; attempt++) {
      final client = HttpClient();
      client.connectionTimeout = _requestTimeout;
      try {
        final url = Uri.parse('${baseUrl.replaceAll(RegExp(r"/$"), "")}$path');
        final request = await client
            .openUrl(method, url)
            .timeout(_requestTimeout);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        await _attachAuthHeaders(request, user, overrideToken: freshToken);
        if (body != null) {
          request.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json',
          );
          // Encode first and set contentLength explicitly. A bare
          // request.write() leaves it at -1, which makes dart:io fall back to
          // Transfer-Encoding: chunked - and plenty of things upstream cannot
          // read a chunked request body (Django's dev server drops it entirely,
          // and some proxies/WAFs reject it), so the server sees an empty body
          // and answers "this field is required" for every field we sent.
          final encoded = utf8.encode(jsonEncode(body));
          request.contentLength = encoded.length;
          request.add(encoded);
        }

        final response = await request.close().timeout(_requestTimeout);
        final bodyText = await utf8
            .decodeStream(response)
            .timeout(_requestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          // The free-tier host returns 502/503/504 while cold-starting or
          // redeploying — wait and retry so a sleeping server doesn't lose the
          // write or fail the login.
          if (_coldStartStatuses.contains(response.statusCode) &&
              attempt < _maxAttempts) {
            await Future<void>.delayed(Duration(seconds: 5 * attempt));
            continue;
          }
          // The access token expired, or was withdrawn. Trade the refresh
          // token for a new one and try the same request once more, so the
          // shopkeeper never sees a login screen mid-sale.
          if (response.statusCode == 401 && !refreshed) {
            refreshed = true;
            final renewed = await _refreshOnce();
            if (renewed != null && renewed.isNotEmpty) {
              freshToken = renewed;
              continue;
            }
          }
          throw BackendApiException(
            'Backend request failed (${response.statusCode}) for $path: $bodyText',
            statusCode: response.statusCode,
          );
        }

        if (bodyText.trim().isEmpty) {
          return <String, dynamic>{};
        }
        return Map<String, dynamic>.from(
          jsonDecode(bodyText) as Map<String, dynamic>,
        );
      } on TimeoutException {
        if (attempt < _maxAttempts) {
          await Future<void>.delayed(Duration(seconds: 3 * attempt));
          continue;
        }
        throw BackendApiException(
          'Backend request timed out for $path. Check connectivity or backend load.',
        );
      } finally {
        client.close(force: true);
      }
    }
  }

  /// One product's photo, as bytes, or null when there is none.
  ///
  /// Photos used to arrive inside the inventory list as base64 on every row,
  /// so one sync pulled every picture in the shop whether it had changed or
  /// not. They have their own address now. A missing picture is an ordinary
  /// answer here, not a failure - a product without one is normal - so this
  /// returns null rather than throwing, and a sync is never failed by it.
  Future<({List<int> bytes, String? contentType})?> fetchInventoryImage({
    required User user,
    required String shopId,
    required String itemId,
  }) async {
    if (baseUrl.trim().isEmpty) return null;

    final client = HttpClient();
    client.connectionTimeout = _requestTimeout;
    try {
      final url = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r"/$"), "")}'
        '/shops/$shopId/inventory/$itemId/image/',
      );
      final request = await client.openUrl('GET', url).timeout(_requestTimeout);
      await _attachAuthHeaders(request, user);

      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // 404 is the common case: the product simply has no photo.
        await response.drain<void>();
        return null;
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_requestTimeout)) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) return null;
      return (
        bytes: bytes,
        contentType: response.headers.contentType?.mimeType,
      );
    } catch (_) {
      // A picture is never worth failing a sync over. The product still
      // arrives; it shows its initial instead.
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Map<String, dynamic>>> _requestList({
    required User user,
    required String method,
    required String path,
  }) async {
    final page = await _requestListPage(user: user, method: method, path: path);
    return page.rows;
  }

  Future<_ListPage> _requestListPage({
    required User user,
    required String method,
    required String path,
  }) async {
    if (baseUrl.trim().isEmpty) {
      throw BackendApiException(
        'BUSINESS_HUB_API_BASE_URL is not configured for Flutter mobile.',
      );
    }

    // One refresh attempt per call. A second 401 after refreshing means the
    // session is genuinely gone, and retrying again would loop.
    var refreshed = false;
    String? freshToken;

    for (var attempt = 1; ; attempt++) {
      final client = HttpClient();
      client.connectionTimeout = _requestTimeout;
      try {
        final url = Uri.parse('${baseUrl.replaceAll(RegExp(r"/$"), "")}$path');
        final request = await client
            .openUrl(method, url)
            .timeout(_requestTimeout);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        await _attachAuthHeaders(request, user, overrideToken: freshToken);

        final response = await request.close().timeout(_requestTimeout);
        final bodyText = await utf8
            .decodeStream(response)
            .timeout(_requestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (_coldStartStatuses.contains(response.statusCode) &&
              attempt < _maxAttempts) {
            await Future<void>.delayed(Duration(seconds: 5 * attempt));
            continue;
          }
          // Same one-shot refresh as _request: the token expired or was
          // withdrawn, so renew it and repeat the call rather than surfacing a
          // sign-out to somebody mid-sale.
          if (response.statusCode == 401 && !refreshed) {
            refreshed = true;
            final renewed = await _refreshOnce();
            if (renewed != null && renewed.isNotEmpty) {
              freshToken = renewed;
              continue;
            }
          }
          throw BackendApiException(
            'Backend request failed (${response.statusCode}) for $path: $bodyText',
            statusCode: response.statusCode,
          );
        }

        if (bodyText.trim().isEmpty) {
          return const _ListPage(<Map<String, dynamic>>[], null);
        }

        final decoded = jsonDecode(bodyText);
        if (decoded is! List) {
          throw BackendApiException(
            'Backend request for $path did not return a list payload.',
          );
        }
        final rows = decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        final cursor = response.headers.value('x-next-cursor');
        return _ListPage(
          rows,
          (cursor == null || cursor.trim().isEmpty) ? null : cursor.trim(),
        );
      } on TimeoutException {
        if (attempt < _maxAttempts) {
          await Future<void>.delayed(Duration(seconds: 3 * attempt));
          continue;
        }
        throw BackendApiException(
          'Backend request timed out for $path. Check connectivity or backend load.',
        );
      } finally {
        client.close(force: true);
      }
    }
  }

  /// Exchange email + password for a JWT pair. Unauthenticated.
  Future<Map<String, String>> obtainToken({
    required String email,
    required String password,
  }) async {
    final decoded = await _postUnauthenticated(
      '/session/token/',
      <String, dynamic>{'email': email, 'password': password},
    );
    return <String, String>{
      'access': (decoded['access'] ?? '').toString(),
      'refresh': (decoded['refresh'] ?? '').toString(),
    };
  }

  /// Register a new owner + shop. Unauthenticated. Returns the JWT pair plus
  /// the newly-provisioned shop, so the caller is signed in immediately.
  Future<Map<String, dynamic>> register({
    required String ownerName,
    required String email,
    required String password,
    required String businessName,
    String mobile = '',
    String businessType = 'retail',
    String stateCode = '',
    String gstin = '',
    String planTier = 'starter',
  }) async {
    return _postUnauthenticated('/register/', <String, dynamic>{
      'owner_name': ownerName,
      'email': email,
      'password': password,
      'business_name': businessName,
      'mobile': mobile,
      'business_type': businessType,
      'state_code': stateCode,
      'gstin': gstin,
      'plan_tier': planTier,
    });
  }

  /// Accept a shop invitation with a code. Unauthenticated. Creates/links the
  /// user and returns a JWT pair + shop, so the invitee is signed straight in.
  Future<Map<String, dynamic>> acceptInvite({
    required String token,
    required String name,
    required String password,
  }) async {
    return _postUnauthenticated('/invites/accept/', <String, dynamic>{
      'token': token,
      'name': name,
      'password': password,
    });
  }

  /// Send a shop invitation (owner/manager). Authenticated.
  Future<Map<String, dynamic>> createInvite({
    required User user,
    required String shopId,
    required String email,
    required String role,
  }) async {
    return _request(
      user: user,
      method: 'POST',
      path: '/shops/$shopId/invites/',
      body: <String, dynamic>{'email': email, 'role': role},
    );
  }

  /// Exchange a refresh token for a fresh access token.
  Future<String> refreshAccessToken(String refresh) async {
    final decoded = await _postUnauthenticated(
      '/session/token/refresh/',
      <String, dynamic>{'refresh': refresh},
    );
    return (decoded['access'] ?? '').toString();
  }

  /// Swap the stored refresh token for a new pair, or null if that is not
  /// possible. Never throws: a failed refresh must surface as the original
  /// 401, not as a different error from a recovery attempt.
  Future<String?> _refreshOnce() {
    final existing = _inFlightRefresh;
    if (existing != null) return existing;
    final started = _performRefresh();
    _inFlightRefresh = started;
    return started.whenComplete(() {
      _inFlightRefresh = null;
    });
  }

  Future<String?> _performRefresh() async {
    final read = readRefreshToken;
    if (read == null) return null;
    try {
      final refresh = (await read())?.trim() ?? '';
      if (refresh.isEmpty) return null;
      final decoded = await _postUnauthenticated(
        '/session/token/refresh/',
        <String, dynamic>{'refresh': refresh},
      );
      final access = (decoded['access'] ?? '').toString();
      if (access.isEmpty) return null;
      await onTokensRefreshed?.call(
        access,
        (decoded['refresh'] ?? refresh).toString(),
      );
      return access;
    } catch (_) {
      // The refresh token is expired, or the session was signed out on the
      // server. Either way there is no way back in from here — the heartbeat
      // in the sync coordinator owns signing the app out.
      return null;
    }
  }

  /// POST without auth headers, with a long timeout: a free-tier backend can
  /// cold-start slowly (30-50s), which the normal short timeout would abort.
  Future<Map<String, dynamic>> _postUnauthenticated(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (baseUrl.trim().isEmpty) {
      throw BackendApiException('Backend URL is not configured.');
    }
    const authTimeout = Duration(seconds: 60);
    for (var attempt = 1; ; attempt++) {
      final client = HttpClient();
      client.connectionTimeout = authTimeout;
      try {
        final url = Uri.parse('${baseUrl.replaceAll(RegExp(r"/$"), "")}$path');
        final request = await client.postUrl(url).timeout(authTimeout);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        // Explicit Content-Length (never chunked) - some servers drop chunked bodies.
        final encoded = utf8.encode(jsonEncode(body));
        request.contentLength = encoded.length;
        request.add(encoded);
        final response = await request.close().timeout(authTimeout);
        final text = await utf8.decodeStream(response).timeout(authTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          // Wait out a waking / redeploying free-tier server instead of
          // failing the login or register with a 503.
          if (_coldStartStatuses.contains(response.statusCode) &&
              attempt < _maxAttempts) {
            await Future<void>.delayed(Duration(seconds: 5 * attempt));
            continue;
          }
          // No refresh retry here on purpose: this method performs the
          // refresh exchange itself, so a 401 means the refresh token is dead.
          throw BackendApiException(
            _firstErrorMessage(text, response.statusCode),
            statusCode: response.statusCode,
          );
        }
        return Map<String, dynamic>.from(
          jsonDecode(text) as Map<String, dynamic>,
        );
      } on TimeoutException {
        if (attempt < _maxAttempts) {
          await Future<void>.delayed(Duration(seconds: 3 * attempt));
          continue;
        }
        throw BackendApiException(
          'Request timed out. The server may be waking up - please try again.',
        );
      } finally {
        client.close(force: true);
      }
    }
  }

  /// Extract a human-readable message from a DRF error body. DRF returns either
  /// {"field": ["message", ...]} or {"detail": "message"}; fall back to a
  /// status-based message so the user never sees a raw JSON blob.
  String _firstErrorMessage(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
        for (final value in decoded.values) {
          if (value is List && value.isNotEmpty) return value.first.toString();
          if (value is String && value.isNotEmpty) return value;
        }
      }
    } catch (_) {
      // fall through to the generic message
    }
    if (statusCode == 401) return 'Invalid email or password.';
    return 'Request failed ($statusCode). Please try again.';
  }

  Future<void> _attachAuthHeaders(
    HttpClientRequest request,
    User user, {
    String? overrideToken,
  }) async {
    // On a retry after refreshing, the in-memory User still holds the token
    // that just failed, so the fresh one has to be passed in explicitly.
    final token = overrideToken ?? await user.getIdToken();
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      return;
    }

    if (MobileRuntimeConfig.backendAuthMode == 'dev_header') {
      request.headers.set('X-Dev-User-Email', user.email);
      request.headers.set('X-Dev-User-Name', user.displayName);
      request.headers.set('X-Dev-Platform-Admin', 'true');
      return;
    }

    throw BackendApiException(
      'Missing Business Hub auth token for backend request.',
    );
  }

  BackendCustomerSummary _mapCustomerSummary(Map<String, dynamic> row) {
    return BackendCustomerSummary(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? 'Unnamed customer').toString(),
      loyaltyPoints: _asInt(row['loyalty_points']),
      phone: _nullableText(row['phone']),
      email: _nullableText(row['email']),
      totalSpent: _asDouble(row['total_spent']),
      balance: _asDouble(row['balance']),
      status: (row['status'] ?? 'active').toString(),
      notes: _nullableText(row['notes']),
    );
  }

  WorkspaceTeamMemberRecord _mapWorkspaceTeamMember(Map<String, dynamic> row) {
    return WorkspaceTeamMemberRecord(
      id: (row['id'] ?? '').toString(),
      memberName: (row['member_name'] ?? 'Workspace member').toString(),
      memberEmail: (row['member_email'] ?? '').toString(),
      phone: (row['phone'] ?? '').toString(),
      role: (row['role'] ?? 'staff').toString(),
      roleLabel: (row['role_label'] ?? 'Staff').toString(),
      roleSummary: (row['role_summary'] ?? '').toString(),
      roleProfile: (row['role_profile'] ?? '').toString(),
      status: (row['status'] ?? 'active').toString(),
      permissionsVersion: _asInt(row['permissions_version']),
      permissions: row['permissions_json'] is Map
          ? Map<String, dynamic>.from(row['permissions_json'] as Map)
          : const <String, dynamic>{},
      isCurrentUser: row['is_current_user'] == true,
      canManage: row['can_manage'] == true,
      createdAt: _asDateTime(row['created_at']),
      updatedAt: _asDateTime(row['updated_at']),
      inviteCode: (row['invite_code'] ?? '').toString(),
      inviteLink: (row['invite_link'] ?? '').toString(),
    );
  }

  AttendanceSessionRecord _mapAttendanceSession(Map<String, dynamic> row) {
    return AttendanceSessionRecord(
      id: (row['id'] ?? '').toString(),
      membershipId: (row['membership_id'] ?? '').toString(),
      memberName: (row['member_name'] ?? 'Team member').toString(),
      memberRole: (row['member_role'] ?? 'staff').toString(),
      sessionDate: _asDateTime(row['session_date']),
      clockInAt: _asNullableDateTime(row['clock_in_at']),
      clockOutAt: _asNullableDateTime(row['clock_out_at']),
      status: (row['status'] ?? 'ABSENT').toString(),
      totalHours: row['total_hours'] == null
          ? null
          : _asDouble(row['total_hours']),
      overtimeHours: _asDouble(row['overtime_hours']),
      bonusAmount: _asDouble(row['bonus_amount']),
      note: (row['note'] ?? '').toString(),
      tombstone: row['tombstone'] == true,
    );
  }

  ExpenseRecord _mapExpense(Map<String, dynamic> row) {
    return ExpenseRecord(
      id: (row['id'] ?? '').toString(),
      category: (row['category'] ?? 'Expense').toString(),
      amount: _asDouble(row['amount']),
      description: (row['description'] ?? '').toString(),
      paymentMethod: (row['payment_method'] ?? 'CASH').toString(),
      paymentReference: (row['payment_reference'] ?? '').toString(),
      expenseDate: _asDateTime(row['expense_date']),
      actorName: _nullableText(row['actor_name']),
      tombstone: row['tombstone'] == true,
    );
  }

  PurchaseRecord _mapPurchase(Map<String, dynamic> row) {
    return PurchaseRecord(
      id: (row['id'] ?? '').toString(),
      supplierName: (row['supplier_name'] ?? 'Unnamed supplier').toString(),
      // The server keeps the phone on the Supplier record, not the purchase.
      supplierPhone: (row['supplier_phone'] ?? '').toString(),
      reference: (row['reference'] ?? row['invoice_number'] ?? '').toString(),
      total: _asDouble(row['total_amount'] ?? row['total']),
      amountPaid: _asDouble(row['amount_paid']),
      paymentMethod: (row['payment_mode'] ?? 'CASH').toString(),
      notes: (row['note'] ?? '').toString(),
      purchaseDate: _asDateTime(row['purchase_date']),
      actorName: _nullableText(row['actor_name']),
      tombstone: row['tombstone'] == true,
    );
  }

  UserMfaStatus _mapUserMfaStatus(Map<String, dynamic> row) {
    return UserMfaStatus(
      totpEnabled: row['totp_enabled'] == true,
      totpPendingEnrollment: row['totp_pending_enrollment'] == true,
      enabledAt: _asNullableDateTime(row['enabled_at']),
      lastVerifiedAt: _asNullableDateTime(row['last_verified_at']),
      issuerLabel: (row['issuer_label'] ?? 'Business Hub').toString(),
      accountLabel: (row['account_label'] ?? '').toString(),
      challengeWindowSeconds: row['challenge_window_seconds'] is num
          ? (row['challenge_window_seconds'] as num).toInt()
          : int.tryParse('${row['challenge_window_seconds']}') ?? 0,
      pendingManualSecret: (row['pending_manual_secret'] ?? '').toString(),
      pendingOtpauthUri: (row['pending_otpauth_uri'] ?? '').toString(),
    );
  }
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

DateTime _asDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
  }
  return DateTime.now();
}

DateTime? _asNullableDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

String? _nullableText(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

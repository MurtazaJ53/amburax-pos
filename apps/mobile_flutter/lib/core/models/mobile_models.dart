class ShopInfo {
  const ShopInfo({
    required this.name,
    required this.tagline,
    required this.footer,
    required this.currency,
    required this.phone,
    this.gstin = '',
    this.upiVpa = '',
    this.planTier = 'growth',
    this.enabledFeatures = const <String, bool>{},
  });

  final String name;
  final String tagline;
  final String footer;
  final String currency;
  final String phone;
  final String gstin;

  /// Merchant UPI ID (e.g. `shop@okhdfcbank`) used to build the POS collect-QR
  /// with the exact bill amount. Set once by the owner in Business settings.
  final String upiVpa;
  final String planTier;
  final Map<String, bool> enabledFeatures;

  bool get hasGstin => gstin.trim().isNotEmpty;
  bool get hasUpi => upiVpa.trim().isNotEmpty;

  String get normalizedPlanTier => _normalizePlanTier(planTier);
  String get planLabel {
    switch (normalizedPlanTier) {
      case 'starter':
        return 'Starter';
      case 'pro':
        return 'Pro';
      default:
        return 'Growth';
    }
  }

  bool get supportsExpenses =>
      enabledFeatures['expenses'] ?? normalizedPlanTier != 'starter';
  bool get supportsAttendance =>
      enabledFeatures['attendance'] ?? normalizedPlanTier != 'starter';
  bool get supportsAdvancedReports =>
      enabledFeatures['advanced_reports'] ?? normalizedPlanTier == 'pro';
  bool get supportsFinanceSummary =>
      enabledFeatures['finance_summary'] ?? normalizedPlanTier == 'pro';
  bool get supportsSupplierDirectory =>
      enabledFeatures['supplier_directory'] ?? normalizedPlanTier != 'starter';
  bool get supportsPurchaseWorkflow =>
      enabledFeatures['purchase_workflow'] ?? normalizedPlanTier == 'pro';
  bool get supportsAdvancedOps =>
      enabledFeatures['advanced_ops'] ?? normalizedPlanTier == 'pro';

  factory ShopInfo.fallback() {
    return const ShopInfo(
      name: 'Business Hub Pro',
      tagline: 'ZARRA ECOSYSTEM',
      footer: 'Thank you for your business!',
      currency: 'INR',
      phone: '',
      planTier: 'growth',
      enabledFeatures: <String, bool>{
        'expenses': true,
        'attendance': true,
        'advanced_reports': false,
        'finance_summary': false,
        'advanced_ops': false,
      },
    );
  }
}

class ShopMembershipAccessRecord {
  const ShopMembershipAccessRecord({
    required this.id,
    required this.role,
    required this.roleLabel,
    required this.roleSummary,
    required this.roleProfile,
    required this.status,
    required this.shopId,
    required this.shopName,
    required this.shopSlug,
    required this.shopCurrencyCode,
    required this.shopTimezone,
    required this.shopPlanTier,
    required this.shopEnabledFeatures,
    this.shopPhone = '',
    this.permissions = const <String, dynamic>{},
    this.permissionsVersion = 1,
  });

  final String id;
  final String role;
  final String roleLabel;
  final String roleSummary;
  final String roleProfile;
  final String status;
  final String shopId;
  final String shopName;
  final String shopSlug;
  final String shopCurrencyCode;
  final String shopTimezone;
  final String shopPlanTier;
  final Map<String, bool> shopEnabledFeatures;
  final String shopPhone;
  // Per-member custom permission overrides ({module: {action: bool}}).
  final Map<String, dynamic> permissions;
  final int permissionsVersion;

  bool get isActive => status == 'active';
}

class WorkspaceTeamMemberRecord {
  const WorkspaceTeamMemberRecord({
    required this.id,
    required this.memberName,
    required this.memberEmail,
    required this.phone,
    required this.role,
    required this.roleLabel,
    required this.roleSummary,
    required this.roleProfile,
    required this.status,
    required this.permissionsVersion,
    required this.permissions,
    required this.isCurrentUser,
    required this.canManage,
    required this.createdAt,
    required this.updatedAt,
    this.inviteCode = '',
    this.inviteLink = '',
  });

  final String id;
  final String memberName;
  final String memberEmail;
  final String phone;
  final String role;
  final String roleLabel;
  final String roleSummary;
  final String roleProfile;
  final String status;
  final int permissionsVersion;
  final Map<String, dynamic> permissions;
  final bool isCurrentUser;
  final bool canManage;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Single-use invite token minted when a new member is added, and the
  /// shareable deep link that wraps it. Empty for existing/listed members.
  final String inviteCode;
  final String inviteLink;

  bool get hasInvite => inviteCode.isNotEmpty;
}

class AttendanceSummarySnapshot {
  const AttendanceSummarySnapshot({
    required this.totalSessions,
    required this.presentCount,
    required this.leaveCount,
    required this.activeWorkersToday,
  });

  final int totalSessions;
  final int presentCount;
  final int leaveCount;
  final int activeWorkersToday;
}

class AttendanceSessionRecord {
  const AttendanceSessionRecord({
    required this.id,
    required this.membershipId,
    required this.memberName,
    required this.memberRole,
    required this.sessionDate,
    required this.clockInAt,
    required this.clockOutAt,
    required this.status,
    required this.totalHours,
    required this.overtimeHours,
    required this.bonusAmount,
    required this.note,
    required this.tombstone,
  });

  final String id;
  final String membershipId;
  final String memberName;
  final String memberRole;
  final DateTime sessionDate;
  final DateTime? clockInAt;
  final DateTime? clockOutAt;
  final String status;
  final double? totalHours;
  final double overtimeHours;
  final double bonusAmount;
  final String note;
  final bool tombstone;
}

class ExpenseSummarySnapshot {
  const ExpenseSummarySnapshot({
    required this.totalEntries,
    required this.totalAmount,
    required this.uniqueCategories,
    required this.biggestCategory,
  });

  final int totalEntries;
  final double totalAmount;
  final int uniqueCategories;
  final String? biggestCategory;
}

class ExpenseRecord {
  const ExpenseRecord({
    required this.id,
    required this.category,
    required this.amount,
    required this.description,
    required this.paymentMethod,
    required this.paymentReference,
    required this.expenseDate,
    required this.actorName,
    required this.tombstone,
  });

  final String id;
  final String category;
  final double amount;
  final String description;
  final String paymentMethod;
  final String paymentReference;
  final DateTime expenseDate;
  final String? actorName;
  final bool tombstone;
}

/// End-of-day Z-report figures for a single business day.
class ZReportSnapshot {
  const ZReportSnapshot({
    required this.salesCount,
    required this.grossSales,
    required this.discountTotal,
    required this.taxCollected,
    required this.collected,
    required this.due,
    required this.tenderBreakdown,
    this.firstBillAt,
    this.lastBillAt,
  });

  final int salesCount;
  final double grossSales;
  final double discountTotal;
  final double taxCollected;
  final double collected;
  final double due;

  /// Amount received per tender type (CASH / UPI / CARD / ...), from the actual
  /// payment splits — so a split-tender bill is counted correctly.
  final Map<String, double> tenderBreakdown;
  final DateTime? firstBillAt;
  final DateTime? lastBillAt;

  double get cashCollected => tenderBreakdown['CASH'] ?? 0;

  static const ZReportSnapshot empty = ZReportSnapshot(
    salesCount: 0,
    grossSales: 0,
    discountTotal: 0,
    taxCollected: 0,
    collected: 0,
    due: 0,
    tenderBreakdown: <String, double>{},
  );
}

/// A sale reduced to just what a P&L needs. Built from stored sale rows.
class ReportSaleLine {
  const ReportSaleLine({
    required this.name,
    required this.quantity,
    required this.price,
    this.costPrice,
    this.gstRate = 0,
    this.priceIncludesTax = true,
  });

  final String name;
  final double quantity;
  final double price;
  final double? costPrice;
  final double gstRate;
  final bool priceIncludesTax;
}

class ReportSale {
  const ReportSale({
    required this.total,
    required this.lines,
    this.customerName,
  });

  final double total;
  final List<ReportSaleLine> lines;
  final String? customerName;
}

class TopProduct {
  const TopProduct({
    required this.name,
    required this.quantity,
    required this.revenue,
  });
  final String name;
  final double quantity;
  final double revenue;
}

class TopSpender {
  const TopSpender({
    required this.name,
    required this.orders,
    required this.spend,
  });
  final String name;
  final int orders;
  final double spend;
}

/// Profit & loss for a period: Gross sales − COGS − Expenses = Net profit,
/// plus GST collected and the leaderboards.
class ProfitLossSnapshot {
  const ProfitLossSnapshot({
    required this.grossSales,
    required this.cogs,
    required this.expenses,
    required this.gstCollected,
    required this.orderCount,
    required this.topProducts,
    required this.topCustomers,
  });

  final double grossSales;
  final double cogs;
  final double expenses;
  final double gstCollected;
  final int orderCount;
  final List<TopProduct> topProducts;
  final List<TopSpender> topCustomers;

  double get grossProfit => grossSales - cogs;
  double get netProfit => grossSales - cogs - expenses;
  double get marginPct => grossSales <= 0 ? 0 : (grossProfit / grossSales) * 100;

  static const ProfitLossSnapshot empty = ProfitLossSnapshot(
    grossSales: 0,
    cogs: 0,
    expenses: 0,
    gstCollected: 0,
    orderCount: 0,
    topProducts: <TopProduct>[],
    topCustomers: <TopSpender>[],
  );
}

/// Pure aggregation: fold sales + total expenses into a [ProfitLossSnapshot].
/// Kept free of Drift/JSON so it is unit-testable.
ProfitLossSnapshot computeProfitAndLoss({
  required List<ReportSale> sales,
  required double expenses,
  int topN = 5,
}) {
  var grossSales = 0.0;
  var cogs = 0.0;
  var gst = 0.0;
  final productQty = <String, double>{};
  final productRevenue = <String, double>{};
  final customerSpend = <String, double>{};
  final customerOrders = <String, int>{};

  for (final sale in sales) {
    grossSales += sale.total;
    for (final line in sale.lines) {
      final lineTotal = line.price * line.quantity;
      cogs += (line.costPrice ?? 0) * line.quantity;
      final rate = line.gstRate;
      if (rate > 0) {
        gst += line.priceIncludesTax
            ? lineTotal * rate / (100 + rate)
            : lineTotal * rate / 100;
      }
      productQty[line.name] = (productQty[line.name] ?? 0) + line.quantity;
      productRevenue[line.name] =
          (productRevenue[line.name] ?? 0) + lineTotal;
    }
    final customer = sale.customerName?.trim();
    if (customer != null && customer.isNotEmpty) {
      customerSpend[customer] = (customerSpend[customer] ?? 0) + sale.total;
      customerOrders[customer] = (customerOrders[customer] ?? 0) + 1;
    }
  }

  final topProducts =
      productRevenue.entries
          .map(
            (e) => TopProduct(
              name: e.key,
              quantity: productQty[e.key] ?? 0.0,
              revenue: e.value,
            ),
          )
          .toList()
        ..sort((a, b) => b.revenue.compareTo(a.revenue));
  final topCustomers =
      customerSpend.entries
          .map(
            (e) => TopSpender(
              name: e.key,
              orders: customerOrders[e.key] ?? 0,
              spend: e.value,
            ),
          )
          .toList()
        ..sort((a, b) => b.spend.compareTo(a.spend));

  return ProfitLossSnapshot(
    grossSales: grossSales,
    cogs: cogs,
    expenses: expenses,
    gstCollected: gst,
    orderCount: sales.length,
    topProducts: topProducts.take(topN).toList(growable: false),
    topCustomers: topCustomers.take(topN).toList(growable: false),
  );
}

/// One entry in a customer's khata (credit/payment) timeline.
class CustomerLedgerRecord {
  const CustomerLedgerRecord({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.createdAt,
    this.refId,
    this.note = '',
    this.actorName,
  });

  final String id;
  final String customerId;
  final String type; // SALE_CREDIT | PAYMENT | ADJUST
  final double amount;
  final double balanceAfter;
  final DateTime createdAt;
  final String? refId;
  final String note;
  final String? actorName;

  bool get isPayment => type == 'PAYMENT';

  /// A balance brought forward from an import rather than earned on a sale.
  bool get isOpening => type == 'OPENING';

  /// Label for the khata timeline.
  String get typeLabel => switch (type) {
    'PAYMENT' => 'Payment',
    'OPENING' => 'Opening balance',
    'ADJUST' => 'Adjustment',
    _ => 'Credit',
  };
}

/// A set of imported receipts that look like the same sale stored more than
/// once - the fallout of re-importing a file before ids were content-derived.
class ImportedDuplicateGroup {
  const ImportedDuplicateGroup({
    required this.date,
    required this.total,
    required this.customerName,
    required this.copies,
  });

  final String date;
  final double total;
  final String customerName;

  /// How many rows exist; one is kept, so [copies] - 1 would be retired.
  final int copies;

  int get extras => copies - 1;
}

/// One entry in an item's stock audit trail.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.delta,
    required this.reason,
    required this.createdAt,
    this.balanceAfter,
    this.refId,
    this.note = '',
    this.actorName,
  });

  final String id;
  final String itemId;
  final String itemName;
  final double delta;
  final String reason; // SALE | PURCHASE | RETURN | ADJUST | OPENING
  final DateTime createdAt;
  final double? balanceAfter;
  final String? refId;
  final String note;
  final String? actorName;

  bool get isIn => delta > 0;
}

/// A single stock line on a purchase: an existing item, how many units were
/// received, and the unit cost paid.
class PurchaseStockLine {
  const PurchaseStockLine({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unitCost,
  });

  final String itemId;
  final String itemName;
  final double quantity;
  final double unitCost;
}

/// One row of a "create product with variants" form: a single size/colour
/// with its own price, stock, SKU and (optionally) cost + reorder level.
class VariantDraft {
  const VariantDraft({
    required this.label,
    required this.sellPrice,
    required this.openingStock,
    this.sku = '',
    this.costPrice,
    this.reorderLevel,
  });

  final String label;
  final double sellPrice;
  final double openingStock;
  final String sku;
  final double? costPrice;
  final int? reorderLevel;
}

class PurchaseRecord {
  const PurchaseRecord({
    required this.id,
    required this.supplierName,
    required this.supplierPhone,
    required this.reference,
    required this.total,
    required this.amountPaid,
    required this.paymentMethod,
    required this.notes,
    required this.purchaseDate,
    required this.actorName,
    required this.tombstone,
  });

  final String id;
  final String supplierName;
  final String supplierPhone;
  final String reference;
  final double total;
  final double amountPaid;
  final String paymentMethod;
  final String notes;
  final DateTime purchaseDate;
  final String? actorName;
  final bool tombstone;

  /// Money still owed to the supplier for this purchase (never negative).
  double get balanceDue {
    final due = total - amountPaid;
    return due < 0 ? 0 : due;
  }

  bool get isSettled => balanceDue <= 0.0001;
}

/// A supplier rolled up from their purchases: what you've bought and what you
/// still owe. Derived, not a stored entity.
class SupplierDue {
  const SupplierDue({
    required this.name,
    required this.phone,
    required this.purchaseCount,
    required this.totalPurchased,
    required this.payable,
  });

  final String name;
  final String phone;
  final int purchaseCount;
  final double totalPurchased;
  final double payable;
}

class PurchaseSummarySnapshot {
  const PurchaseSummarySnapshot({
    required this.totalPurchases,
    required this.totalSpent,
    required this.totalPayable,
    required this.supplierCount,
  });

  final int totalPurchases;

  /// Gross value of stock bought (sum of purchase totals).
  final double totalSpent;

  /// Outstanding across all suppliers (sum of unpaid balances).
  final double totalPayable;
  final int supplierCount;
}

class WorkspaceAccessSessionHeartbeatResult {
  const WorkspaceAccessSessionHeartbeatResult({
    required this.sessionId,
    required this.status,
    required this.deviceLabel,
    required this.shouldSignOut,
    required this.shouldWipeLocalData,
    this.revokeReason,
    this.revokedAt,
    this.wipeRequestedAt,
    this.wipeAcknowledgedAt,
  });

  final String sessionId;
  final String status;
  final String deviceLabel;
  final bool shouldSignOut;
  final bool shouldWipeLocalData;
  final String? revokeReason;
  final DateTime? revokedAt;
  final DateTime? wipeRequestedAt;
  final DateTime? wipeAcknowledgedAt;
}

class WorkspaceAccessSessionRecord {
  const WorkspaceAccessSessionRecord({
    required this.id,
    required this.memberName,
    required this.memberEmail,
    required this.membershipRoleSnapshot,
    required this.roleLabel,
    required this.status,
    required this.deviceLabel,
    required this.platformName,
    required this.packageName,
    required this.appVersion,
    required this.buildNumber,
    required this.releaseChannel,
    required this.releaseTag,
    required this.lastSeenAt,
    required this.revokedAt,
    required this.revokeReason,
    required this.wipeRequested,
    required this.wipeRequestedAt,
    required this.wipeAcknowledgedAt,
    required this.trustScore,
    required this.trustLevel,
    required this.trustSummary,
    required this.trustReasons,
    required this.metadata,
    required this.canManage,
    required this.createdAt,
    required this.updatedAt,
    this.ipAddress = '',
    this.userAgent = '',
  });

  final String id;
  final String memberName;
  final String memberEmail;
  final String membershipRoleSnapshot;
  final String roleLabel;
  final String status;
  final String deviceLabel;
  final String platformName;
  final String packageName;
  final String appVersion;
  final String buildNumber;
  final String releaseChannel;
  final String releaseTag;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;
  final String? revokeReason;
  final bool wipeRequested;
  final DateTime? wipeRequestedAt;
  final DateTime? wipeAcknowledgedAt;
  final int trustScore;
  final String trustLevel;
  final String trustSummary;
  final List<String> trustReasons;
  final Map<String, dynamic> metadata;
  final bool canManage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String ipAddress;
  final String userAgent;

  bool get isActive => status == 'active';
  bool get isRevoked => status == 'revoked';
  bool get isTrusted => trustLevel == 'trusted';
  bool get needsReview => trustLevel == 'review';
  bool get isRisky => trustLevel == 'risky' || trustLevel == 'blocked';
  bool get isBlocked => trustLevel == 'blocked';
}

class UserMfaStatus {
  const UserMfaStatus({
    required this.totpEnabled,
    required this.totpPendingEnrollment,
    required this.enabledAt,
    required this.lastVerifiedAt,
    required this.issuerLabel,
    required this.accountLabel,
    required this.challengeWindowSeconds,
    required this.pendingManualSecret,
    required this.pendingOtpauthUri,
  });

  final bool totpEnabled;
  final bool totpPendingEnrollment;
  final DateTime? enabledAt;
  final DateTime? lastVerifiedAt;
  final String issuerLabel;
  final String accountLabel;
  final int challengeWindowSeconds;
  final String pendingManualSecret;
  final String pendingOtpauthUri;
}

class UserMfaVerifyResult {
  const UserMfaVerifyResult({
    required this.status,
    required this.verifiedAt,
    required this.verifiedUntil,
  });

  final UserMfaStatus status;
  final DateTime verifiedAt;
  final DateTime verifiedUntil;
}

class WorkspacePulseHeadline {
  const WorkspacePulseHeadline({
    required this.title,
    required this.body,
    required this.route,
    required this.ctaLabel,
    required this.tone,
  });

  final String title;
  final String body;
  final String route;
  final String ctaLabel;
  final String tone;
}

class WorkspacePulseTask {
  const WorkspacePulseTask({
    required this.code,
    required this.priority,
    required this.tone,
    required this.title,
    required this.body,
    required this.route,
    required this.ctaLabel,
    required this.count,
    this.metadata = const <String, dynamic>{},
  });

  final String code;
  final String priority;
  final String tone;
  final String title;
  final String body;
  final String route;
  final String ctaLabel;
  final int count;
  final Map<String, dynamic> metadata;
}

class WorkspacePulseAnomaly {
  const WorkspacePulseAnomaly({
    required this.code,
    required this.severity,
    required this.title,
    required this.body,
    required this.route,
    required this.ctaLabel,
    required this.metricValue,
    this.metadata = const <String, dynamic>{},
  });

  final String code;
  final String severity;
  final String title;
  final String body;
  final String route;
  final String ctaLabel;
  final String metricValue;
  final Map<String, dynamic> metadata;
}

class WorkspacePulseStats {
  const WorkspacePulseStats({
    required this.openTaskCount,
    required this.criticalAnomalyCount,
    required this.warningAnomalyCount,
    required this.staleSessionCount,
    required this.wipePendingCount,
    required this.openPlanRequestCount,
    required this.lowStockCount,
  });

  final int openTaskCount;
  final int criticalAnomalyCount;
  final int warningAnomalyCount;
  final int staleSessionCount;
  final int wipePendingCount;
  final int openPlanRequestCount;
  final int lowStockCount;
}

class WorkspacePulseSnapshot {
  const WorkspacePulseSnapshot({
    required this.refreshedAt,
    required this.headline,
    required this.stats,
    required this.tasks,
    required this.anomalies,
  });

  final DateTime refreshedAt;
  final WorkspacePulseHeadline headline;
  final WorkspacePulseStats stats;
  final List<WorkspacePulseTask> tasks;
  final List<WorkspacePulseAnomaly> anomalies;
}

class WorkspacePulseSignal {
  const WorkspacePulseSignal({
    required this.id,
    required this.signalKind,
    required this.code,
    required this.status,
    required this.signalLevel,
    required this.signalRank,
    required this.tone,
    required this.title,
    required this.body,
    required this.route,
    required this.ctaLabel,
    required this.metricValue,
    required this.count,
    required this.firstDetectedAt,
    required this.lastDetectedAt,
    required this.lastSnapshotRefreshedAt,
    required this.assignedMembershipId,
    required this.assignedMemberName,
    required this.assignedMemberRole,
    required this.assignedAt,
    required this.assignedByName,
    required this.acknowledgedAt,
    required this.acknowledgedByName,
    required this.isEscalated,
    required this.escalatedAt,
    required this.escalatedByName,
    required this.escalationNote,
    required this.followUpNote,
    required this.resolvedAt,
    required this.resolvedByName,
    required this.resolutionNote,
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String signalKind;
  final String code;
  final String status;
  final String signalLevel;
  final int signalRank;
  final String tone;
  final String title;
  final String body;
  final String route;
  final String ctaLabel;
  final String metricValue;
  final int count;
  final DateTime firstDetectedAt;
  final DateTime lastDetectedAt;
  final DateTime lastSnapshotRefreshedAt;
  final String? assignedMembershipId;
  final String? assignedMemberName;
  final String? assignedMemberRole;
  final DateTime? assignedAt;
  final String? assignedByName;
  final DateTime? acknowledgedAt;
  final String? acknowledgedByName;
  final bool isEscalated;
  final DateTime? escalatedAt;
  final String? escalatedByName;
  final String escalationNote;
  final String followUpNote;
  final DateTime? resolvedAt;
  final String? resolvedByName;
  final String resolutionNote;
  final Map<String, dynamic> metadata;

  bool get isResolved => status == 'resolved';
  bool get isAcknowledged => status == 'acknowledged';
  bool get isOpen => status == 'open';
}

String _normalizePlanTier(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'starter' || normalized == 'pro') {
    return normalized;
  }
  return 'growth';
}

class DomainControlState {
  const DomainControlState({
    required this.domain,
    required this.currentEpoch,
    required this.cutoverStatus,
    required this.writeMaster,
    required this.controlPresent,
    required this.shadowReadsEnabled,
    required this.isEnabled,
    required this.canWriteOnPostgresSurface,
    this.pilotSignoffStatus,
    this.pilotSignoffSummary,
    this.pilotRecommendedAction,
    this.pilotLatestVerifyResult,
  });

  final String domain;
  final int currentEpoch;
  final String cutoverStatus;
  final String writeMaster;
  final bool controlPresent;
  final bool shadowReadsEnabled;
  final bool isEnabled;
  final bool canWriteOnPostgresSurface;
  final String? pilotSignoffStatus;
  final String? pilotSignoffSummary;
  final String? pilotRecommendedAction;
  final String? pilotLatestVerifyResult;

  bool get isPostgresPrimary =>
      cutoverStatus == 'postgres_primary' || writeMaster == 'postgres';

  bool get isPilotReady =>
      pilotSignoffStatus == 'ready_for_cutover' ||
      pilotSignoffStatus == 'production_safe';

  String get postureLabel {
    if (cutoverStatus == 'postgres_primary') {
      return 'Postgres primary';
    }
    if (cutoverStatus == 'ready') {
      return 'Pilot ready';
    }
    if (cutoverStatus == 'pilot') {
      return 'Pilot active';
    }
    return 'Legacy bridge';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'domain': domain,
    'current_epoch': currentEpoch,
    'cutover_status': cutoverStatus,
    'write_master': writeMaster,
    'control_present': controlPresent,
    'shadow_reads_enabled': shadowReadsEnabled,
    'is_enabled': isEnabled,
    'can_write_on_postgres_surface': canWriteOnPostgresSurface,
    'pilot_signoff_status': pilotSignoffStatus,
    'pilot_signoff_summary': pilotSignoffSummary,
    'pilot_recommended_action': pilotRecommendedAction,
    'pilot_latest_verify_result': pilotLatestVerifyResult,
  };

  factory DomainControlState.fromJson(
    Map<String, dynamic> json, {
    String? fallbackDomain,
  }) {
    final epoch = json['current_epoch'];
    return DomainControlState(
      domain: (json['domain'] ?? fallbackDomain ?? 'unknown').toString(),
      currentEpoch: epoch is int
          ? epoch
          : epoch is num
          ? epoch.toInt()
          : int.tryParse('$epoch') ?? 1,
      cutoverStatus: (json['cutover_status'] ?? 'legacy').toString(),
      writeMaster: (json['write_master'] ?? 'local').toString(),
      controlPresent: json['control_present'] == true,
      shadowReadsEnabled: json['shadow_reads_enabled'] == true,
      isEnabled: json['is_enabled'] != false,
      canWriteOnPostgresSurface: json['can_write_on_postgres_surface'] == true,
      pilotSignoffStatus: _nullableText(json['pilot_signoff_status']),
      pilotSignoffSummary: _nullableText(json['pilot_signoff_summary']),
      pilotRecommendedAction: _nullableText(json['pilot_recommended_action']),
      pilotLatestVerifyResult: _nullableText(
        json['pilot_latest_verify_result'],
      ),
    );
  }

  factory DomainControlState.legacy(String domain) {
    return DomainControlState(
      domain: domain,
      currentEpoch: 1,
      cutoverStatus: 'legacy',
      writeMaster: 'local',
      controlPresent: false,
      shadowReadsEnabled: false,
      isEnabled: true,
      canWriteOnPostgresSurface: false,
    );
  }
}

class InventoryMetrics {
  const InventoryMetrics({
    required this.totalItems,
    required this.totalStock,
    required this.inventoryValue,
    required this.potentialProfit,
    required this.lowStock,
  });

  final int totalItems;
  final double totalStock;
  final double inventoryValue;
  final double potentialProfit;
  final int lowStock;

  factory InventoryMetrics.empty() {
    return const InventoryMetrics(
      totalItems: 0,
      totalStock: 0,
      inventoryValue: 0,
      potentialProfit: 0,
      lowStock: 0,
    );
  }
}

class DashboardOverview {
  const DashboardOverview({
    required this.metrics,
    required this.todaySalesCount,
    required this.todayRevenue,
  });

  final InventoryMetrics metrics;
  final int todaySalesCount;
  final double todayRevenue;

  factory DashboardOverview.empty() {
    return DashboardOverview(
      metrics: InventoryMetrics.empty(),
      todaySalesCount: 0,
      todayRevenue: 0,
    );
  }
}

class HistoryOverview {
  const HistoryOverview({
    required this.totalSales,
    required this.syncedSales,
    required this.queuedSales,
    required this.failedSales,
    this.rejectedSales = 0,
    required this.totalRevenue,
    required this.queuedRevenue,
    this.lastSyncedAt,
  });

  final int totalSales;
  final int syncedSales;
  final int queuedSales;

  /// Sales whose last push attempt failed for a *transient* reason (offline,
  /// 5xx, timeout). The outbox flush picks these up again automatically, so
  /// they are informational — not something the owner must act on.
  final int failedSales;

  /// Sales the server *permanently* rejected (dead-lettered 4xx). These never
  /// retry on their own and are the only ones that genuinely need attention.
  final int rejectedSales;
  final double totalRevenue;
  final double queuedRevenue;
  final DateTime? lastSyncedAt;

  factory HistoryOverview.empty() {
    return const HistoryOverview(
      totalSales: 0,
      syncedSales: 0,
      queuedSales: 0,
      failedSales: 0,
      rejectedSales: 0,
      totalRevenue: 0,
      queuedRevenue: 0,
    );
  }
}

enum HistoryDateWindow {
  all('All time'),
  today('Today'),
  sevenDays('7 days'),
  thirtyDays('30 days'),
  ninetyDays('90 days');

  const HistoryDateWindow(this.label);

  final String label;
}

class HistoryFilter {
  const HistoryFilter({
    this.search = '',
    this.syncState,
    this.paymentMode,
    this.dateWindow = HistoryDateWindow.all,
    this.onlyDueSales = false,
    this.limit = 100,
  });

  final String search;
  final CommerceSyncState? syncState;
  final String? paymentMode;
  final HistoryDateWindow dateWindow;
  final bool onlyDueSales;
  final int limit;

  HistoryFilter copyWith({
    String? search,
    CommerceSyncState? syncState,
    String? paymentMode,
    HistoryDateWindow? dateWindow,
    bool? onlyDueSales,
    int? limit,
    bool clearSyncState = false,
    bool clearPaymentMode = false,
  }) {
    return HistoryFilter(
      search: search ?? this.search,
      syncState: clearSyncState ? null : (syncState ?? this.syncState),
      paymentMode: clearPaymentMode ? null : (paymentMode ?? this.paymentMode),
      dateWindow: dateWindow ?? this.dateWindow,
      onlyDueSales: onlyDueSales ?? this.onlyDueSales,
      limit: limit ?? this.limit,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HistoryFilter &&
        other.search == search &&
        other.syncState == syncState &&
        other.paymentMode == paymentMode &&
        other.dateWindow == dateWindow &&
        other.onlyDueSales == onlyDueSales &&
        other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(
    search,
    syncState,
    paymentMode,
    dateWindow,
    onlyDueSales,
    limit,
  );
}

class InventoryCategorySummary {
  const InventoryCategorySummary({
    required this.category,
    required this.productCount,
  });

  final String category;
  final int productCount;
}

class InventoryCatalogItem {
  const InventoryCatalogItem({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    required this.stock,
    required this.createdAt,
    this.sku,
    this.subcategory,
    this.size,
    this.description,
    this.sourceMeta,
    this.costPrice,
    this.supplierId,
    this.lastPurchaseDate,
    this.hsnCode,
    this.gstRate = 0,
    this.priceIncludesTax = true,
    this.imagePath,
    this.unit,
    this.reorderLevel,
    this.variantGroupId,
    this.variantLabel,
  });

  /// Fallback low-stock threshold when an item has no explicit reorder level.
  static const int defaultReorderLevel = 5;

  final String id;
  final String name;
  final double price;
  final String category;
  final double stock;
  final DateTime createdAt;
  final String? sku;
  final String? subcategory;
  final String? size;
  final String? description;
  final String? sourceMeta;
  final double? costPrice;
  final String? supplierId;
  final String? lastPurchaseDate;
  final String? hsnCode;
  final double gstRate;
  final bool priceIncludesTax;
  final String? imagePath;

  /// Unit of measurement (pcs, kg, litre, ...). Null when unspecified.
  final String? unit;

  /// Per-item low-stock threshold. Null falls back to [defaultReorderLevel].
  final int? reorderLevel;

  /// Shared id linking sibling variants (size/colour) of one product. Null for
  /// plain single-tier items.
  final String? variantGroupId;

  /// Human label for this variant within its group, e.g. "S / Red".
  final String? variantLabel;

  double get marginPerUnit => price - (costPrice ?? 0);

  int get effectiveReorderLevel => reorderLevel ?? defaultReorderLevel;

  bool get isLowStock => stock <= effectiveReorderLevel;

  bool get hasVariantGroup =>
      variantGroupId != null && variantGroupId!.isNotEmpty;
}

class PosCatalogFilter {
  const PosCatalogFilter({
    this.search = '',
    this.category,
    this.page = 1,
    this.pageSize = 40,
    this.includeCost = false,
    this.lowStockOnly = false,
  });

  final String search;
  final String? category;
  final int page;
  final int pageSize;
  final bool includeCost;
  final bool lowStockOnly;

  PosCatalogFilter copyWith({
    String? search,
    String? category,
    int? page,
    int? pageSize,
    bool? includeCost,
    bool? lowStockOnly,
    bool clearCategory = false,
  }) {
    return PosCatalogFilter(
      search: search ?? this.search,
      category: clearCategory ? null : (category ?? this.category),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      includeCost: includeCost ?? this.includeCost,
      lowStockOnly: lowStockOnly ?? this.lowStockOnly,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PosCatalogFilter &&
        other.search == search &&
        other.category == category &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.includeCost == includeCost &&
        other.lowStockOnly == lowStockOnly;
  }

  @override
  int get hashCode =>
      Object.hash(search, category, page, pageSize, includeCost, lowStockOnly);
}

class InventoryCatalogFilter {
  const InventoryCatalogFilter({
    this.search = '',
    this.category,
    this.page = 1,
    this.pageSize = 40,
    this.includeCost = false,
    this.lowStockOnly = false,
  });

  final String search;
  final String? category;
  final int page;
  final int pageSize;
  final bool includeCost;
  final bool lowStockOnly;

  InventoryCatalogFilter copyWith({
    String? search,
    String? category,
    int? page,
    int? pageSize,
    bool? includeCost,
    bool? lowStockOnly,
    bool clearCategory = false,
  }) {
    return InventoryCatalogFilter(
      search: search ?? this.search,
      category: clearCategory ? null : (category ?? this.category),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      includeCost: includeCost ?? this.includeCost,
      lowStockOnly: lowStockOnly ?? this.lowStockOnly,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is InventoryCatalogFilter &&
        other.search == search &&
        other.category == category &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.includeCost == includeCost &&
        other.lowStockOnly == lowStockOnly;
  }

  @override
  int get hashCode =>
      Object.hash(search, category, page, pageSize, includeCost, lowStockOnly);
}

/// An item that has fallen to or below its reorder level, with everything a
/// purchase decision needs.
/// Stock that isn't selling — money sitting on a shelf.
/// A product ranked by how much it actually sells — the mirror of dead stock.
class BestSellerItem {
  const BestSellerItem({
    required this.name,
    required this.quantitySold,
    required this.revenue,
    this.profit,
  });

  final String name;
  final double quantitySold;
  final double revenue;

  /// Null when cost prices aren't known, rather than 0 — a false "no profit"
  /// is worse than admitting we can't tell.
  final double? profit;
}

/// Money in vs money out over a period.
class CashFlowSnapshot {
  const CashFlowSnapshot({
    required this.salesCollected,
    required this.purchases,
    required this.expenses,
  });

  final double salesCollected;
  final double purchases;
  final double expenses;

  double get moneyOut => purchases + expenses;
  double get net => salesCollected - moneyOut;
  bool get isPositive => net >= 0;

  static const CashFlowSnapshot empty =
      CashFlowSnapshot(salesCollected: 0, purchases: 0, expenses: 0);
}

class DeadStockItem {
  const DeadStockItem({
    required this.id,
    required this.name,
    required this.category,
    required this.stock,
    required this.price,
    this.costPrice,
    this.lastSoldAt,
  });

  final String id;
  final String name;
  final String category;
  final double stock;
  final double price;
  final double? costPrice;

  /// Null when the item has never sold at all — the worst case, not the best.
  final DateTime? lastSoldAt;

  int? get daysSinceSold {
    final at = lastSoldAt;
    if (at == null) return null;
    return DateTime.now().difference(at).inDays;
  }

  bool get neverSold => lastSoldAt == null;

  /// Cash tied up, valued at cost where known. Falls back to selling price so
  /// an item without a cost price still shows up rather than reading as free.
  ///
  /// A stored 0.00 counts as "not recorded", not "free" — the server's version
  /// of this report says exactly that. Treating it as zero valued the shelf at
  /// nothing and sorted the worst offenders to the bottom of the list, which
  /// is the problem the report exists to surface.
  double get tiedUpValue {
    final cost = costPrice;
    return stock * (cost != null && cost > 0 ? cost : price);
  }

  String get lastSoldLabel {
    if (neverSold) return 'Never sold';
    final days = daysSinceSold!;
    if (days == 0) return 'Sold today';
    if (days == 1) return 'Sold yesterday';
    if (days < 60) return 'Last sold $days days ago';
    return 'Last sold ${(days / 30).floor()} months ago';
  }
}

class ReorderItem {
  const ReorderItem({
    required this.id,
    required this.name,
    required this.category,
    required this.stock,
    required this.reorderLevel,
    this.unit,
    this.sku,
    this.costPrice,
  });

  final String id;
  final String name;
  final String category;
  final double stock;
  final int reorderLevel;
  final String? unit;
  final String? sku;
  final double? costPrice;

  bool get isOutOfStock => stock <= 0;

  /// How much to buy: enough to reach twice the reorder level, so the shop
  /// isn't back at the threshold the day after restocking. Always at least 1.
  double get suggestedQty {
    final target = reorderLevel * 2;
    final gap = target - stock;
    return gap < 1 ? 1 : gap.ceilToDouble();
  }

  /// What the suggested quantity is likely to cost, when a cost price is known.
  double? get estimatedCost =>
      costPrice == null ? null : costPrice! * suggestedQty;
}

class LowStockItem {
  const LowStockItem({
    required this.id,
    required this.name,
    required this.category,
    required this.stock,
    this.size,
  });

  final String id;
  final String name;
  final String category;
  final double stock;
  final String? size;
}

class CustomerPulseSummary {
  const CustomerPulseSummary({
    required this.name,
    required this.visitCount,
    required this.lifetimeSpend,
    required this.lastSeenAt,
    this.phone,
    this.pendingSales = 0,
  });

  final String name;
  final String? phone;
  final int visitCount;
  final double lifetimeSpend;
  final DateTime lastSeenAt;
  final int pendingSales;
}

/// A customer who owes money, with everything the collection screen needs to
/// decide who to chase next.
class KhataDebtor {
  const KhataDebtor({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
    this.lastRemindedAt,
    this.lastSeenAt,
  });

  final String id;
  final String name;
  final String phone;
  final double balance;
  final DateTime? lastRemindedAt;
  final DateTime? lastSeenAt;

  bool get hasPhone => phone.trim().length >= 10;

  /// Days since the last reminder; null if never reminded.
  int? get daysSinceReminder {
    final at = lastRemindedAt;
    if (at == null) return null;
    return DateTime.now().difference(at).inDays;
  }

  /// Reminded today already — the collection run should skip them so a
  /// customer never gets chased twice in one day.
  bool get remindedToday {
    final at = lastRemindedAt;
    if (at == null) return false;
    final now = DateTime.now();
    return at.year == now.year && at.month == now.month && at.day == now.day;
  }

  /// Overdue once a week has passed since the last nudge (or there never was
  /// one). Mirrors how shopkeepers actually chase udhaar.
  bool get isOverdue => (daysSinceReminder ?? 999) >= 7;

  String get reminderStatus {
    if (remindedToday) return 'Reminded today';
    final days = daysSinceReminder;
    if (days == null) return 'Never reminded';
    if (days == 1) return 'Reminded yesterday';
    return 'Reminded $days days ago';
  }
}

class BackendCustomerSummary {
  const BackendCustomerSummary({
    required this.id,
    required this.name,
    required this.totalSpent,
    required this.balance,
    required this.status,
    this.phone,
    this.email,
    this.notes,
    this.loyaltyPoints = 0,
  });

  final String id;
  final String name;

  /// Loyalty points available to redeem. Whole points only.
  final int loyaltyPoints;
  final String? phone;
  final String? email;
  final double totalSpent;
  final double balance;
  final String status;
  final String? notes;
}

class CustomerLedgerPreviewEntry {
  const CustomerLedgerPreviewEntry({
    required this.id,
    required this.eventType,
    required this.amountDelta,
    required this.occurredAt,
    this.note,
    this.actorName,
  });

  final String id;
  final String eventType;
  final double amountDelta;
  final DateTime occurredAt;
  final String? note;
  final String? actorName;
}

class PosPayment {
  const PosPayment({required this.mode, required this.amount});

  final String mode;
  final double amount;

  Map<String, dynamic> toJson() => {'mode': mode, 'amount': amount};
}

enum CommerceCommandType { saleCreate, paymentCreate }

enum CommerceSyncState { localOnly, queued, syncing, synced, failed, refunded }

class CommerceSyncResult {
  const CommerceSyncResult({
    required this.commandId,
    required this.state,
    this.backendEntityId,
    this.message,
  });

  final String commandId;
  final CommerceSyncState state;
  final String? backendEntityId;
  final String? message;

  bool get acceptedByBackend => state == CommerceSyncState.synced;
}

class PosCartItem {
  const PosCartItem({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
    required this.stock,
    required this.category,
    this.size,
    this.sku,
    this.costPrice,
    this.hsnCode,
    this.gstRate = 0,
    this.priceIncludesTax = true,
    this.discount = 0,
  });

  final String id;
  final String name;
  final double price;
  final double quantity;
  final double stock;
  final String category;
  final String? size;
  final String? sku;
  final double? costPrice;
  final String? hsnCode;
  final double gstRate;
  final bool priceIncludesTax;

  /// Money off this line only (per-item discount), entered by the cashier.
  /// Never more than the line itself.
  final double discount;

  double get grossLineTotal => price * quantity;

  /// Effective discount, clamped so a line can never go negative.
  double get effectiveDiscount {
    if (discount <= 0) return 0;
    final gross = grossLineTotal;
    return discount > gross ? gross : discount;
  }

  double get lineTotal => grossLineTotal - effectiveDiscount;

  PosCartItem copyWith({
    String? id,
    String? name,
    double? price,
    double? quantity,
    double? stock,
    String? category,
    String? size,
    String? sku,
    double? costPrice,
    String? hsnCode,
    double? gstRate,
    bool? priceIncludesTax,
    double? discount,
  }) {
    return PosCartItem(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      stock: stock ?? this.stock,
      category: category ?? this.category,
      size: size ?? this.size,
      sku: sku ?? this.sku,
      costPrice: costPrice ?? this.costPrice,
      hsnCode: hsnCode ?? this.hsnCode,
      gstRate: gstRate ?? this.gstRate,
      priceIncludesTax: priceIncludesTax ?? this.priceIncludesTax,
      discount: discount ?? this.discount,
    );
  }

  Map<String, dynamic> toSaleJson() => {
    'itemId': id,
    'name': name,
    'quantity': quantity,
    'price': price,
    'size': size,
    'costPrice': costPrice,
    'hsnCode': hsnCode,
    'gstRate': gstRate,
    'priceIncludesTax': priceIncludesTax,
    'discount': effectiveDiscount,
  };
}

String? _nullableText(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

class RecentSaleSummary {
  const RecentSaleSummary({
    required this.id,
    required this.total,
    required this.amountReceived,
    required this.amountDue,
    required this.date,
    required this.paymentMode,
    required this.syncState,
    this.customerName,
    this.itemSummary,
  });

  final String id;
  final double total;
  final double amountReceived;
  final double amountDue;
  final String date;
  final String paymentMode;
  final CommerceSyncState syncState;
  final String? customerName;

  /// Short summary of line items (e.g. "Rice + 2 more") used as the receipt
  /// title when there's no customer name (walk-in sale).
  final String? itemSummary;

  bool get hasOutstandingDue => amountDue > 0.009;

  /// The main line shown in the History list: customer name if present, else a
  /// readable item summary, else a generic fallback.
  String get displayTitle {
    if (customerName != null && customerName!.trim().isNotEmpty) {
      return customerName!.trim();
    }
    if (itemSummary != null && itemSummary!.trim().isNotEmpty) {
      return itemSummary!.trim();
    }
    return 'Walk-in customer';
  }
}

class SaleDetailItem {
  const SaleDetailItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.size,
    this.sku,
    this.unitCost,
    this.hsnCode,
    this.gstRate = 0,
    this.taxableAmount = 0,
    this.taxAmount = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
    this.priceIncludesTax = true,
    this.lineDiscount = 0,
  });

  final String name;
  final double quantity;
  final double unitPrice;

  /// Money taken off this line (per-item discount + its share of any
  /// bill-level discount), so the receipt can show it.
  final double lineDiscount;
  final String? size;
  final String? sku;
  final double? unitCost;
  final String? hsnCode;
  final double gstRate;
  final double taxableAmount;
  final double taxAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final bool priceIncludesTax;

  double get lineTotal => unitPrice * quantity;
}

class SaleDetailPayment {
  const SaleDetailPayment({
    required this.mode,
    required this.amount,
    this.referenceCode,
    this.note,
  });

  final String mode;
  final double amount;
  final String? referenceCode;
  final String? note;
}

class SaleRecordDetail {
  const SaleRecordDetail({
    required this.id,
    required this.total,
    required this.discount,
    required this.discountType,
    required this.paymentMode,
    required this.date,
    required this.syncState,
    required this.items,
    required this.payments,
    this.customerName,
    this.customerPhone,
    this.footerNote,
    this.commandId,
    this.backendSaleId,
    this.lastSyncError,
  });

  final String id;
  final double total;
  final double discount;
  final String discountType;
  final String paymentMode;
  final String date;
  final CommerceSyncState syncState;
  final List<SaleDetailItem> items;
  final List<SaleDetailPayment> payments;
  final String? customerName;
  final String? customerPhone;
  final String? footerNote;
  final String? commandId;
  final String? backendSaleId;
  final String? lastSyncError;

  int get itemCount =>
      items.fold<double>(0, (sum, item) => sum + item.quantity).round();

  double get subtotal =>
      items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  double get amountReceived =>
      payments.fold<double>(0, (sum, payment) => sum + payment.amount);

  double get amountDue {
    final due = total - amountReceived;
    return due > 0 ? due : 0;
  }

  bool get hasOutstandingDue => amountDue > 0.009;
}

class CommerceOutboxEntryModel {
  const CommerceOutboxEntryModel({
    required this.commandId,
    required this.shopId,
    required this.commandType,
    required this.domain,
    required this.baseDomainEpoch,
    required this.payloadJson,
    required this.syncStatus,
    required this.attemptCount,
    required this.createdAt,
    required this.updatedAt,
    this.lastAttemptAt,
    this.completedAt,
    this.lastError,
  });

  final String commandId;
  final String shopId;
  final String commandType;
  final String domain;
  final int baseDomainEpoch;
  final String payloadJson;
  final String syncStatus;
  final int attemptCount;
  final int createdAt;
  final int updatedAt;
  final int? lastAttemptAt;
  final int? completedAt;
  final String? lastError;
}

class CommerceOutboxAttentionEntry {
  const CommerceOutboxAttentionEntry({
    required this.commandId,
    required this.commandType,
    required this.syncStatus,
    required this.attemptCount,
    required this.updatedAt,
    this.lastAttemptAt,
    this.lastError,
    this.saleId,
    this.customerName,
    this.total = 0,
    this.saleDate,
  });

  final String commandId;
  final String commandType;
  final String syncStatus;
  final int attemptCount;
  final int updatedAt;
  final int? lastAttemptAt;
  final String? lastError;
  final String? saleId;
  final String? customerName;
  final double total;
  final String? saleDate;

  bool get isFailed => syncStatus == 'failed';
  bool get isQueued => syncStatus == 'pending';
  bool get isSyncing => syncStatus == 'syncing';

  String get statusLabel {
    switch (syncStatus) {
      case 'failed':
        return 'FAILED';
      case 'syncing':
        return 'SYNCING';
      case 'pending':
        return 'QUEUED';
      default:
        return syncStatus.toUpperCase();
    }
  }

  String get commandLabel {
    switch (commandType) {
      case 'sale_create':
        return 'Sale replay';
      case 'payment_create':
        return 'Payment replay';
      default:
        return commandType;
    }
  }
}

final RegExp _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// The backend's `inventory_item_id` must be a UUID or null. Custom items,
/// weighed lines, and items created offline carry non-UUID local ids — send
/// those as null so the sale still syncs (recorded as a named, catalog-less
/// line) instead of being rejected with "Must be a valid UUID".
Object? _backendUuidOrNull(Object? id) {
  final text = (id ?? '').toString().trim();
  return _uuidRe.hasMatch(text) ? text : null;
}

class LocalSaleCommit {
  const LocalSaleCommit({
    required this.commandId,
    required this.saleId,
    required this.shopId,
    required this.baseDomainEpoch,
    required this.date,
    required this.createdAt,
    required this.total,
    required this.discount,
    required this.discountType,
    required this.paymentMode,
    required this.items,
    required this.payments,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.footerNote,
    this.buyerGstin,
    this.redeemPoints = 0,
    required this.inventoryDeltas,
  });

  final String commandId;
  final String saleId;
  final String shopId;
  final int baseDomainEpoch;
  final String date;
  final String createdAt;
  final double total;
  final double discount;
  final String discountType;
  final String paymentMode;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> payments;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? footerNote;
  final String? buyerGstin;

  /// Loyalty points the customer is spending on this bill. The server decides
  /// what is actually allowed and converts it to a discount.
  final int redeemPoints;
  // Signed stock change per item id (negative = sold). Fractional for weighed
  // goods. NOTE: the backend sale serializer must accept fractional quantity
  // before cloud sync is enabled for weighed items.
  final Map<String, double> inventoryDeltas;

  Map<String, dynamic> toBackendCommandPayload() => {
    'command_id': commandId,
    'base_domain_epoch': baseDomainEpoch,
    'source_surface': 'flutter_pos',
    'sale': {
      'customer_id': _backendUuidOrNull(customerId),
      'customer_name': customerName ?? '',
      'customer_phone': customerPhone ?? '',
      'buyer_gstin': buyerGstin ?? '',
      'discount_amount': discount.toStringAsFixed(2),
      'redeem_points': redeemPoints,
      'payment_mode': paymentMode,
      'footer_note': footerNote ?? '',
      'sale_date': date,
      'occurred_at': createdAt,
      'items': items
          .map(
            (item) => {
              'inventory_item_id': _backendUuidOrNull(item['itemId']),
              'name': item['name'],
              'sku': item['sku'] ?? '',
              'size': item['size'] ?? '',
              'quantity': item['quantity'],
              'unit_price': (item['price'] as num).toStringAsFixed(2),
              'unit_cost': item['costPrice'] == null
                  ? null
                  : (item['costPrice'] as num).toStringAsFixed(2),
              // Per-item discount (money off just this line). The server caps it
              // at the line total and applies the bill discount on top.
              'discount': ((item['discount'] as num?) ?? 0).toStringAsFixed(2),
            },
          )
          .toList(growable: false),
      'payments': payments
          .map(
            (payment) => {
              'payment_method': payment['mode'],
              'amount': (payment['amount'] as num).toStringAsFixed(2),
            },
          )
          .toList(growable: false),
    },
  };

  Map<String, dynamic> toRemotePayload({String? staffId}) => {
    'id': saleId,
    'items': items,
    'total': total,
    'discount': discount,
    'discountValue': discount.toStringAsFixed(2),
    'discountType': discountType,
    'paymentMode': paymentMode,
    'payments': payments,
    'customerId': customerId,
    'customerName': customerName ?? '',
    'customerPhone': customerPhone ?? '',
    'footerNote': footerNote ?? '',
    'date': date,
    'createdAt': createdAt,
    'staffId': staffId ?? '',
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  };
}

class CustomerLedgerMutationDraft {
  CustomerLedgerMutationDraft({
    required this.eventType,
    required this.amountDelta,
    this.totalSpentDelta = 0,
    this.note,
    DateTime? occurredAt,
  }) : occurredAt = occurredAt ?? DateTime.now();

  final String eventType;
  final double amountDelta;
  final double totalSpentDelta;
  final String? note;
  final DateTime occurredAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'event_type': eventType,
    'amount_delta': amountDelta.toStringAsFixed(2),
    'total_spent_delta': totalSpentDelta.toStringAsFixed(2),
    'note': note ?? '',
    'occurred_at': occurredAt.toIso8601String(),
  };
}

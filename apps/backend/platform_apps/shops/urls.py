from django.urls import path

from platform_apps.shops.invite_views import (
    ShopInviteListCreateView,
    ShopInviteRevokeView,
)
from platform_apps.shops.permission_catalog import PermissionCatalogView
from platform_apps.shops.export_views import ShopDataExportView
from platform_apps.shops.settings_views import ShopSettingsView
from platform_apps.shops.pos_pin_views import PosPinVerifyView
from platform_apps.audit.views import WorkspaceAuditEventListView
from platform_apps.attendance.views import (
    AttendanceSessionDetailView,
    AttendanceSessionListCreateView,
    AttendanceSummaryView,
)
from platform_apps.customers.khata_views import CustomerRemindView, DebtorListView
from platform_apps.customers.loyalty_views import LoyaltySettingsView
from platform_apps.customers.views import (
    CustomerBulkCreateView,
    CustomerDetailView,
    CustomerLedgerListCreateView,
    CustomerLedgerTimelineView,
    CustomerListCreateView,
    CustomerSummaryView,
)
from platform_apps.billing.views import (
    SubscriptionCheckoutView,
    SubscriptionInvoiceListView,
    SubscriptionRefreshView,
    SubscriptionView,
)
from platform_apps.expenses.views import ExpenseDetailView, ExpenseListCreateView, ExpenseSummaryView
from platform_apps.customers.statement_views import (
    CustomerStatementLinkBulkView,
    CustomerStatementLinkView,
)
from platform_apps.inventory.health_views import DataHealthView
from platform_apps.inventory.report_views import DeadStockView, ReorderListView
from platform_apps.inventory.stocktake_views import (
    StocktakeApplyView,
    StocktakeCancelView,
    StocktakeCountView,
    StocktakeDetailView,
    StocktakeListCreateView,
)
from platform_apps.inventory.transfer_views import (
    StockTransferCancelView,
    StockTransferListCreateView,
    StockTransferReceiveView,
)
from platform_apps.inventory.views import (
    InventoryItemAdjustmentView,
    InventoryItemBulkCreateView,
    InventoryItemDetailView,
    InventoryItemListCreateView,
    InventorySummaryView,
)
from platform_apps.payments.views import SalePaymentCommandIngestionView, SalePaymentListView
from platform_apps.payments.views import SalePaymentSummaryView
from platform_apps.purchases.price_history_views import SupplierPriceHistoryView
from platform_apps.purchases.views import (
    PurchaseDetailView,
    PurchaseListCreateView,
    PurchaseSummaryView,
    SupplierDetailView,
    SupplierLedgerView,
    SupplierListCreateView,
    SupplierSummaryView,
)
from platform_apps.purchases.order_views import (
    PurchaseOrderDetailView,
    PurchaseOrderListCreateView,
    PurchaseOrderReceiveView,
    PurchaseOrderSendView,
)
from platform_apps.projections.reports import ProfitAndLossView
from platform_apps.projections.views import (
    ShopDashboardSnapshotView,
    ShopPulseSignalDetailView,
    ShopPulseSignalListView,
    ShopPulseSnapshotView,
)
from platform_apps.sales.daybook_views import DayBookView
from platform_apps.sales.return_views import (
    SaleReturnCreateView,
    SaleReturnListView,
    SaleReturnableView,
)
from platform_apps.sales.pulse_views import BestSellersView, CashFlowView
from platform_apps.attendance.person_views import TeamMemberHistoryView
from platform_apps.sales.takings_views import SaleTakingsView
from platform_apps.sales.register_views import (
    RegisterSessionHistoryView,
    RegisterSessionView,
)
from platform_apps.sales.views import (
    SaleStaffPerformanceView,
    SaleTallyExportView,
)
from platform_apps.sales.views import SaleCommandIngestionView, SaleHistoryBulkImportView, SaleDetailView, SaleListCreateView, SaleVoidView, SaleSummaryView, SaleGstSummaryView, GSTR1ExportView, GSTR3BExportView, GSTFilingPackView
from platform_apps.shops.views import (
    ShopDomainStateView,
    ShopMembershipListView,
    ShopPlanRequestListCreateView,
    WorkspaceOwnershipTransferView,
    WorkspaceAccessSessionDetailView,
    WorkspaceAccessSessionHeartbeatView,
    WorkspaceAccessSessionListView,
    WorkspaceAccessSessionRevokeAllView,
    WorkspaceAccessSessionWipeAcknowledgeView,
    WorkspaceTeamDetailView,
    WorkspaceTeamListCreateView,
)

urlpatterns = [
    path("", ShopMembershipListView.as_view(), name="shop-memberships"),
    path("<uuid:shop_id>/domain-state/<slug:domain>/", ShopDomainStateView.as_view(), name="shop-domain-state"),
    path("<uuid:shop_id>/plan-requests/", ShopPlanRequestListCreateView.as_view(), name="shop-plan-requests"),
    path("<uuid:shop_id>/subscription/", SubscriptionView.as_view(), name="shop-subscription"),
    path(
        "<uuid:shop_id>/subscription/checkout/",
        SubscriptionCheckoutView.as_view(),
        name="shop-subscription-checkout",
    ),
    path(
        "<uuid:shop_id>/subscription/refresh/",
        SubscriptionRefreshView.as_view(),
        name="shop-subscription-refresh",
    ),
    path(
        "<uuid:shop_id>/subscription/invoices/",
        SubscriptionInvoiceListView.as_view(),
        name="shop-subscription-invoices",
    ),
    path("<uuid:shop_id>/team/", WorkspaceTeamListCreateView.as_view(), name="workspace-team"),
    path("<uuid:shop_id>/team/<uuid:membership_id>/", WorkspaceTeamDetailView.as_view(), name="workspace-team-detail"),
    path(
        "<uuid:shop_id>/team/<uuid:membership_id>/history/",
        TeamMemberHistoryView.as_view(),
        name="workspace-team-history",
    ),
    path("<uuid:shop_id>/settings/", ShopSettingsView.as_view(), name="shop-settings"),
    path("<uuid:shop_id>/pos-pin/verify/", PosPinVerifyView.as_view(), name="pos-pin-verify"),
    path("<uuid:shop_id>/export/", ShopDataExportView.as_view(), name="shop-data-export"),
    path("<uuid:shop_id>/permission-catalog/", PermissionCatalogView.as_view(), name="permission-catalog"),
    path("<uuid:shop_id>/invites/", ShopInviteListCreateView.as_view(), name="shop-invites"),
    path("<uuid:shop_id>/invites/<uuid:invite_id>/revoke/", ShopInviteRevokeView.as_view(), name="shop-invite-revoke"),
    path("<uuid:shop_id>/audit/", WorkspaceAuditEventListView.as_view(), name="workspace-audit"),
    path("<uuid:shop_id>/sessions/", WorkspaceAccessSessionListView.as_view(), name="workspace-sessions"),
    path(
        "<uuid:shop_id>/sessions/revoke-all/",
        WorkspaceAccessSessionRevokeAllView.as_view(),
        name="workspace-sessions-revoke-all",
    ),
    path(
        "<uuid:shop_id>/sessions/mobile/heartbeat/",
        WorkspaceAccessSessionHeartbeatView.as_view(),
        name="workspace-sessions-mobile-heartbeat",
    ),
    path(
        "<uuid:shop_id>/sessions/<uuid:session_id>/",
        WorkspaceAccessSessionDetailView.as_view(),
        name="workspace-session-detail",
    ),
    path(
        "<uuid:shop_id>/sessions/<uuid:session_id>/wipe-ack/",
        WorkspaceAccessSessionWipeAcknowledgeView.as_view(),
        name="workspace-session-wipe-ack",
    ),
    path(
        "<uuid:shop_id>/team/transfer-ownership/",
        WorkspaceOwnershipTransferView.as_view(),
        name="workspace-team-transfer-ownership",
    ),
    path("<uuid:shop_id>/customers/", CustomerListCreateView.as_view(), name="customer-list"),
    path("<uuid:shop_id>/customers/bulk/", CustomerBulkCreateView.as_view(), name="customer-bulk"),
    path("<uuid:shop_id>/customers/debtors/", DebtorListView.as_view(), name="customer-debtors"),
    path("<uuid:shop_id>/loyalty/", LoyaltySettingsView.as_view(), name="shop-loyalty"),
    path(
        "<uuid:shop_id>/customers/<uuid:customer_id>/remind/",
        CustomerRemindView.as_view(),
        name="customer-remind",
    ),
    path(
        "<uuid:shop_id>/customers/statement-links/bulk/",
        CustomerStatementLinkBulkView.as_view(),
        name="customer-statement-links-bulk",
    ),
    path(
        "<uuid:shop_id>/customers/<uuid:customer_id>/statement-link/",
        CustomerStatementLinkView.as_view(),
        name="customer-statement-link",
    ),
    path("<uuid:shop_id>/customers/summary/", CustomerSummaryView.as_view(), name="customer-summary"),
    path("<uuid:shop_id>/customers/<uuid:customer_id>/", CustomerDetailView.as_view(), name="customer-detail"),
    path(
        "<uuid:shop_id>/customers/<uuid:customer_id>/ledger/",
        CustomerLedgerListCreateView.as_view(),
        name="customer-ledger",
    ),
    path(
        "<uuid:shop_id>/customers/<uuid:customer_id>/timeline/",
        CustomerLedgerTimelineView.as_view(),
        name="customer-ledger-timeline",
    ),
    path("<uuid:shop_id>/attendance/", AttendanceSessionListCreateView.as_view(), name="attendance-list"),
    path("<uuid:shop_id>/attendance/summary/", AttendanceSummaryView.as_view(), name="attendance-summary"),
    path(
        "<uuid:shop_id>/attendance/<uuid:attendance_id>/",
        AttendanceSessionDetailView.as_view(),
        name="attendance-detail",
    ),
    path(
        "<uuid:shop_id>/purchase-orders/",
        PurchaseOrderListCreateView.as_view(),
        name="purchase-order-list",
    ),
    path(
        "<uuid:shop_id>/purchase-orders/<uuid:order_id>/",
        PurchaseOrderDetailView.as_view(),
        name="purchase-order-detail",
    ),
    path(
        "<uuid:shop_id>/purchase-orders/<uuid:order_id>/send/",
        PurchaseOrderSendView.as_view(),
        name="purchase-order-send",
    ),
    path(
        "<uuid:shop_id>/purchase-orders/<uuid:order_id>/receive/",
        PurchaseOrderReceiveView.as_view(),
        name="purchase-order-receive",
    ),
    path("<uuid:shop_id>/suppliers/", SupplierListCreateView.as_view(), name="supplier-list"),
    path("<uuid:shop_id>/suppliers/summary/", SupplierSummaryView.as_view(), name="supplier-summary"),
    path("<uuid:shop_id>/suppliers/<uuid:supplier_id>/", SupplierDetailView.as_view(), name="supplier-detail"),
    path(
        "<uuid:shop_id>/suppliers/<uuid:supplier_id>/ledger/",
        SupplierLedgerView.as_view(),
        name="supplier-ledger",
    ),
    path("<uuid:shop_id>/purchases/", PurchaseListCreateView.as_view(), name="purchase-list"),
    path("<uuid:shop_id>/purchases/summary/", PurchaseSummaryView.as_view(), name="purchase-summary"),
    path(
        "<uuid:shop_id>/purchases/price-history/",
        SupplierPriceHistoryView.as_view(),
        name="supplier-price-history",
    ),
    path("<uuid:shop_id>/purchases/<uuid:purchase_id>/", PurchaseDetailView.as_view(), name="purchase-detail"),
    path("<uuid:shop_id>/expenses/", ExpenseListCreateView.as_view(), name="expense-list"),
    path("<uuid:shop_id>/expenses/summary/", ExpenseSummaryView.as_view(), name="expense-summary"),
    path("<uuid:shop_id>/expenses/<uuid:expense_id>/", ExpenseDetailView.as_view(), name="expense-detail"),
    path("<uuid:shop_id>/inventory/", InventoryItemListCreateView.as_view(), name="inventory-list"),
    path("<uuid:shop_id>/inventory/bulk/", InventoryItemBulkCreateView.as_view(), name="inventory-bulk"),
    path("<uuid:shop_id>/inventory/summary/", InventorySummaryView.as_view(), name="inventory-summary"),
    path("<uuid:shop_id>/inventory/<uuid:item_id>/", InventoryItemDetailView.as_view(), name="inventory-detail"),
    path("<uuid:shop_id>/payments/", SalePaymentListView.as_view(), name="payment-list"),
    path("<uuid:shop_id>/payments/summary/", SalePaymentSummaryView.as_view(), name="payment-summary"),
    path(
        "<uuid:shop_id>/payments/commands/",
        SalePaymentCommandIngestionView.as_view(),
        name="payment-command-ingestion",
    ),
    path(
        "<uuid:shop_id>/projections/dashboard/",
        ShopDashboardSnapshotView.as_view(),
        name="projection-dashboard",
    ),
    path(
        "<uuid:shop_id>/reports/profit-loss/",
        ProfitAndLossView.as_view(),
        name="report-profit-loss",
    ),
    path(
        "<uuid:shop_id>/projections/pulse/",
        ShopPulseSnapshotView.as_view(),
        name="projection-pulse",
    ),
    path(
        "<uuid:shop_id>/projections/pulse/signals/",
        ShopPulseSignalListView.as_view(),
        name="projection-pulse-signals",
    ),
    path(
        "<uuid:shop_id>/projections/pulse/signals/<uuid:signal_id>/",
        ShopPulseSignalDetailView.as_view(),
        name="projection-pulse-signal-detail",
    ),
    path("<uuid:shop_id>/sales/", SaleListCreateView.as_view(), name="sale-list"),
    path(
        "<uuid:shop_id>/reports/data-health/",
        DataHealthView.as_view(),
        name="report-data-health",
    ),
    path(
        "<uuid:shop_id>/reports/dead-stock/",
        DeadStockView.as_view(),
        name="report-dead-stock",
    ),
    path(
        "<uuid:shop_id>/reports/reorder-list/",
        ReorderListView.as_view(),
        name="report-reorder-list",
    ),
    path(
        "<uuid:shop_id>/reports/best-sellers/",
        BestSellersView.as_view(),
        name="report-best-sellers",
    ),
    path(
        "<uuid:shop_id>/reports/cash-flow/",
        CashFlowView.as_view(),
        name="report-cash-flow",
    ),
    path(
        "<uuid:shop_id>/sales/staff-performance/",
        SaleStaffPerformanceView.as_view(),
        name="sale-staff-performance",
    ),
    path(
        "<uuid:shop_id>/sales/tally-export/",
        SaleTallyExportView.as_view(),
        name="sale-tally-export",
    ),
    path("<uuid:shop_id>/sales/export/gstr1/", GSTR1ExportView.as_view(), name="sale-gstr1-export"),
    path("<uuid:shop_id>/sales/export/gstr3b/", GSTR3BExportView.as_view(), name="sale-gstr3b-export"),
    path("<uuid:shop_id>/sales/export/gst-pack/", GSTFilingPackView.as_view(), name="sale-gst-pack"),
    path(
        "<uuid:shop_id>/reports/day-book/",
        DayBookView.as_view(),
        name="report-day-book",
    ),
    path(
        "<uuid:shop_id>/sales/takings/",
        SaleTakingsView.as_view(),
        name="sale-takings",
    ),
    path(
        "<uuid:shop_id>/sales/register/",
        RegisterSessionView.as_view(),
        name="register-session",
    ),
    path(
        "<uuid:shop_id>/sales/register/history/",
        RegisterSessionHistoryView.as_view(),
        name="register-session-history",
    ),
    path("<uuid:shop_id>/sales/summary/", SaleSummaryView.as_view(), name="sale-summary"),
    path("<uuid:shop_id>/sales/summary/gst/", SaleGstSummaryView.as_view(), name="sale-gst-summary"),
    path("<uuid:shop_id>/sales/commands/", SaleCommandIngestionView.as_view(), name="sale-command-ingestion"),
    path("<uuid:shop_id>/sales/history-import/", SaleHistoryBulkImportView.as_view(), name="sale-history-import"),
    path("<uuid:shop_id>/sales/<uuid:sale_id>/", SaleDetailView.as_view(), name="sale-detail"),
    path("<uuid:shop_id>/sales/<uuid:sale_id>/void/", SaleVoidView.as_view(), name="sale-void"),
    path(
        "<uuid:shop_id>/sales/<uuid:sale_id>/returnable/",
        SaleReturnableView.as_view(),
        name="sale-returnable",
    ),
    path(
        "<uuid:shop_id>/sales/<uuid:sale_id>/return/",
        SaleReturnCreateView.as_view(),
        name="sale-return",
    ),
    path("<uuid:shop_id>/returns/", SaleReturnListView.as_view(), name="sale-return-list"),
    path(
        "<uuid:shop_id>/inventory/<uuid:item_id>/adjust-stock/",
        InventoryItemAdjustmentView.as_view(),
        name="inventory-adjust-stock",
    ),
    # shop_id is the shop ACTING, which differs by verb: the destination
    # receives, the source cancels. Each view checks the transfer really has
    # that shop on that side, so a valid id from the wrong shop is rejected
    # rather than quietly accepted.
    path(
        "<uuid:shop_id>/inventory/stocktakes/",
        StocktakeListCreateView.as_view(),
        name="stocktake-list",
    ),
    path(
        "<uuid:shop_id>/inventory/stocktakes/<uuid:stocktake_id>/",
        StocktakeDetailView.as_view(),
        name="stocktake-detail",
    ),
    path(
        "<uuid:shop_id>/inventory/stocktakes/<uuid:stocktake_id>/count/",
        StocktakeCountView.as_view(),
        name="stocktake-count",
    ),
    path(
        "<uuid:shop_id>/inventory/stocktakes/<uuid:stocktake_id>/apply/",
        StocktakeApplyView.as_view(),
        name="stocktake-apply",
    ),
    path(
        "<uuid:shop_id>/inventory/stocktakes/<uuid:stocktake_id>/cancel/",
        StocktakeCancelView.as_view(),
        name="stocktake-cancel",
    ),
    path(
        "<uuid:shop_id>/inventory/transfers/",
        StockTransferListCreateView.as_view(),
        name="stock-transfer-list",
    ),
    path(
        "<uuid:shop_id>/inventory/transfers/<uuid:transfer_id>/receive/",
        StockTransferReceiveView.as_view(),
        name="stock-transfer-receive",
    ),
    path(
        "<uuid:shop_id>/inventory/transfers/<uuid:transfer_id>/cancel/",
        StockTransferCancelView.as_view(),
        name="stock-transfer-cancel",
    ),
]

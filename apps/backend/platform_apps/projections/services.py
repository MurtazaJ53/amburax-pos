from __future__ import annotations

import logging
from datetime import datetime, time, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from django.db import models, transaction
from django.db.models import Count, Max, Sum
from django.db.models.functions import Coalesce
from django.utils import timezone

from platform_apps.customers.models import Customer
from platform_apps.inventory.models import InventoryItem
from platform_apps.payments.models import SalePayment
from platform_apps.projections.models import ShopDashboardSnapshot, ShopLowStockSnapshot

#: How many low-stock rows the dashboard is given. The panel shows six and
#: pages through the rest, so eight left the count reading 135 above a list
#: the shopkeeper could never see past the first eight of.
LOW_STOCK_PREVIEW_LIMIT = 24
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop


logger = logging.getLogger(__name__)

#: An item at or below this count shows in the low-stock preview. Decimal so a
#: shop selling by weight compares like with like.
LOW_STOCK_THRESHOLD = Decimal("5")


def refresh_projection_after_write(shop: Shop, *, context: str) -> None:
    """Refresh the dashboard after a write that has already been committed.

    The dashboard is derived data: every number on it can be rebuilt from the
    sales and payments it summarises, and a scheduled job rebuilds it anyway.
    The sale is not derived. So when the refresh fails after the sale has
    committed, the sale is the thing that matters and the caller must still
    report success.

    It used to raise straight through. The sale was written, the projection
    then failed, and the cashier saw a 500 for a sale that was in fact in the
    database — so they rang it up again, and the shop's own till was the thing
    creating duplicate sales. A stale dashboard until the next refresh is a
    strictly smaller problem than a double-charged customer.

    Logged at ERROR with the shop id, because a projection that fails every
    time is a real fault; it just is not the till's emergency.
    """
    try:
        refresh_shop_dashboard_projection(shop)
    except Exception:
        logger.error(
            "Dashboard projection refresh failed after %s for shop %s. The write "
            "itself is committed and correct; the dashboard will be stale until "
            "the next refresh.",
            context,
            shop.id,
            exc_info=True,
        )


def refresh_shop_dashboard_projection(shop: Shop) -> ShopDashboardSnapshot:
    refreshed_at = timezone.now()

    inventory_rows = list(
        InventoryItem.objects.filter(shop=shop, tombstone=False)
        .annotate(stock_on_hand=Coalesce(Sum("ledger_entries__quantity_delta"), Decimal("0")))
        .values("id", "name", "sku", "category", "status", "sell_price", "stock_on_hand")
    )
    inventory_items_count = len(inventory_rows)
    active_inventory_items_count = sum(1 for item in inventory_rows if item["status"] == InventoryItem.Status.ACTIVE)
    category_count = len({(item["category"] or "").strip() for item in inventory_rows if (item["category"] or "").strip()})
    # Decimal throughout. int() here reported a grocer's remaining 0.750 kg as
    # 0: out of stock, absent from the preview, and worth nothing in the stock
    # valuation. The ledger has always stored three decimal places.
    def _stock(item) -> Decimal:
        return Decimal(item["stock_on_hand"] or 0)

    low_stock_preview_rows = [
        item for item in inventory_rows if Decimal("0") < _stock(item) <= LOW_STOCK_THRESHOLD
    ]
    low_stock_preview_rows.sort(key=lambda item: (_stock(item), item["name"].lower()))
    out_of_stock_items_count = sum(1 for item in inventory_rows if _stock(item) <= 0)
    projected_sell_value = sum(
        (item["sell_price"] or Decimal("0.00")) * _stock(item)
        for item in inventory_rows
        if _stock(item) > 0
    )

    customer_summary = Customer.objects.filter(shop=shop, tombstone=False).aggregate(
        customer_count=Count("id"),
        active_credit_customers_count=Count("id", filter=models.Q(balance__gt=0)),
        total_outstanding_balance=Coalesce(Sum("balance"), Decimal("0.00")),
        total_lifetime_spend=Coalesce(Sum("total_spent"), Decimal("0.00")),
    )

    # The shop's own local day, not the server's. A Kolkata shop closing at
    # 22:00 IST is still on the previous UTC day, so a UTC "today" would drop
    # the evening's takings off the dashboard exactly when the owner cashes up
    # and looks at it.
    shop_tz = ZoneInfo(shop.timezone or "Asia/Kolkata")
    shop_today = timezone.now().astimezone(shop_tz).date()
    day_start = datetime.combine(shop_today, time.min, tzinfo=shop_tz)
    day_end = day_start + timedelta(days=1)

    completed_sales = Sale.objects.filter(
        shop=shop,
        tombstone=False,
        status=Sale.Status.COMPLETED,
    )
    today_summary = completed_sales.filter(
        occurred_at__gte=day_start, occurred_at__lt=day_end
    ).aggregate(
        today_sales_count=Count("id"),
        today_gross_revenue=Coalesce(Sum("total_amount"), Decimal("0.00")),
    )

    sales_summary = completed_sales.aggregate(
        sales_count=Count("id"),
        gross_revenue=Coalesce(Sum("total_amount"), Decimal("0.00")),
        outstanding_revenue=Coalesce(Sum("amount_due"), Decimal("0.00")),
        last_sale_at=Max("occurred_at"),
    )

    payment_summary = SalePayment.objects.filter(shop=shop).aggregate(
        payment_count=Count("id"),
        total_collected=Coalesce(Sum("amount"), Decimal("0.00")),
        credit_payment_count=Count("id", filter=models.Q(payment_method=SalePayment.PaymentMethod.CREDIT)),
        digital_payment_count=Count(
            "id",
            filter=models.Q(
                payment_method__in=[
                    SalePayment.PaymentMethod.UPI,
                    SalePayment.PaymentMethod.BANK,
                    SalePayment.PaymentMethod.CARD,
                ]
            ),
        ),
    )

    with transaction.atomic():
        snapshot, _ = ShopDashboardSnapshot.objects.update_or_create(
            shop=shop,
            defaults={
                "inventory_items_count": inventory_items_count,
                "active_inventory_items_count": active_inventory_items_count,
                "category_count": category_count,
                "low_stock_items_count": len(low_stock_preview_rows),
                "out_of_stock_items_count": out_of_stock_items_count,
                "projected_sell_value": projected_sell_value,
                "customer_count": customer_summary["customer_count"] or 0,
                "active_credit_customers_count": customer_summary["active_credit_customers_count"] or 0,
                "total_outstanding_balance": customer_summary["total_outstanding_balance"] or Decimal("0.00"),
                "total_lifetime_spend": customer_summary["total_lifetime_spend"] or Decimal("0.00"),
                "sales_count": sales_summary["sales_count"] or 0,
                "today_sales_count": today_summary["today_sales_count"] or 0,
                "today_gross_revenue": today_summary["today_gross_revenue"] or Decimal("0.00"),
                "today_date": shop_today,
                "gross_revenue": sales_summary["gross_revenue"] or Decimal("0.00"),
                "outstanding_revenue": sales_summary["outstanding_revenue"] or Decimal("0.00"),
                "payment_count": payment_summary["payment_count"] or 0,
                "total_collected": payment_summary["total_collected"] or Decimal("0.00"),
                "credit_payment_count": payment_summary["credit_payment_count"] or 0,
                "digital_payment_count": payment_summary["digital_payment_count"] or 0,
                "last_sale_at": sales_summary["last_sale_at"],
                "refreshed_at": refreshed_at,
                "metadata_json": {
                    "low_stock_preview_size": min(len(low_stock_preview_rows), LOW_STOCK_PREVIEW_LIMIT),
                    "source": "projection_refresh",
                },
            },
        )

        ShopLowStockSnapshot.objects.filter(shop=shop).delete()
        ShopLowStockSnapshot.objects.bulk_create(
            [
                ShopLowStockSnapshot(
                    shop=shop,
                    dashboard_snapshot=snapshot,
                    inventory_item_id=item["id"],
                    item_name=item["name"],
                    sku=item["sku"] or "",
                    category=item["category"] or "",
                    stock_on_hand=_stock(item),
                    sell_price=item["sell_price"] or Decimal("0.00"),
                    severity_rank=index + 1,
                    refreshed_at=refreshed_at,
                )
                for index, item in enumerate(low_stock_preview_rows[:LOW_STOCK_PREVIEW_LIMIT])
            ]
        )

    return ShopDashboardSnapshot.objects.select_related("shop").prefetch_related("low_stock_preview").get(pk=snapshot.pk)

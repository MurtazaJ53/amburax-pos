"""Stock reports: what isn't moving, and what needs buying.

Both mirror queries that already exist locally in the mobile app
(`watchDeadStock`, `watchReorderList`). The rules must stay identical — an
owner who sees 12 items to reorder on the phone should not see 9 on the web.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.db.models import DecimalField, F, Max, Q, Sum, Value
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

_ZERO = Decimal("0")

#: Used when an item has no reorder level of its own. Matches the mobile
#: fallback in `watchReorderList`.
DEFAULT_REORDER_LEVEL = 5


def _stocked_items(shop):
    return InventoryItem.objects.filter(shop=shop, tombstone=False).annotate(
        stock=Coalesce(
            Sum("ledger_entries__quantity_delta"),
            Value(_ZERO),
            output_field=DecimalField(max_digits=14, decimal_places=3),
        ),
    )


class DeadStockView(APIView):
    """Money sitting on the shelf: in stock, but not sold for a long time.

    Usually a shop's largest hidden problem — cash converted into stock nobody
    is buying, invisible because every other screen shows what IS selling.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        # Cost prices are involved, so this is not a cashier's report.
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.MANAGER
        )
        try:
            days = int(request.query_params.get("days", 90))
        except (TypeError, ValueError):
            days = 90
        days = max(1, min(days, 730))
        cutoff = timezone.now() - timedelta(days=days)

        rows = (
            _stocked_items(membership.shop)
            .annotate(
                last_sold_at=Max(
                    "ledger_entries__occurred_at",
                    filter=Q(
                        ledger_entries__event_type=InventoryStockLedger.EventType.SALE
                    ),
                ),
            )
            .filter(stock__gt=0)
            .filter(Q(last_sold_at__isnull=True) | Q(last_sold_at__lt=cutoff))
            .select_related("private")
        )

        can_view_costs = membership.role in (
            ShopMembership.Role.OWNER,
            ShopMembership.Role.ADMIN,
            ShopMembership.Role.MANAGER,
        )

        items = []
        for item in rows:
            cost = None
            if can_view_costs and getattr(item, "private", None) is not None:
                raw = item.private.cost_price
                # A stored 0.00 means "not recorded", not "free" — valuing the
                # shelf at zero would hide the problem this report exists for.
                cost = raw if raw and raw > 0 else None
            # Fall back to sale price so the card still shows what is at stake,
            # and say which basis was used rather than implying a cost figure.
            unit_value = cost if cost is not None else item.sell_price
            items.append(
                {
                    "id": str(item.id),
                    "name": item.name,
                    "category": item.category or "General",
                    "stock": item.stock,
                    "sell_price": item.sell_price,
                    "cost_price": cost,
                    "tied_up_value": (item.stock or _ZERO) * (unit_value or _ZERO),
                    "valued_at": "cost" if cost is not None else "sale_price",
                    "last_sold_at": item.last_sold_at,
                    "never_sold": item.last_sold_at is None,
                }
            )

        items.sort(key=lambda row: row["tied_up_value"], reverse=True)
        return Response(
            {
                "days": days,
                "tied_up_total": sum(
                    (row["tied_up_value"] for row in items), _ZERO
                ),
                "never_sold_count": sum(1 for row in items if row["never_sold"]),
                "items": items,
            }
        )


def _on_order_by_item(shop) -> dict[str, Decimal]:
    """How much of each item is already ordered and not yet received.

    Purchase orders exist now, which broke an assumption this report was built
    on: an item can be below its reorder level *because* a delivery is on a van
    rather than because nobody has acted. Without this, the buying list keeps
    demanding stock that is already paid for, and a shop ends up ordering the
    same carton twice.

    Imported here rather than at module scope: inventory reports are the more
    fundamental app, and a top-level import would make it depend on purchases.
    """
    from platform_apps.purchases.models import PurchaseOrder, PurchaseOrderLine

    rows = (
        PurchaseOrderLine.objects.filter(
            order__shop=shop,
            order__status__in=[
                PurchaseOrder.Status.ORDERED,
                PurchaseOrder.Status.PARTIALLY_RECEIVED,
            ],
            inventory_item__isnull=False,
        )
        .values("inventory_item_id")
        .annotate(
            ordered=Coalesce(
                Sum("quantity_ordered"),
                Value(_ZERO),
                output_field=DecimalField(max_digits=14, decimal_places=3),
            ),
            received=Coalesce(
                Sum("quantity_received"),
                Value(_ZERO),
                output_field=DecimalField(max_digits=14, decimal_places=3),
            ),
        )
    )

    out: dict[str, Decimal] = {}
    for row in rows:
        outstanding = (row["ordered"] or _ZERO) - (row["received"] or _ZERO)
        if outstanding > _ZERO:
            out[str(row["inventory_item_id"])] = outstanding
    return out


def _in_transit_by_item(shop) -> dict[str, Decimal]:
    """How much stock is on its way to this shop from another of its own shops.

    Dispatching a transfer removes the stock from the source immediately; it
    only appears here once someone confirms it arrived. In between, the
    destination looks short of an item that is sitting in a van — and the
    buying list would tell the shop to purchase more of it.

    Transfer lines reference the SOURCE shop's item, and the destination row is
    not resolved until receipt, so each line has to be mapped to the local item
    using the same barcode → SKU → name+size rule receiving uses. That rule is
    imported rather than restated: two copies would drift, and the symptom
    would be exactly the double-ordering this exists to prevent.
    """
    from platform_apps.inventory.transfer_views import find_destination_item
    from platform_apps.inventory.models import StockTransfer, StockTransferLine

    lines = (
        StockTransferLine.objects.filter(
            transfer__destination_shop=shop,
            transfer__status=StockTransfer.Status.IN_TRANSIT,
        )
        .select_related("source_item")
    )

    out: dict[str, Decimal] = {}
    for line in lines:
        local = find_destination_item(shop, line.source_item)
        # No local row yet means the shop has never stocked it, so it cannot be
        # below a reorder level and cannot appear on the buying list anyway.
        if local is None:
            continue
        key = str(local.id)
        out[key] = out.get(key, _ZERO) + line.quantity
    return out


class ReorderListView(APIView):
    """Everything at or below its reorder level — the full buying list.

    Not capped: a purchase run needs every item, not a dashboard teaser.

    Quantities already on a live purchase order are subtracted from the
    suggestion, and an item fully covered by an open order drops off the list
    entirely: it does not need buying, it needs chasing.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.STAFF
        )
        can_view_costs = membership.role in (
            ShopMembership.Role.OWNER,
            ShopMembership.Role.ADMIN,
            ShopMembership.Role.MANAGER,
        )

        rows = (
            _stocked_items(membership.shop)
            .annotate(
                effective_reorder_level=Coalesce(
                    F("reorder_level"), Value(DEFAULT_REORDER_LEVEL)
                ),
            )
            .filter(stock__lte=F("effective_reorder_level"))
            .select_related("private")
        )

        on_order = _on_order_by_item(membership.shop)
        in_transit = _in_transit_by_item(membership.shop)

        items = []
        fully_covered = 0
        for item in rows:
            level = int(item.effective_reorder_level)
            stock = item.stock or _ZERO
            # Both count as stock already secured: one bought from a supplier,
            # one already paid for and moving between the owner's own shops.
            incoming = on_order.get(str(item.id), _ZERO) + in_transit.get(
                str(item.id), _ZERO
            )

            # Buy up to twice the reorder level so the shop isn't back at the
            # threshold the day after restocking. Always at least 1.
            target = Decimal(level * 2)
            suggested = target - stock - incoming
            if suggested < 1:
                # Everything needed is already on its way. Chasing the supplier
                # is the action here, not raising a second order.
                if incoming > _ZERO:
                    fully_covered += 1
                    continue
                suggested = Decimal(1)
            suggested = suggested.to_integral_value(rounding="ROUND_CEILING")

            cost = None
            if can_view_costs and getattr(item, "private", None) is not None:
                raw = item.private.cost_price
                cost = raw if raw and raw > 0 else None

            items.append(
                {
                    "id": str(item.id),
                    "name": item.name,
                    "sku": item.sku,
                    "category": item.category or "General",
                    "unit": item.unit,
                    "stock": stock,
                    "reorder_level": level,
                    "uses_default_level": item.reorder_level is None,
                    "on_order": on_order.get(str(item.id), _ZERO),
                    "in_transit": in_transit.get(str(item.id), _ZERO),
                    "incoming_total": incoming,
                    "suggested_qty": suggested,
                    "cost_price": cost,
                    "estimated_cost": None if cost is None else cost * suggested,
                    "out_of_stock": stock <= 0,
                }
            )

        # Out of stock first (those are losing sales today), then emptiest.
        items.sort(key=lambda row: (not row["out_of_stock"], row["stock"], row["name"].lower()))

        estimated = [row["estimated_cost"] for row in items if row["estimated_cost"] is not None]
        return Response(
            {
                "default_reorder_level": DEFAULT_REORDER_LEVEL,
                "out_of_stock_count": sum(1 for row in items if row["out_of_stock"]),
                # Low, but already ordered or already in transit. Surfaced as
                # a count so the absence of these rows reads as deliberate
                # rather than as a bug.
                "covered_by_open_orders": fully_covered,
                # Null rather than a partial sum: a half-counted buying budget
                # is worse than none.
                "estimated_total": sum(estimated, _ZERO) if len(estimated) == len(items) else None,
                "items": items,
            }
        )

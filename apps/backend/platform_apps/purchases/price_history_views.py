"""What the shop has actually been paying, and which supplier is quietly
raising prices.

Nothing new is recorded for this. Every purchase already stores the cost per
item, and the purchase carries the supplier and the date, so the shop has been
accumulating a price history since the first bill was entered — it simply had
no way to look at it. A shopkeeper today discovers a rise when the total on an
invoice feels bigger than last time, which is to say usually not at all.

Three rules decide whether the answer is trustworthy, and each exists because
the obvious alternative produces a confident wrong number:

- **Compare a supplier only against itself.** The same shirt at 100 from one
  supplier and 120 from another is not a price rise, it is two suppliers. Mixing
  them invents increases and decreases out of nothing but purchasing order.

- **Ignore lines with no cost.** A zero unit cost is a free sample or a gap in
  the data, never a real price. Treated as a price it makes the next real
  purchase look like an infinite increase, and it drags any average down.

- **Two purchases minimum.** One purchase is a price, not a trend. Reporting a
  change against a baseline that does not exist is how a report loses its
  reader permanently.
"""
from __future__ import annotations

from decimal import Decimal

from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.purchases.models import Purchase, PurchaseItem
from platform_apps.purchases.views import ShopScopedMixin
from platform_apps.shops.permissions import ensure_feature_enabled_or_403

_ZERO = Decimal("0")
_MONEY = Decimal("0.01")
_PERCENT = Decimal("0.1")

#: How much a price has to move before it is worth a shopkeeper's attention.
#: Below this, rounding on a small item reads as a trend and the list fills
#: with noise nobody acts on.
MATERIAL_CHANGE_PERCENT = Decimal("5")

#: A trend needs a previous price to compare against.
MIN_PURCHASES_FOR_TREND = 2


def percent_change(previous: Decimal, latest: Decimal) -> Decimal | None:
    """Movement from one price to the next, or None when it cannot be stated.

    A zero baseline has no percentage — the item was free and is now not, which
    is a fact about the data rather than a price rise, and dividing by it would
    either crash or report an infinity somebody would try to act on.
    """
    if previous is None or latest is None or previous <= _ZERO:
        return None
    return (((latest - previous) / previous) * Decimal("100")).quantize(_PERCENT)


def build_price_points(rows: list[dict]) -> list[dict]:
    """Collapse purchase lines into one price point per purchase, oldest first.

    A single invoice can list the same item twice — two cartons booked as two
    lines. They are one purchase at one moment, so they are averaged by
    quantity rather than counted as two observations, which would otherwise
    make one invoice look like a price that held steady over time.
    """
    by_purchase: dict[str, dict] = {}
    for row in rows:
        cost = row["unit_cost"]
        quantity = row["quantity"]
        if cost is None or cost <= _ZERO or quantity is None or quantity <= _ZERO:
            # See the module docstring: a zero cost is not a price.
            continue
        key = str(row["purchase_id"])
        bucket = by_purchase.setdefault(
            key,
            {
                "purchase_id": key,
                "date": row["purchase_date"],
                "invoice_number": row["invoice_number"],
                "value": _ZERO,
                "quantity": _ZERO,
            },
        )
        bucket["value"] += cost * quantity
        bucket["quantity"] += quantity

    points = []
    for bucket in by_purchase.values():
        if bucket["quantity"] <= _ZERO:
            continue
        points.append(
            {
                "purchase_id": bucket["purchase_id"],
                "date": bucket["date"].isoformat() if bucket["date"] else None,
                "invoice_number": bucket["invoice_number"],
                "unit_cost": str(
                    (bucket["value"] / bucket["quantity"]).quantize(_MONEY)
                ),
                "quantity": str(bucket["quantity"]),
            }
        )
    points.sort(key=lambda p: (p["date"] or "", p["purchase_id"]))
    return points


def summarise_series(points: list[dict]) -> dict:
    """Latest price, the one before it, and how far it moved."""
    if not points:
        return {
            "latest_cost": None,
            "previous_cost": None,
            "change_percent": None,
            "purchases": 0,
        }

    latest = Decimal(points[-1]["unit_cost"])
    previous = (
        Decimal(points[-2]["unit_cost"])
        if len(points) >= MIN_PURCHASES_FOR_TREND
        else None
    )
    change = percent_change(previous, latest) if previous is not None else None
    return {
        "latest_cost": str(latest),
        "previous_cost": str(previous) if previous is not None else None,
        "change_percent": str(change) if change is not None else None,
        "purchases": len(points),
    }


def _line_rows(shop, *, item_id=None, supplier_id=None) -> list[dict]:
    """Purchase lines for this shop, flattened to what the maths needs.

    Only completed, live purchases count. A voided invoice is money the shop
    did not spend, and a tombstoned one was deleted on purpose.
    """
    queryset = (
        PurchaseItem.objects.filter(
            purchase__shop=shop,
            purchase__tombstone=False,
            purchase__status=Purchase.Status.COMPLETED,
            inventory_item__isnull=False,
        )
        .select_related("purchase")
        .order_by("purchase__purchase_date", "purchase_id")
    )
    if item_id:
        queryset = queryset.filter(inventory_item_id=item_id)
    if supplier_id:
        queryset = queryset.filter(purchase__supplier_id=supplier_id)

    return [
        {
            "purchase_id": line.purchase_id,
            "purchase_date": line.purchase.purchase_date,
            "invoice_number": line.purchase.invoice_number,
            "item_id": line.inventory_item_id,
            "item_name": line.name_snapshot,
            "supplier_id": line.purchase.supplier_id,
            "supplier_name": line.purchase.supplier_name_snapshot,
            "unit_cost": line.unit_cost,
            "quantity": line.quantity,
        }
        for line in queryset
    ]


def group_by_item_supplier(rows: list[dict]) -> dict[tuple, list[dict]]:
    """One series per (item, supplier).

    Grouping by item alone would compare one supplier's price against another's
    and call the difference a rise. That is the single most likely way for this
    feature to produce a confident lie, so the grouping is the design.
    """
    grouped: dict[tuple, list[dict]] = {}
    for row in rows:
        if row["item_id"] is None or row["supplier_id"] is None:
            # A purchase entered without a supplier cannot be attributed to
            # one, and guessing would put the blame on whoever is nearest.
            continue
        grouped.setdefault((row["item_id"], row["supplier_id"]), []).append(row)
    return grouped


class SupplierPriceHistoryView(ShopScopedMixin, APIView):
    """The price paid over time, per item and supplier.

    Without `item_id` this answers the question the shop actually has — who has
    put their prices up — by listing only movements big enough to matter, worst
    first. With `item_id` it returns the full series for that one item so the
    figure can be checked against the invoices behind it.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "purchase_workflow")

        item_id = request.query_params.get("item_id") or None
        supplier_id = request.query_params.get("supplier_id") or None
        rows = _line_rows(membership.shop, item_id=item_id, supplier_id=supplier_id)
        grouped = group_by_item_supplier(rows)

        series = []
        for (grouped_item_id, grouped_supplier_id), lines in grouped.items():
            points = build_price_points(lines)
            if not points:
                continue
            summary = summarise_series(points)
            series.append(
                {
                    "item_id": str(grouped_item_id),
                    "item_name": lines[-1]["item_name"],
                    "supplier_id": str(grouped_supplier_id),
                    "supplier_name": lines[-1]["supplier_name"],
                    **summary,
                    # The full series only when one item was asked for. Sending
                    # every point for every pair would be a large payload the
                    # overview does not draw.
                    "points": points if item_id else [],
                }
            )

        movements = [
            row
            for row in series
            if row["change_percent"] is not None
            and abs(Decimal(row["change_percent"])) >= MATERIAL_CHANGE_PERCENT
        ]
        movements.sort(key=lambda r: Decimal(r["change_percent"]), reverse=True)

        return Response(
            {
                "series": sorted(
                    series, key=lambda r: (r["item_name"], r["supplier_name"])
                ),
                # Pre-filtered rather than left to the client, so every surface
                # agrees on what counts as a movement worth showing.
                "movements": movements,
                "material_change_percent": str(MATERIAL_CHANGE_PERCENT),
                "tracked_pairs": len(series),
            }
        )

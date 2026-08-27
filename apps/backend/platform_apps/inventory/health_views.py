"""Data health: the problems that quietly corrupt every report built on them.

Scanned server-side on purpose. The first version of this ran in the browser
over the inventory and customer list endpoints, which slice to 200 rows
(``bounded_list_limit``) — so a shop with 900 products was told about the
duplicates in the first 200 and nothing else, while the page claimed it had
scanned the whole catalog. An undercount presented as a complete answer is
worse than no scan.

The matching rules mirror `core/health/data_health.dart` and `lib/data-health.ts`
exactly: SKU when there is one, otherwise name + size. Size matters — a garment
shop's S and XL are different products, not duplicates.

The SKU branch is now a safety net rather than the common case. A unique index
on (shop, Lower(sku)) means two active products can no longer share a code, so
what this finds in practice is the other kind: rows with no code at all,
matched on name and size. That is what a re-imported spreadsheet produces, and
it is the kind a database constraint cannot prevent — "Cotton Shirt" and
"cotton shirt (new)" are the same product only to a person.
"""
from __future__ import annotations

from decimal import Decimal

from django.db.models import DecimalField, Sum, Value
from django.db.models.functions import Coalesce
from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.customers.models import Customer
from platform_apps.inventory.models import InventoryItem
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

_ZERO = Decimal("0")

#: A debt with no reachable number cannot be chased.
MIN_USABLE_PHONE_DIGITS = 10


def _normalise(value: str | None) -> str:
    return (value or "").strip().lower()


def _group_key(item) -> str | None:
    sku = _normalise(item.sku)
    if sku:
        return f"sku:{sku}"
    name = _normalise(item.name)
    if not name:
        # A nameless row with no SKU cannot be matched to anything; lumping
        # them together would invent a duplicate group.
        return None
    return f"name:{name}|{_normalise(item.size)}"


def _keeper(items: list) -> object:
    """Most stock first, then oldest — usually the original row with the real
    history behind it."""
    return sorted(items, key=lambda i: (-i.stock, i.created_at))[0]


class DataHealthView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.STAFF
        )
        shop = membership.shop

        items = list(
            InventoryItem.objects.filter(shop=shop, tombstone=False).annotate(
                stock=Coalesce(
                    Sum("ledger_entries__quantity_delta"),
                    Value(_ZERO),
                    output_field=DecimalField(max_digits=14, decimal_places=3),
                )
            )
        )

        groups: dict[str, list] = {}
        for item in items:
            key = _group_key(item)
            if key is None:
                continue
            groups.setdefault(key, []).append(item)

        duplicate_groups = []
        for key, group in groups.items():
            if len(group) < 2:
                continue
            keeper = _keeper(group)
            duplicate_groups.append(
                {
                    "key": key,
                    "name": keeper.name,
                    "copies": len(group),
                    "combined_stock": sum((i.stock for i in group), _ZERO),
                    "keeper": {
                        "id": str(keeper.id),
                        "name": keeper.name,
                        "stock": keeper.stock,
                    },
                    # Each copy's stock, because the merge moves it onto the
                    # keeper one ledger adjustment at a time.
                    "duplicates": [
                        {"id": str(i.id), "name": i.name, "stock": i.stock}
                        for i in group
                        if i.id != keeper.id
                    ],
                }
            )
        # Worst first: most copies, then most stock at stake.
        duplicate_groups.sort(
            key=lambda g: (g["copies"], g["combined_stock"]), reverse=True
        )

        negative_stock = [
            {"id": str(i.id), "name": i.name, "stock": i.stock}
            for i in items
            if i.stock < 0
        ]
        # A zero price means the till will happily ring up a free sale.
        missing_price = [
            {"id": str(i.id), "name": i.name}
            for i in items
            if (i.sell_price or _ZERO) <= 0
        ]

        unreachable_debtors = []
        for customer in Customer.objects.filter(shop=shop, tombstone=False):
            # Only customers who owe money: a walk-in with no number is not a
            # problem, but a debt you cannot chase is.
            if (customer.balance or _ZERO) <= Decimal("0.009"):
                continue
            digits = "".join(ch for ch in (customer.phone or "") if ch.isdigit())
            if len(digits) < MIN_USABLE_PHONE_DIGITS:
                unreachable_debtors.append(
                    {
                        "id": str(customer.id),
                        "name": customer.name,
                        "balance": customer.balance,
                    }
                )

        # A group of 3 copies is 2 rows too many, not 1 problem.
        duplicate_row_count = sum(g["copies"] - 1 for g in duplicate_groups)
        total_issues = (
            duplicate_row_count
            + len(negative_stock)
            + len(missing_price)
            + len(unreachable_debtors)
        )

        return Response(
            {
                "scanned_items": len(items),
                "scanned_customers": Customer.objects.filter(
                    shop=shop, tombstone=False
                ).count(),
                "duplicate_groups": duplicate_groups,
                "duplicate_row_count": duplicate_row_count,
                "negative_stock": negative_stock,
                "missing_price": missing_price,
                "customers_without_phone": unreachable_debtors,
                "total_issues": total_issues,
                "is_healthy": total_issues == 0,
            }
        )

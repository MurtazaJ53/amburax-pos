"""Take your data out.

The counter app can back its local database up to a file. The website holds no
local data at all, so "backup" has nothing to back up there — the equivalent is
an export of the shop's records from the server, which is also the answer to
the fair question "what happens to my data if I stop paying".

Deliberately JSON rather than a database dump: a dump is useless to a
shopkeeper and ties them to this schema forever, while JSON opens in anything
and can be read by whoever they move to next.
"""
from __future__ import annotations

import json
import zipfile
import io
import csv
import uuid
from decimal import Decimal

from django.http import HttpResponse
from django.utils import timezone
from rest_framework import permissions
from rest_framework.views import APIView

from platform_apps.customers.models import Customer, CustomerLedgerEntry
from platform_apps.expenses.models import Expense
from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.purchases.models import Purchase, Supplier
from platform_apps.sales.models import Sale
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403


class _Encoder(json.JSONEncoder):
    """Decimals, UUIDs and datetimes, as strings.

    Decimal must not become a float: 0.1 + 0.2 is how money goes wrong, and an
    export is precisely where a rounding artefact would be preserved forever.

    UUID matters because `.values()` hands back real UUID objects rather than
    strings, so every row keyed by id fails to serialise without this.
    """

    def default(self, o):
        if isinstance(o, Decimal):
            return str(o)
        if isinstance(o, uuid.UUID):
            return str(o)
        if hasattr(o, "isoformat"):
            return o.isoformat()
        return super().default(o)


def _csv_bundle(payload: dict) -> bytes:
    """The same export as a zip of spreadsheets.

    JSON is the right format for re-importing and the wrong one for a
    shopkeeper: the owner who most needs their own data out of the product is
    the least likely to be able to read it. Each list in the payload becomes
    one CSV that opens in Excel by double-clicking, and nested values are
    flattened to text rather than dropped.

    utf-8-sig, not utf-8: without the byte-order mark Excel on Windows renders
    Hindi and Gujarati product names as mojibake, which for this audience makes
    the file useless.
    """
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as bundle:
        for name, rows in payload.items():
            if not isinstance(rows, list) or not rows:
                continue
            columns: list[str] = []
            for row in rows:
                for key in row:
                    if key not in columns:
                        columns.append(key)
            text = io.StringIO()
            writer = csv.DictWriter(
                text, fieldnames=columns, extrasaction="ignore", lineterminator="\n"
            )
            writer.writeheader()
            for row in rows:
                writer.writerow(
                    {
                        k: ("" if v is None else str(v))
                        for k, v in row.items()
                        if k in columns
                    }
                )
            bundle.writestr(f"{name}.csv", text.getvalue().encode("utf-8-sig"))

        # The shop record is a single object, not a list, so it would otherwise
        # be the one thing missing from the readable export.
        shop = payload.get("shop") or {}
        if shop:
            text = io.StringIO()
            writer = csv.writer(text, lineterminator="\n")
            writer.writerow(["field", "value"])
            for key, value in shop.items():
                writer.writerow([key, "" if value is None else str(value)])
            bundle.writestr("shop.csv", text.getvalue().encode("utf-8-sig"))
    return buffer.getvalue()


class ShopDataExportView(APIView):
    """Everything this shop owns — as JSON, or as a zip of spreadsheets.

    `?output=csv` returns the readable version. The default stays JSON so any
    existing caller keeps working.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        # The whole shop's trading history, cost prices included. Owner only —
        # this is the one call that hands over everything at once.
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.OWNER
        )
        shop = membership.shop

        payload = {
            "exported_at": timezone.now().isoformat(),
            "format_version": 1,
            "shop": {
                "id": str(shop.id),
                "name": shop.name,
                "slug": shop.slug,
                "gstin": shop.gstin,
                "settings": getattr(shop, "settings_json", {}) or {},
            },
            "inventory": [
                {
                    "id": str(item.id),
                    "name": item.name,
                    "sku": item.sku,
                    "barcode": item.barcode,
                    "category": item.category,
                    "size": item.size,
                    "unit": item.unit,
                    "sell_price": item.sell_price,
                    "hsn_code": item.hsn_code,
                    "gst_rate": item.gst_rate,
                    "reorder_level": item.reorder_level,
                    # Cost lives in a separate private table; include it,
                    # because an export the owner cannot reconcile is useless.
                    "cost_price": getattr(
                        getattr(item, "private", None), "cost_price", None
                    ),
                }
                for item in InventoryItem.objects.filter(
                    shop=shop, tombstone=False
                ).select_related("private")
            ],
            # The ledger, not a stock number: stock is derived from these rows,
            # so exporting the total instead would lose how it was arrived at.
            "stock_ledger": list(
                InventoryStockLedger.objects.filter(shop=shop).values(
                    "item_id", "event_type", "quantity_delta", "unit_cost",
                    "note", "occurred_at",
                )
            ),
            "customers": [
                {
                    "id": str(customer.id),
                    "name": customer.name,
                    # Decrypted here because it is the owner's own record and
                    # they are entitled to it.
                    "phone": customer.phone,
                    "balance": customer.balance,
                }
                for customer in Customer.objects.filter(
                    shop=shop, tombstone=False
                )
            ],
            "customer_ledger": list(
                CustomerLedgerEntry.objects.filter(shop=shop).values(
                    "customer_id", "event_type", "amount_delta", "note",
                    "occurred_at",
                )
            ),
            "sales": list(
                Sale.objects.filter(shop=shop).values(
                    "id", "customer_id", "receipt_number", "subtotal_amount",
                    "discount_amount", "total_amount", "taxable_amount",
                    "tax_amount", "amount_received", "amount_due",
                    "payment_mode", "sale_date", "occurred_at", "status",
                )
            ),
            "suppliers": list(
                Supplier.objects.filter(shop=shop, tombstone=False).values(
                    "id", "name", "phone", "gstin", "balance",
                )
            ),
            "purchases": list(
                Purchase.objects.filter(shop=shop, tombstone=False).values(
                    "id", "supplier_id", "invoice_number", "total_amount",
                    "amount_paid", "amount_due", "purchase_date", "status",
                )
            ),
            "expenses": list(
                Expense.objects.filter(shop=shop, tombstone=False).values(
                    "id", "category", "amount", "description",
                    "payment_method", "expense_date",
                )
            ),
        }

        stamp = timezone.now().strftime("%Y-%m-%d")
        base = f"business-hub-{shop.slug or shop.id}-{stamp}"

        # NOT "format": Django REST Framework reserves that query parameter
        # for renderer negotiation, so ?format=csv is intercepted before this
        # view runs and answered with 404 "Not found" for an unknown renderer.
        if request.query_params.get("output", "").lower() == "csv":
            # Round-trip through the JSON encoder first so Decimals, UUIDs and
            # datetimes are already strings; the CSV writer would otherwise
            # emit Python reprs for them.
            normalised = json.loads(json.dumps(payload, cls=_Encoder))
            response = HttpResponse(
                _csv_bundle(normalised), content_type="application/zip"
            )
            response["Content-Disposition"] = (
                f'attachment; filename="{base}-spreadsheets.zip"'
            )
            return response

        body = json.dumps(payload, cls=_Encoder, indent=2)
        filename = f"{base}.json"

        response = HttpResponse(body, content_type="application/json")
        response["Content-Disposition"] = f'attachment; filename="{filename}"'
        return response

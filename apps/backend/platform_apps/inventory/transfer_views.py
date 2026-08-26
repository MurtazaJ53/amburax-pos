"""Moving stock between two of the owner's shops.

The whole point of the two-step flow is the middle state. Dispatch takes the
stock out of the source shop; receive puts it into the destination. Between
those, the transfer sits IN_TRANSIT and both shops can see it. Previously this
movement was two unrelated manual adjustments, so a forgotten second half left
the numbers wrong with nothing to point at.

Three rules the endpoints enforce, each because the alternative is silent
corruption:

- You must be a member of BOTH shops. Otherwise dispatching would let someone
  push stock into a shop they cannot see, and receiving would let them pull
  from one.
- You cannot dispatch more than is on hand. Negative stock is exactly the
  symptom this feature exists to prevent.
- Receive and cancel lock the transfer row. Two people tapping "Receive" at
  once would otherwise post the incoming stock twice.
"""
from __future__ import annotations

import secrets
from decimal import Decimal, InvalidOperation

from django.db import transaction
from django.db.models import DecimalField, Sum, Value
from django.db.models.functions import Coalesce
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import exceptions, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.projections.services import refresh_projection_after_write
from platform_apps.inventory.models import (
    InventoryItem,
    InventoryStockLedger,
    StockTransfer,
    StockTransferLine,
)
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

_ZERO = Decimal("0")

#: Moving stock changes what two shops are worth, so it is not a cashier's job.
TRANSFER_ROLE = ShopMembership.Role.MANAGER


def _make_reference() -> str:
    """Short, unambiguous handle for the paperwork travelling with the goods.

    Excludes I, O, 0 and 1 so a code read off a printed slip is not mistyped.
    """
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "TR-" + "".join(secrets.choice(alphabet) for _ in range(4))


def _stock_on_hand(item: InventoryItem) -> Decimal:
    return (
        InventoryStockLedger.objects.filter(item=item).aggregate(
            total=Coalesce(
                Sum("quantity_delta"),
                Value(_ZERO),
                output_field=DecimalField(max_digits=14, decimal_places=3),
            )
        )["total"]
        or _ZERO
    )


def _parse_quantity(raw) -> Decimal:
    try:
        quantity = Decimal(str(raw))
    except (InvalidOperation, TypeError, ValueError):
        raise exceptions.ValidationError({"quantity": "Must be a number."})
    if quantity <= _ZERO:
        raise exceptions.ValidationError({"quantity": "Must be greater than zero."})
    return quantity


def _serialize(transfer: StockTransfer) -> dict:
    return {
        "id": str(transfer.id),
        "reference": transfer.reference,
        "status": transfer.status,
        "note": transfer.note,
        "source_shop": {
            "id": str(transfer.source_shop_id),
            "name": transfer.source_shop.name,
        },
        "destination_shop": {
            "id": str(transfer.destination_shop_id),
            "name": transfer.destination_shop.name,
        },
        "dispatched_at": transfer.dispatched_at.isoformat(),
        "received_at": transfer.received_at.isoformat() if transfer.received_at else None,
        "cancelled_at": (
            transfer.cancelled_at.isoformat() if transfer.cancelled_at else None
        ),
        "lines": [
            {
                "id": str(line.id),
                "source_item_id": str(line.source_item_id),
                "destination_item_id": (
                    str(line.destination_item_id) if line.destination_item_id else None
                ),
                "name": line.source_item.name,
                "sku": line.source_item.sku,
                "size": line.source_item.size,
                "unit": line.source_item.unit,
                # DRF renders Decimal as a string; the web client parses it.
                "quantity": str(line.quantity),
                "unit_cost": str(line.unit_cost) if line.unit_cost is not None else None,
            }
            for line in transfer.lines.all()
        ],
    }


class StockTransferListCreateView(APIView):
    """GET: transfers touching this shop, in either direction. POST: dispatch."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        # Viewing does not move anything, so staff may see what is in transit —
        # they are often the ones physically receiving the boxes.
        membership = get_membership_or_403(request.user, shop_id)
        shop = membership.shop

        transfers = (
            StockTransfer.objects.filter(source_shop=shop)
            | StockTransfer.objects.filter(destination_shop=shop)
        )
        state = request.query_params.get("status")
        if state in StockTransfer.Status.values:
            transfers = transfers.filter(status=state)

        transfers = transfers.select_related(
            "source_shop", "destination_shop"
        ).prefetch_related("lines__source_item")[:200]

        rows = [_serialize(t) for t in transfers]
        return Response(
            {
                "shop_id": str(shop.id),
                # Counted separately so the UI can badge "3 waiting for you"
                # without paging through everything.
                "incoming_in_transit": sum(
                    1
                    for r in rows
                    if r["status"] == StockTransfer.Status.IN_TRANSIT
                    and r["destination_shop"]["id"] == str(shop.id)
                ),
                "outgoing_in_transit": sum(
                    1
                    for r in rows
                    if r["status"] == StockTransfer.Status.IN_TRANSIT
                    and r["source_shop"]["id"] == str(shop.id)
                ),
                "transfers": rows,
            }
        )

    @transaction.atomic
    def post(self, request, shop_id):
        source = get_membership_or_403(request.user, shop_id, TRANSFER_ROLE).shop

        destination_id = request.data.get("destination_shop_id")
        if not destination_id:
            raise exceptions.ValidationError(
                {"destination_shop_id": "This field is required."}
            )
        if str(destination_id) == str(source.id):
            raise exceptions.ValidationError(
                {"destination_shop_id": "Pick a different shop to send stock to."}
            )
        # Membership of the destination too: without this check, a manager of
        # one shop could push stock into any shop whose id they could guess.
        destination = get_membership_or_403(
            request.user, destination_id, TRANSFER_ROLE
        ).shop

        raw_lines = request.data.get("lines")
        if not isinstance(raw_lines, list) or not raw_lines:
            raise exceptions.ValidationError({"lines": "Add at least one item."})

        now = timezone.now()
        transfer = StockTransfer.objects.create(
            source_shop=source,
            destination_shop=destination,
            reference=str(request.data.get("reference") or _make_reference())[:32],
            note=str(request.data.get("note") or "")[:2000],
            status=StockTransfer.Status.IN_TRANSIT,
            dispatched_at=now,
            dispatched_by=request.user,
        )

        seen_items: set[str] = set()
        for raw in raw_lines:
            item_id = (raw or {}).get("item_id")
            if not item_id:
                raise exceptions.ValidationError({"lines": "Each line needs an item_id."})
            if str(item_id) in seen_items:
                # Two lines for one item would each pass the stock check on
                # their own while together exceeding what is on the shelf.
                raise exceptions.ValidationError(
                    {"lines": "The same item appears more than once."}
                )
            seen_items.add(str(item_id))

            item = get_object_or_404(
                InventoryItem, id=item_id, shop=source, tombstone=False
            )
            quantity = _parse_quantity(raw.get("quantity"))

            on_hand = _stock_on_hand(item)
            if quantity > on_hand:
                raise exceptions.ValidationError(
                    {
                        "lines": (
                            f"{item.name}: only {on_hand} in stock, "
                            f"cannot send {quantity}."
                        )
                    }
                )

            private = getattr(item, "private", None)
            # A stored 0.00 means "no cost recorded", not "free" — the same
            # convention the dead-stock and reorder reports use.
            unit_cost = (
                private.cost_price
                if private and private.cost_price and private.cost_price > _ZERO
                else None
            )

            StockTransferLine.objects.create(
                transfer=transfer,
                source_item=item,
                quantity=quantity,
                unit_cost=unit_cost,
            )
            InventoryStockLedger.objects.create(
                shop=source,
                item=item,
                actor_user=request.user,
                event_type=InventoryStockLedger.EventType.TRANSFER_OUT,
                quantity_delta=-quantity,
                unit_cost=unit_cost,
                note=f"Transfer {transfer.reference} to {destination.name}",
                occurred_at=now,
            )

        transfer.refresh_from_db()
        # The goods have left this shop, so its low-stock and out-of-stock
        # counts and its shelf value all moved. The dashboard is a stored
        # snapshot and would otherwise keep quoting the pre-dispatch figures.
        refresh_projection_after_write(source, context="a stock transfer sent")
        return Response(_serialize(transfer), status=status.HTTP_201_CREATED)


def find_destination_item(shop, source_item: InventoryItem) -> InventoryItem | None:
    """The destination shop's existing row for this product, or None.

    Matched on barcode first, then SKU, then name+size — the same precedence
    the data-health duplicate scan uses, so the two agree about what counts as
    "the same product".

    Read-only and public because the reorder list needs to answer the same
    question — "which local item is this incoming transfer line?" — without
    creating anything. A second copy of this rule in the reports module would
    drift from this one, and then a shop would be told to buy stock that is
    already on its way.
    """
    barcode = (source_item.barcode or "").strip()
    if barcode:
        match = InventoryItem.objects.filter(
            shop=shop, barcode__iexact=barcode, tombstone=False
        ).first()
        if match:
            return match

    sku = (source_item.sku or "").strip()
    if sku:
        match = InventoryItem.objects.filter(
            shop=shop, sku__iexact=sku, tombstone=False
        ).first()
        if match:
            return match

    return InventoryItem.objects.filter(
        shop=shop,
        name__iexact=(source_item.name or "").strip(),
        size__iexact=(source_item.size or "").strip(),
        tombstone=False,
    ).first()


def _matching_destination_item(shop, source_item: InventoryItem) -> InventoryItem:
    """As find_destination_item, but creates the row when there is no match.

    A transfer can be sent to a shop that does not stock the item yet. Created
    rows carry the source's selling price and GST setup but not its stock:
    stock arrives through the ledger entry.
    """
    existing = find_destination_item(shop, source_item)
    if existing is not None:
        return existing

    return InventoryItem.objects.create(
        shop=shop,
        name=source_item.name,
        sku=source_item.sku,
        barcode=source_item.barcode,
        category=source_item.category,
        subcategory=source_item.subcategory,
        size=source_item.size,
        sell_price=source_item.sell_price,
        hsn_code=source_item.hsn_code,
        gst_rate=source_item.gst_rate,
        price_includes_tax=source_item.price_includes_tax,
        unit=source_item.unit,
        reorder_level=source_item.reorder_level,
        status=InventoryItem.Status.ACTIVE,
    )


class StockTransferReceiveView(APIView):
    """Confirm the goods arrived: post the incoming half of the movement."""

    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, shop_id, transfer_id):
        # Lock first, then check state. Doing it the other way round lets two
        # simultaneous taps both read IN_TRANSIT and both post the stock.
        transfer = get_object_or_404(
            StockTransfer.objects.select_for_update(), id=transfer_id
        )
        get_membership_or_403(request.user, shop_id, TRANSFER_ROLE)
        # Only the shop the goods were sent to can accept them. Without this,
        # a manager could confirm delivery into their own shop for a transfer
        # addressed elsewhere, and the stock would land in the wrong place.
        if str(transfer.destination_shop_id) != str(shop_id):
            raise exceptions.PermissionDenied(
                "This transfer was not sent to this shop."
            )

        if transfer.status != StockTransfer.Status.IN_TRANSIT:
            raise exceptions.ValidationError(
                {"status": f"This transfer is already {transfer.get_status_display().lower()}."}
            )

        now = timezone.now()
        for line in transfer.lines.select_related("source_item"):
            destination_item = _matching_destination_item(
                transfer.destination_shop, line.source_item
            )
            line.destination_item = destination_item
            line.save(update_fields=["destination_item", "updated_at"])

            InventoryStockLedger.objects.create(
                shop=transfer.destination_shop,
                item=destination_item,
                actor_user=request.user,
                event_type=InventoryStockLedger.EventType.TRANSFER_IN,
                quantity_delta=line.quantity,
                unit_cost=line.unit_cost,
                note=f"Transfer {transfer.reference} from {transfer.source_shop.name}",
                occurred_at=now,
            )

        transfer.status = StockTransfer.Status.RECEIVED
        transfer.received_at = now
        transfer.received_by = request.user
        transfer.save(update_fields=["status", "received_at", "received_by", "updated_at"])
        # It arrived here, so this shop's figures moved - and an item that was
        # out of stock is the very reason someone sent it.
        refresh_projection_after_write(
            transfer.destination_shop, context="a stock transfer received"
        )

        return Response(_serialize(transfer))


class StockTransferCancelView(APIView):
    """Call off a transfer that never left, putting the stock back."""

    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, shop_id, transfer_id):
        transfer = get_object_or_404(
            StockTransfer.objects.select_for_update(), id=transfer_id
        )
        # The source shop owns the decision: the goods are still theirs, and
        # the destination has not accepted anything.
        get_membership_or_403(request.user, shop_id, TRANSFER_ROLE)
        if str(transfer.source_shop_id) != str(shop_id):
            raise exceptions.PermissionDenied("This transfer was not sent by this shop.")

        if transfer.status != StockTransfer.Status.IN_TRANSIT:
            raise exceptions.ValidationError(
                {"status": f"This transfer is already {transfer.get_status_display().lower()}."}
            )

        now = timezone.now()
        for line in transfer.lines.select_related("source_item"):
            # A compensating entry, not a deletion. The ledger is append-only
            # so that the history explains itself: stock left, then came back.
            InventoryStockLedger.objects.create(
                shop=transfer.source_shop,
                item=line.source_item,
                actor_user=request.user,
                event_type=InventoryStockLedger.EventType.TRANSFER_IN,
                quantity_delta=line.quantity,
                unit_cost=line.unit_cost,
                note=f"Transfer {transfer.reference} cancelled",
                occurred_at=now,
            )

        transfer.status = StockTransfer.Status.CANCELLED
        transfer.cancelled_at = now
        transfer.save(update_fields=["status", "cancelled_at", "updated_at"])
        # A cancel puts the goods back, which is a stock movement like any
        # other and moves the same three figures.
        refresh_projection_after_write(
            transfer.source_shop, context="a stock transfer cancelled"
        )

        return Response(_serialize(transfer))

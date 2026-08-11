"""Counting the shelves, and reconciling what is found against the books.

Correcting stock one item at a time already worked. Nobody does it for a whole
shop, so the figures drift until they are not trusted, and every report built
on them quietly loses its value.

The decision that matters is how the correction is applied. Counting a shop
takes hours and the shop keeps trading, so each line records what the ledger
said **at the moment it was counted**, and applying posts the DIFFERENCE rather
than the counted figure.

    An item reads 10. The counter finds 8. Three more sell before the
    stocktake is applied, so the ledger now reads 7.

    Setting stock to 8 would silently undo those three sales.
    Posting the variance of -2 against 7 gives 5, which is what is on the
    shelf.

Getting that wrong produces a system that destroys real sales every time
somebody counts, which is worse than never counting at all.
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

from platform_apps.inventory.models import (
    InventoryItem,
    InventoryStockLedger,
    Stocktake,
    StocktakeLine,
)
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

_ZERO = Decimal("0")
_QTY = Decimal("0.001")
_MONEY = Decimal("0.01")

#: Counting is floor work, so staff can record a count. Applying it rewrites
#: stock across the shop and reveals shrinkage, so that needs a manager.
COUNT_ROLE = ShopMembership.Role.STAFF
APPLY_ROLE = ShopMembership.Role.MANAGER


def _reference() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "ST-" + "".join(secrets.choice(alphabet) for _ in range(4))


def _quantity(raw, field: str = "counted_quantity") -> Decimal:
    try:
        value = Decimal(str(raw))
    except (InvalidOperation, TypeError, ValueError):
        raise exceptions.ValidationError({field: "Must be a number."})
    if value < _ZERO:
        # Zero is meaningful — "I looked and there are none" is a real count,
        # and the most common one worth recording.
        raise exceptions.ValidationError({field: "Cannot be negative."})
    return value


def current_stock(item: InventoryItem) -> Decimal:
    total = InventoryStockLedger.objects.filter(item=item).aggregate(
        t=Coalesce(
            Sum("quantity_delta"),
            Value(_ZERO),
            output_field=DecimalField(max_digits=14, decimal_places=3),
        )
    )["t"]
    return (total or _ZERO).quantize(_QTY)


def _line_payload(line: StocktakeLine) -> dict:
    variance = line.variance
    value = None
    if line.unit_cost is not None:
        value = (variance * line.unit_cost).quantize(_MONEY)
    return {
        "id": str(line.id),
        "item_id": str(line.item_id),
        "name": line.name_snapshot,
        "expected": str(line.expected_quantity.quantize(_QTY)),
        "counted": str(line.counted_quantity.quantize(_QTY)),
        "variance": str(variance.quantize(_QTY)),
        "unit_cost": str(line.unit_cost) if line.unit_cost is not None else None,
        "variance_value": str(value) if value is not None else None,
        "counted_at": line.counted_at.isoformat(),
    }


def _serialize(stocktake: Stocktake) -> dict:
    lines = list(stocktake.lines.all())
    missing = [l for l in lines if l.variance < _ZERO]
    extra = [l for l in lines if l.variance > _ZERO]

    # Null rather than a partial sum: a shrinkage figure that silently omits
    # every item without a recorded cost understates the loss, and that is the
    # number somebody acts on.
    costed = [l for l in lines if l.unit_cost is not None and l.variance != _ZERO]
    varied = [l for l in lines if l.variance != _ZERO]
    shrinkage = None
    if varied and len(costed) == len(varied):
        shrinkage = str(
            sum((l.variance * l.unit_cost for l in costed), _ZERO).quantize(_MONEY)
        )

    return {
        "id": str(stocktake.id),
        "reference": stocktake.reference,
        "status": stocktake.status,
        "note": stocktake.note,
        "started_at": stocktake.started_at.isoformat(),
        "applied_at": stocktake.applied_at.isoformat() if stocktake.applied_at else None,
        "counted_lines": len(lines),
        "missing_count": len(missing),
        "extra_count": len(extra),
        "matched_count": len(lines) - len(missing) - len(extra),
        "variance_value": shrinkage,
        "lines": [_line_payload(l) for l in lines],
    }


class StocktakeListCreateView(APIView):
    """GET: stocktakes for this shop. POST: begin a new count."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(request.user, shop_id, COUNT_ROLE)
        rows = (
            Stocktake.objects.filter(shop=membership.shop)
            .prefetch_related("lines")[:100]
        )
        return Response({"stocktakes": [_serialize(s) for s in rows]})

    def post(self, request, shop_id):
        membership = get_membership_or_403(request.user, shop_id, COUNT_ROLE)

        # One open count at a time. Two people counting the same shelves into
        # separate stocktakes would each measure a variance against the same
        # books, and applying both would double every correction.
        existing = Stocktake.objects.filter(
            shop=membership.shop, status=Stocktake.Status.OPEN
        ).first()
        if existing is not None:
            raise exceptions.ValidationError(
                {
                    "status": (
                        f"Stocktake {existing.reference} is still open. "
                        "Finish or cancel it before starting another."
                    )
                }
            )

        stocktake = Stocktake.objects.create(
            shop=membership.shop,
            reference=str(request.data.get("reference") or _reference())[:32],
            note=str(request.data.get("note") or "")[:2000],
            started_by=request.user,
            started_at=timezone.now(),
        )
        return Response(_serialize(stocktake), status=status.HTTP_201_CREATED)


class StocktakeCountView(APIView):
    """Record what was found on the shelf for one item."""

    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, shop_id, stocktake_id):
        membership = get_membership_or_403(request.user, shop_id, COUNT_ROLE)
        shop = membership.shop
        stocktake = get_object_or_404(
            Stocktake.objects.select_for_update(), id=stocktake_id, shop=shop
        )
        if stocktake.status != Stocktake.Status.OPEN:
            raise exceptions.ValidationError(
                {"status": f"This stocktake is already {stocktake.get_status_display().lower()}."}
            )

        item_id = request.data.get("item_id")
        if not item_id:
            raise exceptions.ValidationError({"item_id": "This field is required."})
        item = get_object_or_404(
            InventoryItem, id=item_id, shop=shop, tombstone=False
        )
        counted = _quantity(request.data.get("counted_quantity"))

        private = getattr(item, "private", None)
        cost = (
            private.cost_price
            if private and private.cost_price and private.cost_price > _ZERO
            else None
        )

        now = timezone.now()
        # Re-counting an item replaces the earlier figure rather than adding a
        # second line: the shelf has one true quantity, and a counter who
        # recounts is correcting themselves. expected is re-snapshotted so the
        # variance stays measured from the same instant as the count.
        line, _created = StocktakeLine.objects.update_or_create(
            stocktake=stocktake,
            item=item,
            defaults={
                "name_snapshot": item.name,
                "expected_quantity": current_stock(item),
                "counted_quantity": counted,
                "unit_cost": cost,
                "counted_at": now,
            },
        )
        return Response(_line_payload(line), status=status.HTTP_201_CREATED)


class StocktakeApplyView(APIView):
    """Post the corrections and close the count."""

    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, shop_id, stocktake_id):
        membership = get_membership_or_403(request.user, shop_id, APPLY_ROLE)
        shop = membership.shop
        # Locked before the status check: two managers pressing apply at once
        # would otherwise both pass and post every correction twice.
        stocktake = get_object_or_404(
            Stocktake.objects.select_for_update(), id=stocktake_id, shop=shop
        )
        if stocktake.status != Stocktake.Status.OPEN:
            raise exceptions.ValidationError(
                {"status": f"This stocktake is already {stocktake.get_status_display().lower()}."}
            )

        lines = list(stocktake.lines.select_related("item"))
        if not lines:
            raise exceptions.ValidationError(
                {"lines": "Nothing was counted, so there is nothing to apply."}
            )

        now = timezone.now()
        applied = 0
        for line in lines:
            variance = line.variance
            if variance == _ZERO:
                # The books were right. Recording a zero adjustment would add
                # noise to a ledger people read.
                continue

            InventoryStockLedger.objects.create(
                shop=shop,
                item=line.item,
                actor_user=request.user,
                event_type=InventoryStockLedger.EventType.ADJUSTMENT,
                # The DIFFERENCE, not the counted figure. See the module
                # docstring: setting stock to the counted number would erase
                # anything sold between counting and applying.
                quantity_delta=variance,
                unit_cost=line.unit_cost,
                note=(
                    f"Stocktake {stocktake.reference}: counted "
                    f"{line.counted_quantity.quantize(_QTY)}, "
                    f"books said {line.expected_quantity.quantize(_QTY)}"
                ),
                occurred_at=now,
            )
            applied += 1

        stocktake.status = Stocktake.Status.APPLIED
        stocktake.applied_at = now
        stocktake.applied_by = request.user
        stocktake.save(
            update_fields=["status", "applied_at", "applied_by", "updated_at"]
        )

        payload = _serialize(stocktake)
        payload["adjustments_posted"] = applied
        return Response(payload)


class StocktakeCancelView(APIView):
    """Abandon a count without touching stock."""

    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, shop_id, stocktake_id):
        membership = get_membership_or_403(request.user, shop_id, COUNT_ROLE)
        stocktake = get_object_or_404(
            Stocktake.objects.select_for_update(),
            id=stocktake_id,
            shop=membership.shop,
        )
        if stocktake.status == Stocktake.Status.APPLIED:
            raise exceptions.ValidationError(
                {"status": "This stocktake has already been applied to stock."}
            )
        stocktake.status = Stocktake.Status.CANCELLED
        stocktake.save(update_fields=["status", "updated_at"])
        return Response(_serialize(stocktake))


class StocktakeDetailView(APIView):
    """One stocktake, with every counted line."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id, stocktake_id):
        membership = get_membership_or_403(request.user, shop_id, COUNT_ROLE)
        stocktake = get_object_or_404(
            Stocktake, id=stocktake_id, shop=membership.shop
        )
        return Response(_serialize(stocktake))

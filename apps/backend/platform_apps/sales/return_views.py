"""Taking goods back against an original bill.

Voiding a sale already existed and cancels the whole thing. That is the wrong
tool for what shops actually do: a customer brings one shirt back out of four
items, or swaps it for a different size. Doing that with a void and a fresh
bill destroys the record of what was really sold.

Three rules the endpoint enforces, each because the alternative corrupts
something quietly:

- You cannot return more than was sold, counting every earlier return of that
  line. Otherwise stock is created out of nothing.
- You cannot return against a voided sale — the void already put the stock
  back, and doing it again doubles it.
- A khata refund reduces what the customer owes rather than paying cash out,
  because for a credit sale no money changed hands in the first place.
"""
from __future__ import annotations

import secrets
from decimal import Decimal, InvalidOperation

from django.db import transaction
from django.db.models import Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import exceptions, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.customers.models import CustomerLedgerEntry
from platform_apps.inventory.models import InventoryStockLedger
from platform_apps.sales.models import Sale, SaleReturn, SaleReturnLine
from platform_apps.shops.models import ShopMembership
from platform_apps.projections.services import refresh_projection_after_write
from platform_apps.shops.permissions import get_membership_or_403

_ZERO = Decimal("0")
_MONEY = Decimal("0.01")
#: Quantity scale, matching the model. Sum() returns an unscaled Decimal, so
#: without this the same field reads "4.000" in one key and "1" in another.
_QTY = Decimal("0.001")

#: Returns move money and stock, so not a viewer's action. Staff can process
#: one, because refusing a return needs a manager present at the counter and
#: that is not a software decision.
RETURN_ROLE = ShopMembership.Role.STAFF


def _reference() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "RT-" + "".join(secrets.choice(alphabet) for _ in range(4))


def _quantity(raw) -> Decimal:
    try:
        value = Decimal(str(raw))
    except (InvalidOperation, TypeError, ValueError):
        raise exceptions.ValidationError({"quantity": "Must be a number."})
    if value <= _ZERO:
        raise exceptions.ValidationError({"quantity": "Must be greater than zero."})
    return value


def already_returned(sale_item) -> Decimal:
    """How much of this line has come back on earlier returns."""
    total = SaleReturnLine.objects.filter(sale_item=sale_item).aggregate(
        t=Sum("quantity")
    )["t"]
    return (total or _ZERO).quantize(_QTY)


def _serialize(sale_return: SaleReturn) -> dict:
    return {
        "id": str(sale_return.id),
        "reference": sale_return.reference,
        "sale_id": str(sale_return.sale_id),
        "receipt_number": sale_return.sale.receipt_number,
        "refund_mode": sale_return.refund_mode,
        "refund_amount": str(sale_return.refund_amount),
        "note": sale_return.note,
        "occurred_at": sale_return.occurred_at.isoformat(),
        "lines": [
            {
                "id": str(line.id),
                "sale_item_id": str(line.sale_item_id),
                "name": line.name_snapshot,
                "quantity": str(line.quantity),
                "unit_price": str(line.unit_price),
                "line_total": str(line.line_total),
            }
            for line in sale_return.lines.all()
        ],
    }


class SaleReturnableView(APIView):
    """What is still returnable on this bill, after earlier returns."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id, sale_id):
        membership = get_membership_or_403(request.user, shop_id, RETURN_ROLE)
        sale = get_object_or_404(
            Sale, id=sale_id, shop=membership.shop, tombstone=False
        )

        lines = []
        for item in sale.items.all().order_by("position"):
            returned = already_returned(item)
            remaining = item.quantity - returned
            lines.append(
                {
                    "sale_item_id": str(item.id),
                    "name": item.name_snapshot,
                    "size": item.size_snapshot,
                    "sold": str(item.quantity.quantize(_QTY)),
                    "returned": str(returned),
                    "returnable": str(
                        (remaining if remaining > _ZERO else _ZERO).quantize(_QTY)
                    ),
                    "unit_price": str(item.unit_price),
                }
            )

        return Response(
            {
                "sale_id": str(sale.id),
                "receipt_number": sale.receipt_number,
                "is_void": sale.status == Sale.Status.VOID,
                "customer_id": str(sale.customer_id) if sale.customer_id else None,
                # A bill with nothing left to return should say so rather than
                # presenting a form that can only be rejected.
                "any_returnable": any(
                    Decimal(row["returnable"]) > _ZERO for row in lines
                ),
                "lines": lines,
            }
        )


class SaleReturnCreateView(APIView):
    """Process a return: stock back, money back or credited."""

    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, shop_id, sale_id):
        membership = get_membership_or_403(request.user, shop_id, RETURN_ROLE)
        shop = membership.shop
        # Locked so two staff processing the same return cannot both pass the
        # "not more than was sold" check and put the stock back twice.
        sale = get_object_or_404(
            Sale.objects.select_for_update(), id=sale_id, shop=shop, tombstone=False
        )

        if sale.status == Sale.Status.VOID:
            raise exceptions.ValidationError(
                {"sale": "This bill was voided, which already returned the stock."}
            )

        raw_lines = request.data.get("lines")
        if not isinstance(raw_lines, list) or not raw_lines:
            raise exceptions.ValidationError({"lines": "Say what is coming back."})

        mode = str(request.data.get("refund_mode") or SaleReturn.RefundMode.CASH).upper()
        if mode not in SaleReturn.RefundMode.values:
            raise exceptions.ValidationError({"refund_mode": "Unknown refund method."})
        if mode == SaleReturn.RefundMode.KHATA and not sale.customer_id:
            raise exceptions.ValidationError(
                {"refund_mode": "This bill has no customer, so there is no khata to credit."}
            )

        # Cash-type refunds are capped at what the shop actually COLLECTED on
        # this bill.
        #
        # Only the reverse case was checked before — khata mode without a
        # customer — so nothing stopped a cash refund against a bill sold
        # entirely on credit, and CASH is the form's default. On a 2,000 credit
        # sale where one 500 shirt comes back, the till paid out 500 it had
        # never received AND left the customer owing the full 2,000, because a
        # non-khata mode writes no CustomerLedgerEntry. A 500 loss, invisible
        # until someone reconciles, if ever.
        #
        # EXCHANGE is exempt: it moves no money, the value carries into the
        # replacement bill.
        refundable = None
        if mode not in {SaleReturn.RefundMode.KHATA, SaleReturn.RefundMode.EXCHANGE}:
            already_refunded = (
                SaleReturn.objects.filter(sale=sale)
                .exclude(
                    refund_mode__in=[
                        SaleReturn.RefundMode.KHATA,
                        SaleReturn.RefundMode.EXCHANGE,
                    ]
                )
                .aggregate(total=Sum("refund_amount"))["total"]
                or _ZERO
            )
            refundable = (sale.amount_received or _ZERO) - already_refunded

        now = timezone.now()
        sale_return = SaleReturn(
            shop=shop,
            sale=sale,
            actor_user=request.user,
            reference=str(request.data.get("reference") or _reference())[:32],
            refund_mode=mode,
            note=str(request.data.get("note") or "")[:2000],
            occurred_at=now,
        )
        sale_return.save()

        seen: set[str] = set()
        refund_total = _ZERO

        for raw in raw_lines:
            raw = raw or {}
            item_id = raw.get("sale_item_id")
            if not item_id:
                raise exceptions.ValidationError(
                    {"lines": "Each line needs a sale_item_id."}
                )
            if str(item_id) in seen:
                # Two lines for one item would each pass the remaining-quantity
                # check alone while together exceeding what was sold.
                raise exceptions.ValidationError(
                    {"lines": "The same item appears more than once."}
                )
            seen.add(str(item_id))

            item = get_object_or_404(sale.items, id=item_id)
            quantity = _quantity(raw.get("quantity"))
            remaining = item.quantity - already_returned(item)
            if quantity > remaining:
                raise exceptions.ValidationError(
                    {
                        "lines": (
                            f"{item.name_snapshot}: only {remaining} left to return "
                            f"on this bill, not {quantity}."
                        )
                    }
                )

            # Refund at the price actually charged, discounts included, rather
            # than the current shelf price — the customer paid the former.
            unit = item.unit_price
            if item.quantity > _ZERO:
                unit = (item.line_total / item.quantity).quantize(_MONEY)
            line_total = (unit * quantity).quantize(_MONEY)
            refund_total += line_total

            SaleReturnLine.objects.create(
                sale_return=sale_return,
                sale_item=item,
                inventory_item_id=item.inventory_item_id,
                name_snapshot=item.name_snapshot,
                quantity=quantity,
                unit_price=unit,
                line_total=line_total,
            )

            if item.inventory_item_id:
                InventoryStockLedger.objects.create(
                    shop=shop,
                    item_id=item.inventory_item_id,
                    actor_user=request.user,
                    event_type=InventoryStockLedger.EventType.RETURN,
                    quantity_delta=quantity,
                    unit_cost=item.unit_cost,
                    unit_price=unit,
                    note=f"Return {sale_return.reference} against {sale.receipt_number}",
                    occurred_at=now,
                )

        if refundable is not None and refund_total > refundable:
            # Named precisely, because the cashier has a customer in front of
            # them and needs to know what to do instead, not merely that they
            # cannot proceed.
            raise exceptions.ValidationError(
                {
                    "refund_mode": (
                        f"Only {refundable} was paid on this bill, so "
                        f"{refund_total} cannot be refunded in cash. Refund "
                        "against khata instead, or exchange it."
                    )
                }
            )

        # An exchange moves no money: the value is carried into the replacement
        # bill the cashier is about to ring up.
        sale_return.refund_amount = (
            _ZERO if mode == SaleReturn.RefundMode.EXCHANGE else refund_total
        )
        sale_return.save(update_fields=["refund_amount", "updated_at"])

        if mode == SaleReturn.RefundMode.KHATA:
            # Reduces what they owe rather than paying cash out — for a credit
            # sale no money changed hands to refund.
            CustomerLedgerEntry.objects.create(
                shop=shop,
                customer_id=sale.customer_id,
                actor_user=request.user,
                event_type=CustomerLedgerEntry.EventType.ADJUSTMENT,
                amount_delta=-refund_total,
                note=f"Return {sale_return.reference}",
                occurred_at=now,
            )
            customer = sale.customer
            customer.balance = (customer.balance or _ZERO) - refund_total
            customer.save(update_fields=["balance", "updated_at"])

        sale_return.refresh_from_db()
        # A return moves revenue, stock and possibly a customer's balance —
        # every headline figure on the dashboard. It refreshed none of them.
        refresh_projection_after_write(membership.shop, context="a return")
        return Response(_serialize(sale_return), status=status.HTTP_201_CREATED)


class SaleReturnListView(APIView):
    """Returns processed by this shop."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(request.user, shop_id, RETURN_ROLE)
        rows = (
            SaleReturn.objects.filter(shop=membership.shop)
            .select_related("sale")
            .prefetch_related("lines")[:200]
        )
        returns = [_serialize(r) for r in rows]
        return Response(
            {
                "returns": returns,
                "refunded_total": str(
                    sum((Decimal(r["refund_amount"]) for r in returns), _ZERO)
                ),
            }
        )

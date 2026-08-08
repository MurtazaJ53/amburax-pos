"""Purchase orders: the gap between ordered and received.

A Purchase already IS the goods-received event — creating one posts stock,
refreshes cost price and moves the supplier's payables. What was missing was
everything before it. An order placed and never delivered looked identical to
an order never placed, so nobody chased the supplier, and the reorder list
went on saying "buy this" for stock already on a van.

So a purchase order touches no stock and no money. Receiving one builds a
normal Purchase through the existing PurchaseSerializer, which means stock,
costing and payables behave exactly as they do for a purchase typed in by
hand. None of that logic is repeated here — repeating it is how the two paths
drift apart.
"""
from __future__ import annotations

import secrets
from decimal import Decimal, InvalidOperation

from django.db import transaction
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import exceptions, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.common.emailer import send_email
from platform_apps.inventory.models import InventoryItem
from platform_apps.purchases.models import (
    PurchaseOrder,
    PurchaseOrderLine,
    Supplier,
)
from platform_apps.purchases.serializers import PurchaseSerializer
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

_ZERO = Decimal("0")

#: Ordering commits the shop's money, so it is not a cashier's decision.
ORDER_ROLE = ShopMembership.Role.MANAGER


def _make_reference() -> str:
    """Short handle for the order, safe to read aloud over a phone."""
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "PO-" + "".join(secrets.choice(alphabet) for _ in range(4))


def _decimal(raw, field: str, *, allow_zero: bool = False) -> Decimal:
    try:
        value = Decimal(str(raw))
    except (InvalidOperation, TypeError, ValueError):
        raise exceptions.ValidationError({field: "Must be a number."})
    if value < _ZERO or (value == _ZERO and not allow_zero):
        raise exceptions.ValidationError({field: "Must be greater than zero."})
    return value


def _serialize(order: PurchaseOrder) -> dict:
    today = timezone.localdate()
    lines = list(order.lines.all())
    outstanding_value = sum(
        (line.quantity_outstanding * line.unit_cost for line in lines), _ZERO
    )
    return {
        "id": str(order.id),
        "reference": order.reference,
        "status": order.status,
        "supplier_id": str(order.supplier_id) if order.supplier_id else None,
        "supplier_name": order.supplier_name_snapshot,
        "expected_date": order.expected_date.isoformat() if order.expected_date else None,
        # Only meaningful once ordered: a draft nobody sent is not late.
        "is_overdue": bool(
            order.expected_date
            and order.expected_date < today
            and order.status
            in (PurchaseOrder.Status.ORDERED, PurchaseOrder.Status.PARTIALLY_RECEIVED)
        ),
        "note": order.note,
        "ordered_at": order.ordered_at.isoformat() if order.ordered_at else None,
        "closed_at": order.closed_at.isoformat() if order.closed_at else None,
        "outstanding_value": str(outstanding_value.quantize(Decimal("0.01"))),
        "lines": [
            {
                "id": str(line.id),
                "inventory_item_id": (
                    str(line.inventory_item_id) if line.inventory_item_id else None
                ),
                "name": line.name_snapshot,
                "sku": line.sku_snapshot,
                "quantity_ordered": str(line.quantity_ordered),
                "quantity_received": str(line.quantity_received),
                "quantity_outstanding": str(line.quantity_outstanding),
                "unit_cost": str(line.unit_cost),
            }
            for line in lines
        ],
    }


def _refresh_status(order: PurchaseOrder) -> None:
    """Derive the order's state from its lines rather than trusting a flag.

    A status set by hand drifts from the quantities the moment a receipt is
    edited; computing it means the badge can never disagree with the numbers
    underneath it.
    """
    if order.status in (PurchaseOrder.Status.CANCELLED, PurchaseOrder.Status.DRAFT):
        return

    lines = list(order.lines.all())
    if lines and all(line.quantity_outstanding <= _ZERO for line in lines):
        order.status = PurchaseOrder.Status.RECEIVED
        order.closed_at = order.closed_at or timezone.now()
    elif any(line.quantity_received > _ZERO for line in lines):
        order.status = PurchaseOrder.Status.PARTIALLY_RECEIVED
        order.closed_at = None
    else:
        order.status = PurchaseOrder.Status.ORDERED
        order.closed_at = None
    order.save(update_fields=["status", "closed_at", "updated_at"])


class PurchaseOrderListCreateView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        # Staff receive deliveries, so staff can see what is expected.
        membership = get_membership_or_403(request.user, shop_id)

        orders = PurchaseOrder.objects.filter(shop=membership.shop)
        state = request.query_params.get("status")
        if state in PurchaseOrder.Status.values:
            orders = orders.filter(status=state)
        elif request.query_params.get("open") == "1":
            orders = orders.filter(
                status__in=[
                    PurchaseOrder.Status.ORDERED,
                    PurchaseOrder.Status.PARTIALLY_RECEIVED,
                ]
            )

        orders = orders.select_related("supplier").prefetch_related("lines")[:200]
        rows = [_serialize(order) for order in orders]

        return Response(
            {
                "orders": rows,
                "open_count": sum(
                    1
                    for r in rows
                    if r["status"]
                    in (
                        PurchaseOrder.Status.ORDERED,
                        PurchaseOrder.Status.PARTIALLY_RECEIVED,
                    )
                ),
                "overdue_count": sum(1 for r in rows if r["is_overdue"]),
            }
        )

    @transaction.atomic
    def post(self, request, shop_id):
        membership = get_membership_or_403(request.user, shop_id, ORDER_ROLE)
        shop = membership.shop

        supplier = None
        supplier_id = request.data.get("supplier_id")
        if supplier_id:
            supplier = get_object_or_404(
                Supplier, id=supplier_id, shop=shop, tombstone=False
            )

        raw_lines = request.data.get("lines")
        if not isinstance(raw_lines, list) or not raw_lines:
            raise exceptions.ValidationError({"lines": "Add at least one item."})

        send_now = bool(request.data.get("place", True))
        order = PurchaseOrder.objects.create(
            shop=shop,
            supplier=supplier,
            supplier_name_snapshot=(
                str(request.data.get("supplier_name") or "")[:255]
                or (supplier.name if supplier else "")
            ),
            created_by=request.user,
            reference=str(request.data.get("reference") or _make_reference())[:32],
            note=str(request.data.get("note") or "")[:2000],
            expected_date=request.data.get("expected_date") or None,
            status=(
                PurchaseOrder.Status.ORDERED
                if send_now
                else PurchaseOrder.Status.DRAFT
            ),
            ordered_at=timezone.now() if send_now else None,
        )

        for raw in raw_lines:
            raw = raw or {}
            item = None
            if raw.get("item_id"):
                item = get_object_or_404(
                    InventoryItem, id=raw["item_id"], shop=shop, tombstone=False
                )
            name = str(raw.get("name") or (item.name if item else "")).strip()
            if not name:
                # A line with no catalogue item and no name cannot be received
                # against anything, so it is worthless on the order.
                raise exceptions.ValidationError(
                    {"lines": "Each line needs an item or a name."}
                )

            PurchaseOrderLine.objects.create(
                order=order,
                inventory_item=item,
                name_snapshot=name[:255],
                sku_snapshot=str(raw.get("sku") or (item.sku if item else ""))[:128],
                quantity_ordered=_decimal(raw.get("quantity"), "quantity"),
                unit_cost=_decimal(raw.get("unit_cost", 0), "unit_cost", allow_zero=True),
            )

        order.refresh_from_db()
        return Response(_serialize(order), status=status.HTTP_201_CREATED)


class PurchaseOrderDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id, order_id):
        membership = get_membership_or_403(request.user, shop_id)
        order = get_object_or_404(PurchaseOrder, id=order_id, shop=membership.shop)
        return Response(_serialize(order))

    @transaction.atomic
    def delete(self, request, shop_id, order_id):
        """Cancel an order. Anything already received stays received."""
        membership = get_membership_or_403(request.user, shop_id, ORDER_ROLE)
        order = get_object_or_404(
            PurchaseOrder.objects.select_for_update(), id=order_id, shop=membership.shop
        )
        if order.status == PurchaseOrder.Status.RECEIVED:
            raise exceptions.ValidationError(
                {"status": "This order has already been fully received."}
            )
        order.status = PurchaseOrder.Status.CANCELLED
        order.closed_at = timezone.now()
        order.save(update_fields=["status", "closed_at", "updated_at"])
        return Response(_serialize(order))


def _order_email_html(order, lines) -> tuple[str, str]:
    """The order as an email a supplier can act on.

    Both HTML and plain text: many small-supplier mailboxes strip HTML, and a
    purchase order that arrives as an empty message is worse than none.

    Deliberately excludes anything the supplier should not see. They are told
    what is being ordered and at what rate — not what the shop sells it for,
    nor which other suppliers exist.
    """
    shop = order.shop
    rows_html = "".join(
        f"<tr><td style='padding:6px 10px;border-bottom:1px solid #eee'>{line.name_snapshot}</td>"
        f"<td style='padding:6px 10px;border-bottom:1px solid #eee'>{line.sku_snapshot}</td>"
        f"<td style='padding:6px 10px;border-bottom:1px solid #eee;text-align:right'>{line.quantity_ordered}</td>"
        f"<td style='padding:6px 10px;border-bottom:1px solid #eee;text-align:right'>{line.unit_cost}</td></tr>"
        for line in lines
    )
    expected = (
        f"<p>Expected by: <b>{order.expected_date}</b></p>" if order.expected_date else ""
    )
    note = f"<p>{order.note}</p>" if order.note.strip() else ""
    html = (
        f"<div style='font-family:sans-serif;max-width:600px'>"
        f"<h2 style='margin-bottom:4px'>Purchase order {order.reference}</h2>"
        f"<p style='color:#555;margin-top:0'>From <b>{shop.name}</b></p>"
        f"{expected}"
        f"<table style='border-collapse:collapse;width:100%;font-size:14px'>"
        f"<thead><tr>"
        f"<th style='text-align:left;padding:6px 10px;border-bottom:2px solid #333'>Item</th>"
        f"<th style='text-align:left;padding:6px 10px;border-bottom:2px solid #333'>SKU</th>"
        f"<th style='text-align:right;padding:6px 10px;border-bottom:2px solid #333'>Qty</th>"
        f"<th style='text-align:right;padding:6px 10px;border-bottom:2px solid #333'>Rate</th>"
        f"</tr></thead><tbody>{rows_html}</tbody></table>"
        f"{note}"
        f"<p style='color:#777;font-size:12px'>Please confirm availability and "
        f"delivery date by replying to this email.</p></div>"
    )

    text_lines = [f"Purchase order {order.reference}", f"From: {shop.name}"]
    if order.expected_date:
        text_lines.append(f"Expected by: {order.expected_date}")
    text_lines.append("")
    for line in lines:
        sku = f" ({line.sku_snapshot})" if line.sku_snapshot else ""
        text_lines.append(
            f"  {line.name_snapshot}{sku} — {line.quantity_ordered} @ {line.unit_cost}"
        )
    if order.note.strip():
        text_lines += ["", order.note.strip()]
    text_lines += ["", "Please confirm availability and delivery date by reply."]
    return html, "\n".join(text_lines)


class PurchaseOrderSendView(APIView):
    """Email the order to the supplier.

    Recording an order in the system does not tell the supplier anything, so
    until now the shop still had to communicate it by whatever means it already
    used. This closes that gap for suppliers who have an email address.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, shop_id, order_id):
        membership = get_membership_or_403(request.user, shop_id, ORDER_ROLE)
        order = get_object_or_404(PurchaseOrder, id=order_id, shop=membership.shop)

        if order.status == PurchaseOrder.Status.CANCELLED:
            raise exceptions.ValidationError(
                {"status": "This order was cancelled."}
            )

        to = (request.data.get("email") or "").strip()
        if not to and order.supplier_id:
            to = (order.supplier.email or "").strip()
        if not to:
            raise exceptions.ValidationError(
                {"email": "This supplier has no email address. Add one, or "
                          "pass an address to send to."}
            )

        lines = list(order.lines.all())
        if not lines:
            raise exceptions.ValidationError({"lines": "This order has no items."})

        html, text = _order_email_html(order, lines)
        result = send_email(
            to=to,
            subject=f"Purchase order {order.reference} from {membership.shop.name}",
            html=html,
            text=text,
        )

        # A draft that has now been communicated is, in every sense that
        # matters, an order. Sending it is the act of placing it.
        if order.status == PurchaseOrder.Status.DRAFT and result.get("ok"):
            order.status = PurchaseOrder.Status.ORDERED
            order.ordered_at = timezone.now()
            order.save(update_fields=["status", "ordered_at", "updated_at"])

        # The provider's own outcome is passed through rather than flattened to
        # "sent": a shop whose sending domain is unverified needs to know the
        # supplier never received it.
        return Response(
            {
                "sent": bool(result.get("ok")),
                "skipped": bool(result.get("skipped")),
                "to": to,
                "detail": result.get("status") or result.get("error") or "",
                "order": _serialize(order),
            },
            status=status.HTTP_200_OK,
        )


class PurchaseOrderReceiveView(APIView):
    """Book in a delivery against an order.

    Partial is the normal case, not the exception: suppliers short-ship, and a
    van arrives with eight of the ten cartons. Each receipt records what
    actually turned up and leaves the rest outstanding.
    """

    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, shop_id, order_id):
        membership = get_membership_or_403(request.user, shop_id, ORDER_ROLE)
        shop = membership.shop
        order = get_object_or_404(
            PurchaseOrder.objects.select_for_update(), id=order_id, shop=shop
        )

        if order.status in (
            PurchaseOrder.Status.CANCELLED,
            PurchaseOrder.Status.RECEIVED,
        ):
            raise exceptions.ValidationError(
                {"status": f"This order is already {order.get_status_display().lower()}."}
            )

        raw_lines = request.data.get("lines")
        if not isinstance(raw_lines, list) or not raw_lines:
            raise exceptions.ValidationError({"lines": "Say what actually arrived."})

        purchase_items = []
        touched: list[PurchaseOrderLine] = []
        seen: set[str] = set()

        for raw in raw_lines:
            raw = raw or {}
            line_id = raw.get("line_id")
            if not line_id:
                raise exceptions.ValidationError({"lines": "Each line needs a line_id."})
            if str(line_id) in seen:
                raise exceptions.ValidationError(
                    {"lines": "The same line appears more than once."}
                )
            seen.add(str(line_id))

            line = get_object_or_404(PurchaseOrderLine, id=line_id, order=order)
            quantity = _decimal(raw.get("quantity"), "quantity", allow_zero=True)
            if quantity == _ZERO:
                continue

            # Over-receiving is almost always a typo, and it silently inflates
            # stock and the bill. Reject it and let a human look.
            if quantity > line.quantity_outstanding:
                raise exceptions.ValidationError(
                    {
                        "lines": (
                            f"{line.name_snapshot}: only {line.quantity_outstanding} "
                            f"still outstanding, cannot receive {quantity}."
                        )
                    }
                )

            # The supplier may bill a different rate than quoted; honour what
            # actually arrived so cost price reflects reality.
            unit_cost = (
                _decimal(raw["unit_cost"], "unit_cost", allow_zero=True)
                if raw.get("unit_cost") is not None
                else line.unit_cost
            )

            item_payload = {
                "quantity": str(quantity),
                "unit_cost": str(unit_cost),
                "name": line.name_snapshot,
                "sku": line.sku_snapshot,
            }
            if line.inventory_item_id:
                item_payload["inventory_item_id"] = str(line.inventory_item_id)
            purchase_items.append(item_payload)

            line.quantity_received = line.quantity_received + quantity
            line.unit_cost = unit_cost
            touched.append(line)

        if not purchase_items:
            raise exceptions.ValidationError({"lines": "Nothing was received."})

        # Hand off to the ordinary purchase path so stock, cost price and
        # payables are posted by the same code as a hand-entered purchase.
        serializer = PurchaseSerializer(
            data={
                "supplier_id": str(order.supplier_id) if order.supplier_id else None,
                "supplier_name": order.supplier_name_snapshot,
                "invoice_number": str(request.data.get("invoice_number") or "")[:64],
                "reference": order.reference,
                "payment_mode": request.data.get("payment_mode") or "CREDIT",
                "amount_paid": str(request.data.get("amount_paid") or "0"),
                "note": f"Against order {order.reference}",
                "items": purchase_items,
            },
            context={"shop": shop, "actor": request.user, "request": request},
        )
        serializer.is_valid(raise_exception=True)
        purchase = serializer.save()

        for line in touched:
            line.save(update_fields=["quantity_received", "unit_cost", "updated_at"])

        order.refresh_from_db()
        _refresh_status(order)
        order.refresh_from_db()

        payload = _serialize(order)
        payload["purchase_id"] = str(purchase.id)
        return Response(payload, status=status.HTTP_201_CREATED)

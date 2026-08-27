"""The end-of-day register close.

A day close answers one question a shopkeeper must be able to answer months
later: was the drawer right, and if not, by how much and who counted it. That
record has to survive a cleared browser and be readable from any device, so it
lives here rather than in localStorage.

Design notes worth keeping:

- The close is addressed by business date, not by id. The client always knows
  which day it is looking at and never has to hunt for a session id.
- Locking is one-way from this API's point of view. Reopening a locked day is
  a deliberate act with an audit trail, not an accidental PATCH.
- `expected_cash` is computed here from the sales table, never accepted from
  the client. A till figure the browser can post is a till figure that can be
  made to say anything.
"""
from __future__ import annotations

from datetime import date as date_cls
from decimal import Decimal, InvalidOperation

from django.db import IntegrityError, transaction
from django.db.models import DecimalField, Sum, Value
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import exceptions, permissions, serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.payments.models import SalePayment
from platform_apps.sales import returns_summary
from platform_apps.sales.models import RegisterSession, Sale
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

_ZERO = Decimal("0.00")


def _parse_date(raw) -> date_cls:
    """The business date, defaulting to today rather than erroring.

    A cashier opening the screen means "today"; making them pass a date to see
    the day they are standing in would be hostile.
    """
    text = str(raw or "").strip()
    if not text:
        return timezone.localdate()
    try:
        return date_cls.fromisoformat(text)
    except ValueError:
        raise exceptions.ValidationError({"date": "Expected YYYY-MM-DD."})


def _money(raw, field: str) -> Decimal:
    try:
        value = Decimal(str(raw))
    except (InvalidOperation, TypeError, ValueError):
        raise exceptions.ValidationError({field: "Expected a number."})
    if value < 0:
        # A negative count is always a typo, and silently absorbing it would
        # turn into a fabricated shortfall.
        raise exceptions.ValidationError({field: "Cannot be negative."})
    return value.quantize(Decimal("0.01"))


def cash_taken(shop, business_date: date_cls) -> Decimal:
    """Cash that actually entered the drawer on this trading day.

    Read from the tender rows, not `Sale.payment_mode`: a split bill settled
    partly in cash is stored as SPLIT, so bucketing on the mode loses the cash
    entirely - which is exactly the money this screen is reconciling. Voided
    sales are excluded because their cash was handed back.
    """
    total = (
        SalePayment.objects.filter(
            sale__shop=shop,
            sale__sale_date=business_date,
            sale__tombstone=False,
            payment_method__iexact="CASH",
        )
        .exclude(sale__status=Sale.Status.VOID)
        .aggregate(
            total=Coalesce(
                Sum("amount"),
                Value(_ZERO),
                output_field=DecimalField(max_digits=14, decimal_places=2),
            )
        )["total"]
    )

    # Cash handed back over the counter is cash that left the drawer. Without
    # this the expected figure is high by every refund given that day, and the
    # count comes up short by exactly that much - which reads as a cashier
    # being light, not as a report being wrong. That is an accusation, and it
    # is the kind that gets someone spoken to before anybody checks the code.
    refunded = returns_summary.for_day(shop, business_date).cash_paid_out

    return ((total or _ZERO) - refunded).quantize(Decimal("0.01"))


class RegisterSessionSerializer(serializers.ModelSerializer):
    closed_by_name = serializers.SerializerMethodField()
    is_locked = serializers.BooleanField(read_only=True)

    class Meta:
        model = RegisterSession
        fields = (
            "id",
            "business_date",
            "opening_float",
            "counted_cash",
            "cash_sales",
            "expected_cash",
            "discrepancy",
            "float_entered",
            "notes",
            "closed_at",
            "closed_by_name",
            "is_locked",
        )
        read_only_fields = fields

    def get_closed_by_name(self, obj):
        if not obj.closed_by_id:
            return None
        return obj.closed_by.full_name or obj.closed_by.email


class RegisterSessionView(APIView):
    """Read, save, and lock one shop-day's register close."""

    permission_classes = [permissions.IsAuthenticated]

    def _payload(self, session, shop, business_date):
        """A close plus the live figures the screen needs to show it.

        While the day is open the tender totals are read fresh, so the expected
        figure tracks sales as they are rung up. Once locked, the stored
        snapshot wins - a later return must not rewrite a signed-off day.
        """
        if session is not None and session.is_locked:
            live_cash = session.cash_sales if session.cash_sales is not None else _ZERO
            expected = session.expected_cash if session.expected_cash is not None else _ZERO
        else:
            live_cash = cash_taken(shop, business_date)
            opening = session.opening_float if session else _ZERO
            expected = (opening + live_cash).quantize(Decimal("0.01"))

        return {
            "business_date": business_date.isoformat(),
            "cash_sales": live_cash,
            "expected_cash": expected,
            "session": RegisterSessionSerializer(session).data if session else None,
        }

    def get(self, request, shop_id):
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.VIEWER
        )
        business_date = _parse_date(request.query_params.get("date"))
        session = (
            RegisterSession.objects.filter(
                shop=membership.shop, business_date=business_date
            )
            .select_related("closed_by")
            .first()
        )
        return Response(self._payload(session, membership.shop, business_date))

    @transaction.atomic
    def put(self, request, shop_id):
        """Save the in-progress count, or lock the day when `lock` is true."""
        # Whoever works the till closes the till, so STAFF is the floor. The
        # figures here are takings and a drawer count: no cost prices, no
        # margins.
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.STAFF
        )
        shop = membership.shop
        business_date = _parse_date(request.data.get("business_date"))

        session = (
            RegisterSession.objects.select_for_update()
            .filter(shop=shop, business_date=business_date)
            .first()
        )
        if session is not None and session.is_locked:
            # A locked day is a signed record. Silently accepting the write and
            # discarding it would be worse than refusing it.
            raise exceptions.ValidationError(
                {"detail": "This day is already closed and cannot be edited."}
            )

        float_entered = bool(request.data.get("float_entered", False))
        opening_float = _money(request.data.get("opening_float", 0), "opening_float")
        counted_cash = _money(request.data.get("counted_cash", 0), "counted_cash")
        notes = str(request.data.get("notes") or "")
        lock = bool(request.data.get("lock", False))

        if lock and not float_entered:
            # Without a float, "expected in till" is a guess, and every
            # over/short built on it accuses someone on the strength of a
            # number nobody entered.
            raise exceptions.ValidationError(
                {"detail": "Enter the opening float before closing the day."}
            )

        if session is None:
            session = RegisterSession(shop=shop, business_date=business_date)

        session.opening_float = opening_float
        session.counted_cash = counted_cash
        session.float_entered = float_entered
        session.notes = notes

        if lock:
            live_cash = cash_taken(shop, business_date)
            expected = (opening_float + live_cash).quantize(Decimal("0.01"))
            session.cash_sales = live_cash
            session.expected_cash = expected
            session.discrepancy = (counted_cash - expected).quantize(Decimal("0.01"))
            session.closed_by = request.user
            session.closed_at = timezone.now()

        try:
            session.save()
        except IntegrityError:
            # Two cashiers locking the same drawer at once. The unique
            # constraint is the arbiter; the loser re-reads rather than
            # overwriting a record they never saw.
            raise exceptions.ValidationError(
                {"detail": "This day was just closed on another device. Reload to see it."}
            )

        session = RegisterSession.objects.select_related("closed_by").get(pk=session.pk)
        return Response(self._payload(session, shop, business_date))


class RegisterSessionHistoryView(APIView):
    """Past closes, so an over/short can be looked up months later."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.VIEWER
        )
        sessions = (
            RegisterSession.objects.filter(
                shop=membership.shop, closed_at__isnull=False
            )
            .select_related("closed_by")
            .order_by("-business_date")[:60]
        )
        return Response(
            {"sessions": RegisterSessionSerializer(sessions, many=True).data}
        )

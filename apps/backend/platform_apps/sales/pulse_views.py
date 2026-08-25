"""Business pulse: what is selling, and whether the shop kept any money.

The dead-stock report answers "what isn't moving". These are the other side of
that question, and the two an owner actually asks day to day.
"""
from __future__ import annotations

from datetime import date as date_cls, timedelta
from decimal import Decimal

from django.db.models import Count, DecimalField, F, Sum
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import exceptions, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.expenses.models import Expense
from platform_apps.purchases.models import Purchase
from platform_apps.sales.models import Sale, SaleItem
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

_ZERO = Decimal("0.00")


def _window(request, shop=None, default_days: int = 30):
    """The window a report covers, as (start, end, days).

    `days` alone could only ever mean "the last N days ending today". That
    cannot express yesterday, a custom window that ended last month, or all
    of history - so a screen offering those presets would have been showing a
    filter that quietly did something else.

    date_from/date_to win where given; `days` remains for existing callers,
    and `all=1` asks for everything.
    """
    today = timezone.localdate()

    if str(request.query_params.get("all") or "").lower() in {"1", "true", "yes"}:
        # A real start date rather than year zero, so the window a report
        # prints matches the data behind it.
        earliest = (
            Sale.objects.filter(shop=shop, tombstone=False)
            .exclude(status=Sale.Status.VOID)
            .order_by("sale_date")
            .values_list("sale_date", flat=True)
            .first()
            if shop is not None
            else None
        )
        start = earliest or today
        return start, today, max(1, (today - start).days)

    raw_from = str(request.query_params.get("date_from") or "").strip()
    raw_to = str(request.query_params.get("date_to") or "").strip()
    if raw_from or raw_to:
        try:
            start = date_cls.fromisoformat(raw_from) if raw_from else today
            end = date_cls.fromisoformat(raw_to) if raw_to else today
        except ValueError:
            raise exceptions.ValidationError(
                {"date_from": "Expected YYYY-MM-DD."}
            )
        if start > end:
            start, end = end, start
        return start, end, max(1, (end - start).days + 1)

    try:
        days = int(request.query_params.get("days", default_days))
    except (TypeError, ValueError):
        days = default_days
    # Keep the window sane: a huge value would scan the whole table for a
    # dashboard card.
    days = max(1, min(days, 365))
    return today - timedelta(days=days), today, days


class BestSellersView(APIView):
    """Top products by quantity sold, with revenue and (where known) profit."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.VIEWER
        )
        since, until, days = _window(request, membership.shop)
        try:
            limit = int(request.query_params.get("limit", 20))
        except (TypeError, ValueError):
            limit = 20
        limit = max(1, min(limit, 100))

        rows = (
            SaleItem.objects.filter(
                sale__shop=membership.shop,
                sale__tombstone=False,
                sale__sale_date__gte=since,
                sale__sale_date__lte=until,
            )
            # A refunded bill must not keep a product in the best-seller list.
            .exclude(sale__status=Sale.Status.VOID)
            .values("name_snapshot")
            .annotate(
                quantity_sold=Coalesce(Sum("quantity"), Decimal("0")),
                revenue=Coalesce(
                    Sum(F("line_total") - F("line_discount")),
                    _ZERO,
                    output_field=DecimalField(max_digits=14, decimal_places=2),
                ),
                # Only lines that actually carry a cost can contribute profit.
                cost=Coalesce(
                    Sum(F("unit_cost") * F("quantity")),
                    _ZERO,
                    output_field=DecimalField(max_digits=14, decimal_places=2),
                ),
                priced_lines=Count("unit_cost"),
                total_lines=Count("id"),
            )
            .order_by("-quantity_sold")[:limit]
        )

        results = []
        for row in rows:
            # Report profit only when EVERY line had a cost. A partial figure
            # looks authoritative and is quietly wrong.
            complete = row["priced_lines"] == row["total_lines"] and row["total_lines"] > 0
            results.append(
                {
                    "name": row["name_snapshot"] or "Unknown item",
                    "quantity_sold": row["quantity_sold"] or Decimal("0"),
                    "revenue": row["revenue"] or _ZERO,
                    "profit": (row["revenue"] - row["cost"]) if complete else None,
                }
            )
        return Response({"days": days, "items": results})


class CashFlowView(APIView):
    """Money in versus money out over a window."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.MANAGER
        )
        since, until, days = _window(request, membership.shop)

        collected = (
            Sale.objects.filter(
                shop=membership.shop,
                tombstone=False,
                sale_date__gte=since,
                sale_date__lte=until,
            )
            .exclude(status=Sale.Status.VOID)
            .aggregate(total=Coalesce(Sum("amount_received"), _ZERO))["total"]
        )
        # Only what was actually PAID to suppliers — an unpaid invoice hasn't
        # left the till yet.
        purchases = Purchase.objects.filter(
            shop=membership.shop,
            tombstone=False,
            purchase_date__gte=since,
            purchase_date__lte=until,
        ).aggregate(total=Coalesce(Sum("amount_paid"), _ZERO))["total"]

        expenses = Expense.objects.filter(
            shop=membership.shop,
            tombstone=False,
            expense_date__gte=since,
            expense_date__lte=until,
        ).aggregate(total=Coalesce(Sum("amount"), _ZERO))["total"]

        money_out = purchases + expenses
        return Response(
            {
                "days": days,
                "sales_collected": collected,
                "purchases": purchases,
                "expenses": expenses,
                "money_out": money_out,
                "net": collected - money_out,
            }
        )

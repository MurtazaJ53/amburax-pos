"""Takings over any window the shopkeeper asks for.

The dashboard could only ever answer "today". Every other question - how was
last month, is this quarter better than the last, what did the year do - meant
reading the sales list by eye.

Three things this does that the existing summary endpoint does not:

- Buckets the window into a series, so the shape of the period is visible and
  not just its total.
- Reads the payment mix from TENDER ROWS rather than `Sale.payment_mode`. A
  split bill is stored as SPLIT, so bucketing on the mode loses the cash and
  the UPI inside it entirely.
- Returns the immediately preceding, equally long window, so the comparison is
  computed on the server against all sales rather than against whatever page
  of history the browser happens to be holding.
"""
from __future__ import annotations

from datetime import date as date_cls, timedelta
from decimal import Decimal

from django.db.models import DecimalField, Sum, Value
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import exceptions, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.payments.models import SalePayment
from platform_apps.sales.models import Sale
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

_ZERO = Decimal("0.00")

#: A window longer than this is refused rather than served slowly. Five years
#: is past any question a shop counter asks, and an unbounded range invites a
#: scan of the whole sales table.
MAX_RANGE_DAYS = 366 * 5

MIX_LABELS = {
    "CASH": "Cash",
    "UPI": "UPI",
    "CARD": "Card",
    "BANK": "Bank",
    "CREDIT": "Khata",
    "OTHER": "Other",
    # A split bill whose tender rows were never written. The breakdown is
    # genuinely unknown; calling it cash would be inventing it.
    "SPLIT": "Split (not itemised)",
    "UNPAID": "Still owed",
}


def _parse(raw, field: str, fallback: date_cls) -> date_cls:
    text = str(raw or "").strip()
    if not text:
        return fallback
    try:
        return date_cls.fromisoformat(text)
    except ValueError:
        raise exceptions.ValidationError({field: "Expected YYYY-MM-DD."})


def _money(value) -> Decimal:
    return (value or _ZERO).quantize(Decimal("0.01"))


def _sum(queryset, field: str) -> Decimal:
    return _money(
        queryset.aggregate(
            total=Coalesce(
                Sum(field),
                Value(_ZERO),
                output_field=DecimalField(max_digits=14, decimal_places=2),
            )
        )["total"]
    )


class SaleTakingsView(APIView):
    """Totals, mix and a series for one date window."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.VIEWER
        )
        shop = membership.shop
        today = timezone.localdate()

        # "All time" has no start date, so one is found rather than guessed:
        # the shop's first trading day. Without it the series would have to
        # begin at an arbitrary date and draw empty months before the shop
        # existed.
        all_time = str(request.query_params.get("all") or "").lower() in {"1", "true", "yes"}
        if all_time:
            earliest = (
                Sale.objects.filter(shop=shop, tombstone=False)
                .exclude(status=Sale.Status.VOID)
                .order_by("sale_date")
                .values_list("sale_date", flat=True)
                .first()
            )
            date_from = earliest or today
            date_to = today
        else:
            date_from = _parse(request.query_params.get("from"), "from", today)
            date_to = _parse(request.query_params.get("to"), "to", today)
            if date_from > date_to:
                # Obvious what was meant; refusing it would be pedantry.
                date_from, date_to = date_to, date_from

        span = (date_to - date_from).days + 1
        # The length guard exists to stop an unbounded scan being asked for by
        # accident. All time is asked for on purpose, and its start is a real
        # date from the shop's own history, so it is exempt.
        if not all_time and span > MAX_RANGE_DAYS:
            raise exceptions.ValidationError(
                {"detail": f"Range too long. Ask for {MAX_RANGE_DAYS} days or fewer."}
            )

        sales = self._sales(shop, date_from, date_to)
        total = _sum(sales, "total_amount")
        bill_count = sales.count()

        # The preceding window of EQUAL length. Comparing a 30-day month
        # against a 31-day one manufactures a change that did not happen.
        previous_to = date_from - timedelta(days=1)
        previous_from = previous_to - timedelta(days=span - 1)
        previous_total = _sum(
            self._sales(shop, previous_from, previous_to), "total_amount"
        )

        return Response(
            {
                "from": date_from.isoformat(),
                "to": date_to.isoformat(),
                "days": span,
                "total": total,
                "bill_count": bill_count,
                "average_bill": (
                    (total / bill_count).quantize(Decimal("0.01")) if bill_count else _ZERO
                ),
                "previous_total": previous_total,
                "previous_from": previous_from.isoformat(),
                "previous_to": previous_to.isoformat(),
                "mix": self._mix(shop, date_from, date_to),
                "series": self._series(shop, date_from, date_to, span),
                "granularity": self._granularity(span),
            }
        )

    # --- pieces ----------------------------------------------------------

    @staticmethod
    def _sales(shop, date_from: date_cls, date_to: date_cls):
        # Voided sales are excluded everywhere: a refunded bill that still
        # counts toward takings is a figure nobody can reconcile.
        return Sale.objects.filter(
            shop=shop,
            tombstone=False,
            sale_date__gte=date_from,
            sale_date__lte=date_to,
        ).exclude(status=Sale.Status.VOID)

    @staticmethod
    def _granularity(span: int) -> str:
        if span <= 1:
            return "hour"
        if span <= 92:
            return "day"
        return "month"

    def _mix(self, shop, date_from: date_cls, date_to: date_cls):
        """How the money arrived, covering ALL of it.

        Tender rows are the truth where they exist: a split bill is stored as
        SPLIT, so bucketing on `payment_mode` loses the cash and the UPI inside
        it. But only sales rung up through the POS have tenders. Imported and
        synced history has none, and reading tenders alone silently reported a
        year of takings as the few hundred rupees that happened to have them -
        a mix bar covering 0.25% of the total sitting under the total.

        So: tenders where present, the sale's own mode where not, and what is
        still owed named as owed. The slices add up to the headline figure,
        which is the only way the bar can be trusted.
        """
        sales = self._sales(shop, date_from, date_to)
        totals: dict[str, Decimal] = {}

        def add(key: str, amount) -> None:
            value = _money(amount)
            if value > _ZERO:
                totals[key] = totals.get(key, _ZERO) + value

        # 1. Real tenders. This join only reaches sales that have them.
        for row in (
            SalePayment.objects.filter(
                sale__shop=shop,
                sale__tombstone=False,
                sale__sale_date__gte=date_from,
                sale__sale_date__lte=date_to,
            )
            .exclude(sale__status=Sale.Status.VOID)
            .values("payment_method")
            .annotate(
                amount=Coalesce(
                    Sum("amount"),
                    Value(_ZERO),
                    output_field=DecimalField(max_digits=14, decimal_places=2),
                )
            )
        ):
            add((row["payment_method"] or "OTHER").upper(), row["amount"])

        # 2. Sales with no tenders: fall back to the mode on the sale itself.
        #    `amount_received` is derived where it was never populated, which
        #    is the case for most imported history.
        for row in (
            # `payments__isnull=True` and NOT annotate(Count).filter(count=0).
            # The count filter becomes a HAVING that is re-evaluated after the
            # regrouping by payment_mode, so a mode holding any tendered sale
            # loses ALL its untendered ones - cash silently disappeared from
            # the mix the moment one cash sale had tender rows.
            sales.filter(payments__isnull=True)
            .values("payment_mode")
            .annotate(
                received=Coalesce(
                    Sum("amount_received"),
                    Value(_ZERO),
                    output_field=DecimalField(max_digits=14, decimal_places=2),
                ),
                gross=Coalesce(
                    Sum("total_amount"),
                    Value(_ZERO),
                    output_field=DecimalField(max_digits=14, decimal_places=2),
                ),
                due=Coalesce(
                    Sum("amount_due"),
                    Value(_ZERO),
                    output_field=DecimalField(max_digits=14, decimal_places=2),
                ),
            )
        ):
            mode = (row["payment_mode"] or "OTHER").upper()
            received = row["received"] or _ZERO
            if received <= _ZERO:
                received = (row["gross"] or _ZERO) - (row["due"] or _ZERO)
            # A SPLIT with no tender rows cannot be broken down. Claiming it
            # as cash would be inventing the answer.
            add("SPLIT" if mode == "SPLIT" else mode, received)

        # 3. What has not been paid yet, named rather than left as a gap
        #    between the mix and the total nobody can account for.
        add("UNPAID", _sum(sales, "amount_due"))

        mix = [
            {
                "key": key,
                "label": MIX_LABELS.get(key, key.title()),
                "amount": amount,
                "count": 0,
            }
            for key, amount in totals.items()
        ]
        mix.sort(key=lambda slice_: slice_["amount"], reverse=True)
        return mix

    def _series(self, shop, date_from: date_cls, date_to: date_cls, span: int):
        """Buckets for the chart, with empty periods kept.

        Dropping a zero day would compress a quiet week into a shorter line
        and make a slump look like normal trading.
        """
        granularity = self._granularity(span)
        sales = self._sales(shop, date_from, date_to)

        if granularity == "hour":
            buckets = {hour: _ZERO for hour in range(24)}
            for sale in sales.only("occurred_at", "total_amount"):
                local = timezone.localtime(sale.occurred_at)
                buckets[local.hour] += sale.total_amount or _ZERO
            return [
                {"label": f"{hour:02d}:00", "amount": _money(amount)}
                for hour, amount in sorted(buckets.items())
            ]

        totals = {
            row["sale_date"]: row["amount"]
            for row in sales.values("sale_date").annotate(
                amount=Coalesce(
                    Sum("total_amount"),
                    Value(_ZERO),
                    output_field=DecimalField(max_digits=14, decimal_places=2),
                )
            )
        }

        if granularity == "day":
            series = []
            cursor = date_from
            while cursor <= date_to:
                series.append(
                    {"label": cursor.isoformat(), "amount": _money(totals.get(cursor))}
                )
                cursor += timedelta(days=1)
            return series

        months: dict[str, Decimal] = {}
        cursor = date_from
        while cursor <= date_to:
            months.setdefault(f"{cursor.year:04d}-{cursor.month:02d}", _ZERO)
            cursor += timedelta(days=1)
        for day, amount in totals.items():
            key = f"{day.year:04d}-{day.month:02d}"
            months[key] = months.get(key, _ZERO) + (amount or _ZERO)
        return [
            {"label": label, "amount": _money(amount)}
            for label, amount in sorted(months.items())
        ]

"""The day's Roj Mel: what came in on the left, what went out on credit on the right.

Requested in stakeholder review, and deliberately shaped like the paper daybook
a shopkeeper already keeps rather than like a dashboard. Jama is money actually
received today; Udhaar is value handed over on credit and still owed. Keeping
them apart is the whole point — a day with strong sales and weak collection
looks healthy on a revenue figure and is not.

The brief is explicit that this stays short. It answers four questions: how
much came in, by which method, how much went out on credit, and how much cash
should be in the drawer. Anything more belongs in the detailed reports.
"""
from __future__ import annotations

from decimal import Decimal

from django.db.models import DecimalField, Q, Sum, Value
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.customers.models import CustomerLedgerEntry
from platform_apps.expenses.models import Expense
from platform_apps.sales.models import Sale
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

_ZERO = Decimal("0.00")


def _money(value) -> Decimal:
    return (value or _ZERO).quantize(Decimal("0.01"))


def _sum(queryset, field: str) -> Decimal:
    return queryset.aggregate(
        total=Coalesce(
            Sum(field),
            Value(_ZERO),
            output_field=DecimalField(max_digits=14, decimal_places=2),
        )
    )["total"] or _ZERO


class DayBookView(APIView):
    """One day, in the two columns a shopkeeper already thinks in."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        # Whoever closes the till needs this, and it exposes no cost prices or
        # margins — only money in and money owed.
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.STAFF
        )
        shop = membership.shop

        raw_date = (request.query_params.get("date") or "").strip()
        day = timezone.localdate()
        if raw_date:
            parsed = timezone.datetime.strptime(raw_date, "%Y-%m-%d").date()
            day = parsed

        sales = Sale.objects.filter(shop=shop, sale_date=day, tombstone=False).exclude(
            status=Sale.Status.VOID
        )

        # --- Jama: money actually received today ---------------------------
        #
        # Keyed on amount_received rather than total_amount, because a part-paid
        # credit sale contributes only what was handed over. A split payment is
        # recorded with its own mode, so it is counted once under "other" rather
        # than double-counted across the modes it was split into.
        by_mode = {}
        for mode in ("CASH", "UPI", "CARD", "BANK"):
            by_mode[mode.lower()] = _money(
                _sum(sales.filter(payment_mode=mode), "amount_received")
            )
        other_received = _money(
            _sum(
                sales.exclude(payment_mode__in=["CASH", "UPI", "CARD", "BANK"]),
                "amount_received",
            )
        )

        # Repayments against old khata are money in today even though the sale
        # they belong to happened earlier. Omitting them would understate the
        # day's collection, which is the number the owner actually cares about.
        repayments = _money(
            -_sum(
                CustomerLedgerEntry.objects.filter(
                    shop=shop,
                    occurred_at__date=day,
                    event_type=CustomerLedgerEntry.EventType.PAYMENT,
                ),
                "amount_delta",
            )
        )

        jama_total = _money(
            sum(by_mode.values(), _ZERO) + other_received + repayments
        )

        # --- Udhaar: value given out on credit today ------------------------
        credit_given = _money(_sum(sales, "amount_due"))
        credit_customers = (
            sales.filter(amount_due__gt=0)
            .values("customer_id")
            .distinct()
            .count()
        )

        # --- Money out ------------------------------------------------------
        expenses = _money(
            _sum(Expense.objects.filter(shop=shop, expense_date=day), "amount")
        )

        # Cash that should physically be in the drawer, before any opening
        # float. Only cash counts: a UPI collection does not change the drawer.
        cash_in_hand = _money(by_mode["cash"] - expenses)

        sales_count = sales.count()
        currency = getattr(shop, "currency_code", "INR")

        def fmt(amount: Decimal) -> str:
            return f"{amount:,.2f}"

        # A short line the owner can be sent. The brief asked for brief.
        lines = [
            f"{shop.name} — {day.strftime('%d %b %Y')}",
            f"Jama (received): {currency} {fmt(jama_total)}",
            f"  Cash {fmt(by_mode['cash'])} · UPI {fmt(by_mode['upi'])}"
            f" · Card {fmt(by_mode['card'])} · Bank {fmt(by_mode['bank'])}",
        ]
        if repayments > _ZERO:
            lines.append(f"  Khata repayments {fmt(repayments)}")
        lines.append(f"Udhaar (given): {currency} {fmt(credit_given)}")
        if expenses > _ZERO:
            lines.append(f"Expenses: {currency} {fmt(expenses)}")
        lines.append(f"Cash in hand: {currency} {fmt(cash_in_hand)}")
        lines.append(f"{sales_count} bill{'' if sales_count == 1 else 's'}")

        return Response(
            {
                "date": day.isoformat(),
                "shop_name": shop.name,
                "currency_code": currency,
                "jama": {
                    **{k: str(v) for k, v in by_mode.items()},
                    "other": str(other_received),
                    "khata_repayments": str(repayments),
                    "total": str(jama_total),
                },
                "udhaar": {
                    "credit_given": str(credit_given),
                    "customers": credit_customers,
                },
                "money_out": {"expenses": str(expenses)},
                "cash_in_hand": str(cash_in_hand),
                "sales_count": sales_count,
                # Ready to paste into a message, so the caller does not have to
                # rebuild this wording and drift from it.
                "summary_text": "\n".join(lines),
            }
        )

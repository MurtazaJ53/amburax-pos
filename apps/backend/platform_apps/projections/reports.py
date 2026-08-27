from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from django.db.models import Case, DecimalField, F, Sum, When
from django.db.models.functions import Coalesce
from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.expenses.models import Expense
from platform_apps.purchases.models import Purchase
from platform_apps.sales import returns_summary
from platform_apps.sales.models import Sale, SaleItem
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import ensure_feature_enabled_or_403, get_membership_or_403

_MONEY = DecimalField(max_digits=16, decimal_places=2)


def _parse_date(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return datetime.strptime(value.strip(), "%Y-%m-%d").date()
    except (ValueError, AttributeError):
        return None


class ProfitAndLossView(APIView):
    """Unified P&L: gross profit (revenue - COGS) minus tracked expenses = net
    profit, over a date range (defaults to the current calendar month)."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        # RBAC: financial reports are owner/admin only — a cashier (staff) or
        # viewer must not see P&L margins.
        membership = get_membership_or_403(request.user, shop_id, ShopMembership.Role.ADMIN)
        ensure_feature_enabled_or_403(membership, "finance_summary")
        shop = membership.shop

        today = date.today()
        start = _parse_date(request.query_params.get("start")) or today.replace(day=1)
        end = _parse_date(request.query_params.get("end")) or today

        completed_sales = Sale.objects.filter(
            shop=shop,
            tombstone=False,
            status=Sale.Status.COMPLETED,
            sale_date__gte=start,
            sale_date__lte=end,
        )
        sales_agg = completed_sales.aggregate(
            revenue=Coalesce(Sum("total_amount"), Decimal("0.00"), output_field=_MONEY),
            tax_collected=Coalesce(Sum("tax_amount"), Decimal("0.00"), output_field=_MONEY),
            # taxable_amount where it was recorded, else derived.
            #
            # Not a plain Sum("taxable_amount"): the bulk historical-sale
            # importer creates Sale rows without GST columns at all, and older
            # rows predate them. Those would sum to zero and report a large
            # negative profit — worse than the overstatement being fixed. For
            # such rows tax_amount is zero too, so total - tax is simply the
            # total, which is the right answer for untaxed history.
            net_revenue=Coalesce(
                Sum(
                    Case(
                        When(taxable_amount__gt=0, then=F("taxable_amount")),
                        default=F("total_amount") - F("tax_amount"),
                        output_field=_MONEY,
                    )
                ),
                Decimal("0.00"),
                output_field=_MONEY,
            ),
        )
        # What the customer handed over, tax included. This is what a shopkeeper
        # means by "sales", so it stays the headline figure.
        revenue = sales_agg["revenue"]
        tax_collected = sales_agg["tax_collected"]
        # What the shop actually keeps: revenue minus the GST it is merely
        # collecting on the government's behalf. THIS is what profit is measured
        # against.
        net_revenue = sales_agg["net_revenue"]

        # Cost of goods sold: quantity x unit_cost per line, returns subtract.
        cogs = SaleItem.objects.filter(
            sale__in=completed_sales,
            unit_cost__isnull=False,
        ).aggregate(
            value=Coalesce(
                Sum(
                    Case(
                        When(is_return=True, then=-F("quantity") * F("unit_cost")),
                        default=F("quantity") * F("unit_cost"),
                        output_field=_MONEY,
                    ),
                ),
                Decimal("0.00"),
                output_field=_MONEY,
            )
        )["value"]

        total_expenses = Expense.objects.filter(
            shop=shop,
            tombstone=False,
            expense_date__gte=start,
            expense_date__lte=end,
        ).aggregate(
            value=Coalesce(Sum("amount"), Decimal("0.00"), output_field=_MONEY)
        )["value"]

        purchases_total = Purchase.objects.filter(
            shop=shop,
            tombstone=False,
            status=Purchase.Status.COMPLETED,
            purchase_date__gte=start,
            purchase_date__lte=end,
        ).aggregate(
            value=Coalesce(Sum("total_amount"), Decimal("0.00"), output_field=_MONEY)
        )["value"]

        # Goods that came back. Reversed on all four figures at once, which
        # is why they arrive as one object: subtracting the revenue of a
        # return without also removing its cost from COGS would report the
        # refund as an improvement in margin.
        #
        # Reversed whatever the refund method. Cash, card, khata or
        # exchange, the sale of those goods is undone; only whether money
        # left the till differs, and the P&L is not asking that.
        refunds = returns_summary.for_range(shop, start, end)
        revenue = revenue - refunds.gross
        tax_collected = tax_collected - refunds.tax
        net_revenue = net_revenue - refunds.taxable
        cogs = cogs - refunds.cost

        # Net revenue against net cost.
        #
        # This was `revenue - cogs`, which subtracted a cost EXCLUDING GST from
        # a revenue INCLUDING it, so gross profit was overstated by the whole
        # tax collected — 5% of turnover on kirana goods, 18% on many others.
        # unit_cost comes from the purchase invoice's pre-tax rate
        # (purchases/serializers.py), so the two sides were never comparable.
        #
        # The GST is not the shop's money. For a registered dealer it is
        # collected and remitted, and the tax paid on the purchase is input
        # credit rather than cost. Net-vs-net is the only comparison that means
        # anything, and a shopkeeper setting prices off the old number was
        # being told a margin that did not exist.
        gross_profit = net_revenue - cogs
        net_profit = gross_profit - total_expenses
        margin_pct = (
            (net_profit / net_revenue * Decimal("100")).quantize(Decimal("0.01"))
            if net_revenue > 0
            else Decimal("0.00")
        )

        return Response(
            {
                "start": start.isoformat(),
                "end": end.isoformat(),
                "revenue": revenue,
                "tax_collected": tax_collected,
                # Exposed so the arithmetic on screen can be followed:
                # net_revenue = revenue - tax_collected, and profit is measured
                # from net_revenue, not from revenue.
                "net_revenue": net_revenue,
                "cost_of_goods_sold": cogs,
                "gross_profit": gross_profit,
                "total_expenses": total_expenses,
                "net_profit": net_profit,
                "net_margin_pct": margin_pct,
                # Informational: stock bought in the period (cash-flow, not P&L expense).
                "purchases_total": purchases_total,
            }
        )

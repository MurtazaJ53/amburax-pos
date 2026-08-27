"""What a set of returns did to the money, the tax and the cost of goods.

Returns were recorded correctly and read by nothing. SaleReturn was written
by the return screen, stock went back through the ledger, a khata refund
moved the customer balance - and then every report that adds up money
carried on as though the goods had never come back. Refund 50 in cash and
the drawer figure did not move, the profit did not move, and the GST taxable
value did not move, while the screen said refunded bills were excluded.

The model docstring predicted precisely this: a return kept out of the Sale
table will be missed by "every revenue aggregate that does not know to
exclude it, and there are a lot of those". They were kept out for a good
reason. Nobody then told the aggregates.

So this is the one place that answers the question, and the day book, the
P&L and the GST summary all ask it here rather than each deriving it their
own way and drifting apart.

Two decisions worth stating, because they are not the obvious ones.

Goods returned reverse revenue whatever the refund method. Cash, card, khata
or exchange - the sale of those goods is undone in all four cases. What
differs is only whether money left the till, and that is a separate figure.

Tax and cost are apportioned from the original sale line rather than
recomputed. A return line stores what came back and what it was worth, not
its GST split; the line it points at holds the rate, the taxable value and
the cost that were true at the moment of sale. Recomputing from today's rate
or today's cost would quietly restate history, and half a returned line has
to reverse exactly half of what that line contributed.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal, ROUND_HALF_UP

from platform_apps.sales.models import SaleReturn, SaleReturnLine

_ZERO = Decimal("0.00")

#: Refund methods where money actually leaves the business today. KHATA
#: reduces what the customer owes and EXCHANGE carries the value into a
#: replacement bill; in neither case does the drawer or the bank move.
PAID_OUT_MODES = (
    SaleReturn.RefundMode.CASH,
    SaleReturn.RefundMode.UPI,
    SaleReturn.RefundMode.BANK,
    SaleReturn.RefundMode.CARD,
)


def _money(value) -> Decimal:
    return Decimal(value or 0).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


@dataclass
class ReturnsTotals:
    """Everything a report needs to know about goods that came back.

    Kept as one object rather than four loose numbers so a caller cannot
    subtract the revenue and forget the cost, which would turn a refund into
    a profit.
    """

    #: Tax-inclusive value of the goods returned. Reverses revenue.
    gross: Decimal = _ZERO
    #: Net-of-tax value. Reverses the figure profit is measured against.
    taxable: Decimal = _ZERO
    #: GST that is no longer collected on those goods.
    tax: Decimal = _ZERO
    cgst: Decimal = _ZERO
    sgst: Decimal = _ZERO
    igst: Decimal = _ZERO
    #: Cost of the returned goods. Added BACK to stock, so removed from COGS.
    cost: Decimal = _ZERO
    #: Money actually paid out, by refund method. Excludes khata and exchange.
    paid_out: dict = field(default_factory=dict)
    #: How many returns, not how many lines.
    count: int = 0

    @property
    def cash_paid_out(self) -> Decimal:
        """Only this changes what should physically be in the drawer."""
        return self.paid_out.get(SaleReturn.RefundMode.CASH, _ZERO)

    @property
    def total_paid_out(self) -> Decimal:
        return _money(sum(self.paid_out.values(), _ZERO))


def line_share(returned_quantity, sold_quantity) -> Decimal:
    """How much of the original line came back, as a fraction.

    A sold quantity of zero should not exist, but a division by it would take
    down the day book - a report that must open when the till is being
    counted. Nothing returned against nothing sold is nothing reversed.
    """
    sold = Decimal(sold_quantity or 0)
    if sold <= 0:
        return Decimal("0")
    return Decimal(returned_quantity or 0) / sold


def totals_for(returns) -> ReturnsTotals:
    """Add up a queryset (or list) of SaleReturn.

    Takes the returns rather than a date range so each caller keeps its own
    idea of a period - the day book works in shop-local trading dates, the
    P&L in a start/end range, the GST summary in whatever was asked for.
    Sharing the arithmetic without sharing the filter is the point.
    """
    returns = list(returns)
    totals = ReturnsTotals(paid_out={})
    totals.count = len(returns)
    if not returns:
        return totals

    for sale_return in returns:
        if sale_return.refund_mode in PAID_OUT_MODES:
            mode = sale_return.refund_mode
            totals.paid_out[mode] = _money(
                totals.paid_out.get(mode, _ZERO) + _money(sale_return.refund_amount)
            )

    lines = SaleReturnLine.objects.filter(
        sale_return__in=[r.pk for r in returns]
    ).select_related("sale_item")

    for line in lines:
        item = line.sale_item
        totals.gross += _money(line.line_total)
        if item is None:
            continue

        share = line_share(line.quantity, item.quantity)
        totals.taxable += _money(Decimal(item.taxable_amount or 0) * share)
        totals.tax += _money(Decimal(item.tax_amount or 0) * share)
        totals.cgst += _money(Decimal(getattr(item, "cgst_amount", 0) or 0) * share)
        totals.sgst += _money(Decimal(getattr(item, "sgst_amount", 0) or 0) * share)
        totals.igst += _money(Decimal(getattr(item, "igst_amount", 0) or 0) * share)
        if item.unit_cost is not None:
            totals.cost += _money(Decimal(item.unit_cost) * Decimal(line.quantity or 0))

    for name in ("gross", "taxable", "tax", "cgst", "sgst", "igst", "cost"):
        setattr(totals, name, _money(getattr(totals, name)))
    return totals


def for_day(shop, day) -> ReturnsTotals:
    """Returns recorded on one shop-local trading date."""
    return totals_for(
        SaleReturn.objects.filter(shop=shop, occurred_at__date=day)
    )


def for_range(shop, start, end) -> ReturnsTotals:
    """Returns recorded between two dates, both ends included."""
    return totals_for(
        SaleReturn.objects.filter(
            shop=shop,
            occurred_at__date__gte=start,
            occurred_at__date__lte=end,
        )
    )

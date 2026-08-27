"""Records that must agree with other records, and saying so when they do not.

Every money bug found in this system so far was a number that disagreed with
another number, and nothing noticed. A credit sale stored as fully received
while its customer's balance never moved. A day book whose total did not match
the sum of its own parts. In each case both figures sat in the database for
weeks, each individually plausible, and the disagreement was only ever visible
to a person who happened to compare them.

That comparison is the thing worth automating - not the values, which change
constantly, but the relationships between them, which must hold always.

Two kinds of disagreement, and they need different treatment:

A CODE disagreement is a report contradicting another report - the GST rate
table not summing to the GST headline. Both are computed at read time from the
same rows, so this cannot appear without a deploy, and it cannot heal without
one either. `pnpm smoke:money` catches those on the way out.

A DATA disagreement is a stored record contradicting a stored record - a
customer's balance against their own ledger. This CAN appear at any moment: a
half-finished import, a job that died between two writes, a bug that ran for
an hour. Nothing about a deploy is involved, so a deploy-time check will never
see it. That is what this module is for.

Nothing here raises. A shopkeeper with a customer at the counter must always
be able to finish the bill; discovering an inconsistency is a reason to tell
the operator, never a reason to refuse the sale. Every function returns a list
of plain sentences, empty when all is well.
"""
from __future__ import annotations

from decimal import Decimal

from django.db.models import Sum

_ZERO = Decimal("0.00")

#: Money is stored to two places, so anything at or below half a paisa is
#: representation rather than disagreement. Deliberately not a tolerance on
#: the amounts themselves: "close enough" is how a real discrepancy hides.
EPSILON = Decimal("0.005")


def _off(left, right) -> bool:
    return abs(Decimal(left or 0) - Decimal(right or 0)) > EPSILON


def sale_problems(sale) -> list[str]:
    """What this one bill says about itself, checked against itself.

    Called right after a sale is written, so an error is found minutes after
    it happens rather than whenever somebody next opens a report. The original
    khata bug lived here: a bill recorded as fully received while the customer
    was never billed for the part they had not paid.
    """
    problems: list[str] = []
    label = sale.receipt_number or str(sale.pk)

    received = Decimal(sale.amount_received or 0)
    due = Decimal(sale.amount_due or 0)
    total = Decimal(sale.total_amount or 0)

    if _off(received + due, total):
        problems.append(
            f"Sale {label}: received {received} + due {due} does not make the "
            f"bill total {total}."
        )

    # Tendered money must equal what the bill claims was received.
    #
    # Only when the bill HAS tender rows. Imported history is stored as flat
    # bills with no payments at all, and reading that as "nothing was paid"
    # would flag a shop's entire trading history the first night this runs -
    # which is the fastest way to teach an operator to ignore this alert.
    tendered = sale.payments.aggregate(total=Sum("amount"))["total"]
    if tendered is not None and _off(tendered, received):
        problems.append(
            f"Sale {label}: payments add up to {tendered}, but the bill says "
            f"{received} was received."
        )

    return problems


def customer_problems(customer) -> list[str]:
    """A customer's balance against the entries meant to explain it.

    The balance is what the shopkeeper chases and what the customer disputes.
    Its ledger is the evidence. If those two disagree, one of them is lying to
    somebody's neighbour, and there is no way to tell which from the number
    alone.
    """
    from platform_apps.customers.models import CustomerLedgerEntry

    entries = CustomerLedgerEntry.objects.filter(customer=customer)
    ledger_total = entries.aggregate(total=Sum("amount_delta"))["total"] or _ZERO
    balance = Decimal(customer.balance or 0)

    if _off(ledger_total, balance):
        return [
            f"Customer {customer.name}: balance is {balance}, but their ledger "
            f"entries add up to {ledger_total}."
        ]
    return []


def shop_problems(shop, *, since=None, max_reported: int = 20) -> list[str]:
    """Everything disagreeing in one shop, newest first.

    Bounded on purpose. This runs unattended against live data, and a shop
    with twenty thousand bills must not turn a health check into a table scan
    every night. `since` limits the sales examined; customers are limited to
    those actually carrying a balance, because a customer who owes nothing has
    nothing to reconcile.

    The report is capped too. A thousand identical lines in an email is not
    more informative than twenty - it is less, because nobody reads it.
    """
    from platform_apps.customers.models import Customer
    from platform_apps.sales.models import Sale

    problems: list[str] = []

    sales = Sale.objects.filter(shop=shop, tombstone=False).exclude(
        status=Sale.Status.VOID
    )
    if since is not None:
        sales = sales.filter(sale_date__gte=since)

    for sale in sales.order_by("-sale_date", "-id").prefetch_related("payments"):
        problems.extend(sale_problems(sale))
        if len(problems) >= max_reported:
            return problems[:max_reported]

    owing = Customer.objects.filter(shop=shop).exclude(balance=_ZERO)
    for customer in owing.order_by("-updated_at"):
        problems.extend(customer_problems(customer))
        if len(problems) >= max_reported:
            return problems[:max_reported]

    return problems

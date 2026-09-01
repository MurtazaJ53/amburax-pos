"""How much a customer may owe, and what to do when they are about to owe more.

A credit limit is the one number that decides whether a wholesaler survives a
bad season: dealers buy repeatedly on credit, and the exposure to a single
dealer can quietly become larger than the shop's whole cash position. Retail
khata rarely has a number attached at all, which is why "no limit set" and "a
limit of zero" have to stay different things.

The decision this module encodes, and the reason it is a decision rather than
an obvious rule:

    Over the limit WARNS. It never blocks the sale.

Blocking is tempting - it is a financial control, and the software knows the
number. But the counter is the worst place in the world to refuse: the dealer
is standing there, the goods are counted out, and the person who could
authorise an exception is the owner, who is not at the till. A till that
refuses gets worked around, and a till that gets worked around stops recording
anything. Warning loudly and recording that the limit was passed keeps the
sale, keeps the record, and still puts the number in front of somebody.

The same reasoning that lets this product oversell stock.
"""
from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from typing import Any


def _money(value: Any) -> Decimal:
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError, TypeError):
        return Decimal("0.00")


def _plain(amount: Decimal) -> str:
    """A rupee figure for a message body, without currency plumbing."""
    return f"₹{amount.quantize(Decimal('0.01')):,}"


@dataclass(frozen=True)
class CreditStanding:
    """Where a customer sits against their limit, and what to say about it."""

    #: What they owe now.
    balance: Decimal
    #: What they may owe. None when the shop has never set one.
    limit: Decimal | None
    #: What they would owe if this sale went through.
    projected: Decimal
    #: Past the limit already, before this sale.
    over_now: bool
    #: This sale is what takes them past it.
    tips_over: bool

    @property
    def has_limit(self) -> bool:
        return self.limit is not None

    @property
    def over_by(self) -> Decimal:
        """How far past the limit this sale would put them. Zero when inside."""
        if self.limit is None:
            return Decimal("0.00")
        excess = self.projected - self.limit
        return excess if excess > 0 else Decimal("0.00")

    @property
    def headroom(self) -> Decimal | None:
        """What is left to spend on credit. None when no limit is set."""
        if self.limit is None:
            return None
        left = self.limit - self.balance
        return left if left > 0 else Decimal("0.00")

    @property
    def message(self) -> str:
        """One line for a cashier, or empty when there is nothing to say.

        Written to be read out loud to a dealer standing at the counter, which
        is where it will actually get used.
        """
        if not self.has_limit or self.over_by <= 0:
            return ""
        limit = self.limit or Decimal("0.00")
        if self.over_now:
            return (
                f"Already over their credit limit by {_plain(self.balance - limit)}. "
                f"This bill takes them to {_plain(self.projected)}."
            )
        return (
            f"This bill puts them {_plain(self.over_by)} over their "
            f"{_plain(limit)} credit limit."
        )


def standing(
    balance: Any,
    credit_limit: Any,
    adding: Any = Decimal("0.00"),
) -> CreditStanding:
    """Where this customer stands if ``adding`` goes on credit.

    A ``credit_limit`` of None - or anything unparseable - means no limit, and
    then nothing is ever over. A limit the software invented would be worse
    than no limit at all: it would warn about a number the shop never agreed
    to, and a warning nobody agreed to is a warning everybody learns to ignore.
    """
    current = _money(balance)
    extra = _money(adding)
    projected = current + extra

    limit: Decimal | None
    if credit_limit is None or str(credit_limit).strip() == "":
        limit = None
    else:
        try:
            limit = Decimal(str(credit_limit))
        except (InvalidOperation, ValueError, TypeError):
            limit = None

    if limit is None:
        return CreditStanding(
            balance=current,
            limit=None,
            projected=projected,
            over_now=False,
            tips_over=False,
        )

    over_now = current > limit
    return CreditStanding(
        balance=current,
        limit=limit,
        projected=projected,
        over_now=over_now,
        tips_over=not over_now and projected > limit,
    )

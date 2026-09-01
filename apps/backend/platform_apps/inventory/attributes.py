"""What may go in an inventory item's ``attributes_json``, and what may not.

A JSON column reachable from a public write endpoint accumulates whatever
clients feel like sending. Six months later nobody can say what a row contains,
no report can rely on a key existing, and removing anything is guesswork. So
every key is listed here, every value is coerced to a known shape, and anything
unrecognised is dropped rather than stored.

Dropped silently, and deliberately. A client sending an unknown key is a client
running a newer or older build than this server - normal in a product with
app-store releases, and never a reason to fail a shopkeeper's save.
"""
from __future__ import annotations

from decimal import Decimal, InvalidOperation
from typing import Any

#: Free-text attributes, stored as trimmed strings.
#:
#: colour/fabric/season are garment trade; a grocer never sends them. Kept as
#: text rather than as relations because a shop's own words are the point -
#: "Rayon 140 GSM" and "Winter 2026 lot 3" are not rows in a table anybody
#: else maintains.
TEXT_KEYS = ("profile", "colour", "fabric", "season")

#: Longest a free-text attribute may be. Generous for a colour list, short
#: enough that this column cannot become a document store.
MAX_TEXT = 240

#: Most bulk price slabs one product may carry. Past this it is a price list
#: rather than a product, and no till can render it at a counter anyway.
MAX_TIERS = 8


def _text(value: Any) -> str:
    return str(value if value is not None else "").strip()[:MAX_TEXT]


def _decimal_text(value: Any) -> str | None:
    """A number, kept as a STRING.

    Money and quantities cross this boundary as text for the same reason they
    do everywhere else in this codebase: JSON numbers are floats, and a float
    is not a price. Returns None when the value is not a positive number, so
    the caller drops the row instead of storing a zero.
    """
    try:
        number = Decimal(str(value).strip())
    except (InvalidOperation, ValueError, TypeError, AttributeError):
        return None
    if number <= 0:
        return None
    return format(number.quantize(Decimal("0.01")).normalize(), "f")


def _price_tiers(value: Any) -> list[dict[str, str]]:
    """Bulk pricing, cleaned and ordered.

    Wholesale sells the same shirt at 250 a piece for one dozen and 220 for
    five, and the till has to pick the right one. A half-typed row reading
    "from 0 units, 0.00 each" would price an entire lot at nothing, so a row
    missing either half is dropped rather than defaulted.

    Sorted by quantity so every consumer can walk the list once and keep the
    last slab whose minimum has been reached, with no re-sorting at a counter.
    """
    if not isinstance(value, list):
        return []

    cleaned: list[dict[str, str]] = []
    for row in value[: MAX_TIERS * 4]:
        if not isinstance(row, dict):
            continue
        minimum = _decimal_text(row.get("min_quantity"))
        price = _decimal_text(row.get("price_per_piece"))
        if minimum is None or price is None:
            continue
        cleaned.append({"min_quantity": minimum, "price_per_piece": price})

    cleaned.sort(key=lambda row: Decimal(row["min_quantity"]))

    # One price per quantity. A later duplicate wins, which is what a shopkeeper
    # who typed the same slab twice almost certainly meant.
    deduped: dict[str, dict[str, str]] = {row["min_quantity"]: row for row in cleaned}
    return list(deduped.values())[:MAX_TIERS]


def clean_attributes(value: Any) -> dict[str, Any]:
    """Coerce whatever a client sent into the attributes we agree to store.

    Never raises. A bad attribute is not a reason to refuse a product: the
    shopkeeper is standing at a counter, and the name, price and code are the
    parts that matter. Empty values are omitted rather than stored as empty
    strings, so a row carries only what was actually filled in.
    """
    if not isinstance(value, dict):
        return {}

    cleaned: dict[str, Any] = {}

    for key in TEXT_KEYS:
        text = _text(value.get(key))
        if text:
            cleaned[key] = text

    tiers = _price_tiers(value.get("price_tiers"))
    if tiers:
        cleaned["price_tiers"] = tiers

    moq = _decimal_text(value.get("moq"))
    if moq is not None:
        cleaned["moq"] = moq

    # How many sellable pieces are inside one unit a dealer orders.
    #
    # A wholesaler orders in DOZENS and is quoted PER PIECE - "250 a piece for
    # one dozen". Without this the till multiplies three dozen by the piece
    # price and bills for three pieces, which is a bill twelve times too small
    # with nothing on screen looking wrong.
    #
    # Absent means one, which is what retail is: a piece is the unit.
    pieces = _decimal_text(value.get("pieces_per_unit"))
    if pieces is not None:
        cleaned["pieces_per_unit"] = pieces

    return cleaned


def price_for_quantity(attributes: Any, quantity: Any, base_price: Any) -> Decimal:
    """The price per piece at this order size.

    The single place bulk pricing is decided. Every client pricing a wholesale
    line reaches for this rather than walking the tiers itself, because a till
    and an invoice disagreeing about the price of one line is an argument with
    a dealer that the shop cannot win.

    Falls back to ``base_price`` when there are no tiers, when the order is
    below the first slab, or when anything is unparseable. A missing price rule
    must never make a line free.
    """
    try:
        base = Decimal(str(base_price))
    except (InvalidOperation, ValueError, TypeError):
        return Decimal("0.00")

    if not isinstance(attributes, dict):
        return base

    try:
        ordered = Decimal(str(quantity))
    except (InvalidOperation, ValueError, TypeError):
        return base

    price = base
    for tier in attributes.get("price_tiers") or []:
        try:
            minimum = Decimal(str(tier["min_quantity"]))
            candidate = Decimal(str(tier["price_per_piece"]))
        except (InvalidOperation, ValueError, TypeError, KeyError):
            continue
        # Tiers arrive sorted, so the last one reached is the one that applies.
        if ordered >= minimum:
            price = candidate

    return price

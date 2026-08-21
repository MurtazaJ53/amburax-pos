"""The till and the server must agree on what the customer owes.

They did not. The web POS computed `tax = lineTotal * rate` and added it to the
subtotal, while compute_line_gst divides tax OUT of a price that already
contains it (price_includes_tax defaults to True — the Indian MRP convention).

On a ₹150 bill at 5% the till asked for ₹157.50. The server refused the sale
with "Total must equal subtotal minus discount (150.00000)", which is the only
reason no customer was ever overcharged: the disagreement was loud. A quieter
version of this bug takes money.

These pin the server side of that agreement. The browser side is pinned in
apps/admin_web/src/lib/cart-totals.test.ts with the same figures.
"""
from __future__ import annotations

from decimal import Decimal

from platform_apps.sales.gst import compute_line_gst

LINE_TOTAL = Decimal("150.00")
RATE = Decimal("5")


def test_an_inclusive_price_is_what_the_customer_pays():
    """The number on the shelf is the number on the bill."""
    gst = compute_line_gst(
        LINE_TOTAL, RATE, price_includes_tax=True, intra_state=True
    )
    assert gst.gross_amount == Decimal("150.00")


def test_the_tax_inside_an_inclusive_price_is_reported_not_added():
    gst = compute_line_gst(
        LINE_TOTAL, RATE, price_includes_tax=True, intra_state=True
    )
    # 150 / 1.05 = 142.86, so 7.14 is already inside it.
    assert gst.taxable_amount == Decimal("142.86")
    assert gst.tax_amount == Decimal("7.14")
    assert gst.taxable_amount + gst.tax_amount == gst.gross_amount


def test_an_exclusive_price_adds_its_tax():
    """The 157.50 the till was showing is correct ONLY for this case."""
    gst = compute_line_gst(
        LINE_TOTAL, RATE, price_includes_tax=False, intra_state=True
    )
    assert gst.tax_amount == Decimal("7.50")
    assert gst.gross_amount == Decimal("157.50")


def test_cgst_and_sgst_sum_exactly_to_the_tax():
    """A half-paisa gap shows on a GST return as tax that does not add up."""
    gst = compute_line_gst(
        LINE_TOTAL, RATE, price_includes_tax=True, intra_state=True
    )
    assert gst.cgst_amount + gst.sgst_amount == gst.tax_amount
    assert gst.igst_amount == Decimal("0.00")


def test_an_interstate_sale_uses_igst_alone():
    gst = compute_line_gst(
        LINE_TOTAL, RATE, price_includes_tax=True, intra_state=False
    )
    assert gst.igst_amount == gst.tax_amount
    assert gst.cgst_amount == Decimal("0.00")
    assert gst.sgst_amount == Decimal("0.00")


def test_a_zero_rate_leaves_the_line_untouched():
    gst = compute_line_gst(
        LINE_TOTAL, Decimal("0"), price_includes_tax=True, intra_state=True
    )
    assert gst.tax_amount == Decimal("0.00")
    assert gst.gross_amount == LINE_TOTAL

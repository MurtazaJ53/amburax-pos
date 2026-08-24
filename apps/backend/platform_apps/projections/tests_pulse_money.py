"""Money in pulse task text.

These strings go straight onto the dashboard, so `f"{value:.2f}"` was printing
"36567.20" at the shopkeeper - no symbol, and Western grouping for a business
that counts in lakhs.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import SimpleTestCase

from platform_apps.projections.pulse import format_money


class FormatMoneyTests(SimpleTestCase):
    def test_indian_grouping_puts_the_commas_where_a_shopkeeper_expects(self):
        self.assertEqual(format_money(Decimal("36567.20")), "₹36,567.20")
        self.assertEqual(format_money(Decimal("1234567.89")), "₹12,34,567.89")

    def test_small_amounts_are_left_alone(self):
        self.assertEqual(format_money(Decimal("999.00")), "₹999.00")
        self.assertEqual(format_money(Decimal("0")), "₹0.00")

    def test_a_lakh_groups_in_pairs_above_the_first_three_digits(self):
        self.assertEqual(format_money(Decimal("100000")), "₹1,00,000.00")

    def test_other_currencies_keep_western_grouping(self):
        self.assertEqual(format_money(Decimal("36567.20"), "GBP"), "£36,567.20")
        self.assertEqual(format_money(Decimal("1234567.89"), "USD"), "$1,234,567.89")

    def test_an_unknown_currency_is_labelled_rather_than_guessed(self):
        self.assertEqual(format_money(Decimal("10.00"), "XYZ"), "XYZ 10.00")

    def test_a_negative_keeps_its_sign_outside_the_symbol(self):
        self.assertEqual(format_money(Decimal("-500.00")), "-₹500.00")

    def test_garbage_returns_empty_rather_than_crashing_the_dashboard(self):
        self.assertEqual(format_money("not-a-number"), "")

    def test_none_reads_as_zero(self):
        self.assertEqual(format_money(None), "₹0.00")

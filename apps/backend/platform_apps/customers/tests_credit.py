"""A customer's credit limit, and the decision to warn rather than refuse.

Wholesale runs on credit. A dealer buys repeatedly, pays on 30 or 60 day terms,
and the exposure to one dealer can quietly grow past the shop's whole cash
position. The limit is the number that stops that happening - but only if
somebody is told, and only if the till they are told by is still the till the
shop actually uses.

So the rule under test is: over the limit WARNS, and the sale still goes
through. Refusing at the counter, with the dealer standing there and the goods
counted out, sends the sale round the software instead of through it - and a
till that gets worked around records nothing at all.

The other half is the difference between "no limit set" and "a limit of zero".
Most retail khata has no number attached; inventing one would warn about a
figure the shop never agreed to, and a warning nobody agreed to is a warning
everybody learns to ignore.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase

from platform_apps.customers import credit


class NoLimitSetTests(TestCase):
    def test_a_customer_with_no_limit_is_never_over(self):
        # Retail khata usually has no agreed number. Treating that as a limit
        # of zero would put every credit sale in the shop into warning.
        result = credit.standing(balance="50000", credit_limit=None, adding="10000")

        self.assertFalse(result.has_limit)
        self.assertFalse(result.over_now)
        self.assertFalse(result.tips_over)
        self.assertEqual(result.message, "")

    def test_an_empty_limit_is_no_limit(self):
        self.assertFalse(credit.standing("100", "", "50").has_limit)
        self.assertFalse(credit.standing("100", "   ", "50").has_limit)

    def test_an_unparseable_limit_is_no_limit_rather_than_zero(self):
        # Falling back to zero would refuse-by-warning on every sale.
        result = credit.standing("100", "not a number", "50")

        self.assertFalse(result.has_limit)
        self.assertEqual(result.over_by, Decimal("0.00"))

    def test_headroom_is_unknown_without_a_limit(self):
        self.assertIsNone(credit.standing("100", None).headroom)


class LimitOfZeroTests(TestCase):
    """A shop that decided this person pays cash. Different from silence."""

    def test_zero_is_a_real_limit(self):
        result = credit.standing(balance="0", credit_limit="0", adding="500")

        self.assertTrue(result.has_limit)
        self.assertTrue(result.tips_over)
        self.assertEqual(result.over_by, Decimal("500"))


class WithinTheLimitTests(TestCase):
    def test_a_sale_inside_the_limit_says_nothing(self):
        result = credit.standing(balance="2000", credit_limit="10000", adding="3000")

        self.assertFalse(result.over_now)
        self.assertFalse(result.tips_over)
        self.assertEqual(result.message, "")

    def test_landing_exactly_on_the_limit_is_allowed(self):
        # A limit of 10,000 means they may owe 10,000. Off by one here warns on
        # a bill the shop explicitly permitted.
        result = credit.standing(balance="7000", credit_limit="10000", adding="3000")

        self.assertFalse(result.tips_over)
        self.assertEqual(result.over_by, Decimal("0.00"))

    def test_headroom_is_what_is_left_to_spend(self):
        self.assertEqual(credit.standing("4000", "10000").headroom, Decimal("6000"))

    def test_headroom_never_goes_negative(self):
        # "You have -2,000 left" is not a sentence anybody can act on.
        self.assertEqual(credit.standing("12000", "10000").headroom, Decimal("0.00"))


class OverTheLimitTests(TestCase):
    def test_a_sale_that_tips_them_over_is_flagged(self):
        result = credit.standing(balance="9000", credit_limit="10000", adding="2500")

        self.assertTrue(result.tips_over)
        self.assertFalse(result.over_now)
        self.assertEqual(result.over_by, Decimal("1500"))

    def test_someone_already_over_is_distinguished_from_someone_going_over(self):
        # Different sentences, because they are different conversations with
        # the dealer standing at the counter.
        already = credit.standing(balance="12000", credit_limit="10000", adding="500")
        tipping = credit.standing(balance="9000", credit_limit="10000", adding="2000")

        self.assertTrue(already.over_now)
        self.assertFalse(already.tips_over)
        self.assertTrue(tipping.tips_over)
        self.assertFalse(tipping.over_now)

    def test_the_message_names_the_amount_and_the_limit(self):
        result = credit.standing(balance="9000", credit_limit="10000", adding="2500")

        self.assertIn("1,500", result.message)
        self.assertIn("10,000", result.message)

    def test_the_message_for_someone_already_over_says_where_they_end_up(self):
        result = credit.standing(balance="12000", credit_limit="10000", adding="500")

        self.assertIn("Already over", result.message)
        self.assertIn("12,500", result.message)

    def test_the_projected_balance_includes_this_sale(self):
        self.assertEqual(
            credit.standing("9000", "10000", "2500").projected, Decimal("11500")
        )

    def test_nothing_here_refuses_a_sale(self):
        # The decision. There is deliberately no "blocked" or "allowed" on this
        # object: the counter is the worst place to refuse, and a till that
        # refuses is a till the shop works around.
        result = credit.standing(balance="99999", credit_limit="10", adding="99999")

        self.assertFalse(hasattr(result, "blocked"))
        self.assertTrue(result.message)


class OddInputTests(TestCase):
    def test_a_missing_balance_reads_as_nothing_owed(self):
        self.assertEqual(credit.standing(None, "10000").balance, Decimal("0.00"))

    def test_checking_standing_without_a_sale_is_allowed(self):
        # The khata list asks "is this person over?" with no sale in hand.
        result = credit.standing("12000", "10000")

        self.assertTrue(result.over_now)
        self.assertEqual(result.projected, Decimal("12000"))

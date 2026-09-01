"""Attributes only some kinds of shop have, and the price rules on them.

A garment wholesaler sells one shirt at 250 a piece by the dozen and 220 a
piece past five dozen. That slab table is money: if the till and the invoice
disagree about which slab applied, the shop is arguing with a dealer over a
number the software produced, and the shop loses.

So the arithmetic lives in one function and is pinned here. The other half of
this file is about the JSON column itself - a write endpoint that accepts free
JSON accumulates whatever four clients on four release cycles feel like
sending, until nobody can say what a row holds.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase

from platform_apps.inventory.attributes import (
    MAX_TIERS,
    clean_attributes,
    price_for_quantity,
)


class AttributeAllowlistTests(TestCase):
    def test_known_attributes_are_kept(self):
        cleaned = clean_attributes(
            {
                "profile": "wholesale_garment",
                "colour": "Assorted - 4 per dozen",
                "fabric": "Rayon 140 GSM",
                "season": "Winter 2026 lot 3",
            }
        )

        self.assertEqual(cleaned["profile"], "wholesale_garment")
        self.assertEqual(cleaned["fabric"], "Rayon 140 GSM")

    def test_unknown_keys_are_dropped_rather_than_stored(self):
        # The whole point of the allowlist. Without it this column becomes a
        # place client builds quietly leave things nobody later understands.
        cleaned = clean_attributes({"colour": "Blue", "surprise": {"deep": [1, 2]}})

        self.assertEqual(list(cleaned), ["colour"])

    def test_an_unknown_key_does_not_fail_the_save(self):
        # A phone on last month's build must still be able to save a product.
        # It simply saves the keys this server understands.
        self.assertEqual(clean_attributes({"whatever": "x"}), {})

    def test_empty_values_are_omitted_not_stored_blank(self):
        # So a row carries what was filled in, and "has a fabric recorded" is a
        # question with an answer.
        self.assertEqual(clean_attributes({"colour": "   ", "fabric": ""}), {})

    def test_a_non_object_is_not_stored(self):
        for value in ("a string", 7, [1, 2], None):
            self.assertEqual(clean_attributes(value), {})

    def test_long_text_is_truncated_rather_than_refused(self):
        cleaned = clean_attributes({"season": "x" * 5000})

        self.assertLessEqual(len(cleaned["season"]), 240)


class PriceTierCleaningTests(TestCase):
    def test_tiers_are_sorted_by_quantity(self):
        # Consumers walk this list once and keep the last slab reached. That
        # only works if the order is guaranteed here, not at a counter.
        cleaned = clean_attributes(
            {
                "price_tiers": [
                    {"min_quantity": "5", "price_per_piece": "220"},
                    {"min_quantity": "1", "price_per_piece": "250"},
                ]
            }
        )

        self.assertEqual(
            [tier["min_quantity"] for tier in cleaned["price_tiers"]], ["1", "5"]
        )

    def test_a_half_typed_tier_is_dropped(self):
        # "From 0 units, 0.00 each" would price an entire lot at nothing.
        cleaned = clean_attributes(
            {
                "price_tiers": [
                    {"min_quantity": "1", "price_per_piece": "250"},
                    {"min_quantity": "5"},
                    {"price_per_piece": "220"},
                ]
            }
        )

        self.assertEqual(len(cleaned["price_tiers"]), 1)

    def test_zero_and_negative_are_not_prices(self):
        cleaned = clean_attributes(
            {
                "price_tiers": [
                    {"min_quantity": "1", "price_per_piece": "0"},
                    {"min_quantity": "-2", "price_per_piece": "220"},
                ]
            }
        )

        self.assertNotIn("price_tiers", cleaned)

    def test_prices_survive_as_strings(self):
        # JSON numbers are floats, and a float is not a price.
        cleaned = clean_attributes(
            {"price_tiers": [{"min_quantity": "1", "price_per_piece": "249.90"}]}
        )

        self.assertIsInstance(cleaned["price_tiers"][0]["price_per_piece"], str)
        self.assertEqual(cleaned["price_tiers"][0]["price_per_piece"], "249.9")

    def test_a_duplicated_slab_keeps_one_price(self):
        cleaned = clean_attributes(
            {
                "price_tiers": [
                    {"min_quantity": "5", "price_per_piece": "230"},
                    {"min_quantity": "5", "price_per_piece": "220"},
                ]
            }
        )

        self.assertEqual(len(cleaned["price_tiers"]), 1)

    def test_the_number_of_slabs_is_bounded(self):
        cleaned = clean_attributes(
            {
                "price_tiers": [
                    {"min_quantity": str(n), "price_per_piece": "100"}
                    for n in range(1, 40)
                ]
            }
        )

        self.assertLessEqual(len(cleaned["price_tiers"]), MAX_TIERS)

    def test_rubbish_in_the_list_does_not_break_the_save(self):
        cleaned = clean_attributes(
            {
                "price_tiers": [
                    "nonsense",
                    42,
                    None,
                    {"min_quantity": "1", "price_per_piece": "250"},
                ]
            }
        )

        self.assertEqual(len(cleaned["price_tiers"]), 1)


class BulkPriceTests(TestCase):
    """250 a piece by the dozen, 220 past five dozen, 205 past ten."""

    def setUp(self):
        self.attributes = clean_attributes(
            {
                "price_tiers": [
                    {"min_quantity": "1", "price_per_piece": "250"},
                    {"min_quantity": "5", "price_per_piece": "220"},
                    {"min_quantity": "10", "price_per_piece": "205"},
                ]
            }
        )

    def test_the_slab_that_applies_is_the_last_one_reached(self):
        self.assertEqual(price_for_quantity(self.attributes, 1, "300"), Decimal("250"))
        self.assertEqual(price_for_quantity(self.attributes, 4, "300"), Decimal("250"))
        self.assertEqual(price_for_quantity(self.attributes, 5, "300"), Decimal("220"))
        self.assertEqual(price_for_quantity(self.attributes, 9, "300"), Decimal("220"))
        self.assertEqual(price_for_quantity(self.attributes, 40, "300"), Decimal("205"))

    def test_a_slab_boundary_is_inclusive(self):
        # "From 5 dozen" means five qualifies. Off by one here is a discount
        # the dealer was promised and did not get.
        self.assertEqual(price_for_quantity(self.attributes, 5, "300"), Decimal("220"))

    def test_below_the_first_slab_falls_back_to_the_base_price(self):
        attributes = clean_attributes(
            {"price_tiers": [{"min_quantity": "5", "price_per_piece": "220"}]}
        )

        self.assertEqual(price_for_quantity(attributes, 2, "300"), Decimal("300"))

    def test_a_product_with_no_tiers_uses_its_own_price(self):
        self.assertEqual(price_for_quantity({}, 100, "300"), Decimal("300"))

    def test_a_broken_rule_never_makes_a_line_free(self):
        # The direction that matters. Falling back to the base price costs a
        # dealer their discount; falling back to zero gives away the lot.
        for attributes in ("not a dict", None, {"price_tiers": "nonsense"}):
            self.assertEqual(price_for_quantity(attributes, 10, "300"), Decimal("300"))

    def test_an_unparseable_quantity_uses_the_base_price(self):
        self.assertEqual(
            price_for_quantity(self.attributes, "not a number", "300"), Decimal("300")
        )

    def test_a_tier_with_rubbish_in_it_is_skipped_not_applied(self):
        attributes = {
            "price_tiers": [
                {"min_quantity": "1", "price_per_piece": "250"},
                {"min_quantity": "oops", "price_per_piece": "1"},
            ]
        }

        self.assertEqual(price_for_quantity(attributes, 50, "300"), Decimal("250"))

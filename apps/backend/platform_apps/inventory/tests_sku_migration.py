"""Deciding which duplicate codes to rename, and to what.

This runs once, against live data, with no second chance. If it leaves a
duplicate behind the unique index fails to build and the deploy stops
half-way; if it renames the wrong row, a label already stuck to something in
the stockroom stops matching the product it is on.

Tested as a pure decision because it cannot be driven through the ORM: once
the index exists, duplicates can no longer be created for it to separate.
"""
from __future__ import annotations

import importlib

from django.test import SimpleTestCase

plan_renames = importlib.import_module(
    "platform_apps.inventory.migrations.0010_unique_sku_per_shop"
).plan_renames

SHOP = "shop-1"
OTHER = "shop-2"


class PlanRenamesTests(SimpleTestCase):
    def test_a_clean_shop_needs_no_renames(self):
        rows = [("a", SHOP, "R-1"), ("b", SHOP, "R-2")]
        self.assertEqual(plan_renames(rows), [])

    def test_the_first_row_keeps_the_code(self):
        # Rows arrive oldest first, and the oldest is the one whose printed
        # labels are already stuck to things.
        rows = [("old", SHOP, "R-1"), ("new", SHOP, "R-1")]
        self.assertEqual(plan_renames(rows), [("new", "R-1-2")])

    def test_a_difference_of_case_still_counts_as_a_clash(self):
        """The index is case-folded. Separating only exact matches would leave
        behind the pairs that actually collide, and the index would not build."""
        rows = [("a", SHOP, "ABC-1"), ("b", SHOP, "abc-1")]
        self.assertEqual(plan_renames(rows), [("b", "abc-1-2")])

    def test_three_copies_become_two_and_three_not_two_twice(self):
        rows = [("a", SHOP, "C"), ("b", SHOP, "C"), ("c", SHOP, "C")]
        self.assertEqual(plan_renames(rows), [("b", "C-2"), ("c", "C-3")])

    def test_it_steps_over_a_suffix_that_is_already_taken(self):
        # A shop that already has R-1 and R-1-2 must not be given a second
        # R-1-2, or the index still refuses to build.
        rows = [("a", SHOP, "R-1"), ("b", SHOP, "R-1-2"), ("c", SHOP, "R-1")]
        self.assertEqual(plan_renames(rows), [("c", "R-1-3")])

    def test_two_shops_may_hold_the_same_code(self):
        rows = [("a", SHOP, "R-1"), ("b", OTHER, "R-1")]
        self.assertEqual(plan_renames(rows), [])

    def test_surrounding_space_does_not_hide_a_clash(self):
        rows = [("a", SHOP, "R-1"), ("b", SHOP, "  R-1  ")]
        self.assertEqual(plan_renames(rows), [("b", "R-1-2")])

    def test_every_result_is_distinct(self):
        """The property that matters: whatever it decides, the index builds."""
        rows = [(str(n), SHOP, "SAME") for n in range(20)]
        renames = dict(plan_renames(rows))
        codes = [c.lower() for c in renames.values()] + ["same"]
        self.assertEqual(len(codes), len(set(codes)))

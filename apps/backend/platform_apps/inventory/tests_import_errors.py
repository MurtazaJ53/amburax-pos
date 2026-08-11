from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem
from platform_apps.inventory.views import _row_error
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class ImportErrorReportingTests(TestCase):
    """A rejected row has to be findable in the spreadsheet it came from.

    Importing a legacy catalogue is the first thing a new shop does. Reporting
    that 340 of 2,000 products failed, without saying which, means the shop
    cannot proceed and has no way to ask a better question.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="import@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Import Shop", slug="import-shop")
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.url = reverse("inventory-bulk", args=[self.shop.id])

    def _post(self, items):
        return self.client.post(self.url, {"items": items}, format="json")

    # --- what a rejected row says ------------------------------------------

    def test_a_rejected_row_names_the_item_not_just_the_field(self):
        """The person fixing this is looking at a spreadsheet, not a schema."""
        response = self._post([
            {"name": "Good Item", "sell_price": "100.00"},
            {"name": "Bad Item", "sku": "BAD-1", "sell_price": "not a number"},
        ])

        self.assertEqual(response.data["created"], 1)
        error = response.data["errors"][0]
        self.assertEqual(error["name"], "Bad Item")
        self.assertEqual(error["sku"], "BAD-1")
        self.assertIn("sell_price", error["message"])

    def test_the_index_locates_the_row_within_the_request(self):
        response = self._post([
            {"name": "One", "sell_price": "10.00"},
            {"name": "Two", "sell_price": "10.00"},
            {"name": "Three", "sell_price": "oops"},
        ])

        self.assertEqual(response.data["errors"][0]["index"], 2)

    def test_identity_survives_even_when_the_value_was_unparseable(self):
        """Taken from the raw input, so validation rejecting the row does not
        also destroy the only means of finding it."""
        error = _row_error(
            5,
            {"name": "Kurta", "sku": "K-9", "sell_price": "abc"},
            {"sell_price": ["A valid number is required."]},
        )

        self.assertEqual(error["name"], "Kurta")
        self.assertEqual(error["sku"], "K-9")
        self.assertIn("valid number", error["message"])

    def test_a_row_with_no_identifying_fields_still_reports(self):
        error = _row_error(0, {}, {"name": ["This field is required."]})

        self.assertEqual(error["name"], "")
        self.assertTrue(error["message"])

    def test_a_non_field_error_reads_as_a_row_problem(self):
        error = _row_error(0, {"name": "X"}, {"non_field_errors": ["Bad shape."]})

        self.assertIn("row:", error["message"])
        self.assertNotIn("non_field_errors", error["message"])

    # --- counting -----------------------------------------------------------

    def test_the_true_failure_count_is_reported_even_when_the_list_is_capped(self):
        """Returning 50 errors when there were 340 would be a lie the shop
        acts on."""
        items = [
            {"name": f"Bad {n}", "sell_price": "not a number"} for n in range(60)
        ]

        response = self._post(items)

        self.assertEqual(response.data["skipped"], 60)
        self.assertEqual(response.data["error_count"], 60)
        self.assertLessEqual(len(response.data["errors"]), 50)

    def test_good_rows_still_land_when_others_fail(self):
        response = self._post([
            {"name": "Keeper", "sell_price": "250.00"},
            {"name": "Broken", "sell_price": "nope"},
        ])

        self.assertEqual(response.data["created"], 1)
        self.assertTrue(
            InventoryItem.objects.filter(shop=self.shop, name="Keeper").exists()
        )

    def test_a_clean_import_reports_no_errors(self):
        response = self._post([
            {"name": "A", "sell_price": "10.00"},
            {"name": "B", "sell_price": "20.00"},
        ])

        self.assertEqual(response.data["created"], 2)
        self.assertEqual(response.data["error_count"], 0)
        self.assertEqual(response.data["errors"], [])

    def test_re_importing_updates_rather_than_duplicating(self):
        """Stated in the UI as the reason it is safe to fix and re-upload, so
        it needs to be true."""
        self._post([{"name": "Kurta", "sku": "K-1", "sell_price": "100.00"}])
        self._post([{"name": "Kurta", "sku": "K-1", "sell_price": "150.00"}])

        items = InventoryItem.objects.filter(shop=self.shop, tombstone=False)
        self.assertEqual(items.count(), 1)
        self.assertEqual(items.first().sell_price, Decimal("150.00"))

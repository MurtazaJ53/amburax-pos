"""A rejected row has to say which row, and why.

The sales history importer reported only {"created": N, "skipped": M}. A
shopkeeper told "340 skipped" cannot find which 340 in a spreadsheet, so the
usual outcome is abandoning the import — and the app — inside the first hour.
The inventory importer already did this properly; this one did not.
"""
from __future__ import annotations

from django.test import TestCase
from rest_framework.test import APIClient

from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class SaleHistoryImportErrorTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="importer@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Import Shop", slug="import-shop", settings_json={"plan_tier": "pro"}
        )
        ShopMembership.objects.create(
            user=self.user, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/shops/{self.shop.id}/sales/history-import/"

    def _post(self, rows):
        return self.client.post(self.url, {"sales": rows}, format="json")

    def test_a_good_row_is_imported(self):
        response = self._post([{"total": "100", "date": "2026-01-05"}])

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["created"], 1)
        self.assertEqual(response.data["errors"], [])

    def test_a_bad_total_names_the_row_and_the_reason(self):
        response = self._post(
            [
                {"total": "100", "date": "2026-01-05"},
                {"total": "not-a-number", "date": "2026-01-05"},
            ]
        )

        self.assertEqual(response.data["created"], 1)
        self.assertEqual(response.data["skipped"], 1)
        error = response.data["errors"][0]
        # Row 2, counted the way a spreadsheet counts.
        self.assertEqual(error["row"], 2)
        self.assertIn("number", error["reason"].lower())

    def test_a_zero_total_is_explained(self):
        response = self._post([{"total": "0", "date": "2026-01-05"}])

        self.assertEqual(response.data["errors"][0]["reason"],
                         "Total must be greater than zero.")

    def test_a_repeat_import_says_already_imported(self):
        """Re-running the same file is the normal way to resume a part-finished
        import, so it must be explained rather than counted as a mystery."""
        rows = [{"id": "abc-1", "total": "100", "date": "2026-01-05"}]
        self._post(rows)
        response = self._post(rows)

        self.assertEqual(response.data["created"], 0)
        self.assertIn("Already imported", response.data["errors"][0]["reason"])

    def test_the_error_list_is_capped_but_the_count_is_not(self):
        """"20 errors" when there were 60 is a lie; "showing 20 of 60" is
        actionable."""
        rows = [{"total": "0"} for _ in range(60)]

        response = self._post(rows)

        self.assertEqual(len(response.data["errors"]), 20)
        self.assertEqual(response.data["error_count"], 60)
        self.assertEqual(response.data["skipped"], 60)

    def test_good_rows_still_import_alongside_bad_ones(self):
        """A single bad row must not cost the shopkeeper the whole file."""
        response = self._post(
            [
                {"total": "100", "date": "2026-01-05"},
                {"total": "bad"},
                {"total": "250", "date": "2026-01-06"},
            ]
        )

        self.assertEqual(response.data["created"], 2)
        self.assertEqual(Sale.objects.filter(shop=self.shop).count(), 2)

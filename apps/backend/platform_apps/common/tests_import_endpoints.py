"""Import and undo, through the endpoints a screen actually calls.

The service tests prove the rule. These prove the wiring: that an import
records what it created, that a row it merely refreshed is never claimed by
it, and that undo reaches only the shop it belongs to.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from platform_apps.common.models import ImportBatch
from platform_apps.inventory.models import InventoryItem
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class ImportEndpointTests(TestCase):
    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="owner@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Import Shop", slug="import-shop")
        ShopMembership.objects.create(
            user=self.owner, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.bulk_url = reverse("inventory-bulk", args=[self.shop.id])
        self.list_url = reverse("import-batch-list", args=[self.shop.id])

    def _import(self, names, filename="stock.csv"):
        return self.client.post(
            self.bulk_url,
            {
                "filename": filename,
                "items": [{"name": n, "sell_price": "10.00"} for n in names],
            },
            format="json",
        )

    def _undo(self, batch_id):
        return self.client.post(
            reverse("import-batch-undo", args=[self.shop.id, batch_id])
        )

    # --- what an import records -------------------------------------------

    def test_an_import_hands_back_something_to_undo_with(self):
        # "The last import" is ambiguous the moment two people import at once.
        response = self._import(["Rice", "Dal"])
        self.assertEqual(response.status_code, 201, response.content)
        self.assertTrue(response.data.get("batch_id"))

    def test_the_import_is_listed_with_enough_to_recognise_it(self):
        self._import(["Rice"], filename="customers-by-mistake.csv")
        row = self.client.get(self.list_url).data[0]
        self.assertEqual(row["filename"], "customers-by-mistake.csv")
        self.assertEqual(row["created_count"], 1)
        self.assertEqual(row["actor_name"], "Owner")
        self.assertTrue(row["can_undo"])

    def test_a_refreshed_row_is_not_claimed_by_the_import(self):
        """It existed beforehand. Undo must not delete it."""
        InventoryItem.objects.create(
            shop=self.shop, name="Rice", sell_price=Decimal("5")
        )
        response = self._import(["Rice"])
        self.assertEqual(response.data["updated"], 1)
        self.assertEqual(response.data["created"], 0)

        self._undo(response.data["batch_id"])
        self.assertTrue(
            InventoryItem.objects.filter(
                shop=self.shop, name="Rice", tombstone=False
            ).exists(),
            "undo removed a product that existed before the import",
        )

    def test_an_import_that_created_nothing_offers_no_undo(self):
        InventoryItem.objects.create(
            shop=self.shop, name="Rice", sell_price=Decimal("5")
        )
        self._import(["Rice"])
        self.assertFalse(self.client.get(self.list_url).data[0]["can_undo"])

    # --- undoing -----------------------------------------------------------

    def test_undo_removes_what_the_import_created(self):
        batch_id = self._import(["Wrong 1", "Wrong 2", "Wrong 3"]).data["batch_id"]

        response = self._undo(batch_id)

        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.data["removed"], 3)
        self.assertEqual(
            InventoryItem.objects.filter(shop=self.shop, tombstone=False).count(), 0
        )

    def test_an_undone_import_says_so_and_cannot_be_undone_again(self):
        batch_id = self._import(["One"]).data["batch_id"]
        self._undo(batch_id)
        row = self.client.get(self.list_url).data[0]
        self.assertIsNotNone(row["undone_at"])
        self.assertFalse(row["can_undo"])

    def test_the_row_number_from_the_file_is_kept_on_each_row(self):
        # So a person can go back and fix line 2 rather than hunt for it.
        self._import(["First", "Second"])
        second = InventoryItem.objects.get(shop=self.shop, name="Second")
        self.assertEqual(second.source_id, "2")

    # --- who and where -----------------------------------------------------

    def test_another_shops_import_cannot_be_undone(self):
        other = Shop.objects.create(name="Other", slug="other-import-shop")
        theirs = ImportBatch.objects.create(
            shop=other, kind=ImportBatch.Kind.PRODUCTS, row_count=1
        )
        self.assertEqual(self._undo(theirs.id).status_code, 404)

    def test_a_cashier_cannot_undo_an_import(self):
        """It removes rows in bulk, which is more than running one."""
        batch_id = self._import(["One"]).data["batch_id"]
        cashier = PlatformUser.objects.create_user(
            email="cashier@example.com", password="secret", full_name="Cashier"
        )
        ShopMembership.objects.create(
            user=cashier, shop=self.shop,
            role=ShopMembership.Role.CASHIER,
            status=ShopMembership.Status.ACTIVE,
        )
        client = APIClient()
        client.force_authenticate(user=cashier)
        response = client.post(
            reverse("import-batch-undo", args=[self.shop.id, batch_id])
        )
        self.assertIn(response.status_code, (403, 404))

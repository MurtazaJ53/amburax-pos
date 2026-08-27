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


class ChunkedImportTests(TestCase):
    """A file larger than one request still undoes in one click.

    The web proxy splits a large file into requests of five hundred rows. Each
    used to record its own batch, so undoing one twelve-hundred-row mistake
    took three clicks and nothing on screen said so.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="chunk@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Chunk Shop", slug="chunk-shop")
        ShopMembership.objects.create(
            user=self.owner, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.bulk_url = reverse("inventory-bulk", args=[self.shop.id])

    def _chunk(self, names, filename="big.csv"):
        return self.client.post(
            self.bulk_url,
            {
                "filename": filename,
                "items": [{"name": n, "sell_price": "10.00"} for n in names],
            },
            format="json",
        )

    def test_every_chunk_of_one_file_joins_one_batch(self):
        first = self._chunk(["A", "B"])
        second = self._chunk(["C", "D"])
        self.assertEqual(first.data["batch_id"], second.data["batch_id"])
        self.assertEqual(ImportBatch.objects.filter(shop=self.shop).count(), 1)

    def test_the_batch_counts_every_chunk_not_just_the_last(self):
        self._chunk(["A", "B"])
        self._chunk(["C", "D"])
        batch = ImportBatch.objects.get(shop=self.shop)
        self.assertEqual(batch.row_count, 4)
        self.assertEqual(batch.created_count, 4)

    def test_undoing_once_takes_back_the_whole_file(self):
        self._chunk(["A", "B"])
        batch_id = self._chunk(["C", "D"]).data["batch_id"]

        response = self.client.post(
            reverse("import-batch-undo", args=[self.shop.id, batch_id])
        )

        self.assertEqual(response.data["removed"], 4)
        self.assertEqual(
            InventoryItem.objects.filter(shop=self.shop, tombstone=False).count(), 0
        )

    def test_a_different_file_gets_its_own_batch(self):
        self._chunk(["A"], filename="one.csv")
        self._chunk(["B"], filename="two.csv")
        self.assertEqual(ImportBatch.objects.filter(shop=self.shop).count(), 2)

    def test_an_undone_batch_is_never_added_to(self):
        """Rows joining a batch already taken back would be tagged as removed
        while sitting in the shop."""
        batch_id = self._chunk(["A"]).data["batch_id"]
        self.client.post(reverse("import-batch-undo", args=[self.shop.id, batch_id]))

        again = self._chunk(["B"]).data["batch_id"]

        self.assertNotEqual(again, batch_id)

    def test_a_file_with_no_name_is_not_lumped_in_with_the_next(self):
        # Two unrelated pastes cannot be told apart, so they stay separate.
        self._chunk(["A"], filename="")
        self._chunk(["B"], filename="")
        self.assertEqual(ImportBatch.objects.filter(shop=self.shop).count(), 2)


class SalesHistoryUndoTests(TestCase):
    """Undoing imported history, and the rule that makes it safe.

    A historical sale deliberately moves no stock - the shelf today already
    reflects that it happened. That is what makes taking one back safe: there
    is no stock movement to reverse, only a record to remove.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="hist@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="History Shop", slug="history-imp-shop")
        ShopMembership.objects.create(
            user=self.owner, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.url = f"/api/v1/shops/{self.shop.id}/sales/history-import/"

    def _import(self, rows, filename="last-year.csv"):
        return self.client.post(
            self.url, {"filename": filename, "sales": rows}, format="json"
        )

    def test_imported_history_moves_no_stock(self):
        """The whole design. Replaying a year of sales against today's shelf
        would drive every product deeply negative."""
        from platform_apps.inventory.models import InventoryStockLedger

        self._import(
            [{"id": "a1", "date": "2026-03-04", "total": "500"},
             {"id": "a2", "date": "2026-03-05", "total": "250"}]
        )
        self.assertEqual(
            InventoryStockLedger.objects.filter(shop=self.shop).count(), 0
        )

    def test_an_import_can_be_taken_back(self):
        from platform_apps.sales.models import Sale

        response = self._import(
            [{"id": "b1", "date": "2026-03-04", "total": "500"},
             {"id": "b2", "date": "2026-03-05", "total": "250"}]
        )
        self.assertEqual(response.status_code, 201, response.content)
        batch_id = response.data["batch_id"]

        undone = self.client.post(
            reverse("import-batch-undo", args=[self.shop.id, batch_id])
        )

        self.assertEqual(undone.data["removed"], 2)
        self.assertEqual(
            Sale.objects.filter(shop=self.shop, tombstone=False).count(), 0
        )

    def test_re_importing_the_same_file_does_not_duplicate(self):
        """It was already idempotent by client id. Adding a batch must not
        have broken that."""
        from platform_apps.sales.models import Sale

        rows = [{"id": "c1", "date": "2026-03-04", "total": "500"}]
        self._import(rows)
        self._import(rows)
        self.assertEqual(Sale.objects.filter(shop=self.shop).count(), 1)

    def test_the_import_is_listed_as_undoable(self):
        self._import([{"id": "d1", "date": "2026-03-04", "total": "500"}])
        row = self.client.get(
            reverse("import-batch-list", args=[self.shop.id])
        ).data[0]
        self.assertEqual(row["kind"], "sales")
        self.assertTrue(row["can_undo"])

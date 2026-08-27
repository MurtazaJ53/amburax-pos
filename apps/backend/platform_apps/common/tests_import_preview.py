"""A preview must leave no trace, and must tell the truth about what it saw.

The preview is the real import rolled back, so the thing to prove is that the
rollback is complete - no rows, no batch, no dashboard rebuild - while the
counts it reports still match what a real run would do.
"""
from __future__ import annotations

from decimal import Decimal
from unittest.mock import patch

from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from platform_apps.common.models import ImportBatch
from platform_apps.customers.models import Customer
from platform_apps.inventory.models import InventoryItem
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class ImportPreviewTests(TestCase):
    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="preview@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Preview Shop", slug="preview-shop")
        ShopMembership.objects.create(
            user=self.owner, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    def _products(self, names, dry_run):
        return self.client.post(
            reverse("inventory-bulk", args=[self.shop.id]),
            {
                "filename": "stock.csv",
                "dry_run": dry_run,
                "items": [{"name": n, "sell_price": "10.00"} for n in names],
            },
            format="json",
        )

    # --- nothing is written ------------------------------------------------

    def test_a_preview_creates_no_products(self):
        response = self._products(["Rice", "Dal"], dry_run=True)
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(InventoryItem.objects.filter(shop=self.shop).count(), 0)

    def test_a_preview_leaves_no_import_record(self):
        """Otherwise the undo list fills with imports that never happened."""
        self._products(["Rice"], dry_run=True)
        self.assertEqual(ImportBatch.objects.filter(shop=self.shop).count(), 0)

    def test_a_preview_does_not_rebuild_the_dashboard(self):
        # It is not a database write, so it would not roll back with the rest.
        with patch(
            "platform_apps.inventory.views.refresh_projection_after_write"
        ) as refresh:
            self._products(["Rice"], dry_run=True)
        self.assertFalse(refresh.called)

    # --- but it reports what would happen -----------------------------------

    def test_a_preview_counts_what_would_be_created(self):
        response = self._products(["Rice", "Dal", "Oil"], dry_run=True)
        self.assertEqual(response.data["created"], 3)

    def test_a_preview_says_it_wrote_nothing(self):
        # In the payload, not only on screen: a client that ignored this would
        # otherwise report a successful import of rows that do not exist.
        response = self._products(["Rice"], dry_run=True)
        self.assertIs(response.data["dry_run"], True)
        self.assertIs(response.data["written"], False)

    def test_a_preview_tells_you_what_is_already_here(self):
        """The count people actually want: how much of this file is new.

        Reported by running the real matching rules rather than a second copy
        of them, so it cannot disagree with the import that follows.
        """
        InventoryItem.objects.create(
            shop=self.shop, name="Rice", sell_price=Decimal("5")
        )
        response = self._products(["Rice", "Dal"], dry_run=True)
        self.assertEqual(response.data["updated"], 1)
        self.assertEqual(response.data["created"], 1)

    def test_a_preview_reports_bad_rows_without_importing_the_good_ones(self):
        response = self.client.post(
            reverse("inventory-bulk", args=[self.shop.id]),
            {
                "dry_run": True,
                "items": [{"name": "Fine", "sell_price": "10"}, {"sell_price": "5"}],
            },
            format="json",
        )
        self.assertEqual(response.data["created"], 1)
        self.assertEqual(response.data["skipped"], 1)
        self.assertEqual(InventoryItem.objects.filter(shop=self.shop).count(), 0)

    # --- the real thing still works ----------------------------------------

    def test_without_the_flag_the_import_really_happens(self):
        self._products(["Rice"], dry_run=False)
        self.assertEqual(InventoryItem.objects.filter(shop=self.shop).count(), 1)
        self.assertEqual(ImportBatch.objects.filter(shop=self.shop).count(), 1)

    def test_only_a_real_boolean_counts_as_a_preview(self):
        """A truthy string would silently turn a real import into a no-op."""
        self._products(["Rice"], dry_run="false")
        self.assertEqual(InventoryItem.objects.filter(shop=self.shop).count(), 1)

    # --- the other two kinds ------------------------------------------------

    def test_a_customer_preview_writes_nothing(self):
        response = self.client.post(
            reverse("customer-bulk", args=[self.shop.id]),
            {"dry_run": True, "customers": [{"name": "Asha", "phone": "9876500001"}]},
            format="json",
        )
        self.assertEqual(response.data["created"], 1)
        self.assertEqual(Customer.objects.filter(shop=self.shop).count(), 0)

    def test_a_sales_preview_writes_nothing(self):
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/history-import/",
            {"dry_run": True, "sales": [{"id": "p1", "date": "2026-03-04", "total": "500"}]},
            format="json",
        )
        self.assertEqual(response.data["created"], 1)
        self.assertEqual(Sale.objects.filter(shop=self.shop).count(), 0)

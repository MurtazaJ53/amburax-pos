"""The homepage after stock moves.

The dashboard is a stored snapshot, not a live query. Anything that moves
stock and does not rebuild it leaves the shop looking at yesterday: an item
received this morning still counted as out of stock, and a shelf value that
does not include what is on the shelf.

Selling already rebuilt it. Receiving a delivery and applying a count did
not, which are the two other ways stock moves.
"""
from __future__ import annotations

from decimal import Decimal
from unittest.mock import patch

from django.test import TestCase
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.purchases.models import Supplier
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser

REFRESH = "platform_apps.purchases.views.refresh_projection_after_write"


class StockMovementRefreshesTheDashboard(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="owner@example.com", password="secret", full_name="Owner"
        )
        # Pro unlocks purchase_workflow, which is what books a delivery.
        self.shop = Shop.objects.create(
            name="Refresh Shop", slug="refresh-shop", settings_json={"plan_tier": "pro"}
        )
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Basmati Rice", sku="RICE-01", sell_price=Decimal("80")
        )
        self.supplier = Supplier.objects.create(shop=self.shop, name="Wholesaler")
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_receiving_a_delivery_rebuilds_the_dashboard(self):
        """Otherwise the homepage still calls it out of stock after it arrives."""
        with patch(REFRESH) as refresh:
            response = self.client.post(
                f"/api/v1/shops/{self.shop.id}/purchases/",
                {
                    "supplier_id": str(self.supplier.id),
                    "invoice_number": "INV-1",
                    "amount_paid": "0.00",
                    "items": [
                        {
                            "inventory_item_id": str(self.item.id),
                            "name": "Basmati Rice",
                            "quantity": "50",
                            "unit_cost": "40.00",
                        }
                    ],
                },
                format="json",
            )
        self.assertEqual(response.status_code, 201, response.content)
        # The stock really moved...
        self.assertEqual(
            InventoryStockLedger.objects.filter(item=self.item).count(), 1
        )
        # ...so the figure the homepage reads must be rebuilt.
        self.assertTrue(refresh.called, "a delivery left the dashboard stale")

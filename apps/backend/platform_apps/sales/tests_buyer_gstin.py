"""The buyer's GSTIN on a B2B bill.

gstin_on_every_bill was stored, resolvable and toggleable, and read by nothing.
A wholesaler could turn it on and watch nothing happen. Sale.buyer_gstin has
existed all along, and the GSTR-1 export already reads it — the only missing
piece was the counter asking for it.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser

GSTIN = "27AABCU9603R1ZM"


class BuyerGstinOnSaleTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="wholesale@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Wholesale Co", slug="wholesale-co",
            settings_json={"plan_tier": "pro", "business_type": "wholesale"},
        )
        ShopMembership.objects.create(
            user=self.user, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Cement Bag", sku="CEM-1",
            sell_price=Decimal("400.00"),
        )
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("100.000"), occurred_at=timezone.now(),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/shops/{self.shop.id}/sales/"

    def _payload(self, **extra):
        body = {
            "customer_id": None,
            "items": [
                {
                    "inventory_item_id": str(self.item.id),
                    "quantity": 1,
                    "unit_price": "400.00",
                }
            ],
            "payments": [{"payment_method": "CASH", "amount": "400.00"}],
        }
        body.update(extra)
        return body

    def test_a_wholesale_shop_has_the_flag_on_by_default(self):
        self.assertIs(self.shop.enabled_features["gstin_on_every_bill"], True)

    def test_a_retail_shop_does_not(self):
        """A retail counter must never be stopped by a field its customers do
        not have."""
        retail = Shop.objects.create(
            name="Retail", slug="retail-gstin",
            settings_json={"plan_tier": "pro", "business_type": "retail"},
        )
        self.assertIs(retail.enabled_features["gstin_on_every_bill"], False)

    def test_the_buyer_gstin_is_stored_on_the_sale(self):
        response = self.client.post(
            self.url, self._payload(buyer_gstin=GSTIN), format="json"
        )

        self.assertEqual(response.status_code, 201, response.data)
        sale = Sale.objects.get(shop=self.shop)
        self.assertEqual(sale.buyer_gstin, GSTIN)

    def test_it_comes_back_on_the_sale_payload(self):
        """The receipt and the GSTR-1 export both read it from here."""
        response = self.client.post(
            self.url, self._payload(buyer_gstin=GSTIN), format="json"
        )

        self.assertEqual(response.data["buyer_gstin"], GSTIN)

    def test_a_sale_without_one_still_works(self):
        """Most shops never send it, and the column is nullable."""
        response = self.client.post(self.url, self._payload(), format="json")

        self.assertEqual(response.status_code, 201, response.data)
        sale = Sale.objects.get(shop=self.shop)
        self.assertFalse(sale.buyer_gstin)

"""Completing a sale from a client that sends its own totals.

The website's POS posts subtotal_amount and total_amount alongside the items.
Both are writable, so they survived validation into validated_data and then
arrived as a second value for a keyword the create() call already supplied.
Python raised "got multiple values for keyword argument" and the shopkeeper
saw "Failed to save sale to cloud backend" on the one action a shop performs
more than any other.

Nothing in the existing suite covered it, because the tests posted only the
items and let the server work the totals out.
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


class SaleCreateWithDeclaredTotalsTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="owner@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Demo Shop", slug="demo-shop", settings_json={"plan_tier": "pro"}
        )
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Cotton Shirt", sku="SH-01",
            sell_price=Decimal("899.00"),
        )
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("10.000"), occurred_at=timezone.now(),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    @property
    def url(self):
        return f"/api/v1/shops/{self.shop.id}/sales/"

    def _payload(self, **overrides):
        """Exactly what apps/admin_web pos-terminal.tsx posts."""
        payload = {
            "customer_id": None,
            "subtotal_amount": "899.00",
            "discount_amount": "0.00",
            "total_amount": "899.00",
            "items": [
                {
                    "inventory_item_id": str(self.item.id),
                    "quantity": 1,
                    "unit_price": "899.00",
                }
            ],
            "payments": [{"payment_method": "CASH", "amount": "899.00"}],
        }
        payload.update(overrides)
        return payload

    def test_a_sale_with_declared_totals_is_accepted(self):
        response = self.client.post(self.url, self._payload(), format="json")

        self.assertEqual(response.status_code, 201, response.data)
        sale = Sale.objects.get(shop=self.shop)
        self.assertEqual(sale.subtotal_amount, Decimal("899.00"))
        self.assertEqual(sale.total_amount, Decimal("899.00"))

    def test_the_server_stores_its_own_figures_not_the_client_s(self):
        # The declared values are a cross-check, never the stored value. If a
        # caller could dictate the total, a 10,000 cart could be rung up as 1.
        response = self.client.post(
            self.url, self._payload(subtotal_amount="1.00", total_amount="1.00"),
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("subtotal_amount", response.data)
        self.assertEqual(Sale.objects.count(), 0)

    def test_a_sale_without_declared_totals_still_works(self):
        # The counter app posts only the items. That path must not regress.
        payload = self._payload()
        payload.pop("subtotal_amount")
        payload.pop("total_amount")

        response = self.client.post(self.url, payload, format="json")

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Sale.objects.get(shop=self.shop).total_amount, Decimal("899.00"))

    def test_a_split_payment_sale_with_declared_totals(self):
        # The other shape the web POS produces: more than one tender.
        response = self.client.post(
            self.url,
            self._payload(payments=[
                {"payment_method": "CASH", "amount": "400.00"},
                {"payment_method": "UPI", "amount": "499.00"},
            ]),
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Sale.objects.get(shop=self.shop).payment_mode, Sale.PaymentMode.SPLIT)

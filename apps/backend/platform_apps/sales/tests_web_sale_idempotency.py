"""Ringing the same bill twice must not charge the customer twice.

The website posted sales with no idempotency key and no in-flight guard, and
showed alert() on failure. A lost response — timeout, dropped connection, a
second press — gave a committed sale, a scary error, and a re-ring: duplicate
sale, duplicate stock deduction, duplicate khata entry.

SaleCommandReceipt already carried a UniqueConstraint on (shop, command_id) for
the counter app's sync. It was simply never used from the web.
"""
from __future__ import annotations

from decimal import Decimal
from uuid import uuid4

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class WebSaleIdempotencyTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="till@example.com", password="secret", full_name="Cashier"
        )
        self.shop = Shop.objects.create(
            name="Till Shop", slug="till-shop", settings_json={"plan_tier": "pro"}
        )
        ShopMembership.objects.create(
            user=self.user, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Rice", sku="RICE-1", sell_price=Decimal("60.00")
        )
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("100.000"), occurred_at=timezone.now(),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/shops/{self.shop.id}/sales/"

    def _payload(self, command_id=None):
        body = {
            "customer_id": None,
            "items": [
                {
                    "inventory_item_id": str(self.item.id),
                    "quantity": 1,
                    "unit_price": "60.00",
                }
            ],
            "payments": [{"payment_method": "CASH", "amount": "60.00"}],
        }
        if command_id:
            body["command_id"] = command_id
        return body

    def test_the_same_command_id_creates_one_sale(self):
        """The whole point. This used to create two."""
        command_id = str(uuid4())

        first = self.client.post(self.url, self._payload(command_id), format="json")
        second = self.client.post(self.url, self._payload(command_id), format="json")

        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(second.status_code, 200, second.data)
        self.assertEqual(Sale.objects.filter(shop=self.shop).count(), 1)

    def test_the_retry_returns_the_original_sale(self):
        """A retry that succeeded but returned nothing useful would still leave
        the cashier unsure whether to ring it again."""
        command_id = str(uuid4())

        first = self.client.post(self.url, self._payload(command_id), format="json")
        second = self.client.post(self.url, self._payload(command_id), format="json")

        self.assertEqual(first.data["id"], second.data["id"])
        self.assertEqual(second.data["total_amount"], "60.00")

    def test_stock_is_deducted_once(self):
        """The accusation that kills a POS in a shop is "your stock count is
        wrong"."""
        command_id = str(uuid4())
        self.client.post(self.url, self._payload(command_id), format="json")
        self.client.post(self.url, self._payload(command_id), format="json")

        sold = InventoryStockLedger.objects.filter(
            shop=self.shop, item=self.item, quantity_delta__lt=0
        ).count()
        self.assertEqual(sold, 1)

    def test_different_command_ids_create_different_sales(self):
        """Two genuine sales of the same thing must both go through — a shop
        sells the same item all day."""
        self.client.post(self.url, self._payload(str(uuid4())), format="json")
        self.client.post(self.url, self._payload(str(uuid4())), format="json")

        self.assertEqual(Sale.objects.filter(shop=self.shop).count(), 2)

    def test_a_sale_without_a_command_id_still_works(self):
        """Older clients, and the counter app's own path, must not break."""
        response = self.client.post(self.url, self._payload(), format="json")

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Sale.objects.filter(shop=self.shop).count(), 1)

    def test_a_command_id_is_scoped_to_its_shop(self):
        """A shared id across tenants must not let one shop read another's
        sale."""
        other_user = PlatformUser.objects.create_user(
            email="other@example.com", password="secret", full_name="Other"
        )
        other_shop = Shop.objects.create(
            name="Other", slug="other-till", settings_json={"plan_tier": "pro"}
        )
        ShopMembership.objects.create(
            user=other_user, shop=other_shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        other_item = InventoryItem.objects.create(
            shop=other_shop, name="Rice", sku="RICE-1", sell_price=Decimal("60.00")
        )
        InventoryStockLedger.objects.create(
            shop=other_shop, item=other_item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("10.000"), occurred_at=timezone.now(),
        )

        command_id = str(uuid4())
        self.client.post(self.url, self._payload(command_id), format="json")

        other_client = APIClient()
        other_client.force_authenticate(user=other_user)
        response = other_client.post(
            f"/api/v1/shops/{other_shop.id}/sales/",
            {
                "customer_id": None,
                "command_id": command_id,
                "items": [
                    {
                        "inventory_item_id": str(other_item.id),
                        "quantity": 1,
                        "unit_price": "60.00",
                    }
                ],
                "payments": [{"payment_method": "CASH", "amount": "60.00"}],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Sale.objects.filter(shop=other_shop).count(), 1)

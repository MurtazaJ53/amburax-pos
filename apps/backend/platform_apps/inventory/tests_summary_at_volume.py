"""The figures above the product table describe the shop, not the page.

They were summed in the browser over whatever products had been loaded, and
then labelled as the size of the shop: a catalogue of 285 read as "200 items"
with a stock value to match. Nothing failed. The number was smaller and just
as confident, and a shopkeeper has no way to tell a small shop from a
half-loaded one.

The screen asks the server now. So these tests hold the server to it at a size
where paging exists - the existing summary test uses two products, which is
exactly the size at which this class of defect is invisible.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.utils import timezone

from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser
from rest_framework.test import APIClient

#: Comfortably past a page, so a summary that counted one page would be wrong
#: by a margin no rounding could explain.
PRODUCTS = 450


class InventorySummaryAtVolumeTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="volume.summary@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Big Catalogue",
            slug="big-catalogue",
            settings_json={"plan_tier": "pro"},
        )
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

        items = InventoryItem.objects.bulk_create(
            [
                InventoryItem(
                    shop=self.shop,
                    name=f"Product {n:04d}",
                    sku=f"VOL-{n:04d}",
                    category=f"Aisle {n % 7}",
                    status=InventoryItem.Status.ACTIVE,
                    sell_price=Decimal("10.00"),
                )
                for n in range(PRODUCTS)
            ]
        )
        # Two units each, so the whole shop is worth a round number and a
        # partial sum cannot coincidentally match it.
        now = timezone.now()
        InventoryStockLedger.objects.bulk_create(
            [
                InventoryStockLedger(
                    shop=self.shop,
                    item=item,
                    actor_user=self.user,
                    event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
                    quantity_delta=2,
                    unit_price=Decimal("10.00"),
                    occurred_at=now,
                )
                for item in items
            ]
        )

    def _summary(self):
        response = self.client.get(f"/api/v1/shops/{self.shop.id}/inventory/summary/")
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def test_one_page_of_the_list_is_smaller_than_the_shop(self):
        # The premise. Without this the tests below could pass on a server
        # that returned everything at once, proving nothing about paging.
        page = self.client.get(f"/api/v1/shops/{self.shop.id}/inventory/").json()
        self.assertLess(len(page), PRODUCTS)

    def test_the_count_is_the_whole_shop(self):
        self.assertEqual(self._summary()["total_items"], PRODUCTS)

    def test_the_stock_value_covers_every_product(self):
        # 450 products x 2 units x 10.00. A summary built from the first page
        # would land near 2,000 and read as perfectly plausible.
        self.assertEqual(self._summary()["projected_sell_value"], "9000.00")

    def test_the_categories_count_is_the_whole_shop(self):
        self.assertEqual(self._summary()["categories"], 7)

    def test_every_product_is_accounted_for_as_stocked_or_not(self):
        summary = self._summary()
        self.assertEqual(
            summary["available_items"] + summary["out_of_stock_items"],
            summary["total_items"],
        )

    def test_a_filtered_summary_describes_the_filter_not_the_page(self):
        # The filters narrow the same queryset the aggregate runs over, so a
        # filtered figure has to stay exact rather than exact-for-one-page.
        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/inventory/summary/", {"category": "Aisle 3"}
        )
        self.assertEqual(response.status_code, 200)
        expected = len([n for n in range(PRODUCTS) if n % 7 == 3])
        self.assertEqual(response.json()["total_items"], expected)

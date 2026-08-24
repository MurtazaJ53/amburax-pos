"""Telling "the shelf is empty" apart from "nobody ever counted this".

A stock of zero means both, and the difference decides what the counter is
allowed to claim. If an item was never given stock, selling it cannot produce
a shortfall - there was no count to fall short of. If it WAS stocked and now
reads -3, that is three units sold that nobody recorded buying, and it needs
fixing.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class StockHistoryFlagTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="stock@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Track Shop", slug="track-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/shops/{self.shop.id}/inventory/"

    def _item(self, name):
        return InventoryItem.objects.create(
            shop=self.shop, name=name, sell_price=Decimal("100.00")
        )

    def _move(self, item, delta, event_type):
        InventoryStockLedger.objects.create(
            shop=self.shop,
            item=item,
            event_type=event_type,
            quantity_delta=Decimal(delta),
            occurred_at=timezone.now(),
        )

    def _row(self, name):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        rows = body if isinstance(body, list) else body.get("results", [])
        return next(row for row in rows if row["name"] == name)

    def test_an_item_nobody_ever_stocked_reports_no_history(self):
        self._item("Imported Name Row")
        self.assertFalse(self._row("Imported Name Row")["has_stock_history"])

    def test_an_opening_balance_counts_as_having_been_stocked(self):
        item = self._item("Woolen Caps")
        self._move(item, "40", InventoryStockLedger.EventType.OPENING_BALANCE)
        self.assertTrue(self._row("Woolen Caps")["has_stock_history"])

    def test_a_purchase_counts(self):
        item = self._item("Gents Socks")
        self._move(item, "12", InventoryStockLedger.EventType.PURCHASE)
        self.assertTrue(self._row("Gents Socks")["has_stock_history"])

    def test_selling_alone_never_makes_an_item_look_tracked(self):
        """The heart of it.

        An untracked item sold at the counter writes a NEGATIVE entry. If that
        counted as history, one sale would turn "never counted" into "short by
        one" - a shortfall invented out of nothing.
        """
        item = self._item("Kids Socks")
        self._move(item, "-3", InventoryStockLedger.EventType.SALE)
        row = self._row("Kids Socks")
        self.assertFalse(row["has_stock_history"])
        self.assertEqual(Decimal(row["stock_on_hand"]), Decimal("-3.000"))

    def test_a_stocked_item_sold_past_zero_keeps_its_history(self):
        item = self._item("Ladies Socks")
        self._move(item, "5", InventoryStockLedger.EventType.PURCHASE)
        self._move(item, "-8", InventoryStockLedger.EventType.SALE)
        row = self._row("Ladies Socks")
        self.assertTrue(row["has_stock_history"])
        self.assertEqual(Decimal(row["stock_on_hand"]), Decimal("-3.000"))

    def test_an_item_that_sold_out_cleanly_is_still_tracked(self):
        item = self._item("Jackets")
        self._move(item, "2", InventoryStockLedger.EventType.OPENING_BALANCE)
        self._move(item, "-2", InventoryStockLedger.EventType.SALE)
        row = self._row("Jackets")
        self.assertTrue(row["has_stock_history"])
        self.assertEqual(Decimal(row["stock_on_hand"]), Decimal("0.000"))

    def test_history_is_per_item_not_per_shop(self):
        stocked = self._item("Stocked")
        self._move(stocked, "10", InventoryStockLedger.EventType.PURCHASE)
        self._item("Never Stocked")
        self.assertTrue(self._row("Stocked")["has_stock_history"])
        self.assertFalse(self._row("Never Stocked")["has_stock_history"])

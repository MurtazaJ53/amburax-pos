from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.purchases.models import (
    PurchaseOrder,
    PurchaseOrderLine,
    Supplier,
)

from platform_apps.inventory.models import (
    InventoryItem,
    InventoryItemPrivate,
    InventoryStockLedger,
)
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class StockReportTests(TestCase):
    """Dead stock and the reorder list decide what a shop spends money on, so
    the rules here must match the mobile app's local queries exactly."""

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="stock@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Stock Shop", slug="stock-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def _item(self, name, *, stock=0, sell="100.00", cost=None, reorder=None, unit=""):
        item = InventoryItem.objects.create(
            shop=self.shop,
            name=name,
            sell_price=Decimal(sell),
            reorder_level=reorder,
            unit=unit,
        )
        if stock:
            InventoryStockLedger.objects.create(
                shop=self.shop,
                item=item,
                event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
                quantity_delta=Decimal(str(stock)),
                occurred_at=timezone.now(),
            )
        if cost is not None:
            InventoryItemPrivate.objects.create(item=item, cost_price=Decimal(cost))
        return item

    def _sold(self, item, *, days_ago, qty="1"):
        InventoryStockLedger.objects.create(
            shop=self.shop,
            item=item,
            event_type=InventoryStockLedger.EventType.SALE,
            quantity_delta=Decimal(f"-{qty}"),
            occurred_at=timezone.now() - timedelta(days=days_ago),
        )

    def _dead_stock(self, days=90):
        return self.client.get(
            f"/api/v1/shops/{self.shop.id}/reports/dead-stock/?days={days}"
        ).json()

    def _reorder(self):
        return self.client.get(
            f"/api/v1/shops/{self.shop.id}/reports/reorder-list/"
        ).json()

    # --- dead stock ------------------------------------------------------

    def test_recently_sold_items_are_not_dead(self):
        item = self._item("Moving", stock=10)
        self._sold(item, days_ago=3)
        self.assertEqual(self._dead_stock()["items"], [])

    def test_an_item_sold_long_ago_is_dead(self):
        item = self._item("Stale", stock=10)
        self._sold(item, days_ago=200)
        body = self._dead_stock(days=90)
        self.assertEqual(len(body["items"]), 1)
        self.assertFalse(body["items"][0]["never_sold"])

    def test_an_item_never_sold_is_dead_and_flagged(self):
        self._item("Never", stock=4)
        body = self._dead_stock()
        self.assertEqual(len(body["items"]), 1)
        self.assertTrue(body["items"][0]["never_sold"])
        self.assertEqual(body["never_sold_count"], 1)

    def test_items_with_no_stock_are_not_dead_money(self):
        # Nothing on the shelf means no cash is tied up, however long ago it
        # last sold.
        self._item("Empty", stock=0)
        self.assertEqual(self._dead_stock()["items"], [])

    def test_value_uses_cost_when_known(self):
        self._item("Costed", stock=10, sell="100.00", cost="60.00")
        row = self._dead_stock()["items"][0]
        self.assertEqual(Decimal(row["tied_up_value"]), Decimal("600.000"))
        self.assertEqual(row["valued_at"], "cost")

    def test_value_falls_back_to_sale_price_and_says_so(self):
        # A stored 0.00 cost means "not recorded". Valuing the shelf at zero
        # would hide the very problem this report exists to surface.
        self._item("Uncosted", stock=10, sell="100.00", cost="0.00")
        row = self._dead_stock()["items"][0]
        self.assertEqual(Decimal(row["tied_up_value"]), Decimal("1000.000"))
        self.assertEqual(row["valued_at"], "sale_price")

    def test_worst_first_by_money_tied_up(self):
        self._item("Small", stock=1, sell="100.00")
        self._item("Big", stock=50, sell="100.00")
        names = [row["name"] for row in self._dead_stock()["items"]]
        self.assertEqual(names, ["Big", "Small"])

    def test_a_cashier_cannot_read_dead_stock(self):
        staff = PlatformUser.objects.create_user(
            email="stock-staff@example.com", password="secret", full_name="Staff"
        )
        ShopMembership.objects.create(
            user=staff,
            shop=self.shop,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
        )
        client = APIClient()
        client.force_authenticate(user=staff)
        response = client.get(f"/api/v1/shops/{self.shop.id}/reports/dead-stock/")
        self.assertEqual(response.status_code, 403, response.content)

    # --- reorder list ----------------------------------------------------

    def test_items_above_their_level_are_not_listed(self):
        self._item("Plenty", stock=50, reorder=10)
        self.assertEqual(self._reorder()["items"], [])

    def test_an_item_at_its_level_is_listed(self):
        self._item("AtLevel", stock=10, reorder=10)
        self.assertEqual(len(self._reorder()["items"]), 1)

    def test_items_with_no_level_use_the_shop_default(self):
        self._item("NoLevel", stock=4)
        row = self._reorder()["items"][0]
        self.assertEqual(row["reorder_level"], 5)
        self.assertTrue(row["uses_default_level"])

    def test_suggested_quantity_reaches_twice_the_level(self):
        # Stock 4, level 10 -> target 20 -> buy 16, so the shop isn't back at
        # the threshold tomorrow.
        self._item("Restock", stock=4, reorder=10)
        self.assertEqual(Decimal(self._reorder()["items"][0]["suggested_qty"]), Decimal("16"))

    def test_suggested_quantity_is_never_below_one(self):
        # A level of 0 makes the target 0, so the arithmetic alone would suggest
        # buying nothing — useless on a buying list. Floor it at 1.
        self._item("Edge", stock=0, reorder=0)
        self.assertEqual(Decimal(self._reorder()["items"][0]["suggested_qty"]), Decimal("1"))

    def test_negative_stock_still_gets_a_sane_suggestion(self):
        item = self._item("Oversold", stock=2, reorder=5)
        self._sold(item, days_ago=1, qty="5")  # stock is now -3
        self.assertEqual(Decimal(self._reorder()["items"][0]["suggested_qty"]), Decimal("13"))

    def test_out_of_stock_items_come_first(self):
        self._item("Low", stock=3, reorder=10)
        self._item("Gone", stock=0, reorder=10)
        body = self._reorder()
        self.assertEqual(body["items"][0]["name"], "Gone")
        self.assertTrue(body["items"][0]["out_of_stock"])
        self.assertEqual(body["out_of_stock_count"], 1)

    def test_estimated_total_is_null_when_any_cost_is_missing(self):
        self._item("Costed", stock=1, reorder=10, cost="20.00")
        self._item("Uncosted", stock=1, reorder=10)
        self.assertIsNone(self._reorder()["estimated_total"])

    def test_estimated_total_is_given_when_every_cost_is_known(self):
        # Stock 1, level 10 -> buy 19 at Rs.20 = Rs.380.
        self._item("Costed", stock=1, reorder=10, cost="20.00")
        self.assertEqual(Decimal(self._reorder()["estimated_total"]), Decimal("380.00"))

    def test_a_cashier_can_read_the_buying_list_but_not_the_costs(self):
        staff = PlatformUser.objects.create_user(
            email="reorder-staff@example.com", password="secret", full_name="Staff"
        )
        ShopMembership.objects.create(
            user=staff,
            shop=self.shop,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
        )
        self._item("Costed", stock=1, reorder=10, cost="20.00")
        client = APIClient()
        client.force_authenticate(user=staff)
        body = client.get(f"/api/v1/shops/{self.shop.id}/reports/reorder-list/").json()
        self.assertEqual(len(body["items"]), 1)
        self.assertIsNone(body["items"][0]["cost_price"])
        self.assertIsNone(body["items"][0]["estimated_cost"])


class ReorderListOnOrderTests(TestCase):
    """The buying list must not demand stock that is already on a van.

    Purchase orders arrived after this report was written. Without accounting
    for them, a shop reorders the same carton twice and pays for it twice.
    """

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="buyer@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Buy Shop", slug="buy-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.supplier = Supplier.objects.create(shop=self.shop, name="Mills")
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def _item(self, name, *, stock, level):
        item = InventoryItem.objects.create(
            shop=self.shop, name=name, sell_price=Decimal("100.00"), reorder_level=level
        )
        if stock:
            InventoryStockLedger.objects.create(
                shop=self.shop,
                item=item,
                event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
                quantity_delta=Decimal(str(stock)),
                occurred_at=timezone.now(),
            )
        return item

    def _order(self, item, quantity, *, status=PurchaseOrder.Status.ORDERED, received="0"):
        order = PurchaseOrder.objects.create(
            shop=self.shop,
            supplier=self.supplier,
            reference="PO-TEST",
            status=status,
            ordered_at=timezone.now(),
        )
        PurchaseOrderLine.objects.create(
            order=order,
            inventory_item=item,
            name_snapshot=item.name,
            quantity_ordered=Decimal(str(quantity)),
            quantity_received=Decimal(str(received)),
            unit_cost=Decimal("50.00"),
        )
        return order

    def _fetch(self):
        return self.client.get(reverse("report-reorder-list", args=[self.shop.id]))

    def test_open_order_reduces_the_suggested_quantity(self):
        # Level 5, stock 2 -> target 10, so 8 without an order.
        item = self._item("Kurta", stock=2, level=5)
        self._order(item, 3)

        row = self._fetch().data["items"][0]

        self.assertEqual(Decimal(str(row["on_order"])), Decimal("3"))
        self.assertEqual(Decimal(str(row["suggested_qty"])), Decimal("5"))

    def test_item_fully_covered_drops_off_the_list(self):
        """It does not need buying; it needs chasing."""
        item = self._item("Saree", stock=2, level=5)
        self._order(item, 20)

        payload = self._fetch().data

        self.assertEqual(payload["items"], [])
        self.assertEqual(payload["covered_by_open_orders"], 1)

    def test_a_received_order_no_longer_counts(self):
        item = self._item("Shirt", stock=2, level=5)
        self._order(item, 8, status=PurchaseOrder.Status.RECEIVED, received="8")

        row = self._fetch().data["items"][0]

        self.assertEqual(Decimal(str(row["on_order"])), Decimal("0"))
        self.assertEqual(Decimal(str(row["suggested_qty"])), Decimal("8"))

    def test_a_cancelled_order_no_longer_counts(self):
        item = self._item("Shirt", stock=2, level=5)
        self._order(item, 8, status=PurchaseOrder.Status.CANCELLED)

        self.assertEqual(Decimal(str(self._fetch().data["items"][0]["on_order"])), Decimal("0"))

    def test_only_the_outstanding_part_of_a_partial_order_counts(self):
        """6 ordered, 4 already arrived -> 2 still coming, not 6."""
        item = self._item("Jeans", stock=2, level=5)
        self._order(
            item, 6, status=PurchaseOrder.Status.PARTIALLY_RECEIVED, received="4"
        )

        row = self._fetch().data["items"][0]

        self.assertEqual(Decimal(str(row["on_order"])), Decimal("2"))
        self.assertEqual(Decimal(str(row["suggested_qty"])), Decimal("6"))

    def test_another_shops_order_does_not_count(self):
        other = Shop.objects.create(name="Other", slug="other-buy")
        item = self._item("Kurta", stock=2, level=5)
        order = PurchaseOrder.objects.create(
            shop=other,
            reference="PO-OTHER",
            status=PurchaseOrder.Status.ORDERED,
            ordered_at=timezone.now(),
        )
        PurchaseOrderLine.objects.create(
            order=order,
            inventory_item=item,
            name_snapshot=item.name,
            quantity_ordered=Decimal("50"),
        )

        self.assertEqual(Decimal(str(self._fetch().data["items"][0]["on_order"])), Decimal("0"))

    def test_out_of_stock_item_on_order_still_leaves_the_list(self):
        """Zero stock is urgent, but a second order would still be a duplicate."""
        item = self._item("Rice", stock=0, level=5)
        self._order(item, 30)

        payload = self._fetch().data

        self.assertEqual(payload["items"], [])
        self.assertEqual(payload["out_of_stock_count"], 0)
        self.assertEqual(payload["covered_by_open_orders"], 1)

    def test_nothing_on_order_behaves_exactly_as_before(self):
        item = self._item("Towel", stock=2, level=5)

        row = self._fetch().data["items"][0]

        self.assertEqual(Decimal(str(row["on_order"])), Decimal("0"))
        self.assertEqual(Decimal(str(row["suggested_qty"])), Decimal("8"))
        self.assertEqual(self._fetch().data["covered_by_open_orders"], 0)


class ReorderListInTransitTests(TestCase):
    """Stock already moving between the owner's own shops must not be re-bought.

    Dispatch removes stock from the source at once but adds nothing at the
    destination until receipt. In between, the destination looks short of
    something sitting in a van.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="transit@example.com", password="secret", full_name="Owner"
        )
        self.main = Shop.objects.create(name="Main", slug="t-main")
        self.branch = Shop.objects.create(name="Branch", slug="t-branch")
        for shop in (self.main, self.branch):
            ShopMembership.objects.create(
                user=self.owner,
                shop=shop,
                role=ShopMembership.Role.OWNER,
                status=ShopMembership.Status.ACTIVE,
            )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    def _item(self, shop, name, *, stock, level=5, sku="", barcode=""):
        item = InventoryItem.objects.create(
            shop=shop, name=name, sku=sku, barcode=barcode,
            sell_price=Decimal("100.00"), reorder_level=level,
        )
        if stock:
            InventoryStockLedger.objects.create(
                shop=shop, item=item,
                event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
                quantity_delta=Decimal(str(stock)), occurred_at=timezone.now(),
            )
        return item

    def _dispatch(self, item, qty, *, to):
        return self.client.post(
            reverse("stock-transfer-list", args=[item.shop_id]),
            {"destination_shop_id": str(to.id),
             "lines": [{"item_id": str(item.id), "quantity": str(qty)}]},
            format="json",
        )

    def _reorder(self, shop):
        return self.client.get(reverse("report-reorder-list", args=[shop.id])).data

    def test_incoming_transfer_reduces_the_suggestion(self):
        source = self._item(self.main, "Kurta", stock=20, sku="K-1")
        # Branch: level 5, stock 2 -> target 10, so 8 without anything incoming.
        self._item(self.branch, "Kurta", stock=2, level=5, sku="K-1")

        self._dispatch(source, 3, to=self.branch)
        row = self._reorder(self.branch)["items"][0]

        self.assertEqual(Decimal(str(row["in_transit"])), Decimal("3"))
        self.assertEqual(Decimal(str(row["suggested_qty"])), Decimal("5"))

    def test_fully_covered_by_a_transfer_leaves_the_list(self):
        source = self._item(self.main, "Saree", stock=50, sku="S-1")
        self._item(self.branch, "Saree", stock=2, level=5, sku="S-1")

        self._dispatch(source, 20, to=self.branch)
        payload = self._reorder(self.branch)

        self.assertEqual(payload["items"], [])
        self.assertEqual(payload["covered_by_open_orders"], 1)

    def test_the_sending_shop_is_not_credited(self):
        """Stock leaving must not look like stock arriving."""
        source = self._item(self.main, "Shirt", stock=6, level=5, sku="SH-1")
        self._item(self.branch, "Shirt", stock=50, level=5, sku="SH-1")

        self._dispatch(source, 4, to=self.branch)
        rows = self._reorder(self.main)["items"]

        self.assertEqual(len(rows), 1)
        self.assertEqual(Decimal(str(rows[0]["in_transit"])), Decimal("0"))
        # 6 dispatched down to 2; target 10 -> buy 8.
        self.assertEqual(Decimal(str(rows[0]["suggested_qty"])), Decimal("8"))

    def test_a_received_transfer_stops_counting(self):
        source = self._item(self.main, "Jeans", stock=20, sku="J-1")
        self._item(self.branch, "Jeans", stock=2, level=5, sku="J-1")
        transfer_id = self._dispatch(source, 3, to=self.branch).data["id"]

        self.client.post(
            reverse("stock-transfer-receive", args=[self.branch.id, transfer_id])
        )
        row = self._reorder(self.branch)["items"][0]

        # The stock is real now, so it counts as stock rather than as incoming.
        self.assertEqual(Decimal(str(row["in_transit"])), Decimal("0"))
        self.assertEqual(Decimal(str(row["stock"])), Decimal("5"))

    def test_a_cancelled_transfer_stops_counting(self):
        source = self._item(self.main, "Towel", stock=20, sku="T-1")
        self._item(self.branch, "Towel", stock=2, level=5, sku="T-1")
        transfer_id = self._dispatch(source, 3, to=self.branch).data["id"]

        self.client.post(
            reverse("stock-transfer-cancel", args=[self.main.id, transfer_id])
        )

        self.assertEqual(
            Decimal(str(self._reorder(self.branch)["items"][0]["in_transit"])),
            Decimal("0"),
        )

    def test_matching_uses_barcode_not_just_name(self):
        """Same rule as receiving, or the credit lands on the wrong local item."""
        source = self._item(self.main, "Cap", stock=20, barcode="890999")
        # Local row has a different name but the same barcode: it is the item.
        local = self._item(
            self.branch, "Cap Blue", stock=1, level=5, barcode="890999"
        )
        self._item(self.branch, "Cap", stock=1, level=5)

        # 4, not 9: at 9 the item would be fully covered (1 in stock + 9
        # incoming reaches the target of 10) and correctly drop off the list,
        # which would prove nothing about which row got the credit.
        self._dispatch(source, 4, to=self.branch)
        rows = {r["id"]: r for r in self._reorder(self.branch)["items"]}

        self.assertEqual(
            Decimal(str(rows[str(local.id)]["in_transit"])), Decimal("4")
        )
        # And the same-named row must NOT have been credited.
        same_name = [r for r in rows.values() if r["name"] == "Cap"][0]
        self.assertEqual(Decimal(str(same_name["in_transit"])), Decimal("0"))

    def test_an_item_the_branch_never_stocked_is_ignored(self):
        """Nothing to reorder, so nothing to correct — and no crash."""
        source = self._item(self.main, "Brand New", stock=20, sku="BN-1")
        self._item(self.branch, "Something Else", stock=2, level=5, sku="SE-1")

        self._dispatch(source, 5, to=self.branch)
        payload = self._reorder(self.branch)

        self.assertEqual(len(payload["items"]), 1)
        self.assertEqual(payload["items"][0]["name"], "Something Else")

    def test_purchase_orders_and_transfers_add_up_together(self):
        source = self._item(self.main, "Rice", stock=50, sku="R-1")
        local = self._item(self.branch, "Rice", stock=0, level=5, sku="R-1")
        supplier = Supplier.objects.create(shop=self.branch, name="Mills")
        order = PurchaseOrder.objects.create(
            shop=self.branch, supplier=supplier, reference="PO-X",
            status=PurchaseOrder.Status.ORDERED, ordered_at=timezone.now(),
        )
        PurchaseOrderLine.objects.create(
            order=order, inventory_item=local, name_snapshot=local.name,
            quantity_ordered=Decimal("4"), unit_cost=Decimal("10"),
        )

        self._dispatch(source, 3, to=self.branch)
        row = self._reorder(self.branch)["items"][0]

        self.assertEqual(Decimal(str(row["on_order"])), Decimal("4"))
        self.assertEqual(Decimal(str(row["in_transit"])), Decimal("3"))
        self.assertEqual(Decimal(str(row["incoming_total"])), Decimal("7"))
        # target 10 - stock 0 - incoming 7 = 3
        self.assertEqual(Decimal(str(row["suggested_qty"])), Decimal("3"))

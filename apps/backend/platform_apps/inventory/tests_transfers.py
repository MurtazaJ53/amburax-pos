from __future__ import annotations

from decimal import Decimal
from unittest.mock import patch

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import (
    InventoryItem,
    InventoryItemPrivate,
    InventoryStockLedger,
    StockTransfer,
)
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


def _stock(item: InventoryItem) -> Decimal:
    total = Decimal("0")
    for entry in InventoryStockLedger.objects.filter(item=item):
        total += entry.quantity_delta
    return total


class StockTransferTests(TestCase):
    """Moving stock between shops.

    The invariant every test here defends: across both shops, a transfer moves
    quantity but never creates or destroys it. Getting that wrong silently is
    the reason the feature exists — before it, the move was two unrelated
    manual adjustments.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="owner@example.com", password="secret", full_name="Owner"
        )
        self.main = Shop.objects.create(name="Main Shop", slug="main-shop")
        self.branch = Shop.objects.create(name="Branch Shop", slug="branch-shop")
        for shop in (self.main, self.branch):
            ShopMembership.objects.create(
                user=self.owner,
                shop=shop,
                role=ShopMembership.Role.OWNER,
                status=ShopMembership.Status.ACTIVE,
            )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    # -- helpers ---------------------------------------------------------

    def _item(self, shop, name, *, stock="0", sku="", barcode="", cost=None, size=""):
        item = InventoryItem.objects.create(
            shop=shop,
            name=name,
            sku=sku,
            barcode=barcode,
            size=size,
            sell_price=Decimal("100.00"),
        )
        if Decimal(stock) != Decimal("0"):
            InventoryStockLedger.objects.create(
                shop=shop,
                item=item,
                event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
                quantity_delta=Decimal(stock),
                occurred_at=timezone.now(),
            )
        if cost is not None:
            InventoryItemPrivate.objects.create(item=item, cost_price=Decimal(cost))
        return item

    def _dispatch(self, lines, *, source=None, destination=None, **extra):
        source = source or self.main
        destination = destination or self.branch
        return self.client.post(
            reverse("stock-transfer-list", args=[source.id]),
            {
                "destination_shop_id": str(destination.id),
                "lines": lines,
                **extra,
            },
            format="json",
        )

    # -- the happy path --------------------------------------------------

    def test_dispatch_removes_stock_from_source_only(self):
        item = self._item(self.main, "Kurta", stock="10")

        response = self._dispatch([{"item_id": str(item.id), "quantity": "4"}])

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["status"], StockTransfer.Status.IN_TRANSIT)
        self.assertEqual(_stock(item), Decimal("6"))
        # Nothing lands at the destination until someone confirms it arrived.
        self.assertEqual(InventoryItem.objects.filter(shop=self.branch).count(), 0)

    def test_receive_adds_the_same_quantity_at_the_destination(self):
        item = self._item(self.main, "Kurta", stock="10")
        transfer_id = self._dispatch(
            [{"item_id": str(item.id), "quantity": "4"}]
        ).data["id"]

        response = self.client.post(
            reverse("stock-transfer-receive", args=[self.branch.id, transfer_id])
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["status"], StockTransfer.Status.RECEIVED)
        destination_item = InventoryItem.objects.get(shop=self.branch)
        self.assertEqual(_stock(item), Decimal("6"))
        self.assertEqual(_stock(destination_item), Decimal("4"))

    def test_decimal_quantities_survive_the_round_trip(self):
        """Kirana shops sell by weight, so 2.5 kg must not become 2 or 3."""
        item = self._item(self.main, "Rice", stock="10.000")
        transfer_id = self._dispatch(
            [{"item_id": str(item.id), "quantity": "2.500"}]
        ).data["id"]
        self.client.post(
            reverse("stock-transfer-receive", args=[self.branch.id, transfer_id])
        )

        self.assertEqual(_stock(item), Decimal("7.500"))
        self.assertEqual(_stock(InventoryItem.objects.get(shop=self.branch)), Decimal("2.500"))

    # -- matching the destination item -----------------------------------

    def test_existing_destination_item_is_reused_not_duplicated(self):
        source = self._item(self.main, "Kurta", stock="10", sku="KUR-1")
        existing = self._item(self.branch, "Kurta", stock="3", sku="KUR-1")

        transfer_id = self._dispatch(
            [{"item_id": str(source.id), "quantity": "4"}]
        ).data["id"]
        self.client.post(
            reverse("stock-transfer-receive", args=[self.branch.id, transfer_id])
        )

        self.assertEqual(InventoryItem.objects.filter(shop=self.branch).count(), 1)
        self.assertEqual(_stock(existing), Decimal("7"))

    def test_barcode_wins_over_a_name_that_happens_to_match(self):
        """Two different products can share a name; a barcode is the product."""
        source = self._item(self.main, "Shirt", stock="5", barcode="890123")
        by_barcode = self._item(self.branch, "Shirt Blue", stock="0", barcode="890123")
        self._item(self.branch, "Shirt", stock="0")

        transfer_id = self._dispatch(
            [{"item_id": str(source.id), "quantity": "2"}]
        ).data["id"]
        self.client.post(
            reverse("stock-transfer-receive", args=[self.branch.id, transfer_id])
        )

        self.assertEqual(_stock(by_barcode), Decimal("2"))

    def test_created_destination_item_carries_price_but_not_stock(self):
        source = self._item(self.main, "Saree", stock="6", sku="SAR-9", size="M")

        transfer_id = self._dispatch(
            [{"item_id": str(source.id), "quantity": "6"}]
        ).data["id"]
        self.client.post(
            reverse("stock-transfer-receive", args=[self.branch.id, transfer_id])
        )

        created = InventoryItem.objects.get(shop=self.branch)
        self.assertEqual(created.sku, "SAR-9")
        self.assertEqual(created.size, "M")
        self.assertEqual(created.sell_price, Decimal("100.00"))
        # Exactly what was sent — not the source shop's opening balance too.
        self.assertEqual(_stock(created), Decimal("6"))

    def test_cost_price_travels_with_the_goods(self):
        source = self._item(self.main, "Jeans", stock="5", cost="400.00")

        transfer_id = self._dispatch(
            [{"item_id": str(source.id), "quantity": "2"}]
        ).data["id"]
        self.client.post(
            reverse("stock-transfer-receive", args=[self.branch.id, transfer_id])
        )

        entry = InventoryStockLedger.objects.get(
            shop=self.branch, event_type=InventoryStockLedger.EventType.TRANSFER_IN
        )
        self.assertEqual(entry.unit_cost, Decimal("400.00"))

    def test_zero_cost_is_treated_as_unrecorded_not_free(self):
        """A stored 0.00 means nobody entered a cost — the same convention the
        dead-stock and reorder reports use."""
        source = self._item(self.main, "Gift", stock="5", cost="0.00")

        response = self._dispatch([{"item_id": str(source.id), "quantity": "1"}])

        self.assertIsNone(response.data["lines"][0]["unit_cost"])

    # -- refusing to corrupt stock ---------------------------------------

    def test_cannot_send_more_than_is_on_hand(self):
        item = self._item(self.main, "Kurta", stock="3")

        response = self._dispatch([{"item_id": str(item.id), "quantity": "5"}])

        self.assertEqual(response.status_code, 400)
        self.assertEqual(_stock(item), Decimal("3"))
        self.assertEqual(StockTransfer.objects.count(), 0)

    def test_one_bad_line_rolls_back_the_whole_transfer(self):
        """Otherwise the first item leaves the shop and the transfer never
        exists to bring it back."""
        good = self._item(self.main, "Kurta", stock="10")
        bad = self._item(self.main, "Saree", stock="1")

        response = self._dispatch(
            [
                {"item_id": str(good.id), "quantity": "2"},
                {"item_id": str(bad.id), "quantity": "9"},
            ]
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(_stock(good), Decimal("10"))
        self.assertEqual(StockTransfer.objects.count(), 0)

    def test_same_item_twice_is_rejected(self):
        """Each line would pass the stock check alone while together they
        exceed what is on the shelf."""
        item = self._item(self.main, "Kurta", stock="5")

        response = self._dispatch(
            [
                {"item_id": str(item.id), "quantity": "3"},
                {"item_id": str(item.id), "quantity": "3"},
            ]
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(_stock(item), Decimal("5"))

    def test_zero_and_negative_quantities_are_rejected(self):
        item = self._item(self.main, "Kurta", stock="5")

        for quantity in ("0", "-2"):
            with self.subTest(quantity=quantity):
                response = self._dispatch(
                    [{"item_id": str(item.id), "quantity": quantity}]
                )
                self.assertEqual(response.status_code, 400)
        self.assertEqual(_stock(item), Decimal("5"))

    def test_cannot_send_a_shop_its_own_stock(self):
        item = self._item(self.main, "Kurta", stock="5")

        response = self._dispatch(
            [{"item_id": str(item.id), "quantity": "1"}], destination=self.main
        )

        self.assertEqual(response.status_code, 400)

    def test_cannot_send_an_item_belonging_to_another_shop(self):
        stranger = self._item(self.branch, "Kurta", stock="5")

        response = self._dispatch([{"item_id": str(stranger.id), "quantity": "1"}])

        self.assertEqual(response.status_code, 404)

    # -- receiving twice, and cancelling ---------------------------------

    def test_receiving_twice_does_not_post_the_stock_twice(self):
        item = self._item(self.main, "Kurta", stock="10")
        transfer_id = self._dispatch(
            [{"item_id": str(item.id), "quantity": "4"}]
        ).data["id"]
        url = reverse("stock-transfer-receive", args=[self.branch.id, transfer_id])

        self.client.post(url)
        second = self.client.post(url)

        self.assertEqual(second.status_code, 400)
        self.assertEqual(_stock(InventoryItem.objects.get(shop=self.branch)), Decimal("4"))

    def test_cancel_returns_the_stock_to_the_source(self):
        item = self._item(self.main, "Kurta", stock="10")
        transfer_id = self._dispatch(
            [{"item_id": str(item.id), "quantity": "4"}]
        ).data["id"]

        response = self.client.post(
            reverse("stock-transfer-cancel", args=[self.main.id, transfer_id])
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(_stock(item), Decimal("10"))
        # Append-only: the history still shows it left and came back.
        self.assertEqual(
            InventoryStockLedger.objects.filter(item=item).count(), 3
        )

    def test_cannot_cancel_after_receiving(self):
        item = self._item(self.main, "Kurta", stock="10")
        transfer_id = self._dispatch(
            [{"item_id": str(item.id), "quantity": "4"}]
        ).data["id"]
        self.client.post(
            reverse("stock-transfer-receive", args=[self.branch.id, transfer_id])
        )

        response = self.client.post(
            reverse("stock-transfer-cancel", args=[self.main.id, transfer_id])
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(_stock(item), Decimal("6"))

    # -- permissions -----------------------------------------------------

    def test_cannot_send_stock_into_a_shop_you_do_not_belong_to(self):
        outsider_shop = Shop.objects.create(name="Someone Else", slug="someone-else")
        item = self._item(self.main, "Kurta", stock="5")

        response = self._dispatch(
            [{"item_id": str(item.id), "quantity": "1"}], destination=outsider_shop
        )

        self.assertEqual(response.status_code, 403)
        self.assertEqual(_stock(item), Decimal("5"))

    def test_cashier_cannot_move_stock_between_shops(self):
        cashier = PlatformUser.objects.create_user(
            email="cashier@example.com", password="secret", full_name="Cashier"
        )
        for shop in (self.main, self.branch):
            ShopMembership.objects.create(
                user=cashier,
                shop=shop,
                role=ShopMembership.Role.CASHIER,
                status=ShopMembership.Status.ACTIVE,
            )
        item = self._item(self.main, "Kurta", stock="5")
        self.client.force_authenticate(user=cashier)

        response = self._dispatch([{"item_id": str(item.id), "quantity": "1"}])

        self.assertEqual(response.status_code, 403)

    def test_the_wrong_shop_cannot_receive_a_transfer_addressed_elsewhere(self):
        third = Shop.objects.create(name="Third Shop", slug="third-shop")
        ShopMembership.objects.create(
            user=self.owner,
            shop=third,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        item = self._item(self.main, "Kurta", stock="5")
        transfer_id = self._dispatch(
            [{"item_id": str(item.id), "quantity": "2"}]
        ).data["id"]

        response = self.client.post(
            reverse("stock-transfer-receive", args=[third.id, transfer_id])
        )

        self.assertEqual(response.status_code, 403)
        self.assertEqual(InventoryItem.objects.filter(shop=third).count(), 0)

    def test_signed_out_requests_are_rejected(self):
        item = self._item(self.main, "Kurta", stock="5")
        self.client.force_authenticate(user=None)

        response = self._dispatch([{"item_id": str(item.id), "quantity": "1"}])

        self.assertEqual(response.status_code, 401)

    # -- listing ---------------------------------------------------------

    def test_list_shows_both_directions_with_pending_counts(self):
        outbound = self._item(self.main, "Kurta", stock="10")
        inbound = self._item(self.branch, "Saree", stock="10")
        self._dispatch([{"item_id": str(outbound.id), "quantity": "1"}])
        self._dispatch(
            [{"item_id": str(inbound.id), "quantity": "1"}],
            source=self.branch,
            destination=self.main,
        )

        response = self.client.get(reverse("stock-transfer-list", args=[self.main.id]))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["transfers"]), 2)
        self.assertEqual(response.data["incoming_in_transit"], 1)
        self.assertEqual(response.data["outgoing_in_transit"], 1)

    def test_list_does_not_leak_another_owners_transfers(self):
        other_user = PlatformUser.objects.create_user(
            email="other@example.com", password="secret", full_name="Other"
        )
        other_a = Shop.objects.create(name="Other A", slug="other-a")
        other_b = Shop.objects.create(name="Other B", slug="other-b")
        for shop in (other_a, other_b):
            ShopMembership.objects.create(
                user=other_user,
                shop=shop,
                role=ShopMembership.Role.OWNER,
                status=ShopMembership.Status.ACTIVE,
            )
        item = InventoryItem.objects.create(
            shop=other_a, name="Theirs", sell_price=Decimal("10.00")
        )
        InventoryStockLedger.objects.create(
            shop=other_a,
            item=item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("5"),
            occurred_at=timezone.now(),
        )
        self.client.force_authenticate(user=other_user)
        self._dispatch(
            [{"item_id": str(item.id), "quantity": "1"}],
            source=other_a,
            destination=other_b,
        )

        self.client.force_authenticate(user=self.owner)
        response = self.client.get(reverse("stock-transfer-list", args=[self.main.id]))

        self.assertEqual(response.data["transfers"], [])


class TransfersRefreshTheDashboard(StockTransferTests):
    """The homepage after stock moves between shops.

    The dashboard is a stored snapshot. All three steps here move stock - out
    of one shop, into another, or back on a cancel - and a step that does not
    rebuild it leaves that shop's homepage stating a figure the stock screen
    already disagrees with.
    """

    REFRESH = "platform_apps.inventory.transfer_views.refresh_projection_after_write"

    def test_dispatch_rebuilds_the_sending_shop(self):
        item = self._item(self.main, "Kurta", stock="10")
        with patch(self.REFRESH) as refresh:
            response = self._dispatch([{"item_id": str(item.id), "quantity": "4"}])
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(refresh.called, "dispatch left the dashboard stale")

    def test_receiving_rebuilds_the_receiving_shop(self):
        item = self._item(self.main, "Kurta", stock="10")
        transfer_id = self._dispatch(
            [{"item_id": str(item.id), "quantity": "4"}]
        ).data["id"]

        with patch(self.REFRESH) as refresh:
            response = self.client.post(
                reverse("stock-transfer-receive", args=[self.branch.id, transfer_id])
            )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(refresh.called, "receiving left the dashboard stale")

    def test_cancelling_rebuilds_the_shop_the_stock_returns_to(self):
        """A cancel puts the goods back, which is a stock movement like any other."""
        item = self._item(self.main, "Kurta", stock="10")
        transfer_id = self._dispatch(
            [{"item_id": str(item.id), "quantity": "4"}]
        ).data["id"]

        with patch(self.REFRESH) as refresh:
            response = self.client.post(
                reverse("stock-transfer-cancel", args=[self.main.id, transfer_id])
            )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(refresh.called, "cancelling left the dashboard stale")

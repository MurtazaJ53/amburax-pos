from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import (
    InventoryItem,
    InventoryItemPrivate,
    InventoryStockLedger,
    Stocktake,
)
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


def stock_of(item: InventoryItem) -> Decimal:
    total = Decimal("0")
    for entry in InventoryStockLedger.objects.filter(item=item):
        total += entry.quantity_delta
    return total


class StocktakeTests(TestCase):
    """Counting the shelves and reconciling against the books.

    The invariant that matters most: applying a count posts the DIFFERENCE
    measured when the item was counted, never the counted figure itself.
    Counting a shop takes hours and the shop keeps trading, so writing the
    counted number over the current balance would destroy every sale made in
    between.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="stocktake@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Count Shop", slug="count-shop")
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    # -- helpers ---------------------------------------------------------

    def _item(self, name, *, stock="10", cost=None):
        item = InventoryItem.objects.create(
            shop=self.shop, name=name, sell_price=Decimal("100.00")
        )
        if Decimal(stock) != Decimal("0"):
            InventoryStockLedger.objects.create(
                shop=self.shop, item=item,
                event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
                quantity_delta=Decimal(stock), occurred_at=timezone.now(),
            )
        if cost is not None:
            InventoryItemPrivate.objects.create(item=item, cost_price=Decimal(cost))
        return item

    def _sell(self, item, qty):
        InventoryStockLedger.objects.create(
            shop=self.shop, item=item,
            event_type=InventoryStockLedger.EventType.SALE,
            quantity_delta=-Decimal(qty), occurred_at=timezone.now(),
        )

    def _start(self, **body):
        return self.client.post(
            reverse("stocktake-list", args=[self.shop.id]), body, format="json"
        )

    def _count(self, stocktake_id, item, qty):
        return self.client.post(
            reverse("stocktake-count", args=[self.shop.id, stocktake_id]),
            {"item_id": str(item.id), "counted_quantity": str(qty)},
            format="json",
        )

    def _apply(self, stocktake_id):
        return self.client.post(
            reverse("stocktake-apply", args=[self.shop.id, stocktake_id])
        )

    # -- the correctness case --------------------------------------------

    def test_applying_posts_the_difference_not_the_counted_figure(self):
        """The whole reason this feature is not a simple 'set stock to N'.

        Books say 10, counter finds 8, then three more sell before applying.
        Setting stock to 8 would undo those three sales. The variance of -2
        against a ledger now reading 7 gives 5 — what is actually on the shelf.
        """
        item = self._item("Rice", stock="10")
        started = self._start().data
        self._count(started["id"], item, "8")

        # The shop keeps trading while the count is under way.
        self._sell(item, "3")
        self.assertEqual(stock_of(item), Decimal("7"))

        self._apply(started["id"])

        self.assertEqual(stock_of(item), Decimal("5"))

    def test_a_matching_count_posts_no_adjustment(self):
        """Zero-variance rows would be noise in a ledger people read."""
        item = self._item("Sugar", stock="10")
        started = self._start().data
        self._count(started["id"], item, "10")

        before = InventoryStockLedger.objects.filter(item=item).count()
        response = self._apply(started["id"])

        self.assertEqual(response.data["adjustments_posted"], 0)
        self.assertEqual(InventoryStockLedger.objects.filter(item=item).count(), before)
        self.assertEqual(stock_of(item), Decimal("10"))

    def test_missing_stock_reduces_and_extra_increases(self):
        short = self._item("Short", stock="10")
        over = self._item("Over", stock="10")
        started = self._start().data
        self._count(started["id"], short, "7")
        self._count(started["id"], over, "12")

        self._apply(started["id"])

        self.assertEqual(stock_of(short), Decimal("7"))
        self.assertEqual(stock_of(over), Decimal("12"))

    def test_counting_zero_is_a_real_count(self):
        """"I looked and there are none" is the most useful count there is."""
        item = self._item("Gone", stock="6")
        started = self._start().data

        response = self._count(started["id"], item, "0")
        self.assertEqual(response.status_code, 201)

        self._apply(started["id"])
        self.assertEqual(stock_of(item), Decimal("0"))

    def test_a_negative_count_is_rejected(self):
        item = self._item("Rice", stock="10")
        started = self._start().data

        response = self._count(started["id"], item, "-1")

        self.assertEqual(response.status_code, 400)

    # -- recounting -------------------------------------------------------

    def test_recounting_replaces_rather_than_adds(self):
        """A shelf has one true quantity; a recount is a correction."""
        item = self._item("Rice", stock="10")
        started = self._start().data
        self._count(started["id"], item, "6")
        self._count(started["id"], item, "8")

        body = self.client.get(
            reverse("stocktake-detail", args=[self.shop.id, started["id"]])
        ).data

        self.assertEqual(body["counted_lines"], 1)
        self.assertEqual(body["lines"][0]["counted"], "8.000")

        self._apply(started["id"])
        self.assertEqual(stock_of(item), Decimal("8"))

    # -- applying twice, and locking ---------------------------------------

    def test_applying_twice_does_not_correct_twice(self):
        item = self._item("Rice", stock="10")
        started = self._start().data
        self._count(started["id"], item, "8")

        self._apply(started["id"])
        second = self._apply(started["id"])

        self.assertEqual(second.status_code, 400)
        self.assertEqual(stock_of(item), Decimal("8"))

    def test_cannot_count_into_an_applied_stocktake(self):
        item = self._item("Rice", stock="10")
        started = self._start().data
        self._count(started["id"], item, "8")
        self._apply(started["id"])

        response = self._count(started["id"], item, "5")

        self.assertEqual(response.status_code, 400)

    def test_only_one_count_can_be_open_at_a_time(self):
        """Two counts of the same shelves measure against the same books, and
        applying both would double every correction."""
        self._start()

        response = self._start()

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            Stocktake.objects.filter(status=Stocktake.Status.OPEN).count(), 1
        )

    def test_cancelling_frees_the_shop_for_a_new_count(self):
        first = self._start().data
        self.client.post(
            reverse("stocktake-cancel", args=[self.shop.id, first["id"]])
        )

        self.assertEqual(self._start().status_code, 201)

    def test_cancelling_touches_no_stock(self):
        item = self._item("Rice", stock="10")
        started = self._start().data
        self._count(started["id"], item, "3")

        self.client.post(
            reverse("stocktake-cancel", args=[self.shop.id, started["id"]])
        )

        self.assertEqual(stock_of(item), Decimal("10"))

    def test_cannot_cancel_after_applying(self):
        item = self._item("Rice", stock="10")
        started = self._start().data
        self._count(started["id"], item, "8")
        self._apply(started["id"])

        response = self.client.post(
            reverse("stocktake-cancel", args=[self.shop.id, started["id"]])
        )

        self.assertEqual(response.status_code, 400)

    def test_applying_an_empty_count_is_refused(self):
        started = self._start().data

        self.assertEqual(self._apply(started["id"]).status_code, 400)

    # -- the variance report -----------------------------------------------

    def test_the_report_separates_missing_extra_and_matched(self):
        self._count_setup = None
        short = self._item("Short", stock="10")
        over = self._item("Over", stock="10")
        same = self._item("Same", stock="10")
        started = self._start().data
        self._count(started["id"], short, "7")
        self._count(started["id"], over, "12")
        self._count(started["id"], same, "10")

        body = self._apply(started["id"]).data

        self.assertEqual(body["missing_count"], 1)
        self.assertEqual(body["extra_count"], 1)
        self.assertEqual(body["matched_count"], 1)
        self.assertEqual(body["adjustments_posted"], 2)

    def test_shrinkage_is_valued_at_cost(self):
        item = self._item("Rice", stock="10", cost="40.00")
        started = self._start().data
        self._count(started["id"], item, "7")

        body = self._apply(started["id"]).data

        # Three missing at 40 = -120.
        self.assertEqual(body["variance_value"], "-120.00")

    def test_shrinkage_is_unknown_when_any_cost_is_missing(self):
        """A partial total understates the loss, and that is the number
        somebody acts on."""
        costed = self._item("Costed", stock="10", cost="40.00")
        uncosted = self._item("Uncosted", stock="10")
        started = self._start().data
        self._count(started["id"], costed, "8")
        self._count(started["id"], uncosted, "8")

        body = self._apply(started["id"]).data

        self.assertIsNone(body["variance_value"])

    # -- access -------------------------------------------------------------

    def test_staff_can_count_but_not_apply(self):
        """Counting is floor work; applying rewrites stock and reveals
        shrinkage."""
        staff = PlatformUser.objects.create_user(
            email="counter@example.com", password="secret", full_name="Counter"
        )
        ShopMembership.objects.create(
            user=staff, shop=self.shop,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
        )
        item = self._item("Rice", stock="10")
        started = self._start().data
        self.client.force_authenticate(user=staff)

        self.assertEqual(self._count(started["id"], item, "8").status_code, 201)
        self.assertEqual(self._apply(started["id"]).status_code, 403)

    def test_another_shop_cannot_reach_this_stocktake(self):
        started = self._start().data
        stranger = PlatformUser.objects.create_user(
            email="nope-count@example.com", password="secret", full_name="No"
        )
        self.client.force_authenticate(user=stranger)

        response = self.client.get(
            reverse("stocktake-detail", args=[self.shop.id, started["id"]])
        )

        self.assertEqual(response.status_code, 403)

    def test_cannot_count_an_item_from_another_shop(self):
        other = Shop.objects.create(name="Other", slug="other-count")
        stranger_item = InventoryItem.objects.create(
            shop=other, name="Theirs", sell_price=Decimal("10.00")
        )
        started = self._start().data

        response = self._count(started["id"], stranger_item, "5")

        self.assertEqual(response.status_code, 404)

    def test_signed_out_requests_are_rejected(self):
        self.client.force_authenticate(user=None)

        self.assertEqual(self._start().status_code, 401)

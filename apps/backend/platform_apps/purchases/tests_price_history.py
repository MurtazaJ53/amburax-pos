"""Price history has to be right or it is worse than absent.

A shopkeeper who acts on "supplier X put this up 20%" and is wrong once will
never open the screen again, so every test here pins a case where the obvious
implementation reports a confident lie.
"""
from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem
from platform_apps.purchases.models import Purchase, PurchaseItem, Supplier
from platform_apps.purchases.price_history_views import (
    build_price_points,
    group_by_item_supplier,
    percent_change,
    summarise_series,
)
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


# --------------------------------------------------------------------------- #
# The maths, in isolation
# --------------------------------------------------------------------------- #
def test_percent_change_reports_a_rise_and_a_fall():
    assert percent_change(Decimal("100"), Decimal("120")) == Decimal("20.0")
    assert percent_change(Decimal("100"), Decimal("90")) == Decimal("-10.0")


def test_percent_change_refuses_a_zero_baseline():
    # The item was free and now is not. That is a fact about the data, not a
    # price rise, and dividing by it would report an infinity someone acts on.
    assert percent_change(Decimal("0"), Decimal("50")) is None
    assert percent_change(None, Decimal("50")) is None


def _row(purchase_id, day, cost, quantity="1", invoice="INV-1"):
    return {
        "purchase_id": purchase_id,
        "purchase_date": date(2026, 1, day),
        "invoice_number": invoice,
        "unit_cost": Decimal(cost),
        "quantity": Decimal(quantity),
    }


def test_price_points_are_oldest_first():
    points = build_price_points([_row("b", 5, "120"), _row("a", 1, "100")])
    assert [p["unit_cost"] for p in points] == ["100.00", "120.00"]


def test_zero_cost_lines_are_not_prices():
    # A free sample booked at zero would otherwise become the baseline and make
    # the next real purchase look like an infinite increase.
    points = build_price_points([_row("a", 1, "0"), _row("b", 5, "100")])
    assert [p["unit_cost"] for p in points] == ["100.00"]


def test_one_invoice_listing_an_item_twice_is_one_price_point():
    # Two cartons booked as two lines on one bill are one purchase at one
    # moment. Counting them as two observations would make a single invoice
    # look like a price that held steady over time.
    points = build_price_points(
        [
            _row("a", 1, "100", quantity="2"),
            _row("a", 1, "140", quantity="2"),
        ]
    )
    assert len(points) == 1
    assert points[0]["unit_cost"] == "120.00"


def test_a_single_purchase_has_no_trend():
    # One purchase is a price, not a trend. Reporting a change against a
    # baseline that does not exist is how a report loses its reader.
    summary = summarise_series(build_price_points([_row("a", 1, "100")]))
    assert summary["purchases"] == 1
    assert summary["previous_cost"] is None
    assert summary["change_percent"] is None


def test_summary_compares_the_latest_two_prices():
    points = build_price_points(
        [_row("a", 1, "100"), _row("b", 5, "110"), _row("c", 9, "121")]
    )
    summary = summarise_series(points)
    assert summary["purchases"] == 3
    assert summary["latest_cost"] == "121.00"
    assert summary["previous_cost"] == "110.00"
    assert summary["change_percent"] == "10.0"


def test_grouping_keeps_suppliers_apart():
    # The same shirt at 100 from one supplier and 120 from another is not a
    # price rise, it is two suppliers. This is the single most likely way for
    # the feature to produce a confident lie.
    rows = [
        {"item_id": "i1", "supplier_id": "s1"},
        {"item_id": "i1", "supplier_id": "s2"},
        {"item_id": "i1", "supplier_id": "s1"},
    ]
    grouped = group_by_item_supplier(rows)
    assert len(grouped) == 2
    assert len(grouped[("i1", "s1")]) == 2


def test_grouping_drops_lines_with_no_supplier():
    # A purchase entered without a supplier cannot be attributed to one, and
    # guessing would put the rise on whoever happens to be nearest.
    grouped = group_by_item_supplier(
        [{"item_id": "i1", "supplier_id": None}, {"item_id": None, "supplier_id": "s1"}]
    )
    assert grouped == {}



# --------------------------------------------------------------------------- #
# End to end
# --------------------------------------------------------------------------- #
class SupplierPriceHistoryApiTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="owner@example.com", password="secret", full_name="Owner"
        )
        # Pro unlocks purchase_workflow, which this surface sits behind.
        self.shop = Shop.objects.create(
            name="Demo Shop", slug="demo-shop", settings_json={"plan_tier": "pro"}
        )
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.supplier = Supplier.objects.create(shop=self.shop, name="Ratna Textiles")
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Cotton Shirt", sku="SH-01"
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    @property
    def url(self):
        return f"/api/v1/shops/{self.shop.id}/purchases/price-history/"

    def _purchase(self, supplier, item, cost, day, quantity="1"):
        purchase = Purchase.objects.create(
            shop=self.shop,
            supplier=supplier,
            supplier_name_snapshot=supplier.name,
            invoice_number=f"INV-{day}",
            purchase_date=date(2026, 1, 1) + timedelta(days=day),
            occurred_at=timezone.now(),
            status=Purchase.Status.COMPLETED,
            total_amount=Decimal(cost),
        )
        PurchaseItem.objects.create(
            purchase=purchase,
            inventory_item=item,
            name_snapshot=item.name,
            quantity=Decimal(quantity),
            unit_cost=Decimal(cost),
            line_total=Decimal(cost) * Decimal(quantity),
        )
        return purchase

    def test_surfaces_a_material_rise(self):
        self._purchase(self.supplier, self.item, "100.00", 1)
        self._purchase(self.supplier, self.item, "130.00", 30)

        response = self.client.get(self.url)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["tracked_pairs"], 1)
        movements = response.data["movements"]
        self.assertEqual(len(movements), 1)
        self.assertEqual(movements[0]["supplier_name"], "Ratna Textiles")
        self.assertEqual(movements[0]["change_percent"], "30.0")

    def test_a_small_movement_is_not_reported(self):
        # Rounding on a cheap item reads as a trend. Below the threshold the
        # list fills with noise and the real rises get lost in it.
        self._purchase(self.supplier, self.item, "100.00", 1)
        self._purchase(self.supplier, self.item, "101.00", 30)

        response = self.client.get(self.url)

        self.assertEqual(response.data["tracked_pairs"], 1)
        self.assertEqual(response.data["movements"], [])

    def test_two_suppliers_for_one_item_are_never_compared(self):
        dear = Supplier.objects.create(shop=self.shop, name="Dear Mills")
        self._purchase(self.supplier, self.item, "100.00", 1)
        self._purchase(dear, self.item, "160.00", 30)

        response = self.client.get(self.url)

        # Two series, each with a single purchase, so neither has a trend.
        # Grouping by item alone would report a fictional 60% rise here.
        self.assertEqual(response.data["tracked_pairs"], 2)
        self.assertEqual(response.data["movements"], [])

    def test_a_voided_purchase_is_not_a_price(self):
        # A voided invoice is money the shop did not spend. Leaving it in would
        # make a cancelled 300.00 bill read as a 200% rise.
        self._purchase(self.supplier, self.item, "100.00", 1)
        voided = self._purchase(self.supplier, self.item, "300.00", 30)
        voided.status = Purchase.Status.VOID
        voided.save(update_fields=["status"])

        response = self.client.get(self.url)

        self.assertEqual(response.data["movements"], [])
        self.assertEqual(response.data["series"][0]["latest_cost"], "100.00")

    def test_asking_for_one_item_returns_the_series_behind_the_figure(self):
        # The overview omits the points to keep the payload small; a shopkeeper
        # checking the claim against their own invoices needs them.
        self._purchase(self.supplier, self.item, "100.00", 1)
        self._purchase(self.supplier, self.item, "130.00", 30)

        overview = self.client.get(self.url)
        self.assertEqual(overview.data["series"][0]["points"], [])

        detail = self.client.get(f"{self.url}?item_id={self.item.id}")
        points = detail.data["series"][0]["points"]
        self.assertEqual([p["unit_cost"] for p in points], ["100.00", "130.00"])

    def test_staff_cannot_read_what_the_shop_pays_its_suppliers(self):
        # Cost prices are the shop's margin. Every other procurement surface
        # here is admin-only and this one must not be the exception.
        staff = PlatformUser.objects.create_user(
            email="staff@example.com", password="secret", full_name="Staff"
        )
        ShopMembership.objects.create(
            user=staff,
            shop=self.shop,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
        )
        client = APIClient()
        client.force_authenticate(user=staff)

        self.assertEqual(client.get(self.url).status_code, 403)

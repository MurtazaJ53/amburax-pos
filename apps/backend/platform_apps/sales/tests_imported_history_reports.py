"""Imported bills are records, not transactions, and the reports must know it.

"Past sales" is offered as a first-class import on the onboarding screen, so
every shop will use it. The rows it writes are headers: a date, a total, a
payment mode, and no line items at all - deliberately, because replaying last
year's sales through the stock ledger would drive every product negative.

The consequence was not deliberate. No line items means no cost, no GST rate
and no HSN, so the profit and loss reported a business that had spent nothing
- revenue against a cost of zero, a fabricated hundred per cent margin - and
the GST summary carried a row reading rate null, taxable zero, with the value
still counted in the gross.

The second one is the dangerous one. It looks entirely plausible on screen and
it ends up on a government filing.

There is also a volume test at the bottom. Nothing in this suite failed when a
caller dropped a paging cursor, which is why the same defect shipped in three
separate clients: the tests exercise logic and never exercise size.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem
from platform_apps.sales.models import Sale, SaleItem
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class ImportedHistoryTests(TestCase):
    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="history@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="History Shop",
            slug="history-reports-shop",
            settings_json={"plan_tier": "pro"},
        )
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Rice", sku="RICE-1", sell_price=Decimal("100.00")
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    _seq = 0

    def _imported(self, total="1000.00"):
        """A bill from the previous POS: a header, and nothing underneath."""
        type(self)._seq += 1
        return Sale.objects.create(
            shop=self.shop,
            receipt_number=f"OLD-{self._seq}",
            payment_mode="CASH",
            total_amount=Decimal(total),
            amount_received=Decimal(total),
            amount_due=Decimal("0.00"),
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
            status=Sale.Status.COMPLETED,
            source_system="import",
        )

    def _real_sale(self, total="200.00", cost="120.00", taxable="190.48", tax="9.52"):
        type(self)._seq += 1
        sale = Sale.objects.create(
            shop=self.shop,
            receipt_number=f"NEW-{self._seq}",
            payment_mode="CASH",
            total_amount=Decimal(total),
            amount_received=Decimal(total),
            amount_due=Decimal("0.00"),
            taxable_amount=Decimal(taxable),
            tax_amount=Decimal(tax),
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
            status=Sale.Status.COMPLETED,
        )
        SaleItem.objects.create(
            sale=sale,
            inventory_item=self.item,
            name_snapshot="Rice",
            quantity=Decimal("2"),
            unit_price=Decimal("100.00"),
            unit_cost=Decimal(cost) / 2,
            line_total=Decimal(total),
            taxable_amount=Decimal(taxable),
            tax_amount=Decimal(tax),
            cgst_amount=Decimal(tax) / 2,
            sgst_amount=Decimal(tax) / 2,
            gst_rate=Decimal("5.00"),
            hsn_snapshot="1006",
            position=0,
        )
        return sale

    def _pl(self):
        return self.client.get(reverse("report-profit-loss", args=[self.shop.id])).data

    def _gst(self):
        return self.client.get(reverse("sale-gst-summary", args=[self.shop.id])).data

    # --- profit and loss ----------------------------------------------

    def test_imported_bills_do_not_invent_a_hundred_per_cent_margin(self):
        # The whole finding: revenue with no cost behind it read as pure
        # profit, on the screen a shopkeeper uses to set their prices.
        self._imported(total="1000.00")

        pl = self._pl()
        self.assertEqual(Decimal(pl["gross_profit"]), Decimal("0.00"))

    def test_revenue_still_counts_every_bill(self):
        # A shopkeeper asking what they sold means everything they sold.
        # Dropping imported bills from revenue would be its own lie, and the
        # sales history would stop matching the P&L.
        self._imported(total="1000.00")
        self._real_sale(total="200.00")

        self.assertEqual(Decimal(self._pl()["revenue"]), Decimal("1200.00"))

    def test_the_part_without_costs_is_named(self):
        # So the screen can explain why profit is measured against a smaller
        # number than the revenue printed above it.
        self._imported(total="1000.00")
        self._real_sale(total="200.00")

        pl = self._pl()
        self.assertEqual(Decimal(pl["imported_revenue"]), Decimal("1000.00"))
        self.assertLess(Decimal(pl["revenue_with_costs"]), Decimal(pl["net_revenue"]))

    def test_profit_still_reflects_the_bills_that_can_answer_for_it(self):
        self._imported(total="1000.00")
        self._real_sale(total="200.00", cost="120.00")

        pl = self._pl()
        self.assertEqual(Decimal(pl["cost_of_goods_sold"]), Decimal("120.00"))
        self.assertEqual(Decimal(pl["gross_profit"]), Decimal("70.48"))

    def test_the_arithmetic_on_screen_still_follows(self):
        self._imported(total="1000.00")
        self._real_sale()

        pl = self._pl()
        self.assertEqual(
            Decimal(pl["revenue_with_costs"]) - Decimal(pl["cost_of_goods_sold"]),
            Decimal(pl["gross_profit"]),
        )

    def test_a_shop_with_no_imports_is_unaffected(self):
        self._real_sale(total="200.00", cost="120.00")

        pl = self._pl()
        self.assertEqual(Decimal(pl["imported_revenue"]), Decimal("0.00"))
        self.assertEqual(
            Decimal(pl["net_revenue"]) - Decimal(pl["cost_of_goods_sold"]),
            Decimal(pl["gross_profit"]),
        )

    # --- the GST return ------------------------------------------------

    def test_imported_bills_are_not_on_the_gst_return(self):
        # They have no rate and no HSN because they have no lines. Left in,
        # they filed sales under a null rate with no taxable value - and it
        # looked plausible all the way to the tax department.
        self._imported(total="1000.00")

        gst = self._gst()
        self.assertEqual(Decimal(gst["gross_amount"]), Decimal("0.00"))
        self.assertEqual(Decimal(gst["taxable_amount"]), Decimal("0.00"))

    def test_no_null_rate_row_survives(self):
        self._imported(total="1000.00")
        self._real_sale()

        for row in self._gst()["b2c_small"]:
            self.assertIsNotNone(row["items__gst_rate"])

    def test_no_null_hsn_row_survives(self):
        self._imported(total="1000.00")
        self._real_sale()

        for row in self._gst()["hsn_summary"]:
            self.assertTrue(row["items__hsn_snapshot"])

    def test_the_gross_matches_what_was_actually_billed_with_gst(self):
        # The reported symptom: a gross of 2,03,158 against taxable 0.00.
        self._imported(total="1000.00")
        self._real_sale(total="200.00")

        gst = self._gst()
        self.assertEqual(Decimal(gst["gross_amount"]), Decimal("200.00"))
        self.assertGreater(Decimal(gst["taxable_amount"]), Decimal("0.00"))

    def test_a_real_sale_is_still_returned_in_full(self):
        self._real_sale(total="200.00", taxable="190.48", tax="9.52")

        gst = self._gst()
        self.assertEqual(Decimal(gst["taxable_amount"]), Decimal("190.48"))
        self.assertEqual(Decimal(gst["tax_amount"]), Decimal("9.52"))


class CatalogueAtVolumeTests(TestCase):
    """Can a till reach the four hundredth product?

    The suite had 1,391 passing tests while the web point of sale could not
    sell 85 of 285 products, because it fetched one page and searched that in
    memory. Nothing failed: every test used a handful of rows, so a dropped
    cursor was indistinguishable from a working one.

    This is the test that fails when a caller ignores paging. It is
    deliberately about size rather than logic.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="volume@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Big Shop", slug="big-shop")
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.url = reverse("inventory-list", args=[self.shop.id])

        InventoryItem.objects.bulk_create(
            [
                InventoryItem(
                    shop=self.shop,
                    name=f"Bulk {n:04d}",
                    sku=f"BULK-{n:04d}",
                    sell_price=Decimal("10.00"),
                )
                for n in range(500)
            ]
        )

    def _walk(self) -> list[str]:
        """Every product, following the cursor to the end - as a client must."""
        names: list[str] = []
        cursor = None
        for _ in range(25):
            params = {"limit": 100}
            if cursor:
                params["cursor"] = cursor
            response = self.client.get(self.url, params)
            self.assertEqual(response.status_code, 200, response.content)
            names += [row["name"] for row in response.json()]
            cursor = response.get("X-Next-Cursor")
            if not cursor:
                break
        return names

    def test_one_request_does_not_return_the_whole_catalogue(self):
        # The premise. If a single request ever did return everything, the
        # tests below would pass while proving nothing.
        rows = self.client.get(self.url).json()
        self.assertLess(len(rows), 500)

    def test_the_four_hundredth_product_is_reachable(self):
        self.assertIn("Bulk 0400", self._walk())

    def test_every_product_is_reachable(self):
        names = self._walk()
        self.assertEqual(len(names), 500)
        self.assertEqual(len(set(names)), 500)

    def test_the_last_product_is_reachable(self):
        # The one furthest from the first page, and the one a shopkeeper is
        # most likely to be told they do not stock.
        self.assertIn("Bulk 0499", self._walk())

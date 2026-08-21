"""Profit must compare net revenue with net cost.

The report did `revenue - cogs`, where revenue was Sum(total_amount) — GROSS,
including GST — and cogs was quantity x unit_cost, which comes from the
purchase invoice's PRE-TAX rate. So gross profit was overstated by the entire
tax collected: 5% of turnover on kirana goods, 18% on many others.

The GST is not the shop's money. A shopkeeper setting prices off that screen
was being told a margin that did not exist.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem
from platform_apps.sales.models import Sale, SaleItem
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class ProfitMarginTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="pnl@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="P&L Shop", slug="pnl-shop", settings_json={"plan_tier": "pro"}
        )
        ShopMembership.objects.create(
            user=self.user, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Oil", sku="OIL-1",
            sell_price=Decimal("150.00"), gst_rate=Decimal("5"),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def _sale(self):
        """One 150 bill, GST-inclusive at 5%: taxable 142.86, tax 7.14.
        Bought at 120 net of GST."""
        today = timezone.now()
        sale = Sale.objects.create(
            shop=self.shop, receipt_number="P-1", status=Sale.Status.COMPLETED,
            subtotal_amount=Decimal("150.00"), total_amount=Decimal("150.00"),
            taxable_amount=Decimal("142.86"), tax_amount=Decimal("7.14"),
            amount_received=Decimal("150.00"), amount_due=Decimal("0.00"),
            sale_date=today.date(), occurred_at=today,
        )
        SaleItem.objects.create(
            sale=sale, inventory_item=self.item, name_snapshot="Oil",
            quantity=Decimal("1"), unit_price=Decimal("150.00"),
            unit_cost=Decimal("120.00"), line_total=Decimal("150.00"), position=0,
        )
        return sale

    def _report(self):
        return self.client.get(
            f"/api/v1/shops/{self.shop.id}/reports/profit-loss/"
        )

    def test_gross_profit_excludes_the_tax_collected(self):
        """142.86 kept - 120.00 cost = 22.86. The old answer was 30.00, which
        counted the 7.14 of GST as if it were the shop's margin."""
        self._sale()

        response = self._report()

        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(Decimal(str(response.data["gross_profit"])), Decimal("22.86"))

    def test_the_headline_revenue_is_still_what_the_customer_paid(self):
        """A shopkeeper means gross when they say "sales". Changing that would
        trade one confusing number for another."""
        self._sale()

        response = self._report()

        self.assertEqual(Decimal(str(response.data["revenue"])), Decimal("150.00"))

    def test_net_revenue_is_exposed_so_the_arithmetic_can_be_followed(self):
        self._sale()

        data = self._report().data

        self.assertEqual(
            Decimal(str(data["net_revenue"])),
            Decimal(str(data["revenue"])) - Decimal(str(data["tax_collected"])),
        )

    def test_margin_is_measured_against_net_revenue(self):
        """Against gross it is flattered twice: bigger numerator, bigger
        denominator, both wrong."""
        self._sale()

        data = self._report().data
        expected = (
            Decimal(str(data["net_profit"]))
            / Decimal(str(data["net_revenue"]))
            * Decimal("100")
        ).quantize(Decimal("0.01"))
        self.assertEqual(Decimal(str(data["net_margin_pct"])), expected)

    def test_a_zero_rated_shop_is_unaffected(self):
        """Most kirana stock is nil-rated. The fix must not move their numbers."""
        today = timezone.now()
        sale = Sale.objects.create(
            shop=self.shop, receipt_number="P-2", status=Sale.Status.COMPLETED,
            subtotal_amount=Decimal("100.00"), total_amount=Decimal("100.00"),
            taxable_amount=Decimal("100.00"), tax_amount=Decimal("0.00"),
            amount_received=Decimal("100.00"), amount_due=Decimal("0.00"),
            sale_date=today.date(), occurred_at=today,
        )
        SaleItem.objects.create(
            sale=sale, inventory_item=self.item, name_snapshot="Oil",
            quantity=Decimal("1"), unit_price=Decimal("100.00"),
            unit_cost=Decimal("70.00"), line_total=Decimal("100.00"), position=0,
        )

        data = self._report().data

        self.assertEqual(Decimal(str(data["gross_profit"])), Decimal("30.00"))


class ProfitMarginLegacyDataTests(TestCase):
    """Sales recorded before the GST columns existed must not read as a loss.

    The bulk historical-sale importer (sales/views.py) creates Sale rows with
    no taxable_amount, tax_amount or SaleItem rows at all, and older sales
    predate those columns. A plain Sum("taxable_amount") over them is zero, so
    profit would come out hugely negative — worse than the overstatement being
    fixed, and on the screen a shopkeeper prices against.
    """

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="legacy@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Legacy Shop", slug="legacy-shop", settings_json={"plan_tier": "pro"}
        )
        ShopMembership.objects.create(
            user=self.user, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Widget", sku="W-1", sell_price=Decimal("100.00")
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_a_sale_with_no_gst_columns_still_reports_its_revenue(self):
        today = timezone.now()
        sale = Sale.objects.create(
            shop=self.shop, receipt_number="L-1", status=Sale.Status.COMPLETED,
            subtotal_amount=Decimal("200.00"), total_amount=Decimal("200.00"),
            amount_received=Decimal("200.00"), amount_due=Decimal("0.00"),
            sale_date=today.date(), occurred_at=today,
        )
        SaleItem.objects.create(
            sale=sale, inventory_item=self.item, name_snapshot="Widget",
            quantity=Decimal("2"), unit_price=Decimal("100.00"),
            unit_cost=Decimal("60.00"), line_total=Decimal("200.00"), position=0,
        )

        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/reports/profit-loss/"
        )

        data = response.data
        self.assertEqual(Decimal(str(data["net_revenue"])), Decimal("200.00"))
        self.assertEqual(Decimal(str(data["gross_profit"])), Decimal("80.00"))

    def test_taxed_and_untaxed_sales_can_coexist(self):
        """A real shop importing history and then trading has both."""
        today = timezone.now()
        legacy = Sale.objects.create(
            shop=self.shop, receipt_number="L-2", status=Sale.Status.COMPLETED,
            subtotal_amount=Decimal("100.00"), total_amount=Decimal("100.00"),
            amount_received=Decimal("100.00"), amount_due=Decimal("0.00"),
            sale_date=today.date(), occurred_at=today,
        )
        SaleItem.objects.create(
            sale=legacy, inventory_item=self.item, name_snapshot="Widget",
            quantity=Decimal("1"), unit_price=Decimal("100.00"),
            unit_cost=Decimal("60.00"), line_total=Decimal("100.00"), position=0,
        )
        modern = Sale.objects.create(
            shop=self.shop, receipt_number="L-3", status=Sale.Status.COMPLETED,
            subtotal_amount=Decimal("150.00"), total_amount=Decimal("150.00"),
            taxable_amount=Decimal("142.86"), tax_amount=Decimal("7.14"),
            amount_received=Decimal("150.00"), amount_due=Decimal("0.00"),
            sale_date=today.date(), occurred_at=today,
        )
        SaleItem.objects.create(
            sale=modern, inventory_item=self.item, name_snapshot="Widget",
            quantity=Decimal("1"), unit_price=Decimal("150.00"),
            unit_cost=Decimal("60.00"), line_total=Decimal("150.00"), position=0,
        )

        data = self.client.get(
            f"/api/v1/shops/{self.shop.id}/reports/profit-loss/"
        ).data

        # 100 untaxed + 142.86 net of tax
        self.assertEqual(Decimal(str(data["net_revenue"])), Decimal("242.86"))
        self.assertEqual(Decimal(str(data["gross_profit"])), Decimal("122.86"))

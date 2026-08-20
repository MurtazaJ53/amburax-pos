"""What the dashboard actually says, and to whom.

Three defects lived here at once, all on the first screen a shopkeeper sees:

1. The hero card was labelled "Today's Sales" and showed LIFETIME revenue.
   With 19,604 sales that is an absurd number, and it was the demo surface.
2. Stock was cast to int, so a grocer's remaining 0.750 kg read as 0 — out of
   stock, and worth nothing in the valuation. Precisely the shops that
   weight_selling was built to win.
3. The projection was refreshed by two endpoints, both Flutter sync paths.
   Web sales, voids, returns and imports updated nothing, and no scheduled job
   catches up because the deployed compose runs no Celery beat.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.projections.services import refresh_shop_dashboard_projection
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class DashboardTodayFiguresTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="today@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Today Shop", slug="today-shop",
            timezone="Asia/Kolkata",
            settings_json={"plan_tier": "pro"},
        )
        ShopMembership.objects.create(
            user=self.user, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def _sale(self, amount: str, *, when=None):
        moment = when or timezone.now()
        return Sale.objects.create(
            shop=self.shop,
            receipt_number=f"R-{Sale.objects.count() + 1}",
            status=Sale.Status.COMPLETED,
            subtotal_amount=Decimal(amount),
            total_amount=Decimal(amount),
            sale_date=moment.date(),
            occurred_at=moment,
        )

    def test_today_excludes_older_sales(self):
        """The bug: this used to be the all-time total."""
        self._sale("100.00", when=timezone.now() - timedelta(days=40))
        self._sale("250.00", when=timezone.now() - timedelta(days=2))
        self._sale("75.00")

        snapshot = refresh_shop_dashboard_projection(self.shop)

        self.assertEqual(snapshot.today_gross_revenue, Decimal("75.00"))
        self.assertEqual(snapshot.today_sales_count, 1)

    def test_the_lifetime_figures_are_still_reported(self):
        """Both are wanted. The defect was the label, not the arithmetic — so
        removing the all-time number would have been the wrong fix."""
        self._sale("100.00", when=timezone.now() - timedelta(days=40))
        self._sale("75.00")

        snapshot = refresh_shop_dashboard_projection(self.shop)

        self.assertEqual(snapshot.gross_revenue, Decimal("175.00"))
        self.assertEqual(snapshot.sales_count, 2)

    def test_a_shop_with_no_sales_today_reports_zero_not_lifetime(self):
        self._sale("500.00", when=timezone.now() - timedelta(days=3))

        snapshot = refresh_shop_dashboard_projection(self.shop)

        self.assertEqual(snapshot.today_gross_revenue, Decimal("0.00"))
        self.assertEqual(snapshot.today_sales_count, 0)
        self.assertEqual(snapshot.gross_revenue, Decimal("500.00"))

    def test_the_day_is_the_shop_s_own_not_the_server_s(self):
        """A Kolkata shop cashing up at 22:00 IST is on the previous UTC day.
        Using UTC would drop the evening's takings exactly when the owner
        looks."""
        from zoneinfo import ZoneInfo

        snapshot = refresh_shop_dashboard_projection(self.shop)

        expected = timezone.now().astimezone(ZoneInfo("Asia/Kolkata")).date()
        self.assertEqual(snapshot.today_date, expected)

    def test_a_stale_snapshot_is_rebuilt_rather_than_served(self):
        """Yesterday's takings shown as today's is worse than the lifetime bug,
        because the number looks plausible."""
        self._sale("400.00")
        snapshot = refresh_shop_dashboard_projection(self.shop)
        # Pretend this row was built yesterday and nothing has refreshed since.
        type(snapshot).objects.filter(pk=snapshot.pk).update(
            today_date=snapshot.today_date - timedelta(days=1),
            today_gross_revenue=Decimal("9999.00"),
        )

        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/projections/dashboard/"
        )

        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(
            Decimal(response.data["today_gross_revenue"]), Decimal("400.00")
        )

    def test_todays_revenue_is_hidden_from_a_shop_without_finance_summary(self):
        """Same gate as gross_revenue. Adding a revenue field without adding it
        to the gate is how a feature check quietly springs a leak."""
        self.shop.settings_json = {"plan_tier": "starter"}
        self.shop.save(update_fields=["settings_json"])
        self._sale("120.00")

        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/projections/dashboard/"
        )

        self.assertEqual(response.status_code, 200, response.content)
        self.assertIsNone(response.data["today_gross_revenue"])
        self.assertIsNone(response.data["gross_revenue"])


class FractionalStockTests(TestCase):
    """A grocer's part-kilo must not read as nothing."""

    def setUp(self):
        self.shop = Shop.objects.create(
            name="Kirana", slug="kirana-stock",
            settings_json={"plan_tier": "pro", "business_type": "grocery"},
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Toor Dal", sku="DAL-09",
            sell_price=Decimal("120.00"), unit="kg",
        )

    def _stock(self, qty: str):
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal(qty), occurred_at=timezone.now(),
        )

    def test_part_of_a_kilo_is_not_out_of_stock(self):
        self._stock("0.750")

        snapshot = refresh_shop_dashboard_projection(self.shop)

        self.assertEqual(snapshot.out_of_stock_items_count, 0)
        self.assertEqual(snapshot.low_stock_items_count, 1)

    def test_part_of_a_kilo_still_has_value(self):
        """int() dropped this from the stock valuation entirely."""
        self._stock("0.750")

        snapshot = refresh_shop_dashboard_projection(self.shop)

        # 0.750 kg at 120/kg
        self.assertEqual(snapshot.projected_sell_value, Decimal("90.000"))

    def test_the_preview_row_keeps_its_decimals(self):
        self._stock("2.500")

        snapshot = refresh_shop_dashboard_projection(self.shop)
        row = snapshot.low_stock_preview.first()

        self.assertEqual(row.stock_on_hand, Decimal("2.500"))

    def test_genuinely_empty_stock_is_still_out_of_stock(self):
        """The fix must not make everything look in stock."""
        self._stock("0.000")

        snapshot = refresh_shop_dashboard_projection(self.shop)

        self.assertEqual(snapshot.out_of_stock_items_count, 1)
        self.assertEqual(snapshot.projected_sell_value, Decimal("0"))

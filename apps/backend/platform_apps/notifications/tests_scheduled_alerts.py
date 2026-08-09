from __future__ import annotations

from datetime import timezone as dt_timezone
from decimal import Decimal
from unittest.mock import patch

from django.test import TestCase
from django.utils import timezone

from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.notifications.models import Notification
from platform_apps.notifications.services import (
    build_sales_alert,
    build_stock_alert,
    run_due_alerts,
)
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class ScheduledAlertTests(TestCase):
    """Two alerts a day, to the two roles that can act on them.

    The rule these tests defend is restraint. An alert that fires on a quiet
    day teaches the owner to ignore the channel, and then the morning a fast
    seller hits zero is missed too.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="alert-owner@example.com", password="secret", full_name="Owner"
        )
        self.admin = PlatformUser.objects.create_user(
            email="alert-admin@example.com", password="secret", full_name="Admin"
        )
        self.cashier = PlatformUser.objects.create_user(
            email="alert-cashier@example.com", password="secret", full_name="Cashier"
        )
        self.shop = Shop.objects.create(
            name="Alert Shop", slug="alert-shop", timezone="Asia/Kolkata",
            status=Shop.Status.ACTIVE,
        )
        for user, role in (
            (self.owner, ShopMembership.Role.OWNER),
            (self.admin, ShopMembership.Role.ADMIN),
            (self.cashier, ShopMembership.Role.CASHIER),
        ):
            ShopMembership.objects.create(
                user=user, shop=self.shop, role=role,
                status=ShopMembership.Status.ACTIVE,
            )

    def _item(self, name, *, stock, level=5):
        item = InventoryItem.objects.create(
            shop=self.shop, name=name, sell_price=Decimal("100"), reorder_level=level
        )
        if stock:
            InventoryStockLedger.objects.create(
                shop=self.shop, item=item,
                event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
                quantity_delta=Decimal(str(stock)), occurred_at=timezone.now(),
            )
        return item

    def _sale(self, *, received, due):
        return Sale.objects.create(
            shop=self.shop, payment_mode="CASH",
            total_amount=Decimal(received) + Decimal(due),
            amount_received=Decimal(received), amount_due=Decimal(due),
            sale_date=timezone.localdate(), occurred_at=timezone.now(),
        )

    # --- the morning stock alert -------------------------------------------

    def test_names_what_is_out_and_what_is_low_separately(self):
        self._item("Rice", stock=0)
        self._item("Sugar", stock=2, level=5)

        title, message = build_stock_alert(self.shop)

        self.assertIn("1 out of stock", title)
        self.assertIn("1 running low", title)
        self.assertIn("Rice", message)
        self.assertIn("Sugar", message)

    def test_a_healthy_shop_gets_no_morning_alert(self):
        """Silence is the correct output. 'All good' every day is how a
        channel gets muted, and then the day that matters is missed too."""
        self._item("Rice", stock=100, level=5)

        self.assertIsNone(build_stock_alert(self.shop))

    def test_a_long_list_is_truncated_rather_than_unreadable(self):
        for n in range(25):
            self._item(f"Item {n}", stock=0)

        _, message = build_stock_alert(self.shop)

        self.assertIn("and 15 more", message)
        self.assertLessEqual(len(message.splitlines()), 14)

    # --- the evening takings alert -----------------------------------------

    def test_reports_the_days_takings(self):
        self._sale(received="500", due="0")
        self._sale(received="300", due="200")

        title, message = build_sales_alert(self.shop, timezone.localdate())

        self.assertIn("800.00", title)
        self.assertIn("2 bills", message)
        self.assertIn("200.00", message)

    def test_credit_is_mentioned_only_when_it_happened(self):
        self._sale(received="500", due="0")

        _, message = build_sales_alert(self.shop, timezone.localdate())

        self.assertNotIn("udhaar", message.lower())

    def test_a_day_with_no_trade_sends_nothing(self):
        self.assertIsNone(build_sales_alert(self.shop, timezone.localdate()))

    # --- who receives them --------------------------------------------------

    def test_only_owners_and_admins_are_notified(self):
        self._item("Rice", stock=0)

        run_due_alerts(force_slot="morning")

        recipients = set(
            Notification.objects.values_list("recipient__email", flat=True)
        )
        self.assertEqual(
            recipients, {"alert-owner@example.com", "alert-admin@example.com"}
        )

    def test_the_notification_is_stored_so_it_can_be_found_later(self):
        """The 'history for anyone who missed it' the review asked for."""
        self._item("Rice", stock=0)

        run_due_alerts(force_slot="morning")
        note = Notification.objects.filter(recipient=self.owner).first()

        self.assertIsNotNone(note)
        self.assertEqual(note.type, Notification.Type.WARNING)
        self.assertEqual(note.action_url, "/inventory")
        self.assertIn("Rice", note.message)

    # --- scheduling ---------------------------------------------------------

    def test_running_twice_in_a_day_does_not_send_twice(self):
        """Cron runs hourly, so this is the normal case, not an edge case."""
        self._item("Rice", stock=0)

        run_due_alerts(force_slot="morning")
        run_due_alerts(force_slot="morning")

        self.assertEqual(Notification.objects.filter(recipient=self.owner).count(), 1)

    def test_a_healthy_shop_is_not_rechecked_all_day(self):
        """Nothing to send still counts as handled, or an hourly cron would
        re-scan the whole catalogue every hour."""
        self._item("Rice", stock=100)

        run_due_alerts(force_slot="morning")
        self.shop.refresh_from_db()

        self.assertIn("alert_stock_last_sent", self.shop.settings_json)

    def test_nine_means_nine_where_the_shop_is(self):
        """The container clock is UTC; 09:00 UTC is 14:30 in Kolkata."""
        self._item("Rice", stock=0)

        with patch("platform_apps.notifications.services.timezone.now") as now:
            # 03:30 UTC == 09:00 IST
            now.return_value = timezone.datetime(
                2026, 8, 9, 3, 30, tzinfo=dt_timezone.utc
            )
            run_due_alerts()

        self.assertEqual(Notification.objects.count(), 2)

    def test_nothing_fires_at_an_unrelated_hour(self):
        self._item("Rice", stock=0)

        with patch("platform_apps.notifications.services.timezone.now") as now:
            # 08:00 UTC == 13:30 IST, neither slot.
            now.return_value = timezone.datetime(
                2026, 8, 9, 8, 0, tzinfo=dt_timezone.utc
            )
            run_due_alerts()

        self.assertEqual(Notification.objects.count(), 0)

    def test_a_suspended_shop_is_skipped(self):
        self._item("Rice", stock=0)
        self.shop.status = Shop.Status.SUSPENDED
        self.shop.save()

        run_due_alerts(force_slot="morning")

        self.assertEqual(Notification.objects.count(), 0)

    def test_a_broken_timezone_still_gets_its_alerts(self):
        """A typo in settings must not mean a shop silently never hears from
        the system again."""
        self.shop.timezone = "Not/AZone"
        self.shop.save()
        self._item("Rice", stock=0)

        run_due_alerts(force_slot="morning")

        self.assertEqual(Notification.objects.count(), 2)

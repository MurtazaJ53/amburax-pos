"""Nobody was ever told their trial was ending.

days_remaining and expiringSoon existed only inside the billing page — the
16th of 17 sidebar items. A 30-day trial converted at roughly the rate of
people who happened to click "Subscription & billing".
"""
from __future__ import annotations

from datetime import timedelta
from io import StringIO
from unittest.mock import patch

from django.core.management import call_command
from django.test import TestCase
from django.utils import timezone

from platform_apps.billing.models import Subscription
from platform_apps.notifications.models import Notification
from platform_apps.shops.models import Shop
from platform_apps.users.models import PlatformUser

SEND = "platform_apps.billing.management.commands.send_billing_reminders.send_email"


class BillingReminderTests(TestCase):
    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="owner@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Reminder Shop", slug="reminder-shop", owner_user=self.owner
        )
        self.subscription = Subscription.objects.create(
            shop=self.shop,
            status=Subscription.Status.TRIALING,
            trial_ends_at=timezone.now() + timedelta(days=3),
        )

    def _run(self, **kwargs):
        out = StringIO()
        with patch(SEND) as send:
            call_command("send_billing_reminders", stdout=out, **kwargs)
        return send, out.getvalue()

    def test_a_trial_ending_in_three_days_is_emailed(self):
        send, _ = self._run()
        send.assert_called_once()
        self.assertIn("3 days", send.call_args.kwargs["subject"])

    def test_the_same_reminder_is_not_sent_twice(self):
        """It runs hourly. Without dedupe a shop gets the same email 24 times."""
        self._run()
        send, _ = self._run()
        send.assert_not_called()

    def test_a_trial_with_plenty_of_time_is_left_alone(self):
        self.subscription.trial_ends_at = timezone.now() + timedelta(days=20)
        self.subscription.save(update_fields=["trial_ends_at"])

        send, _ = self._run()

        send.assert_not_called()

    def test_a_lapsed_subscription_gets_its_own_message(self):
        self.subscription.trial_ends_at = timezone.now() - timedelta(days=10)
        self.subscription.save(update_fields=["trial_ends_at"])

        send, _ = self._run()

        send.assert_called_once()
        self.assertIn("has ended", send.call_args.kwargs["subject"])

    def test_an_in_app_notification_is_recorded_too(self):
        """The half the shopkeeper sees when they next open the app."""
        self._run()

        note = Notification.objects.get(shop=self.shop)
        self.assertEqual(note.action_url, "/billing")
        self.assertEqual(note.metadata_json["billing_reminder"], "3")

    def test_a_failed_email_still_records_the_notification(self):
        """Losing the in-app nudge because a provider was down would turn a
        transient outage into a permanently missed customer."""
        out = StringIO()
        with patch(SEND, side_effect=RuntimeError("provider down")):
            call_command("send_billing_reminders", stdout=out)

        self.assertTrue(Notification.objects.filter(shop=self.shop).exists())

    def test_a_shop_with_no_owner_email_does_not_crash_the_run(self):
        other_shop = Shop.objects.create(name="Orphan", slug="orphan-shop")
        Subscription.objects.create(
            shop=other_shop,
            status=Subscription.Status.TRIALING,
            trial_ends_at=timezone.now() + timedelta(days=3),
        )

        send, _ = self._run()

        # The reachable shop is still emailed.
        send.assert_called_once()

    def test_dry_run_sends_nothing_and_records_nothing(self):
        send, output = self._run(dry_run=True)

        send.assert_not_called()
        self.assertFalse(Notification.objects.exists())
        self.assertIn("Dry run", output)


class BackfillSubscriptionTests(TestCase):
    """Shops created before billing landed have no Subscription row at all, so
    expire_subscriptions cannot see them — and the billing page would hand them
    a brand-new 30-day trial on first view."""

    def setUp(self):
        self.shop = Shop.objects.create(name="Old Shop", slug="old-shop")

    def test_dry_run_lists_the_shop_and_writes_nothing(self):
        out = StringIO()
        call_command("backfill_subscriptions", "--dry-run", stdout=out)

        self.assertIn("Old Shop", out.getvalue())
        self.assertFalse(Subscription.objects.exists())

    def test_it_refuses_to_guess_a_trial_length(self):
        """A wrong trial_ends_at either gives free months or cuts a shop off
        mid-trade. Not this command's decision to make."""
        from django.core.management.base import CommandError

        with self.assertRaises(CommandError):
            call_command("backfill_subscriptions")

    def test_it_creates_the_missing_subscription(self):
        call_command("backfill_subscriptions", "--trial-days", "14", stdout=StringIO())

        subscription = Subscription.objects.get(shop=self.shop)
        self.assertEqual(subscription.status, Subscription.Status.TRIALING)

    def test_a_date_inside_the_grace_period_keeps_access(self):
        """GRACE_DAYS exists so a slow payment never locks a shop mid-trade.
        A trial that ended today is still inside it — asserting otherwise is
        how a grace period gets deleted by accident."""
        call_command("backfill_subscriptions", "--trial-days", "0", stdout=StringIO())

        self.shop.refresh_from_db()
        self.assertTrue(self.shop.enabled_features["advanced_ops"])

    def test_a_date_past_the_grace_period_locks_the_shop_immediately(self):
        """Not at the next cron run — the whole point is that these shops have
        been on free Pro for months."""
        call_command(
            "backfill_subscriptions", "--trial-days=-10", stdout=StringIO()
        )

        self.shop.refresh_from_db()
        self.assertFalse(self.shop.enabled_features["advanced_ops"])

    def test_shops_that_already_have_one_are_untouched(self):
        existing = Subscription.objects.create(
            shop=self.shop,
            status=Subscription.Status.ACTIVE,
            trial_ends_at=timezone.now() + timedelta(days=5),
        )
        call_command("backfill_subscriptions", "--trial-days", "14", stdout=StringIO())

        existing.refresh_from_db()
        self.assertEqual(existing.status, Subscription.Status.ACTIVE)
        self.assertEqual(Subscription.objects.count(), 1)

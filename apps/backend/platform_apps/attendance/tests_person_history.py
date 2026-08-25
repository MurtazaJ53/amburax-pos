"""One person's history, joined across three tables.

The figures here decide how somebody is judged, so the rules that keep them
honest are pinned: a half day is half, hours on a leave day are not hours, an
average of no bills is not zero, and a colleague cannot read them.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.attendance.models import AttendanceSession
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class TeamMemberHistoryTests(TestCase):
    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="boss@example.com", password="secret", full_name="Owner"
        )
        self.worker = PlatformUser.objects.create_user(
            email="asha@example.com", password="secret", full_name="Asha"
        )
        self.shop = Shop.objects.create(name="History Shop", slug="history-shop")
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.member = ShopMembership.objects.create(
            user=self.worker,
            shop=self.shop,
            role=ShopMembership.Role.CASHIER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.today = timezone.localdate()
        self.url = f"/api/v1/shops/{self.shop.id}/team/{self.member.id}/history/"

    def _session(self, days_ago, status, hours="8", overtime="0", bonus="0"):
        return AttendanceSession.objects.create(
            shop=self.shop,
            membership=self.member,
            session_date=self.today - timedelta(days=days_ago),
            status=status,
            total_hours=Decimal(hours),
            overtime_hours=Decimal(overtime),
            bonus_amount=Decimal(bonus),
        )

    def _sale(self, amount, days_ago=0, discount="0", actor=None):
        return Sale.objects.create(
            shop=self.shop,
            actor_user=actor or self.worker,
            total_amount=Decimal(amount),
            amount_received=Decimal(amount),
            discount_amount=Decimal(discount),
            sale_date=self.today - timedelta(days=days_ago),
            occurred_at=timezone.now() - timedelta(days=days_ago),
        )

    def _get(self, **params):
        response = self.client.get(self.url, params)
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    # --- attendance ------------------------------------------------------

    def test_a_half_day_counts_as_half_a_day_worked(self):
        self._session(1, AttendanceSession.Status.PRESENT)
        self._session(2, AttendanceSession.Status.HALF_DAY, hours="4")
        body = self._get()["attendance"]
        self.assertEqual(body["present"], 1)
        self.assertEqual(body["half_days"], 1)
        self.assertEqual(Decimal(str(body["days_worked"])), Decimal("1.5"))
        self.assertEqual(Decimal(body["hours"]), Decimal("12.00"))

    def test_hours_recorded_against_a_leave_day_are_not_hours(self):
        """A data-entry mistake, not overtime. Adding it inflates the month."""
        self._session(1, AttendanceSession.Status.LEAVE, hours="8", overtime="2")
        body = self._get()["attendance"]
        self.assertEqual(Decimal(body["hours"]), Decimal("0.00"))
        self.assertEqual(Decimal(body["overtime"]), Decimal("0.00"))
        self.assertEqual(body["leave"], 1)

    def test_a_bonus_is_counted_whatever_the_day_was_marked(self):
        self._session(1, AttendanceSession.Status.LEAVE, bonus="500")
        self.assertEqual(Decimal(self._get()["attendance"]["bonus"]), Decimal("500.00"))

    # --- sales -----------------------------------------------------------

    def test_only_this_persons_sales_are_counted(self):
        self._sale("500")
        self._sale("900", actor=self.owner)
        body = self._get()["sales"]
        self.assertEqual(body["bills"], 1)
        self.assertEqual(Decimal(body["gross"]), Decimal("500.00"))

    def test_a_voided_bill_is_not_credited_to_anyone(self):
        sale = self._sale("500")
        sale.status = Sale.Status.VOID
        sale.save(update_fields=["status"])
        self.assertEqual(self._get()["sales"]["bills"], 0)

    def test_discount_given_is_reported_because_it_is_what_gets_watched(self):
        self._sale("500", discount="50")
        self.assertEqual(
            Decimal(self._get()["sales"]["discount_given"]), Decimal("50.00")
        )

    def test_an_average_of_no_bills_is_unanswerable_not_zero(self):
        body = self._get()["sales"]
        self.assertIsNone(body["average_bill"])
        self.assertIsNone(body["per_day_worked"])

    def test_takings_per_day_worked_compares_two_people_fairly(self):
        self._session(1, AttendanceSession.Status.PRESENT)
        self._session(2, AttendanceSession.Status.HALF_DAY, hours="4")
        self._sale("300", days_ago=1)
        self._sale("300", days_ago=2)
        # 600 over 1.5 days worked.
        self.assertEqual(
            Decimal(self._get()["sales"]["per_day_worked"]), Decimal("400.00")
        )

    # --- window ----------------------------------------------------------

    def test_the_window_excludes_what_falls_outside_both_ends(self):
        self._sale("100", days_ago=1)
        self._sale("900", days_ago=60)
        body = self._get(
            date_from=(self.today - timedelta(days=5)).isoformat(),
            date_to=self.today.isoformat(),
        )
        self.assertEqual(Decimal(body["sales"]["gross"]), Decimal("100.00"))

    def test_a_malformed_date_is_refused(self):
        response = self.client.get(self.url, {"date_from": "25-08-2026"})
        self.assertEqual(response.status_code, 400, response.content)

    # --- who may read it -------------------------------------------------

    def test_a_colleague_cannot_read_someone_elses_hours_and_takings(self):
        client = APIClient()
        client.force_authenticate(user=self.worker)
        self.assertIn(client.get(self.url).status_code, (403, 404))

    def test_a_member_of_another_shop_is_not_found(self):
        other = Shop.objects.create(name="Other", slug="other-history-shop")
        stranger = PlatformUser.objects.create_user(
            email="stranger@example.com", password="secret", full_name="Stranger"
        )
        foreign = ShopMembership.objects.create(
            user=stranger,
            shop=other,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
        )
        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/team/{foreign.id}/history/"
        )
        self.assertEqual(response.status_code, 404, response.content)

    def test_recent_sessions_come_back_newest_first(self):
        self._session(3, AttendanceSession.Status.PRESENT)
        self._session(1, AttendanceSession.Status.PRESENT)
        dates = [row["session_date"] for row in self._get()["recent_sessions"]]
        self.assertEqual(dates, sorted(dates, reverse=True))

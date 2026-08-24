"""The day close, now that it is a server record rather than a browser note.

These tests exist because the over/short figure is the one number on the
screen that can get a cashier accused of taking money. Every rule that
protects it - the float must be entered, the client cannot post its own
expected figure, a locked day stops moving - is pinned here.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.payments.models import SalePayment
from platform_apps.sales.models import RegisterSession, Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class RegisterSessionTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="till@example.com", password="secret", full_name="Asha Cashier"
        )
        self.shop = Shop.objects.create(name="Till Shop", slug="till-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.today = timezone.localdate()
        self.url = f"/api/v1/shops/{self.shop.id}/sales/register/"

    # --- helpers ---------------------------------------------------------

    def _sale(self, tenders, sale_date=None, status=Sale.Status.COMPLETED):
        """A bill with its tender rows, which is where cash actually lives."""
        sale_date = sale_date or self.today
        now = timezone.now()
        total = sum(tenders.values(), Decimal("0.00"))
        sale = Sale.objects.create(
            shop=self.shop,
            total_amount=total,
            sale_date=sale_date,
            occurred_at=now,
            status=status,
        )
        for method, amount in tenders.items():
            SalePayment.objects.create(
                sale=sale,
                shop=self.shop,
                payment_method=method,
                amount=amount,
                occurred_at=now,
            )
        return sale

    def _put(self, **body):
        payload = {"business_date": self.today.isoformat()}
        payload.update(body)
        return self.client.put(self.url, payload, format="json")

    # --- reading ---------------------------------------------------------

    def test_a_day_with_no_close_yet_still_reports_the_cash_taken(self):
        self._sale({"CASH": Decimal("1405.00")})
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertIsNone(body["session"])
        self.assertEqual(Decimal(body["cash_sales"]), Decimal("1405.00"))
        # No float entered yet, so expected is the cash alone - not a guess.
        self.assertEqual(Decimal(body["expected_cash"]), Decimal("1405.00"))

    def test_cash_inside_a_split_bill_is_counted(self):
        """The bug this screen used to have: a SPLIT bill's cash vanished."""
        self._sale({"CASH": Decimal("15.00"), "UPI": Decimal("85.00")})
        body = self.client.get(self.url).json()
        self.assertEqual(Decimal(body["cash_sales"]), Decimal("15.00"))

    def test_card_and_upi_never_count_toward_the_drawer(self):
        self._sale({"UPI": Decimal("1385.00"), "CARD": Decimal("1450.00")})
        body = self.client.get(self.url).json()
        self.assertEqual(Decimal(body["cash_sales"]), Decimal("0.00"))

    def test_a_voided_sale_is_not_expected_in_the_drawer(self):
        self._sale({"CASH": Decimal("500.00")}, status=Sale.Status.VOID)
        body = self.client.get(self.url).json()
        self.assertEqual(Decimal(body["cash_sales"]), Decimal("0.00"))

    def test_yesterdays_cash_does_not_land_in_todays_drawer(self):
        self._sale({"CASH": Decimal("900.00")}, sale_date=self.today - timedelta(days=1))
        body = self.client.get(self.url).json()
        self.assertEqual(Decimal(body["cash_sales"]), Decimal("0.00"))

    # --- saving in progress ---------------------------------------------

    def test_an_in_progress_count_is_saved_without_locking_the_day(self):
        self._sale({"CASH": Decimal("1405.00")})
        response = self._put(
            opening_float="1000", counted_cash="2405", float_entered=True
        )
        self.assertEqual(response.status_code, 200, response.content)
        session = response.json()["session"]
        self.assertFalse(session["is_locked"])
        self.assertIsNone(session["closed_at"])
        # Nothing is snapshotted while the day is still open.
        self.assertIsNone(session["discrepancy"])
        self.assertEqual(Decimal(response.json()["expected_cash"]), Decimal("2405.00"))

    def test_saving_twice_updates_the_same_day_rather_than_stacking_rows(self):
        self._put(opening_float="1000", counted_cash="2000", float_entered=True)
        self._put(opening_float="1000", counted_cash="2405", float_entered=True)
        self.assertEqual(RegisterSession.objects.filter(shop=self.shop).count(), 1)

    def test_a_negative_count_is_refused_rather_than_absorbed(self):
        response = self._put(counted_cash="-50", float_entered=True)
        self.assertEqual(response.status_code, 400, response.content)

    # --- locking ---------------------------------------------------------

    def test_locking_snapshots_the_figures_and_records_who_counted(self):
        self._sale({"CASH": Decimal("1405.00")})
        response = self._put(
            opening_float="1000", counted_cash="2405", float_entered=True, lock=True
        )
        self.assertEqual(response.status_code, 200, response.content)
        session = response.json()["session"]
        self.assertTrue(session["is_locked"])
        self.assertEqual(Decimal(session["cash_sales"]), Decimal("1405.00"))
        self.assertEqual(Decimal(session["expected_cash"]), Decimal("2405.00"))
        self.assertEqual(Decimal(session["discrepancy"]), Decimal("0.00"))
        self.assertEqual(session["closed_by_name"], "Asha Cashier")
        self.assertIsNotNone(session["closed_at"])

    def test_a_short_drawer_reports_a_negative_discrepancy(self):
        self._sale({"CASH": Decimal("1405.00")})
        response = self._put(
            opening_float="1000", counted_cash="2305", float_entered=True, lock=True
        )
        self.assertEqual(
            Decimal(response.json()["session"]["discrepancy"]), Decimal("-100.00")
        )

    def test_the_day_cannot_be_locked_before_the_float_is_entered(self):
        """Expected-in-till without a float is a guess, and the over/short
        built on it would accuse someone on the strength of it."""
        response = self._put(counted_cash="2405", float_entered=False, lock=True)
        self.assertEqual(response.status_code, 400, response.content)
        self.assertFalse(RegisterSession.objects.filter(closed_at__isnull=False).exists())

    def test_a_locked_day_refuses_further_edits_instead_of_silently_dropping_them(self):
        self._put(opening_float="1000", counted_cash="2405", float_entered=True, lock=True)
        response = self._put(opening_float="1", counted_cash="9999", float_entered=True)
        self.assertEqual(response.status_code, 400, response.content)
        session = RegisterSession.objects.get(shop=self.shop, business_date=self.today)
        self.assertEqual(session.counted_cash, Decimal("2405.00"))

    def test_a_sale_returned_after_the_close_does_not_rewrite_the_locked_day(self):
        """A signed-off drawer is a statement about a moment, not a live view."""
        self._sale({"CASH": Decimal("1405.00")})
        self._put(opening_float="1000", counted_cash="2405", float_entered=True, lock=True)
        Sale.objects.filter(shop=self.shop).update(status=Sale.Status.VOID)
        body = self.client.get(self.url).json()
        self.assertEqual(Decimal(body["cash_sales"]), Decimal("1405.00"))
        self.assertEqual(Decimal(body["session"]["discrepancy"]), Decimal("0.00"))

    def test_the_client_cannot_dictate_the_expected_figure(self):
        """Posting a till figure the browser chose would let it say anything."""
        self._sale({"CASH": Decimal("1405.00")})
        response = self._put(
            opening_float="1000",
            counted_cash="2405",
            float_entered=True,
            lock=True,
            expected_cash="999999",
            discrepancy="0",
            cash_sales="999999",
        )
        session = response.json()["session"]
        self.assertEqual(Decimal(session["expected_cash"]), Decimal("2405.00"))
        self.assertEqual(Decimal(session["cash_sales"]), Decimal("1405.00"))

    # --- scoping and history --------------------------------------------

    def test_another_shops_close_is_never_returned(self):
        other = Shop.objects.create(name="Other Till", slug="other-till")
        RegisterSession.objects.create(
            shop=other,
            business_date=self.today,
            opening_float=Decimal("5000.00"),
            counted_cash=Decimal("5000.00"),
            closed_at=timezone.now(),
        )
        self.assertIsNone(self.client.get(self.url).json()["session"])

    def test_a_non_member_cannot_read_the_drawer(self):
        outsider = PlatformUser.objects.create_user(
            email="outsider@example.com", password="secret", full_name="Outsider"
        )
        client = APIClient()
        client.force_authenticate(user=outsider)
        self.assertIn(client.get(self.url).status_code, (403, 404))

    def test_history_lists_only_days_that_were_actually_closed(self):
        self._put(opening_float="1000", counted_cash="1000", float_entered=True)
        RegisterSession.objects.create(
            shop=self.shop,
            business_date=self.today - timedelta(days=1),
            opening_float=Decimal("1000.00"),
            counted_cash=Decimal("1100.00"),
            discrepancy=Decimal("100.00"),
            closed_at=timezone.now(),
        )
        response = self.client.get(f"{self.url}history/")
        self.assertEqual(response.status_code, 200, response.content)
        sessions = response.json()["sessions"]
        self.assertEqual(len(sessions), 1)
        self.assertEqual(Decimal(sessions[0]["discrepancy"]), Decimal("100.00"))

    def test_a_malformed_date_is_rejected_rather_than_silently_meaning_today(self):
        response = self.client.get(self.url, {"date": "22-08-2026"})
        self.assertEqual(response.status_code, 400, response.content)

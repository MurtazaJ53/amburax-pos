from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.customers.models import Customer, CustomerLedgerEntry
from platform_apps.expenses.models import Expense
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class DayBookTests(TestCase):
    """The Roj Mel.

    The distinction the report exists to preserve: money received is not the
    same as value sold. A day of strong sales and weak collection reads as
    healthy on revenue alone, and that is precisely the day a shopkeeper needs
    to see plainly.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="daybook@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Roj Shop", slug="roj-shop")
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.today = timezone.localdate()
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.url = reverse("report-day-book", args=[self.shop.id])

    def _sale(self, *, mode, total, received, due, day=None,
              status=Sale.Status.COMPLETED, customer=None):
        return Sale.objects.create(
            shop=self.shop,
            customer=customer,
            payment_mode=mode,
            total_amount=Decimal(total),
            amount_received=Decimal(received),
            amount_due=Decimal(due),
            sale_date=day or self.today,
            occurred_at=timezone.now(),
            status=status,
        )

    def _book(self, **params):
        return self.client.get(self.url, params).data

    # --- Jama -------------------------------------------------------------

    def test_receipts_are_split_by_payment_method(self):
        self._sale(mode="CASH", total="500", received="500", due="0")
        self._sale(mode="UPI", total="300", received="300", due="0")
        self._sale(mode="CARD", total="200", received="200", due="0")

        jama = self._book()["jama"]

        self.assertEqual(jama["cash"], "500.00")
        self.assertEqual(jama["upi"], "300.00")
        self.assertEqual(jama["card"], "200.00")
        self.assertEqual(jama["total"], "1000.00")

    def test_a_part_paid_credit_sale_counts_only_what_was_handed_over(self):
        """The whole reason for two columns instead of one revenue figure."""
        self._sale(mode="CREDIT", total="1000", received="400", due="600")

        book = self._book()

        self.assertEqual(book["jama"]["total"], "400.00")
        self.assertEqual(book["udhaar"]["credit_given"], "600.00")

    def test_a_part_paid_cash_sale_credits_only_the_cash_taken(self):
        """Guards the per-mode figures specifically.

        The CREDIT case above passes through a different branch, so it does
        not prove the per-mode totals use amount_received. A customer paying
        400 cash on a 1,000 bill and owing the rest is recorded with mode
        CASH, and the drawer holds 400 — not 1,000.
        """
        self._sale(mode="CASH", total="1000", received="400", due="600")

        book = self._book()

        self.assertEqual(book["jama"]["cash"], "400.00")
        self.assertEqual(book["cash_in_hand"], "400.00")
        self.assertEqual(book["udhaar"]["credit_given"], "600.00")

    def test_khata_repayment_counts_as_money_in_today(self):
        """It settles an older sale, but the cash arrived today."""
        customer = Customer.objects.create(
            shop=self.shop, name="Ramesh", balance=Decimal("0")
        )
        CustomerLedgerEntry.objects.create(
            shop=self.shop,
            customer=customer,
            event_type=CustomerLedgerEntry.EventType.PAYMENT,
            amount_delta=Decimal("-250.00"),
            occurred_at=timezone.now(),
        )

        jama = self._book()["jama"]

        self.assertEqual(jama["khata_repayments"], "250.00")
        self.assertEqual(jama["total"], "250.00")

    # --- Udhaar -----------------------------------------------------------

    def test_credit_given_counts_distinct_customers(self):
        a = Customer.objects.create(shop=self.shop, name="A", balance=Decimal("0"))
        b = Customer.objects.create(shop=self.shop, name="B", balance=Decimal("0"))
        self._sale(mode="CREDIT", total="100", received="0", due="100", customer=a)
        self._sale(mode="CREDIT", total="150", received="0", due="150", customer=a)
        self._sale(mode="CREDIT", total="200", received="0", due="200", customer=b)

        udhaar = self._book()["udhaar"]

        self.assertEqual(udhaar["credit_given"], "450.00")
        self.assertEqual(udhaar["customers"], 2)

    # --- cash in hand -----------------------------------------------------

    def test_only_cash_and_expenses_move_the_drawer(self):
        """A UPI collection does not change the physical cash."""
        self._sale(mode="CASH", total="800", received="800", due="0")
        self._sale(mode="UPI", total="500", received="500", due="0")
        Expense.objects.create(
            shop=self.shop,
            category="Transport",
            amount=Decimal("120.00"),
            expense_date=self.today,
        )

        book = self._book()

        self.assertEqual(book["cash_in_hand"], "680.00")
        self.assertEqual(book["money_out"]["expenses"], "120.00")

    # --- scope ------------------------------------------------------------

    def test_a_voided_bill_is_excluded(self):
        self._sale(
            mode="CASH", total="500", received="500", due="0",
            status=Sale.Status.VOID,
        )

        book = self._book()

        self.assertEqual(book["jama"]["total"], "0.00")
        self.assertEqual(book["sales_count"], 0)

    def test_yesterdays_trade_is_not_counted_today(self):
        yesterday = self.today - timedelta(days=1)
        self._sale(mode="CASH", total="900", received="900", due="0", day=yesterday)

        self.assertEqual(self._book()["jama"]["total"], "0.00")

    def test_an_explicit_date_returns_that_day(self):
        yesterday = self.today - timedelta(days=1)
        self._sale(mode="CASH", total="900", received="900", due="0", day=yesterday)

        book = self._book(date=yesterday.isoformat())

        self.assertEqual(book["date"], yesterday.isoformat())
        self.assertEqual(book["jama"]["total"], "900.00")

    def test_a_quiet_day_reports_zeros_rather_than_failing(self):
        book = self._book()

        self.assertEqual(book["jama"]["total"], "0.00")
        self.assertEqual(book["udhaar"]["credit_given"], "0.00")
        self.assertEqual(book["sales_count"], 0)

    # --- the shareable summary --------------------------------------------

    def test_summary_carries_the_figures_and_stays_short(self):
        self._sale(mode="CASH", total="500", received="500", due="0")
        self._sale(mode="CREDIT", total="1000", received="0", due="1000")

        text = self._book()["summary_text"]

        self.assertIn("Roj Shop", text)
        self.assertIn("500.00", text)
        self.assertIn("1,000.00", text)
        self.assertIn("Jama", text)
        self.assertIn("Udhaar", text)
        # The brief asked for brief: a message somebody will actually read.
        self.assertLessEqual(len(text.splitlines()), 8)

    def test_another_shop_cannot_read_this_daybook(self):
        stranger = PlatformUser.objects.create_user(
            email="nope-daybook@example.com", password="secret", full_name="No"
        )
        self.client.force_authenticate(user=stranger)

        self.assertEqual(self.client.get(self.url).status_code, 403)

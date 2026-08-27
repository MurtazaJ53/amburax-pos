"""Catching a stored number that disagrees with another stored number.

Every money bug in this system was that shape, and each sat in the database
for weeks because the only thing that would have noticed was a person
comparing two figures on two screens.

Half of these tests assert that a discrepancy IS found. The other half assert
that ordinary, correct data is NOT reported - and those matter more. This runs
hourly against live shops and emails the operator. One false alarm a day and
the sender gets filtered, taking the real alert with it; the backup check
already carries a comment about learning exactly that.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone

from platform_apps.common import reconcile
from platform_apps.customers.models import Customer, CustomerLedgerEntry
from platform_apps.payments.models import SalePayment
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop


class SaleAgreementTests(TestCase):
    def setUp(self):
        self.shop = Shop.objects.create(name="Recon Shop", slug="recon-shop")

    _seq = 0

    def _sale(self, *, total="100.00", received="100.00", due="0.00"):
        type(self)._seq += 1
        return Sale.objects.create(
            shop=self.shop,
            receipt_number=f"RC-{self._seq}",
            payment_mode="CASH",
            total_amount=Decimal(total),
            amount_received=Decimal(received),
            amount_due=Decimal(due),
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
            status=Sale.Status.COMPLETED,
        )

    def _tender(self, sale, amount, method="CASH"):
        return SalePayment.objects.create(
            sale=sale,
            shop=self.shop,
            amount=Decimal(amount),
            payment_method=method,
            occurred_at=sale.occurred_at,
        )

    # --- what must be caught ------------------------------------------

    def test_a_bill_whose_parts_do_not_make_its_total(self):
        # The original khata bug: 570 recorded as received, and also owed.
        sale = self._sale(total="570.00", received="570.00", due="570.00")
        problems = reconcile.sale_problems(sale)
        self.assertTrue(problems)
        self.assertIn("570.00", problems[0])

    def test_tendered_money_that_does_not_match_what_was_received(self):
        sale = self._sale(total="100.00", received="100.00")
        self._tender(sale, "60.00")
        problems = reconcile.sale_problems(sale)
        self.assertTrue(problems)
        self.assertIn("payments add up to", problems[0])

    # --- what must NOT be reported ------------------------------------

    def test_an_ordinary_cash_sale_is_quiet(self):
        sale = self._sale()
        self._tender(sale, "100.00")
        self.assertEqual(reconcile.sale_problems(sale), [])

    def test_a_credit_sale_writes_no_tender_and_is_still_quiet(self):
        # Credit is the absence of payment, so a khata bill has no payment row
        # at all. This is now the normal shape of every credit sale, and
        # firing on it would make the check useless on day one.
        sale = self._sale(total="285.00", received="0.00", due="285.00")
        self.assertEqual(reconcile.sale_problems(sale), [])

    def test_a_part_paid_bill_is_quiet(self):
        sale = self._sale(total="950.00", received="700.00", due="250.00")
        self._tender(sale, "700.00")
        self.assertEqual(reconcile.sale_problems(sale), [])

    def test_imported_history_with_no_tenders_is_not_flagged(self):
        # The importer stores flat bills with no payment rows. Treating that as
        # "nothing was paid" would flag a shop's whole trading history on the
        # first night, which is how an operator learns to ignore this email.
        sale = self._sale(total="450.00", received="450.00")
        self.assertEqual(reconcile.sale_problems(sale), [])

    def test_a_split_bill_across_two_tenders_is_quiet(self):
        sale = self._sale(total="1000.00", received="1000.00")
        self._tender(sale, "600.00", "CASH")
        self._tender(sale, "400.00", "UPI")
        self.assertEqual(reconcile.sale_problems(sale), [])

    def test_a_half_paisa_of_rounding_is_not_a_discrepancy(self):
        sale = self._sale(total="100.00", received="99.999", due="0.00")
        self.assertEqual(reconcile.sale_problems(sale), [])


class CustomerAgreementTests(TestCase):
    def setUp(self):
        self.shop = Shop.objects.create(name="Recon Shop", slug="recon-shop-2")
        self.customer = Customer.objects.create(
            shop=self.shop, name="Asha", phone="9876500123", balance=Decimal("0.00")
        )

    def _entry(self, delta):
        return CustomerLedgerEntry.objects.create(
            shop=self.shop,
            customer=self.customer,
            event_type=CustomerLedgerEntry.EventType.SALE,
            amount_delta=Decimal(delta),
            occurred_at=timezone.now(),
        )

    def test_a_balance_its_ledger_cannot_explain(self):
        # What the legacy credit sale looked like from the customer's side.
        self.customer.balance = Decimal("570.00")
        self.customer.save(update_fields=["balance"])
        self._entry("0.00")

        problems = reconcile.customer_problems(self.customer)
        self.assertTrue(problems)
        self.assertIn("Asha", problems[0])

    def test_a_balance_its_ledger_explains_is_quiet(self):
        self.customer.balance = Decimal("855.00")
        self.customer.save(update_fields=["balance"])
        self._entry("570.00")
        self._entry("285.00")

        self.assertEqual(reconcile.customer_problems(self.customer), [])

    def test_a_customer_who_owes_nothing_and_has_no_entries_is_quiet(self):
        self.assertEqual(reconcile.customer_problems(self.customer), [])

    def test_a_repayment_that_clears_the_balance_is_quiet(self):
        self._entry("300.00")
        self._entry("-300.00")
        self.assertEqual(reconcile.customer_problems(self.customer), [])


class ShopSweepTests(TestCase):
    def setUp(self):
        self.shop = Shop.objects.create(name="Sweep Shop", slug="sweep-shop")

    def _broken_sale(self, receipt):
        return Sale.objects.create(
            shop=self.shop,
            receipt_number=receipt,
            payment_mode="CASH",
            total_amount=Decimal("100.00"),
            amount_received=Decimal("100.00"),
            amount_due=Decimal("100.00"),
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
            status=Sale.Status.COMPLETED,
        )

    def test_a_clean_shop_reports_nothing(self):
        Sale.objects.create(
            shop=self.shop,
            receipt_number="OK-1",
            payment_mode="CASH",
            total_amount=Decimal("100.00"),
            amount_received=Decimal("100.00"),
            amount_due=Decimal("0.00"),
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
            status=Sale.Status.COMPLETED,
        )
        self.assertEqual(reconcile.shop_problems(self.shop), [])

    def test_the_report_is_capped(self):
        # A thousand identical lines in an email is less informative than
        # twenty, because nobody reads it.
        for i in range(8):
            self._broken_sale(f"BAD-{i}")
        self.assertEqual(len(reconcile.shop_problems(self.shop, max_reported=3)), 3)

    def test_a_voided_bill_is_not_reconciled(self):
        sale = self._broken_sale("VOID-1")
        sale.status = Sale.Status.VOID
        sale.save(update_fields=["status"])
        self.assertEqual(reconcile.shop_problems(self.shop), [])

    def test_older_sales_are_skipped_when_a_window_is_given(self):
        # The hourly sweep looks at recent days only. A shop with twenty
        # thousand bills must not be re-read every hour to answer a question
        # about today.
        old = self._broken_sale("OLD-1")
        Sale.objects.filter(pk=old.pk).update(
            sale_date=timezone.localdate() - timedelta(days=30)
        )
        since = timezone.localdate() - timedelta(days=2)
        self.assertEqual(reconcile.shop_problems(self.shop, since=since), [])

    def test_another_shop_is_not_swept_into_this_one(self):
        other = Shop.objects.create(name="Other", slug="sweep-other")
        Sale.objects.create(
            shop=other,
            receipt_number="THEIRS-1",
            payment_mode="CASH",
            total_amount=Decimal("50.00"),
            amount_received=Decimal("50.00"),
            amount_due=Decimal("50.00"),
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
            status=Sale.Status.COMPLETED,
        )
        self.assertEqual(reconcile.shop_problems(self.shop), [])

"""Repairing credit sales that were recorded before khata stopped counting.

These build the broken state directly rather than through the API, because the
API cannot produce it any more - which is the point of the fix that came
first. Every field is set the way the old code left it: paid in full, nothing
due, a CREDIT payment row, a ledger entry that moves the customer by zero.

This command rewrites money. The tests that matter most are the ones proving
it does nothing the second time and nothing to sales it should not touch.
"""
from __future__ import annotations

from decimal import Decimal
from io import StringIO

from django.core.management import call_command
from django.test import TestCase
from django.utils import timezone

from platform_apps.customers.models import Customer, CustomerLedgerEntry
from platform_apps.payments.models import SalePayment
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop


class BackfillCreditSalesTests(TestCase):
    def setUp(self):
        self.shop = Shop.objects.create(name="Legacy Shop", slug="legacy-shop")
        self.customer = Customer.objects.create(
            shop=self.shop,
            name="Asha",
            phone="9876500123",
            balance=Decimal("0.00"),
        )

    def _broken_credit_sale(self, total="570.00", *, customer=True, receipt="S-OLD"):
        """A credit sale exactly as the pre-fix code wrote it."""
        amount = Decimal(total)
        sale = Sale.objects.create(
            shop=self.shop,
            receipt_number=receipt,
            subtotal_amount=amount,
            total_amount=amount,
            # The bug: counted as received, nothing outstanding.
            amount_received=amount,
            amount_due=Decimal("0.00"),
            payment_mode=Sale.PaymentMode.CREDIT,
            occurred_at=timezone.now(),
            sale_date=timezone.localdate(),
        )
        SalePayment.objects.create(
            sale=sale,
            shop=self.shop,
            amount=amount,
            payment_method=Sale.PaymentMode.CREDIT,
            occurred_at=sale.occurred_at,
        )
        if customer:
            CustomerLedgerEntry.objects.create(
                shop=self.shop,
                customer=self.customer,
                event_type=CustomerLedgerEntry.EventType.SALE,
                amount_delta=Decimal("0.00"),
                total_spent_delta=amount,
                note=f"Sale {receipt}",
                occurred_at=sale.occurred_at,
                source_path=f"sales/{sale.id}",
            )
        return sale

    def _run(self, **kwargs):
        out = StringIO()
        call_command("backfill_credit_sales", stdout=out, stderr=StringIO(), **kwargs)
        return out.getvalue()

    def test_the_sale_ends_up_owing_what_was_put_on_khata(self):
        sale = self._broken_credit_sale()
        self._run()
        sale.refresh_from_db()
        self.assertEqual(sale.amount_due, Decimal("570.00"))
        self.assertEqual(sale.amount_received, Decimal("0.00"))

    def test_the_customer_balance_is_restored(self):
        self._broken_credit_sale()
        self._run()
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.balance, Decimal("570.00"))

    def test_the_ledger_entry_stops_reading_zero(self):
        self._broken_credit_sale()
        self._run()
        entry = CustomerLedgerEntry.objects.get()
        self.assertEqual(entry.amount_delta, Decimal("570.00"))

    def test_the_credit_payment_row_is_removed(self):
        # While it exists the day book counts it as a tender and the sales
        # screen sums it into a split that then does not match the bill.
        self._broken_credit_sale()
        self._run()
        self.assertFalse(
            SalePayment.objects.filter(payment_method=Sale.PaymentMode.CREDIT).exists()
        )

    def test_running_it_twice_does_not_double_the_debt(self):
        # The one failure that would be worse than the bug: a customer billed
        # twice for the same purchase because somebody ran it again.
        self._broken_credit_sale()
        self._run()
        self._run()
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.balance, Decimal("570.00"))

    def test_a_dry_run_changes_nothing(self):
        sale = self._broken_credit_sale()
        report = self._run(dry_run=True)
        sale.refresh_from_db()
        self.customer.refresh_from_db()
        self.assertEqual(sale.amount_due, Decimal("0.00"))
        self.assertEqual(self.customer.balance, Decimal("0.00"))
        self.assertTrue(SalePayment.objects.exists())
        self.assertIn("would restore", report)

    def test_a_cash_sale_is_left_alone(self):
        sale = Sale.objects.create(
            shop=self.shop,
            receipt_number="S-CASH",
            subtotal_amount=Decimal("100.00"),
            total_amount=Decimal("100.00"),
            amount_received=Decimal("100.00"),
            amount_due=Decimal("0.00"),
            payment_mode=Sale.PaymentMode.CASH,
            occurred_at=timezone.now(),
            sale_date=timezone.localdate(),
        )
        SalePayment.objects.create(
            sale=sale,
            shop=self.shop,
            amount=Decimal("100.00"),
            payment_method=Sale.PaymentMode.CASH,
            occurred_at=sale.occurred_at,
        )
        self._run()
        sale.refresh_from_db()
        self.assertEqual(sale.amount_due, Decimal("0.00"))
        self.assertEqual(SalePayment.objects.filter(sale=sale).count(), 1)

    def test_only_the_credit_part_of_a_split_bill_moves(self):
        sale = Sale.objects.create(
            shop=self.shop,
            receipt_number="S-SPLIT",
            subtotal_amount=Decimal("950.00"),
            total_amount=Decimal("950.00"),
            amount_received=Decimal("950.00"),
            amount_due=Decimal("0.00"),
            payment_mode=Sale.PaymentMode.CREDIT,
            occurred_at=timezone.now(),
            sale_date=timezone.localdate(),
        )
        SalePayment.objects.create(
            sale=sale,
            shop=self.shop,
            amount=Decimal("700.00"),
            payment_method=Sale.PaymentMode.CASH,
            occurred_at=sale.occurred_at,
        )
        SalePayment.objects.create(
            sale=sale,
            shop=self.shop,
            amount=Decimal("250.00"),
            payment_method=Sale.PaymentMode.CREDIT,
            occurred_at=sale.occurred_at,
        )
        self._run()
        sale.refresh_from_db()
        self.assertEqual(sale.amount_due, Decimal("250.00"))
        self.assertEqual(sale.amount_received, Decimal("700.00"))
        self.assertEqual(SalePayment.objects.filter(sale=sale).count(), 1)

    def test_a_credit_sale_with_no_customer_still_shows_what_is_owed(self):
        # Nobody to bill, but the books should not claim the money arrived.
        sale = self._broken_credit_sale(customer=False, receipt="S-WALKIN")
        self._run()
        sale.refresh_from_db()
        self.assertEqual(sale.amount_due, Decimal("570.00"))

    def test_another_shop_is_untouched_when_one_is_named(self):
        other = Shop.objects.create(name="Other", slug="other-shop")
        theirs = Sale.objects.create(
            shop=other,
            receipt_number="S-THEIRS",
            subtotal_amount=Decimal("40.00"),
            total_amount=Decimal("40.00"),
            amount_received=Decimal("40.00"),
            amount_due=Decimal("0.00"),
            payment_mode=Sale.PaymentMode.CREDIT,
            occurred_at=timezone.now(),
            sale_date=timezone.localdate(),
        )
        SalePayment.objects.create(
            sale=theirs,
            shop=other,
            amount=Decimal("40.00"),
            payment_method=Sale.PaymentMode.CREDIT,
            occurred_at=theirs.occurred_at,
        )
        mine = self._broken_credit_sale()

        self._run(shop=str(self.shop.id))

        mine.refresh_from_db()
        theirs.refresh_from_db()
        self.assertEqual(mine.amount_due, Decimal("570.00"))
        self.assertEqual(theirs.amount_due, Decimal("0.00"))

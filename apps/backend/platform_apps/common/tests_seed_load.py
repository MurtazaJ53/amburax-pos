"""Seeded data has to be data the system would have written itself.

A load test measures whatever it created. If the seeder writes bills that do
not add up, the benchmark still runs and the numbers still look like numbers -
but the hourly reconciliation starts emailing about every one of them, and the
first thing anybody does is turn the check off. That trade is never worth
making for a performance measurement.

So most of this file checks correctness, not volume. Small counts throughout:
the arithmetic is what is being tested, and it does not get more true at ten
thousand rows.
"""
from __future__ import annotations

import uuid
from decimal import Decimal
from io import StringIO

import pytest
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase

from platform_apps.common import reconcile
from platform_apps.common.blind_index import generate_blind_index
from platform_apps.customers.models import Customer, CustomerLedgerEntry
from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.payments.models import SalePayment
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop


class SeedLoadTests(TestCase):
    def setUp(self):
        self.shop = Shop.objects.create(name="Load Shop", slug="load-shop")

    def _run(self, **options):
        out, err = StringIO(), StringIO()
        call_command("seed_load", str(self.shop.id), stdout=out, stderr=err, **options)
        return out.getvalue() + err.getvalue()

    def _seed(self, products=20, customers=10, sales=40):
        return self._run(
            products=products, customers=customers, sales=sales, confirm=True
        )

    # --- refusing ------------------------------------------------------

    def test_it_writes_nothing_without_confirm(self):
        report = self._run(products=20, customers=10, sales=40)

        self.assertEqual(InventoryItem.objects.count(), 0)
        self.assertEqual(Sale.objects.count(), 0)
        self.assertIn("Nothing was written", report)

    def test_it_estimates_before_writing(self):
        # The operator decides from this line whether the box can take it.
        report = self._run(products=10_000, customers=10_000, sales=11_000)
        self.assertIn("rows in total", report)
        self.assertIn("GB free", report)

    def test_an_unknown_shop_is_refused(self):
        with pytest.raises(CommandError):
            call_command("seed_load", str(uuid.uuid4()), stdout=StringIO())

    # --- money that adds up -------------------------------------------

    def test_every_seeded_bill_reconciles(self):
        # The assertion that matters. reconcile is what the hourly ops check
        # runs; if the seeder disagrees with it, the load test breaks the
        # alerting it was meant to be measured alongside.
        self._seed()

        self.assertGreater(Sale.objects.count(), 0)
        self.assertEqual(reconcile.shop_problems(self.shop), [])

    def test_credit_bills_carry_no_tender_row(self):
        # Credit is the absence of payment. Seeding a CREDIT payment row would
        # recreate the exact bug this system spent a day removing.
        self._seed()

        self.assertFalse(SalePayment.objects.filter(payment_method="CREDIT").exists())

    def test_credit_bills_move_the_customer_balance(self):
        self._seed(sales=200)

        credit_sales = Sale.objects.filter(shop=self.shop, amount_due__gt=0)
        if not credit_sales.exists():
            self.skipTest("no credit sale in this sample")

        owed = sum((s.amount_due for s in credit_sales), Decimal("0.00"))
        balances = sum(
            (c.balance for c in Customer.objects.filter(shop=self.shop)),
            Decimal("0.00"),
        )
        self.assertEqual(owed, balances)

    def test_every_credit_bill_has_a_ledger_entry(self):
        self._seed(sales=200)

        credit_count = Sale.objects.filter(shop=self.shop, amount_due__gt=0).count()
        if not credit_count:
            self.skipTest("no credit sale in this sample")
        self.assertEqual(
            CustomerLedgerEntry.objects.filter(shop=self.shop).count(), credit_count
        )

    def test_a_cash_bill_is_tendered_in_full(self):
        self._seed()

        for sale in Sale.objects.filter(shop=self.shop, amount_due=0)[:10]:
            tendered = sum((p.amount for p in sale.payments.all()), Decimal("0.00"))
            self.assertEqual(tendered, sale.amount_received)

    # --- data the app can actually use --------------------------------

    def test_seeded_customers_can_be_found_by_phone(self):
        # bulk_create does not call save(), which is where phone_hash is
        # maintained. Without it these customers are invisible to the search a
        # cashier uses, and benchmarking that lookup would prove nothing.
        self._seed(customers=5, sales=0)

        customer = Customer.objects.filter(shop=self.shop).first()
        self.assertTrue(customer.phone_hash)
        self.assertEqual(customer.phone_hash, generate_blind_index(customer.phone))

    def test_every_product_starts_with_stock(self):
        self._seed(products=20, sales=0)

        opening = InventoryStockLedger.objects.filter(
            shop=self.shop,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
        ).count()
        self.assertEqual(opening, 20)

    def test_each_sold_line_moves_stock(self):
        self._seed(products=20, customers=0, sales=40)

        sold = InventoryStockLedger.objects.filter(
            shop=self.shop, event_type=InventoryStockLedger.EventType.SALE
        ).count()
        # Two lines a bill.
        self.assertEqual(sold, 80)

    def test_receipt_numbers_do_not_collide(self):
        self._seed(sales=40)

        receipts = list(
            Sale.objects.filter(shop=self.shop).values_list("receipt_number", flat=True)
        )
        self.assertEqual(len(set(receipts)), len(receipts))

    def test_running_it_twice_does_not_reuse_receipt_numbers(self):
        # Receipt numbers continue from what is already there, so a second run
        # to add more load does not fail on a collision halfway through.
        self._seed(products=20, customers=0, sales=10)
        self._run(products=0, customers=0, sales=10, confirm=True)

        receipts = list(
            Sale.objects.filter(shop=self.shop).values_list("receipt_number", flat=True)
        )
        self.assertEqual(len(set(receipts)), 20)

    def test_the_same_seed_produces_the_same_shop(self):
        self._seed(products=10, customers=0, sales=5)
        first = list(
            Sale.objects.filter(shop=self.shop)
            .order_by("receipt_number")
            .values_list("total_amount", flat=True)
        )

        other = Shop.objects.create(name="Load Shop 2", slug="load-shop-2")
        call_command(
            "seed_load",
            str(other.id),
            products=10,
            customers=0,
            sales=5,
            confirm=True,
            stdout=StringIO(),
        )
        second = list(
            Sale.objects.filter(shop=other)
            .order_by("receipt_number")
            .values_list("total_amount", flat=True)
        )

        self.assertEqual(first, second)

    def test_another_shop_is_not_seeded(self):
        other = Shop.objects.create(name="Untouched", slug="untouched")
        self._seed()

        self.assertEqual(InventoryItem.objects.filter(shop=other).count(), 0)
        self.assertEqual(Sale.objects.filter(shop=other).count(), 0)

"""The only hard delete in the system, and the guards that stand in front of it.

Twenty-nine tables cascade from a shop and none of them come back. So almost
every test here asserts that nothing was deleted - a refusal, a stale backup,
a mistyped id. The one test that deletes is the short one.

Written this way round on purpose. A destructive tool is judged by what it
declines to do, and every path where it silently proceeds is a path where
somebody loses a shop's trading history to a typo.
"""
from __future__ import annotations

import os
import tempfile
import uuid
from decimal import Decimal
from io import StringIO
from pathlib import Path

import pytest
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase
from django.utils import timezone

from platform_apps.customers.models import Customer
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop


class PurgeShopsTests(TestCase):
    def setUp(self):
        self.backups = Path(tempfile.mkdtemp()) / "daily"
        self.backups.mkdir(parents=True)

        self.shop = Shop.objects.create(name="Flow Test Shop 0828", slug="flow-0828")
        self.keeper = Shop.objects.create(name="Real Shop", slug="real-shop")

    def _backup(self, age_hours: float = 1):
        path = self.backups / "bhub-20260828-020000.dump"
        path.write_bytes(b"x" * 2_000_000)
        when = timezone.now().timestamp() - age_hours * 3600
        os.utime(path, (when, when))
        return path

    def _run(self, *shop_ids, **options):
        out, err = StringIO(), StringIO()
        call_command(
            "purge_shops",
            *[str(i) for i in shop_ids],
            backup_dir=str(self.backups.parent),
            stdout=out,
            stderr=err,
            **options,
        )
        return out.getvalue() + err.getvalue()

    def _sale(self, shop, receipt):
        return Sale.objects.create(
            shop=shop,
            receipt_number=receipt,
            payment_mode="CASH",
            total_amount=Decimal("100.00"),
            amount_received=Decimal("100.00"),
            amount_due=Decimal("0.00"),
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
            status=Sale.Status.COMPLETED,
        )

    # --- what it refuses to do ----------------------------------------

    def test_it_reports_and_deletes_nothing_by_default(self):
        # The default behaviour of a destructive command should be to describe
        # itself. Anyone who runs this to "see what it does" must still have
        # their shop afterwards.
        self._sale(self.shop, "T-1")

        report = self._run(self.shop.id)

        self.assertTrue(Shop.objects.filter(pk=self.shop.pk).exists())
        self.assertIn("Nothing was deleted", report)

    def test_the_report_names_the_shop_and_counts_its_rows(self):
        # An operator confirms from this list. A summary that omits a table is
        # worse than none, because it is read as complete.
        self._sale(self.shop, "T-1")
        Customer.objects.create(shop=self.shop, name="Asha", phone="9876500123")

        report = self._run(self.shop.id)

        self.assertIn("Flow Test Shop 0828", report)
        self.assertIn("sales.Sale", report)
        self.assertIn("customers.Customer", report)

    def test_it_refuses_without_any_backup(self):
        with pytest.raises(CommandError) as caught:
            self._run(self.shop.id, confirm=True)

        self.assertIn("No backup found", str(caught.value))
        self.assertTrue(Shop.objects.filter(pk=self.shop.pk).exists())

    def test_it_refuses_when_the_backup_is_stale(self):
        # A week-old dump loses a week of trading. That is not a safety net,
        # and treating it as one is how a "reversible" delete stops being one.
        self._backup(age_hours=200)

        with pytest.raises(CommandError) as caught:
            self._run(self.shop.id, confirm=True)

        self.assertIn("200 hours old", str(caught.value))
        self.assertTrue(Shop.objects.filter(pk=self.shop.pk).exists())

    def test_one_unknown_id_stops_the_whole_run(self):
        # A stale note with one wrong id means the other ids are not
        # trustworthy either. Deleting the ones that happened to match would be
        # the worst possible reading of the operator's intent.
        self._backup()

        with pytest.raises(CommandError):
            self._run(self.shop.id, uuid.uuid4(), confirm=True)

        self.assertTrue(Shop.objects.filter(pk=self.shop.pk).exists())

    def test_a_dry_run_works_without_any_backup_at_all(self):
        # Describing a shop is not dangerous, and needing a backup to read a
        # report would push people straight to --confirm.
        report = self._run(self.shop.id)
        self.assertIn("Flow Test Shop 0828", report)

    # --- what it does ------------------------------------------------

    def test_a_confirmed_purge_removes_the_shop_and_its_rows(self):
        self._backup()
        self._sale(self.shop, "T-1")
        Customer.objects.create(shop=self.shop, name="Asha", phone="9876500123")

        self._run(self.shop.id, confirm=True)

        self.assertFalse(Shop.objects.filter(pk=self.shop.pk).exists())
        self.assertFalse(Sale.objects.filter(shop_id=self.shop.pk).exists())
        self.assertFalse(Customer.objects.filter(shop_id=self.shop.pk).exists())

    def test_every_other_shop_is_untouched(self):
        # The failure nobody recovers from. Asserted explicitly rather than
        # trusted to the ORM.
        self._backup()
        self._sale(self.keeper, "K-1")

        self._run(self.shop.id, confirm=True)

        self.assertTrue(Shop.objects.filter(pk=self.keeper.pk).exists())
        self.assertEqual(Sale.objects.filter(shop_id=self.keeper.pk).count(), 1)

    def test_it_says_which_backup_it_checked(self):
        # So "the backup named above is the only way back" points at a real
        # file the operator can go and find.
        self._backup()
        report = self._run(self.shop.id, confirm=True)
        self.assertIn("bhub-20260828-020000.dump", report)

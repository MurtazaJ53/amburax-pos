"""Taking back a bad import without taking anything else with it.

The rule under test is what undo REFUSES to remove. Removing a product that
has been sold, or a customer who owes money, corrupts records that have
nothing to do with the bad import - and nobody would notice until the numbers
stopped adding up.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.utils import timezone

from platform_apps.common.import_undo import rows_from, tag_for, undo
from platform_apps.common.models import ImportBatch
from platform_apps.customers.models import Customer, CustomerLedgerEntry
from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.shops.models import Shop


class ImportUndoTests(TestCase):
    def setUp(self):
        self.shop = Shop.objects.create(name="Undo Shop", slug="undo-shop")

    def _batch(self, kind=ImportBatch.Kind.PRODUCTS, **kwargs):
        return ImportBatch.objects.create(
            shop=self.shop, kind=kind, filename="list.csv", **kwargs
        )

    def _product(self, batch, name, row=1):
        return InventoryItem.objects.create(
            shop=self.shop, name=name, sell_price=Decimal("10"),
            **tag_for(batch, row),
        )

    def _customer(self, batch, name, row=1, balance="0"):
        return Customer.objects.create(
            shop=self.shop, name=name, phone=f"90000000{row:02d}",
            balance=Decimal(balance), **tag_for(batch, row),
        )

    # --- finding what an import created ----------------------------------

    def test_only_this_import_is_found(self):
        mine = self._batch()
        other = self._batch()
        self._product(mine, "From mine")
        self._product(other, "From other")
        InventoryItem.objects.create(
            shop=self.shop, name="Typed by hand", sell_price=Decimal("5")
        )
        self.assertEqual([r.name for r in rows_from(mine)], ["From mine"])

    def test_the_row_number_from_the_file_is_kept(self):
        # So somebody can go back and fix line 47 rather than hunt for it.
        batch = self._batch()
        item = self._product(batch, "Rice", row=47)
        self.assertEqual(item.source_id, "47")

    # --- the happy case ---------------------------------------------------

    def test_a_mistaken_import_is_taken_back(self):
        batch = self._batch()
        for n in range(3):
            self._product(batch, f"Customer {n} as a product", row=n + 1)

        result = undo(batch)

        self.assertEqual(result["removed"], 3)
        self.assertEqual(result["kept"], 0)
        self.assertEqual(rows_from(batch).count(), 0)

    def test_rows_typed_by_hand_are_never_touched(self):
        batch = self._batch()
        self._product(batch, "Imported")
        typed = InventoryItem.objects.create(
            shop=self.shop, name="Typed", sell_price=Decimal("5")
        )
        undo(batch)
        typed.refresh_from_db()
        self.assertFalse(typed.tombstone)

    # --- what it refuses to remove ---------------------------------------

    def test_a_product_that_has_moved_is_kept(self):
        """It is on a receipt somebody is holding."""
        batch = self._batch()
        sold = self._product(batch, "Sold since", row=1)
        self._product(batch, "Untouched", row=2)
        InventoryStockLedger.objects.create(
            shop=self.shop, item=sold,
            event_type=InventoryStockLedger.EventType.ADJUSTMENT,
            quantity_delta=Decimal("-1"), occurred_at=timezone.now(),
        )

        result = undo(batch)

        self.assertEqual(result["removed"], 1)
        self.assertEqual(result["kept"], 1)
        sold.refresh_from_db()
        self.assertFalse(sold.tombstone, "a product with history was removed")

    def test_a_customer_who_owes_money_is_kept(self):
        # Removing them loses the debt, and the shop would never know.
        batch = self._batch(kind=ImportBatch.Kind.CUSTOMERS)
        owing = self._customer(batch, "Owes", row=1, balance="500")
        self._customer(batch, "Owes nothing", row=2)

        result = undo(batch)

        self.assertEqual(result["kept"], 1)
        owing.refresh_from_db()
        self.assertFalse(owing.tombstone)

    def test_a_customer_with_a_ledger_entry_is_kept(self):
        batch = self._batch(kind=ImportBatch.Kind.CUSTOMERS)
        active = self._customer(batch, "Has history", row=1)
        CustomerLedgerEntry.objects.create(
            shop=self.shop, customer=active,
            event_type=CustomerLedgerEntry.EventType.ADJUSTMENT,
            amount_delta=Decimal("100"), occurred_at=timezone.now(),
        )
        self.assertEqual(undo(batch)["kept"], 1)

    def test_what_was_kept_is_named_not_just_counted(self):
        batch = self._batch()
        sold = self._product(batch, "Basmati Rice")
        InventoryStockLedger.objects.create(
            shop=self.shop, item=sold,
            event_type=InventoryStockLedger.EventType.ADJUSTMENT,
            quantity_delta=Decimal("-1"), occurred_at=timezone.now(),
        )
        self.assertEqual(undo(batch)["kept_rows"][0]["name"], "Basmati Rice")

    # --- running it twice -------------------------------------------------

    def test_undoing_twice_removes_nothing_more(self):
        batch = self._batch()
        self._product(batch, "One")
        first = undo(batch)
        second = undo(batch)
        self.assertEqual(first["removed"], 1)
        self.assertTrue(second["already_undone"])
        self.assertEqual(second["removed"], 1, "it should report the first run")

    def test_the_batch_records_what_happened(self):
        batch = self._batch()
        self._product(batch, "One")
        undo(batch)
        batch.refresh_from_db()
        self.assertIsNotNone(batch.undone_at)
        self.assertEqual(batch.undone_count, 1)

    def test_undoing_an_import_that_created_nothing_is_harmless(self):
        batch = self._batch()
        result = undo(batch)
        self.assertEqual(result["removed"], 0)

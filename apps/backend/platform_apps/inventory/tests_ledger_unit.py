"""What one unit of a stock movement meant, at the time it was written.

``quantity_delta`` is a bare number. Three is three pieces or three dozen
depending on the item's ``unit`` - and ``unit`` is a field a shopkeeper can
edit. Change it from piece to dozen after a year of trading and every
historical row silently re-reads as twelve times what it was: the stock figure
moves, the valuation moves, and nothing anywhere records that the number ever
meant something else.

Wholesale is what makes this urgent. A shop selling by the dozen has a real
reason to change that setting, and the damage is invisible - no error, no
failed save, just a different past.

So the unit is snapshotted onto the row, for the same reason SaleItem keeps
name_snapshot and hsn_snapshot: history has to stay readable without depending
on a row somebody may edit tomorrow.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.utils import timezone

from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.shops.models import Shop


class LedgerUnitSnapshotTests(TestCase):
    def setUp(self):
        self.shop = Shop.objects.create(name="Wholesaler", slug="wholesaler-unit")
        self.item = InventoryItem.objects.create(
            shop=self.shop,
            name="Design 4471 Kurta",
            sku="LOT-4471",
            unit="dozen",
            sell_price=Decimal("250.00"),
        )

    def _movement(self, **kwargs):
        kwargs.setdefault("event_type", InventoryStockLedger.EventType.PURCHASE)
        kwargs.setdefault("quantity_delta", Decimal("3"))
        return InventoryStockLedger.objects.create(
            shop=self.shop,
            item=self.item,
            occurred_at=timezone.now(),
            **kwargs,
        )

    def test_a_movement_records_what_its_quantity_was_counted_in(self):
        self.assertEqual(self._movement().unit_snapshot, "dozen")

    def test_changing_the_item_later_does_not_rewrite_history(self):
        # The whole point. Three dozen bought in March stays three dozen after
        # somebody switches the product to pieces in September.
        row = self._movement()

        self.item.unit = "piece"
        self.item.save(update_fields=["unit"])
        row.refresh_from_db()

        self.assertEqual(row.unit_snapshot, "dozen")

    def test_a_caller_that_knows_better_is_not_overridden(self):
        # A transfer or a correction may be recorded in a different unit from
        # the one the product currently sells in.
        self.assertEqual(self._movement(unit_snapshot="carton").unit_snapshot, "carton")

    def test_a_product_with_no_unit_records_no_unit(self):
        # Blank rather than a guess. "piece" would be inventing a fact, and an
        # invented fact in a ledger is worse than a gap somebody can see.
        plain = InventoryItem.objects.create(
            shop=self.shop, name="Rice", sku="RICE-1", sell_price=Decimal("60.00")
        )
        row = InventoryStockLedger.objects.create(
            shop=self.shop,
            item=plain,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("10"),
            occurred_at=timezone.now(),
        )

        self.assertEqual(row.unit_snapshot, "")

    def test_it_applies_to_every_kind_of_movement(self):
        # Eight places write stock movements - sale, return, purchase,
        # adjustment, opening balance, both halves of a transfer, stocktake.
        # This lives in save() so none of them has to remember.
        for event_type in (
            InventoryStockLedger.EventType.SALE,
            InventoryStockLedger.EventType.RETURN,
            InventoryStockLedger.EventType.ADJUSTMENT,
            InventoryStockLedger.EventType.TRANSFER_OUT,
            InventoryStockLedger.EventType.TRANSFER_IN,
        ):
            row = self._movement(event_type=event_type)
            self.assertEqual(row.unit_snapshot, "dozen", event_type)

    def test_stock_arithmetic_is_untouched(self):
        # The snapshot is a label on history, not an input to the sum. If it
        # started affecting stock levels it would be a far worse bug than the
        # one it prevents.
        self._movement(quantity_delta=Decimal("3"))
        self._movement(quantity_delta=Decimal("-1"))

        total = sum(
            row.quantity_delta
            for row in InventoryStockLedger.objects.filter(item=self.item)
        )
        self.assertEqual(total, Decimal("2"))

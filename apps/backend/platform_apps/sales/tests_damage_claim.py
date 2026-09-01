"""A return where the goods do not come back on the shelf.

Retail returns restock, and should: a shirt swapped for a larger size is
perfectly sellable and belongs back on the rail before the customer has left.

Wholesale has a case retail does not. A dealer receiving a torn or soiled lot
is credited for it, but the goods are scrap - nobody is selling them to anybody
else. Restocking them anyway inflates stock with items that cannot be sold, and
the shop only discovers it at the next stocktake months later, with no way to
tell which count was wrong.

So the money and the goods are separate decisions. The credit always happens;
the restock is a choice, and it defaults to what every existing client does.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.customers.models import Customer
from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.sales.models import Sale, SaleItem, SaleReturn
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class DamageClaimTests(TestCase):
    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="wholesaler@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Garment Wholesaler", slug="gw-returns")
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop,
            name="Design 4471 Kurta",
            sku="LOT-4471",
            unit="dozen",
            sell_price=Decimal("3000.00"),
        )
        InventoryStockLedger.objects.create(
            shop=self.shop,
            item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("20"),
            occurred_at=timezone.now(),
        )

        # A named dealer, because a khata credit needs somebody to credit.
        self.dealer = Customer.objects.create(
            shop=self.shop, name="Sharma Traders", phone="9000000001"
        )
        self.sale = Sale.objects.create(
            shop=self.shop,
            customer=self.dealer,
            receipt_number="INV-1",
            payment_mode="CASH",
            total_amount=Decimal("9000.00"),
            amount_received=Decimal("9000.00"),
            amount_due=Decimal("0.00"),
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
            status=Sale.Status.COMPLETED,
        )
        self.line = SaleItem.objects.create(
            sale=self.sale,
            inventory_item=self.item,
            name_snapshot="Design 4471 Kurta",
            quantity=Decimal("3"),
            unit_price=Decimal("3000.00"),
            unit_cost=Decimal("2000.00"),
            line_total=Decimal("9000.00"),
            position=0,
        )

        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.url = reverse("sale-return", args=[self.shop.id, self.sale.id])

    def _stock(self) -> Decimal:
        return sum(
            (row.quantity_delta for row in self.item.ledger_entries.all()),
            Decimal("0"),
        )

    def _return(self, **extra):
        payload = {
            "refund_mode": "CASH",
            "lines": [{"sale_item_id": str(self.line.id), "quantity": "1"}],
        }
        payload.update(extra)
        response = self.client.post(self.url, payload, format="json")
        self.assertIn(response.status_code, (200, 201), response.content)
        return response.json()

    def test_an_ordinary_return_still_puts_the_goods_back(self):
        # Unchanged behaviour, and the default. Every return written before
        # this existed did exactly this, and every client that has not been
        # updated still does.
        self._return()

        self.assertEqual(self._stock(), Decimal("21"))

    def test_a_damage_claim_does_not_put_the_goods_back(self):
        self._return(restock_goods=False)

        self.assertEqual(self._stock(), Decimal("20"))

    def test_a_damage_claim_still_credits_the_dealer(self):
        # The money and the goods are separate decisions. Refusing the credit
        # because the goods are scrap would leave the dealer paying for a lot
        # they cannot sell.
        body = self._return(restock_goods=False)

        self.assertEqual(Decimal(body["refund_amount"]), Decimal("3000.00"))

    def test_a_damage_claim_writes_no_stock_row_at_all(self):
        # Not a row of zero. A zero movement reads as "we checked and nothing
        # changed", when what happened is that goods were written off.
        self._return(restock_goods=False)

        self.assertFalse(
            self.item.ledger_entries.filter(
                event_type=InventoryStockLedger.EventType.RETURN
            ).exists()
        )

    def test_the_return_records_which_kind_it_was(self):
        # Months later, "why is this lot short" has to have an answer.
        body = self._return(restock_goods=False)

        self.assertIs(body["restock_goods"], False)
        self.assertFalse(SaleReturn.objects.get(id=body["id"]).restock_goods)

    def test_omitting_the_flag_restocks(self):
        # A client that predates this field - which is every phone in every
        # shop right now - must keep working, and must keep restocking.
        response = self.client.post(
            self.url,
            {
                "refund_mode": "CASH",
                "lines": [{"sale_item_id": str(self.line.id), "quantity": "1"}],
            },
            format="json",
        )

        self.assertIn(response.status_code, (200, 201))
        self.assertTrue(SaleReturn.objects.get(id=response.json()["id"]).restock_goods)

    def test_a_khata_damage_claim_reduces_what_the_dealer_owes(self):
        # The wholesale credit note: no money leaves the till, the dealer's
        # balance comes down, and the goods stay written off.
        body = self._return(refund_mode="KHATA", restock_goods=False)

        self.assertEqual(body["refund_mode"], "KHATA")
        self.assertEqual(self._stock(), Decimal("20"))

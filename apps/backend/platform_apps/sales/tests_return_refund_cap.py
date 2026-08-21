"""A shop must not pay out cash it never took.

The only refund-mode check was the reverse case: khata mode without a
customer. Nothing stopped a CASH refund against a bill sold entirely on credit
— and CASH is the form's default, so it was the likely outcome, not an edge
case.

The shop was then out real money AND still owed the full debt, because a
non-khata mode writes no CustomerLedgerEntry. Invisible until reconciliation,
if ever.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.customers.models import Customer
from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.sales.models import Sale, SaleItem
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class ReturnRefundCapTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="returns@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Return Shop", slug="return-shop", settings_json={"plan_tier": "pro"}
        )
        ShopMembership.objects.create(
            user=self.user, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.customer = Customer.objects.create(
            shop=self.shop, name="Khata Customer", phone="9800000001",
            balance=Decimal("2000.00"),
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Shirt", sku="SH-9", sell_price=Decimal("500.00")
        )
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("50"), occurred_at=timezone.now(),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def _sale(self, *, received: str, due: str, customer=True):
        sale = Sale.objects.create(
            shop=self.shop,
            customer=self.customer if customer else None,
            receipt_number=f"R-{Sale.objects.count() + 1}",
            status=Sale.Status.COMPLETED,
            subtotal_amount=Decimal("2000.00"),
            total_amount=Decimal("2000.00"),
            amount_received=Decimal(received),
            amount_due=Decimal(due),
            sale_date=timezone.now().date(),
            occurred_at=timezone.now(),
        )
        self.sale_item = SaleItem.objects.create(
            sale=sale, inventory_item=self.item,
            name_snapshot="Shirt", quantity=Decimal("4"),
            unit_price=Decimal("500.00"), line_total=Decimal("2000.00"),
            position=0,
        )
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.SALE,
            quantity_delta=Decimal("-4"), occurred_at=timezone.now(),
        )
        return sale

    def _return(self, sale, mode, quantity="1"):
        return self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/{sale.id}/return/",
            {
                "refund_mode": mode,
                "lines": [{"sale_item_id": str(self.sale_item.id), "quantity": quantity}],
            },
            format="json",
        )

    def test_a_cash_refund_on_a_fully_credit_sale_is_refused(self):
        """The exact loss: 500 paid out on a bill where nothing was collected,
        while the customer still owes the whole 2000."""
        sale = self._sale(received="0.00", due="2000.00")

        response = self._return(sale, "CASH")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn("khata", str(response.data).lower())

    def test_the_message_says_what_to_do_instead(self):
        """A cashier with a customer waiting needs the alternative, not just a
        refusal."""
        sale = self._sale(received="0.00", due="2000.00")

        response = self._return(sale, "CASH")

        body = str(response.data).lower()
        self.assertIn("exchange", body)

    def test_khata_refund_on_a_credit_sale_still_works(self):
        """The correct path must stay open, or the guard just blocks returns."""
        sale = self._sale(received="0.00", due="2000.00")

        response = self._return(sale, "KHATA")

        self.assertEqual(response.status_code, 201, response.data)

    def test_a_cash_refund_on_a_fully_paid_sale_still_works(self):
        """Most returns are this. Breaking them would be worse than the bug."""
        sale = self._sale(received="2000.00", due="0.00")

        response = self._return(sale, "CASH")

        self.assertEqual(response.status_code, 201, response.data)

    def test_a_partly_paid_sale_allows_a_refund_up_to_what_was_collected(self):
        sale = self._sale(received="500.00", due="1500.00")

        response = self._return(sale, "CASH")

        self.assertEqual(response.status_code, 201, response.data)

    def test_a_partly_paid_sale_refuses_more_than_was_collected(self):
        sale = self._sale(received="500.00", due="1500.00")

        response = self._return(sale, "CASH", quantity="2")

        self.assertEqual(response.status_code, 400, response.data)

    def test_a_second_cash_refund_cannot_exceed_the_remainder(self):
        """Two 500 returns against a bill where only 500 was collected: the
        first is fine, the second is the shop's money."""
        sale = self._sale(received="500.00", due="1500.00")
        first = self._return(sale, "CASH")
        self.assertEqual(first.status_code, 201, first.data)

        second = self._return(sale, "CASH")

        self.assertEqual(second.status_code, 400, second.data)

    def test_an_exchange_is_exempt_because_no_money_moves(self):
        sale = self._sale(received="0.00", due="2000.00")

        response = self._return(sale, "EXCHANGE")

        self.assertEqual(response.status_code, 201, response.data)

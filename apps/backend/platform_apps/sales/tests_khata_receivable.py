"""A credit sale has to leave the shop owed money.

Found by using the app rather than by reading it. A khata sale posted, the
sales screen said "still owed", and every other screen said nothing was owed:
the customer's ledger recorded +0, the dashboard said everyone had settled
up, and the day book counted the money as received. The shop silently forgot
what it was owed.

The cause was one idea in the wrong place - the till sends the khata portion
as a payment row so the bill is labelled CREDIT, and the server counted it as
money. Credit is the absence of payment.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from platform_apps.customers.models import Customer
from platform_apps.inventory.models import InventoryItem
from platform_apps.payments.models import SalePayment
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class KhataReceivableTests(TestCase):
    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="khata@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Khata Shop", slug="khata-shop")
        ShopMembership.objects.create(
            user=self.owner, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.customer = Customer.objects.create(
            shop=self.shop, name="Asha", phone="9876500123"
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Rice", sell_price=Decimal("285.00")
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.url = reverse("sale-list", args=[self.shop.id])

    def _sell(self, payments, quantity=2):
        return self.client.post(
            self.url,
            {
                "customer_id": str(self.customer.id),
                "subtotal_amount": "570.00",
                "total_amount": "570.00",
                "items": [
                    {
                        "inventory_item_id": str(self.item.id),
                        "quantity": quantity,
                        "unit_price": "285.00",
                    }
                ],
                "payments": payments,
            },
            format="json",
        )

    def test_a_whole_bill_on_khata_is_owed_in_full(self):
        response = self._sell([{"payment_method": "CREDIT", "amount": "570.00"}])
        self.assertEqual(response.status_code, 201, response.content)

        sale = Sale.objects.get()
        self.assertEqual(sale.amount_due, Decimal("570.00"))
        self.assertEqual(sale.amount_received, Decimal("0.00"))

        self.customer.refresh_from_db()
        self.assertEqual(self.customer.balance, Decimal("570.00"))

    def test_the_bill_is_still_labelled_credit(self):
        """The mode is why the row was sent at all - it must survive."""
        self._sell([{"payment_method": "CREDIT", "amount": "570.00"}])
        self.assertEqual(Sale.objects.get().payment_mode, Sale.PaymentMode.CREDIT)

    def test_no_payment_row_is_stored_for_credit(self):
        # Any sum over the payments table - takings, day book, payment mix -
        # would otherwise include money nobody handed over.
        self._sell([{"payment_method": "CREDIT", "amount": "570.00"}])
        self.assertEqual(SalePayment.objects.count(), 0)

    def test_part_paid_leaves_only_the_rest_owed(self):
        self._sell(
            [
                {"payment_method": "CASH", "amount": "200.00"},
                {"payment_method": "CREDIT", "amount": "370.00"},
            ]
        )
        sale = Sale.objects.get()
        self.assertEqual(sale.amount_received, Decimal("200.00"))
        self.assertEqual(sale.amount_due, Decimal("370.00"))
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.balance, Decimal("370.00"))

    def test_a_cash_sale_still_owes_nothing(self):
        self._sell([{"payment_method": "CASH", "amount": "570.00"}])
        self.assertEqual(Sale.objects.get().amount_due, Decimal("0.00"))
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.balance, Decimal("0.00"))

    def test_lifetime_spend_counts_the_whole_bill_either_way(self):
        """What they bought is not what they paid. Spend was already right,
        which is why the sale looked linked while the money was missing."""
        self._sell([{"payment_method": "CREDIT", "amount": "570.00"}])
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.total_spent, Decimal("570.00"))

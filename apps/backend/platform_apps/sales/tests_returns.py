from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.customers.models import Customer, CustomerLedgerEntry
from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.sales.models import Sale, SaleItem, SaleReturn
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


def stock_of(item: InventoryItem) -> Decimal:
    total = Decimal("0")
    for entry in InventoryStockLedger.objects.filter(item=item):
        total += entry.quantity_delta
    return total


class SaleReturnTests(TestCase):
    """Goods coming back against a bill.

    Voiding cancels a whole sale, which is the wrong tool for one shirt out of
    four, or a swap for a different size. The invariant throughout: a return
    puts back exactly what came back, never more, and money moves in whichever
    direction the original sale did.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="returns@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Return Shop", slug="return-shop")
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Cotton Shirt", sku="CS-1",
            sell_price=Decimal("500.00"),
        )
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("20"), occurred_at=timezone.now(),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    _receipt_seq = 0

    def _sale(self, *, qty="4", unit="500.00", line_total=None, customer=None,
              due="0", status_=Sale.Status.COMPLETED):
        # Receipt numbers are unique per shop, so each bill needs its own.
        type(self)._receipt_seq += 1
        total = Decimal(line_total or (Decimal(qty) * Decimal(unit)))
        sale = Sale.objects.create(
            shop=self.shop, customer=customer,
            receipt_number=f"R-{self._receipt_seq}",
            payment_mode="CREDIT" if customer else "CASH",
            total_amount=total,
            amount_received=total - Decimal(due),
            amount_due=Decimal(due),
            sale_date=timezone.localdate(), occurred_at=timezone.now(),
            status=status_,
        )
        item = SaleItem.objects.create(
            sale=sale, inventory_item=self.item, name_snapshot="Cotton Shirt",
            quantity=Decimal(qty), unit_price=Decimal(unit),
            line_total=total, position=0,
        )
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.SALE,
            quantity_delta=-Decimal(qty), occurred_at=timezone.now(),
        )
        return sale, item

    def _return(self, sale, lines, **extra):
        return self.client.post(
            reverse("sale-return", args=[self.shop.id, sale.id]),
            {"lines": lines, **extra},
            format="json",
        )

    def _returnable(self, sale):
        return self.client.get(
            reverse("sale-returnable", args=[self.shop.id, sale.id])
        ).data

    # --- the ordinary case -------------------------------------------------

    def test_a_partial_return_puts_back_only_what_came_back(self):
        sale, item = self._sale(qty="4")
        # 20 opening - 4 sold = 16
        self.assertEqual(stock_of(self.item), Decimal("16"))

        response = self._return(
            sale, [{"sale_item_id": str(item.id), "quantity": "1"}]
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(stock_of(self.item), Decimal("17"))
        self.assertEqual(response.data["refund_amount"], "500.00")

    def test_the_bill_itself_is_untouched(self):
        """A return records what came back; it does not rewrite what was sold."""
        sale, item = self._sale(qty="4")

        self._return(sale, [{"sale_item_id": str(item.id), "quantity": "1"}])
        sale.refresh_from_db()

        self.assertEqual(sale.status, Sale.Status.COMPLETED)
        self.assertEqual(sale.total_amount, Decimal("2000.00"))

    def test_returning_the_rest_later_is_allowed(self):
        sale, item = self._sale(qty="4")
        self._return(sale, [{"sale_item_id": str(item.id), "quantity": "1"}])

        response = self._return(
            sale, [{"sale_item_id": str(item.id), "quantity": "3"}]
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(stock_of(self.item), Decimal("20"))

    # --- refusing to create stock ------------------------------------------

    def test_cannot_return_more_than_was_sold(self):
        sale, item = self._sale(qty="4")

        response = self._return(
            sale, [{"sale_item_id": str(item.id), "quantity": "5"}]
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(stock_of(self.item), Decimal("16"))

    def test_earlier_returns_count_against_the_remaining_quantity(self):
        """Otherwise four separate returns of one each could total eight."""
        sale, item = self._sale(qty="4")
        self._return(sale, [{"sale_item_id": str(item.id), "quantity": "3"}])

        response = self._return(
            sale, [{"sale_item_id": str(item.id), "quantity": "2"}]
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(stock_of(self.item), Decimal("19"))

    def test_the_same_item_twice_in_one_return_is_rejected(self):
        """Each line would pass the remaining check alone."""
        sale, item = self._sale(qty="4")

        response = self._return(sale, [
            {"sale_item_id": str(item.id), "quantity": "3"},
            {"sale_item_id": str(item.id), "quantity": "3"},
        ])

        self.assertEqual(response.status_code, 400)
        self.assertEqual(stock_of(self.item), Decimal("16"))

    def test_zero_and_negative_quantities_are_rejected(self):
        sale, item = self._sale(qty="4")

        for quantity in ("0", "-1"):
            with self.subTest(quantity=quantity):
                response = self._return(
                    sale, [{"sale_item_id": str(item.id), "quantity": quantity}]
                )
                self.assertEqual(response.status_code, 400)

    def test_cannot_return_against_a_voided_bill(self):
        """The void already put the stock back; doing it again doubles it."""
        sale, item = self._sale(qty="4", status_=Sale.Status.VOID)

        response = self._return(
            sale, [{"sale_item_id": str(item.id), "quantity": "1"}]
        )

        self.assertEqual(response.status_code, 400)

    def test_cannot_return_a_line_from_another_bill(self):
        sale_a, _ = self._sale(qty="4")
        sale_b, item_b = self._sale(qty="2")

        response = self._return(
            sale_a, [{"sale_item_id": str(item_b.id), "quantity": "1"}]
        )

        self.assertEqual(response.status_code, 404)

    # --- money --------------------------------------------------------------

    def test_refund_uses_the_price_actually_charged_not_the_shelf_price(self):
        """A discounted line refunds what the customer paid."""
        # Four at 500 list, but the line was discounted to 1,600 total = 400 each.
        sale, item = self._sale(qty="4", unit="500.00", line_total="1600.00")

        response = self._return(
            sale, [{"sale_item_id": str(item.id), "quantity": "1"}]
        )

        self.assertEqual(response.data["refund_amount"], "400.00")

    def test_a_khata_return_reduces_what_is_owed_rather_than_paying_out(self):
        customer = Customer.objects.create(
            shop=self.shop, name="Ramesh", balance=Decimal("2000.00")
        )
        sale, item = self._sale(qty="4", customer=customer, due="2000.00")

        response = self._return(
            sale, [{"sale_item_id": str(item.id), "quantity": "1"}],
            refund_mode="KHATA",
        )

        self.assertEqual(response.status_code, 201)
        customer.refresh_from_db()
        self.assertEqual(customer.balance, Decimal("1500.00"))
        self.assertTrue(
            CustomerLedgerEntry.objects.filter(
                customer=customer, amount_delta=Decimal("-500.00")
            ).exists()
        )

    def test_a_khata_return_needs_a_customer(self):
        sale, item = self._sale(qty="4")

        response = self._return(
            sale, [{"sale_item_id": str(item.id), "quantity": "1"}],
            refund_mode="KHATA",
        )

        self.assertEqual(response.status_code, 400)

    def test_an_exchange_moves_no_money_but_still_returns_the_stock(self):
        """The value carries into the replacement bill, so paying out as well
        would refund the customer twice."""
        sale, item = self._sale(qty="4")

        response = self._return(
            sale, [{"sale_item_id": str(item.id), "quantity": "1"}],
            refund_mode="EXCHANGE",
        )

        self.assertEqual(response.data["refund_amount"], "0.00")
        self.assertEqual(stock_of(self.item), Decimal("17"))

    def test_an_unknown_refund_method_is_rejected(self):
        sale, item = self._sale(qty="4")

        response = self._return(
            sale, [{"sale_item_id": str(item.id), "quantity": "1"}],
            refund_mode="BITCOIN",
        )

        self.assertEqual(response.status_code, 400)

    # --- what is still returnable -------------------------------------------

    def test_returnable_reports_what_is_left(self):
        sale, item = self._sale(qty="4")
        self._return(sale, [{"sale_item_id": str(item.id), "quantity": "1"}])

        body = self._returnable(sale)

        row = body["lines"][0]
        self.assertEqual(row["sold"], "4.000")
        self.assertEqual(row["returned"], "1.000")
        self.assertEqual(row["returnable"], "3.000")
        self.assertTrue(body["any_returnable"])

    def test_a_fully_returned_bill_says_so(self):
        """So the interface can decline to show a form that can only fail."""
        sale, item = self._sale(qty="4")
        self._return(sale, [{"sale_item_id": str(item.id), "quantity": "4"}])

        self.assertFalse(self._returnable(sale)["any_returnable"])

    # --- access -------------------------------------------------------------

    def test_another_shop_cannot_process_this_return(self):
        sale, item = self._sale(qty="4")
        stranger = PlatformUser.objects.create_user(
            email="nope-return@example.com", password="secret", full_name="No"
        )
        self.client.force_authenticate(user=stranger)

        response = self._return(
            sale, [{"sale_item_id": str(item.id), "quantity": "1"}]
        )

        self.assertEqual(response.status_code, 403)
        self.assertEqual(SaleReturn.objects.count(), 0)

    def test_signed_out_requests_are_rejected(self):
        sale, item = self._sale(qty="4")
        self.client.force_authenticate(user=None)

        response = self._return(
            sale, [{"sale_item_id": str(item.id), "quantity": "1"}]
        )

        self.assertEqual(response.status_code, 401)

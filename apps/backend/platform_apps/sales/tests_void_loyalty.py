"""Voiding a sale must undo the points it moved.

The void path rolled back stock and the khata balance and left loyalty
untouched, in both directions:

- Points REDEEMED stayed spent. A customer who paid with 100 points on a sale
  that was then voided simply lost them.
- Points EARNED stayed earned. Ringing a sale up and voiding it minted real
  redeemable value out of nothing, repeatably.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.customers.models import Customer, LoyaltyLedgerEntry
from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.sales.models import Sale, SaleItem
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class VoidReversesLoyaltyTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="void@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Void Shop", slug="void-shop", settings_json={"plan_tier": "pro"}
        )
        ShopMembership.objects.create(
            user=self.user, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.customer = Customer.objects.create(
            shop=self.shop, name="Loyal Customer", phone="9800000002",
            loyalty_points=150,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Soap", sku="SOAP-1", sell_price=Decimal("100.00")
        )
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("50"), occurred_at=timezone.now(),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def _sale_with_points(self, points_delta: int, event_type: str) -> Sale:
        sale = Sale.objects.create(
            shop=self.shop, customer=self.customer,
            receipt_number=f"V-{Sale.objects.count() + 1}",
            status=Sale.Status.COMPLETED,
            subtotal_amount=Decimal("100.00"), total_amount=Decimal("100.00"),
            amount_received=Decimal("100.00"), amount_due=Decimal("0.00"),
            sale_date=timezone.now().date(), occurred_at=timezone.now(),
        )
        SaleItem.objects.create(
            sale=sale, inventory_item=self.item, name_snapshot="Soap",
            quantity=Decimal("1"), unit_price=Decimal("100.00"),
            line_total=Decimal("100.00"), position=0,
        )
        self.customer.loyalty_points += points_delta
        self.customer.save(update_fields=["loyalty_points"])
        LoyaltyLedgerEntry.objects.create(
            shop=self.shop, customer=self.customer, event_type=event_type,
            points_delta=points_delta,
            balance_after=self.customer.loyalty_points,
            sale_id=sale.id, occurred_at=timezone.now(),
        )
        return sale

    def _void(self, sale):
        return self.client.patch(
            f"/api/v1/shops/{self.shop.id}/sales/{sale.id}/void/",
            {"reason": "mis-scanned"}, format="json",
        )

    def test_points_redeemed_on_a_voided_sale_are_given_back(self):
        """The customer paid with 100 points for a sale that never happened."""
        sale = self._sale_with_points(-100, LoyaltyLedgerEntry.EventType.REDEEMED)
        self.assertEqual(self.customer.loyalty_points, 50)

        response = self._void(sale)

        self.assertEqual(response.status_code, 200, response.content)
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.loyalty_points, 150)

    def test_points_earned_on_a_voided_sale_are_taken_back(self):
        """Otherwise ring-up-then-void mints redeemable value from nothing."""
        sale = self._sale_with_points(20, LoyaltyLedgerEntry.EventType.EARNED)
        self.assertEqual(self.customer.loyalty_points, 170)

        response = self._void(sale)

        self.assertEqual(response.status_code, 200, response.content)
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.loyalty_points, 150)

    def test_the_reversal_is_written_to_the_ledger_not_hidden(self):
        """The ledger exists so a disputed balance can be explained, and a
        vanished entry explains nothing."""
        sale = self._sale_with_points(20, LoyaltyLedgerEntry.EventType.EARNED)

        self._void(sale)

        adjustment = LoyaltyLedgerEntry.objects.filter(
            sale_id=sale.id,
            event_type=LoyaltyLedgerEntry.EventType.ADJUSTMENT,
        ).first()
        self.assertIsNotNone(adjustment)
        self.assertEqual(adjustment.points_delta, -20)
        self.assertIn("Void", adjustment.note)

    def test_the_balance_is_never_driven_negative(self):
        """A customer may already have spent the points earned on this bill.
        balance_after is a PositiveIntegerField besides."""
        sale = self._sale_with_points(20, LoyaltyLedgerEntry.EventType.EARNED)
        self.customer.loyalty_points = 5
        self.customer.save(update_fields=["loyalty_points"])

        response = self._void(sale)

        self.assertEqual(response.status_code, 200, response.content)
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.loyalty_points, 0)

    def test_a_sale_with_no_loyalty_activity_is_unaffected(self):
        """The guard must not invent an adjustment where nothing moved."""
        sale = Sale.objects.create(
            shop=self.shop, customer=self.customer,
            receipt_number="V-PLAIN", status=Sale.Status.COMPLETED,
            subtotal_amount=Decimal("100.00"), total_amount=Decimal("100.00"),
            amount_received=Decimal("100.00"), amount_due=Decimal("0.00"),
            sale_date=timezone.now().date(), occurred_at=timezone.now(),
        )
        SaleItem.objects.create(
            sale=sale, inventory_item=self.item, name_snapshot="Soap",
            quantity=Decimal("1"), unit_price=Decimal("100.00"),
            line_total=Decimal("100.00"), position=0,
        )
        before = self.customer.loyalty_points

        response = self._void(sale)

        self.assertEqual(response.status_code, 200, response.content)
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.loyalty_points, before)
        self.assertFalse(
            LoyaltyLedgerEntry.objects.filter(
                sale_id=sale.id,
                event_type=LoyaltyLedgerEntry.EventType.ADJUSTMENT,
            ).exists()
        )

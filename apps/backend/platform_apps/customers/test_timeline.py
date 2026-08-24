from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.customers.models import Customer, CustomerLedgerEntry
from platform_apps.sales.models import Sale, SaleItem
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class CustomerKhataTimelineTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="owner@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Demo Shop", slug="demo-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_timeline_computes_running_balance_newest_first(self):
        customer = Customer.objects.create(shop=self.shop, name="Rahul", balance=Decimal("60.00"))
        now = timezone.now()
        # Credit sale of 100, then a 40 part-payment.
        CustomerLedgerEntry.objects.create(
            shop=self.shop,
            customer=customer,
            event_type=CustomerLedgerEntry.EventType.SALE,
            amount_delta=Decimal("100.00"),
            total_spent_delta=Decimal("100.00"),
            occurred_at=now - timedelta(days=2),
        )
        CustomerLedgerEntry.objects.create(
            shop=self.shop,
            customer=customer,
            event_type=CustomerLedgerEntry.EventType.PAYMENT,
            amount_delta=Decimal("-40.00"),
            occurred_at=now - timedelta(days=1),
        )

        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/customers/{customer.id}/timeline/"
        )
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual(Decimal(str(body["balance"])), Decimal("60.00"))

        entries = body["entries"]
        self.assertEqual(len(entries), 2)
        # Newest-first: payment (running 60) then the credit sale (running 100).
        self.assertEqual(entries[0]["event_type"], "payment")
        self.assertEqual(Decimal(str(entries[0]["running_balance"])), Decimal("60.00"))
        self.assertEqual(entries[1]["event_type"], "sale")
        self.assertEqual(Decimal(str(entries[1]["running_balance"])), Decimal("100.00"))


class CustomerKhataTimelineItemsTests(TestCase):
    """A khata balance is only defensible if the customer can be shown what it
    is made of. The ledger has no foreign key to Sale, but every SALE entry is
    written with the sale's uuid in `source_id`, so the timeline can carry the
    lines. Entries written before that (and manual adjustments, which never had
    a sale) must degrade to a null `sale` rather than break."""

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="owner2@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Items Shop", slug="items-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.customer = Customer.objects.create(
            shop=self.shop, name="Rahul", balance=Decimal("100.00")
        )

    def _sale(self, **kwargs):
        now = timezone.now()
        return Sale.objects.create(
            shop=self.shop,
            customer=self.customer,
            receipt_number="S-1001",
            total_amount=Decimal("100.00"),
            amount_due=Decimal("100.00"),
            payment_mode=Sale.PaymentMode.CREDIT,
            sale_date=now.date(),
            occurred_at=now,
            **kwargs,
        )

    def _entry(self, source_id, event_type=CustomerLedgerEntry.EventType.SALE):
        return CustomerLedgerEntry.objects.create(
            shop=self.shop,
            customer=self.customer,
            event_type=event_type,
            amount_delta=Decimal("100.00"),
            total_spent_delta=Decimal("100.00"),
            note="Sale S-1001",
            occurred_at=timezone.now(),
            source_id=source_id,
        )

    def _timeline(self):
        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/customers/{self.customer.id}/timeline/"
        )
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()["entries"]

    def test_sale_entry_carries_the_lines_that_were_sold(self):
        sale = self._sale()
        SaleItem.objects.create(
            sale=sale,
            position=1,
            name_snapshot="Parle-G",
            sku_snapshot="PG-100",
            quantity=Decimal("2"),
            unit_price=Decimal("10.00"),
            line_total=Decimal("20.00"),
        )
        SaleItem.objects.create(
            sale=sale,
            position=0,
            name_snapshot="Rice 5kg",
            quantity=Decimal("1"),
            unit_price=Decimal("80.00"),
            line_total=Decimal("80.00"),
        )
        self._entry(str(sale.id))

        entry = self._timeline()[0]
        self.assertEqual(entry["sale"]["receipt_number"], "S-1001")
        names = [line["name"] for line in entry["sale"]["items"]]
        # Ordered as the cashier rang them up, not by insert time.
        self.assertEqual(names, ["Rice 5kg", "Parle-G"])
        self.assertEqual(Decimal(str(entry["sale"]["items"][1]["quantity"])), Decimal("2"))
        self.assertEqual(Decimal(str(entry["sale"]["items"][1]["line_total"])), Decimal("20.00"))

    def test_older_entry_without_a_sale_id_reports_no_items(self):
        self._entry("")
        self.assertIsNone(self._timeline()[0]["sale"])

    def test_opening_balance_never_claims_items(self):
        self._entry("", event_type=CustomerLedgerEntry.EventType.OPENING_BALANCE)
        self.assertIsNone(self._timeline()[0]["sale"])

    def test_non_uuid_source_id_from_an_import_does_not_break_the_timeline(self):
        self._entry("legacy-book-page-14")
        self.assertIsNone(self._timeline()[0]["sale"])

    def test_a_sale_from_another_shop_is_never_exposed(self):
        other_shop = Shop.objects.create(name="Other", slug="other-shop")
        other_customer = Customer.objects.create(shop=other_shop, name="Someone")
        now = timezone.now()
        foreign_sale = Sale.objects.create(
            shop=other_shop,
            customer=other_customer,
            receipt_number="S-9999",
            total_amount=Decimal("500.00"),
            sale_date=now.date(),
            occurred_at=now,
        )
        self._entry(str(foreign_sale.id))
        self.assertIsNone(self._timeline()[0]["sale"])

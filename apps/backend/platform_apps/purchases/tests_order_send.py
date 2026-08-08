from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem
from platform_apps.purchases.models import (
    PurchaseOrder,
    PurchaseOrderLine,
    Supplier,
)
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class PurchaseOrderSendTests(TestCase):
    """Emailing an order to the supplier.

    Recording an order told the supplier nothing, so the shop still had to
    communicate it some other way. These tests cover the parts that decide
    whether the email is useful or actively harmful: what it contains, what it
    must not contain, and whether the shop is told the truth about delivery.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="po-send@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Cloth House", slug="cloth-send")
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.supplier = Supplier.objects.create(
            shop=self.shop, name="Mills Ltd", email="mills@example.com"
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Cotton Shirt", sku="CS-1",
            sell_price=Decimal("999.00"),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    def _order(self, *, status=PurchaseOrder.Status.ORDERED, supplier=True,
               expected=None, note=""):
        order = PurchaseOrder.objects.create(
            shop=self.shop,
            supplier=self.supplier if supplier else None,
            supplier_name_snapshot="Mills Ltd" if supplier else "",
            reference="PO-TEST",
            status=status,
            note=note,
            expected_date=expected,
            ordered_at=timezone.now() if status != PurchaseOrder.Status.DRAFT else None,
        )
        PurchaseOrderLine.objects.create(
            order=order,
            inventory_item=self.item,
            name_snapshot="Cotton Shirt",
            sku_snapshot="CS-1",
            quantity_ordered=Decimal("10"),
            unit_cost=Decimal("300.00"),
        )
        return order

    def _send(self, order, **body):
        return self.client.post(
            reverse("purchase-order-send", args=[self.shop.id, order.id]),
            body,
            format="json",
        )

    # --- delivery outcome --------------------------------------------------

    def test_reports_that_nothing_was_sent_when_email_is_not_configured(self):
        """Tests run without an API key, and the shop must not be told 'sent'.

        A shop whose sending domain is unverified needs to know the supplier
        never received it, rather than waiting for goods that were never
        ordered.
        """
        response = self._send(self._order())

        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data["sent"])
        self.assertTrue(response.data["skipped"])
        self.assertIn("RESEND_API_KEY", response.data["detail"])

    def test_uses_the_suppliers_stored_address(self):
        response = self._send(self._order())

        self.assertEqual(response.data["to"], "mills@example.com")

    def test_an_explicit_address_overrides_the_stored_one(self):
        response = self._send(self._order(), email="other@example.com")

        self.assertEqual(response.data["to"], "other@example.com")

    def test_a_supplier_with_no_address_is_refused_with_a_usable_message(self):
        self.supplier.email = ""
        self.supplier.save()

        response = self._send(self._order())

        self.assertEqual(response.status_code, 400)
        self.assertIn("email", str(response.data).lower())

    # --- what the order says -----------------------------------------------

    def test_the_message_carries_what_the_supplier_needs_to_act(self):
        from platform_apps.purchases.order_views import _order_email_html

        order = self._order(expected=date.today() + timedelta(days=7),
                            note="Deliver to the rear entrance.")
        html, text = _order_email_html(order, list(order.lines.all()))

        for body in (html, text):
            self.assertIn("PO-TEST", body)
            self.assertIn("Cotton Shirt", body)
            self.assertIn("CS-1", body)
            self.assertIn("10", body)
            self.assertIn("300.00", body)
            self.assertIn("Cloth House", body)
        self.assertIn("rear entrance", text)

    def test_the_supplier_is_not_shown_the_shops_selling_price(self):
        """They are told the rate being paid, not the margin being made."""
        from platform_apps.purchases.order_views import _order_email_html

        order = self._order()
        html, text = _order_email_html(order, list(order.lines.all()))

        self.assertNotIn("999", html)
        self.assertNotIn("999", text)

    def test_a_plain_text_part_is_always_present(self):
        """Small-supplier mailboxes strip HTML, and an empty message is worse
        than no message."""
        from platform_apps.purchases.order_views import _order_email_html

        order = self._order()
        _, text = _order_email_html(order, list(order.lines.all()))

        self.assertGreater(len(text.strip()), 40)
        self.assertNotIn("<", text)

    # --- state -------------------------------------------------------------

    def test_a_cancelled_order_cannot_be_sent(self):
        response = self._send(self._order(status=PurchaseOrder.Status.CANCELLED))

        self.assertEqual(response.status_code, 400)

    def test_an_order_with_no_lines_is_refused(self):
        order = PurchaseOrder.objects.create(
            shop=self.shop, supplier=self.supplier, reference="PO-EMPTY",
            status=PurchaseOrder.Status.ORDERED, ordered_at=timezone.now(),
        )

        self.assertEqual(self._send(order).status_code, 400)

    def test_a_draft_stays_a_draft_when_the_email_did_not_go(self):
        """Sending is what places an order, so a failed send must not promote
        it — otherwise the shop believes a supplier was told."""
        order = self._order(status=PurchaseOrder.Status.DRAFT)

        response = self._send(order)

        self.assertFalse(response.data["sent"])
        order.refresh_from_db()
        self.assertEqual(order.status, PurchaseOrder.Status.DRAFT)

    # --- permissions -------------------------------------------------------

    def test_a_cashier_cannot_send_an_order(self):
        cashier = PlatformUser.objects.create_user(
            email="po-cashier@example.com", password="secret", full_name="C"
        )
        ShopMembership.objects.create(
            user=cashier, shop=self.shop,
            role=ShopMembership.Role.CASHIER,
            status=ShopMembership.Status.ACTIVE,
        )
        order = self._order()
        self.client.force_authenticate(user=cashier)

        self.assertEqual(self._send(order).status_code, 403)

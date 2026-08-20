"""A broken dashboard must not stop the till.

The projection refresh runs after the sale has already committed. It used to
raise straight through, so a failure there produced a 500 for a sale that was
in fact in the database. The cashier, told the sale failed, rings it up again —
and the shop's own till becomes the thing creating duplicate sales and
double-charging customers.

The dashboard is derived: every number on it rebuilds from the sales it
summarises, and a scheduled job rebuilds it anyway. The sale is not derived.
"""
from __future__ import annotations

from decimal import Decimal
from unittest.mock import patch
from uuid import uuid4

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser

# Where each view imported the helper into its own namespace.
SALES_TARGET = "platform_apps.sales.views.refresh_projection_after_write"
SERVICE_TARGET = "platform_apps.projections.services.refresh_shop_dashboard_projection"


class ProjectionFailureDuringSaleTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="degrade@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Degrade Shop", slug="degrade-shop", settings_json={"plan_tier": "pro"}
        )
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Loose Dal", sku="DAL-01",
            sell_price=Decimal("120.00"),
        )
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("50.000"), occurred_at=timezone.now(),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    @property
    def url(self):
        # The command-ingestion path, which is what the counter app syncs
        # through and the only sale path that refreshes the projection.
        return f"/api/v1/shops/{self.shop.id}/sales/commands/"

    def _payload(self, **sale_overrides):
        sale = {
            "customer_id": None,
            "subtotal_amount": "120.00",
            "discount_amount": "0.00",
            "total_amount": "120.00",
            "items": [
                {
                    "inventory_item_id": str(self.item.id),
                    "quantity": 1,
                    "unit_price": "120.00",
                }
            ],
            "payments": [{"payment_method": "CASH", "amount": "120.00"}],
        }
        sale.update(sale_overrides)
        return {
            "command_id": str(uuid4()),
            "base_domain_epoch": 1,
            "source_surface": "flutter_pos",
            "sale": sale,
        }

    def test_the_sale_still_succeeds_when_the_projection_blows_up(self):
        with patch(SERVICE_TARGET, side_effect=RuntimeError("projection DB down")):
            response = self.client.post(self.url, self._payload(), format="json")

        self.assertEqual(response.status_code, 201, response.data)
        # The half that actually matters: the money is recorded exactly once.
        self.assertEqual(Sale.objects.filter(shop=self.shop).count(), 1)
        sale = Sale.objects.get(shop=self.shop)
        self.assertEqual(sale.total_amount, Decimal("120.00"))

    def test_the_response_is_a_complete_sale_not_a_stub(self):
        """The till renders the receipt from this body. A 201 carrying nothing
        useful would be its own outage."""
        with patch(SERVICE_TARGET, side_effect=RuntimeError("projection DB down")):
            response = self.client.post(self.url, self._payload(), format="json")

        self.assertEqual(response.status_code, 201)
        self.assertIn("sale", response.data)
        self.assertEqual(str(response.data["sale"]["total_amount"]), "120.00")

    def test_the_failure_is_logged_at_error_rather_than_swallowed(self):
        """Degrading quietly is how a temporary fault becomes permanent."""
        with patch(SERVICE_TARGET, side_effect=RuntimeError("projection DB down")):
            with self.assertLogs("platform_apps.projections.services", level="ERROR") as logs:
                self.client.post(self.url, self._payload(), format="json")

        joined = "\n".join(logs.output)
        self.assertIn("projection refresh failed", joined.lower())
        # The shop id, so the log says which shop rather than that "a" shop broke.
        self.assertIn(str(self.shop.id), joined)
        # The original traceback, or the log tells you nothing you can fix.
        self.assertIn("RuntimeError", joined)

    def test_a_working_projection_is_still_refreshed(self):
        """Fail-open must not mean never-run."""
        with patch(SALES_TARGET) as refresh:
            self.client.post(self.url, self._payload(), format="json")
        refresh.assert_called_once()

    def test_a_real_sale_failure_is_still_reported(self):
        """The guard covers the projection only. A sale that genuinely cannot
        be written must still fail loudly — silently accepting an unsaved sale
        would be far worse than the bug being fixed."""
        payload = self._payload()
        payload["sale"]["items"][0]["quantity"] = 9999  # more than the 50 in stock
        response = self.client.post(self.url, payload, format="json")

        self.assertGreaterEqual(response.status_code, 400)
        self.assertEqual(Sale.objects.filter(shop=self.shop).count(), 0)


class ProjectionFailureDuringPaymentTests(TestCase):
    """The same hazard on the other write path that refreshes after commit."""

    def test_the_payment_path_uses_the_guarded_helper(self):
        from platform_apps.payments import views as payment_views

        self.assertTrue(
            hasattr(payment_views, "refresh_projection_after_write"),
            "payments/views.py must refresh through the guarded helper, or a "
            "failed projection will 500 a payment that was already taken.",
        )
        self.assertFalse(
            hasattr(payment_views, "refresh_shop_dashboard_projection"),
            "payments/views.py still imports the raising version.",
        )


class WeightedQuantityTests(TestCase):
    """Selling by weight, end to end.

    The web POS can now post 1.25 instead of 1. The column is
    DecimalField(decimal_places=3), but nothing had ever exercised a
    non-integer quantity through the API, so this pins the assumption the
    whole feature rests on: a grocer can ring up part of a kilo and the money
    comes out right.
    """

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="grocer@example.com", password="secret", full_name="Grocer"
        )
        self.shop = Shop.objects.create(
            name="Kirana", slug="kirana",
            settings_json={"plan_tier": "pro", "business_type": "grocery"},
        )
        ShopMembership.objects.create(
            user=self.user, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Toor Dal", sku="DAL-02",
            sell_price=Decimal("120.00"), unit="kg",
        )
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("50.000"), occurred_at=timezone.now(),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_a_fractional_quantity_is_stored_and_priced_correctly(self):
        url = f"/api/v1/shops/{self.shop.id}/sales/"
        response = self.client.post(
            url,
            {
                "customer_id": None,
                "items": [
                    {
                        "inventory_item_id": str(self.item.id),
                        "quantity": "1.250",
                        "unit_price": "120.00",
                    }
                ],
                "payments": [{"payment_method": "CASH", "amount": "150.00"}],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        sale = Sale.objects.get(shop=self.shop)
        line = sale.items.first()
        self.assertEqual(line.quantity, Decimal("1.250"))
        # 1.25 kg at 120/kg. If this were truncated to 1, the shop would be
        # giving away a quarter kilo on every weighed sale.
        self.assertEqual(sale.total_amount, Decimal("150.00"))

    def test_the_grocery_shop_has_weight_selling_on_by_default(self):
        self.assertIs(self.shop.enabled_features["weight_selling"], True)

    def test_the_unit_survives_to_the_api(self):
        """The POS labels the line "1.25 kg" from this field."""
        url = f"/api/v1/shops/{self.shop.id}/inventory/"
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        rows = response.data["results"] if isinstance(response.data, dict) else response.data
        self.assertEqual(rows[0]["unit"], "kg")

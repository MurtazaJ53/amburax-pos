"""A composition dealer must not charge GST, anywhere.

Under s.10 CGST Act a composition dealer cannot collect tax, issues a Bill of
Supply rather than a Tax Invoice, and files CMP-08/GSTR-4 rather than
GSTR-1/GSTR-3B. Nothing in this product knew that: it printed GST on every
bill and offered their accountant two returns they must not file.

The subtle half is the RECEIPT. Forcing the rate to zero when the sale is
recorded is not enough, because every client recomputes tax locally from its
own copy of the catalogue. The server would store zero while the customer was
handed paper showing CGST+SGST, and books disagreeing with the bill is worse
than the original fault. So the catalogue API masks the rate as well, which
reaches clients already installed without a release.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class CompositionShopTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="comp@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Composition Kirana", slug="comp-kirana",
            state_code="27", gstin="27AABCU9603R1ZM",
            settings_json={
                "plan_tier": "pro",
                "business_type": "grocery",
                "gst_registration_type": "composition",
            },
        )
        ShopMembership.objects.create(
            user=self.user, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Biscuits", sku="BISC-1",
            sell_price=Decimal("100.00"), gst_rate=Decimal("18.00"),
        )
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("50"), occurred_at=timezone.now(),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    # --- the shop itself --------------------------------------------------

    def test_the_shop_knows_it_cannot_collect_gst(self):
        self.assertEqual(self.shop.gst_registration_type, "composition")
        self.assertFalse(self.shop.collects_gst)

    def test_an_existing_shop_defaults_to_regular(self):
        """The live shops carry no such key. Deriving the default rather than
        storing it is what makes this need no migration and no backfill."""
        plain = Shop.objects.create(name="Plain", slug="plain-shop")
        self.assertEqual(plain.gst_registration_type, "regular")
        self.assertTrue(plain.collects_gst)

    # --- the sale ---------------------------------------------------------

    def test_a_sale_records_no_tax(self):
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "customer_id": None,
                "items": [{
                    "inventory_item_id": str(self.item.id),
                    "quantity": 1, "unit_price": "100.00",
                }],
                "payments": [{"payment_method": "CASH", "amount": "100.00"}],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        sale = Sale.objects.get(shop=self.shop)
        self.assertEqual(sale.tax_amount, Decimal("0.00"))
        self.assertEqual(sale.cgst_amount, Decimal("0.00"))
        self.assertEqual(sale.sgst_amount, Decimal("0.00"))
        self.assertEqual(sale.total_amount, Decimal("100.00"))

    def test_the_stored_product_rate_is_left_alone(self):
        """Composition status is annual and reversible. A shop crossing back to
        regular must not have to retype every rate."""
        self.item.refresh_from_db()
        self.assertEqual(self.item.gst_rate, Decimal("18.00"))

    # --- the catalogue clients read --------------------------------------

    def test_the_catalogue_api_serves_a_zero_rate(self):
        """The half that fixes printed receipts on clients already installed:
        they recompute tax from this payload."""
        response = self.client.get(f"/api/v1/shops/{self.shop.id}/inventory/")

        self.assertEqual(response.status_code, 200)
        rows = response.data["results"] if isinstance(response.data, dict) else response.data
        row = next(r for r in rows if r["sku"] == "BISC-1")
        self.assertEqual(str(row["gst_rate"]), "0.00")

    def test_the_rate_is_still_writable(self):
        """Masking the read must not make the field read-only — that would
        break product creation for every shop."""
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/inventory/",
            {"name": "New", "sku": "NEW-1", "sell_price": "50.00",
             "gst_rate": "12.00", "opening_stock": 5},
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        created = InventoryItem.objects.get(shop=self.shop, sku="NEW-1")
        self.assertEqual(created.gst_rate, Decimal("12.00"))

    # --- the returns ------------------------------------------------------

    def test_gstr1_is_refused_and_names_the_right_form(self):
        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/sales/export/gstr1/?month=8&year=2026"
        )

        self.assertEqual(response.status_code, 403)
        self.assertIn("CMP-08", str(response.data))

    def test_gstr3b_is_refused(self):
        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/sales/export/gstr3b/?month=8&year=2026"
        )
        self.assertEqual(response.status_code, 403)


class RegularShopUnaffectedTests(TestCase):
    """The live shops are all implicitly regular. Nothing may change for them —
    same rates, same receipts, same reports."""

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="reg@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Regular Shop", slug="regular-shop",
            settings_json={"plan_tier": "pro"},
        )
        ShopMembership.objects.create(
            user=self.user, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Biscuits", sku="BISC-2",
            sell_price=Decimal("100.00"), gst_rate=Decimal("18.00"),
        )
        InventoryStockLedger.objects.create(
            shop=self.shop, item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("50"), occurred_at=timezone.now(),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_the_catalogue_still_serves_the_real_rate(self):
        response = self.client.get(f"/api/v1/shops/{self.shop.id}/inventory/")
        rows = response.data["results"] if isinstance(response.data, dict) else response.data
        row = next(r for r in rows if r["sku"] == "BISC-2")
        self.assertEqual(Decimal(str(row["gst_rate"])), Decimal("18.00"))

    def test_a_sale_still_charges_tax(self):
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "customer_id": None,
                "items": [{
                    "inventory_item_id": str(self.item.id),
                    "quantity": 1, "unit_price": "100.00",
                }],
                "payments": [{"payment_method": "CASH", "amount": "100.00"}],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        sale = Sale.objects.get(shop=self.shop)
        self.assertGreater(sale.tax_amount, Decimal("0.00"))

    def test_gst_returns_are_still_available(self):
        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/sales/export/gstr1/?month=8&year=2026"
        )
        self.assertEqual(response.status_code, 200)


class GstRegistrationSettingsTests(TestCase):
    """A shop must be able to say what it is, and be believed."""

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="settings-gst@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Settable", slug="settable-shop", settings_json={"plan_tier": "pro"}
        )
        ShopMembership.objects.create(
            user=self.user, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/shops/{self.shop.id}/settings/"

    def test_it_reads_back_regular_by_default(self):
        body = self.client.get(self.url).json()
        self.assertEqual(body["gst_registration_type"], "regular")

    def test_a_shop_can_declare_itself_composition(self):
        response = self.client.patch(
            self.url, {"gst_registration_type": "composition"}, format="json"
        )

        self.assertEqual(response.status_code, 200, response.content)
        self.shop.refresh_from_db()
        self.assertFalse(self.shop.collects_gst)

    def test_switching_records_when_it_happened(self):
        """Bills before are Tax Invoices, bills after are Bills of Supply. An
        accountant reconciling a year needs the boundary."""
        self.client.patch(
            self.url, {"gst_registration_type": "composition"}, format="json"
        )

        self.shop.refresh_from_db()
        self.assertIn("gst_registration_changed_at", self.shop.settings_json)

    def test_an_unknown_type_is_refused_rather_than_coerced(self):
        response = self.client.patch(
            self.url, {"gst_registration_type": "sometimes"}, format="json"
        )

        self.assertEqual(response.status_code, 400)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.gst_registration_type, "regular")

    def test_it_is_not_writable_through_the_feature_toggles(self):
        """Everything in that map is override-able by design. Whether a shop
        may charge tax is not a preference."""
        response = self.client.patch(
            self.url,
            {"features": {"gst_registration_type": "regular"}},
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)

    def test_a_cashier_cannot_change_it(self):
        cashier = PlatformUser.objects.create_user(
            email="till@example.com", password="secret", full_name="Cashier"
        )
        ShopMembership.objects.create(
            user=cashier, shop=self.shop,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
        )
        client = APIClient()
        client.force_authenticate(user=cashier)

        response = client.patch(
            self.url, {"gst_registration_type": "composition"}, format="json"
        )

        self.assertEqual(response.status_code, 403)

from __future__ import annotations

from decimal import Decimal
import xml.etree.ElementTree as ET

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.common.migration import MigrationBridgeMode
from platform_apps.common.migration import MigrationCutoverStatus
from platform_apps.common.migration import MigrationDomain
from platform_apps.common.migration import MigrationWriteMaster
from platform_apps.customers.models import Customer
from platform_apps.customers.models import CustomerLedgerEntry
from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.jobs.models import MigrationDomainControl
from platform_apps.payments.models import SalePayment
from platform_apps.sales.models import Sale, SaleItem
from platform_apps.sales.models import SaleCommandReceipt
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class SalesApiTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(email="owner@example.com", password="secret", full_name="Owner")
        self.shop = Shop.objects.create(name="Demo Shop", slug="demo-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.customer = Customer.objects.create(
            shop=self.shop,
            name="Ayaan Retail",
            phone="9876543210",
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop,
            name="Cotton Shirt",
            sku="SKU-001",
            category="Shirts",
            sell_price=Decimal("500.00"),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_create_sale_creates_items_payments_and_ledgers(self):
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "customer_id": str(self.customer.id),
                "discount_amount": "50.00",
                "items": [
                    {
                        "inventory_item_id": str(self.item.id),
                        "quantity": 2,
                        "unit_price": "500.00",
                    }
                ],
                "payments": [
                    {
                        "payment_method": "CASH",
                        "amount": "700.00",
                    },
                    {
                        "payment_method": "CREDIT",
                        "amount": "250.00",
                    },
                ],
                "footer_note": "Visit again",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        sale = Sale.objects.get()
        self.assertEqual(sale.payment_mode, Sale.PaymentMode.SPLIT)
        self.assertEqual(sale.subtotal_amount, Decimal("1000.00"))
        self.assertEqual(sale.total_amount, Decimal("950.00"))
        # 700 was handed over; 250 went on the khata. This used to assert 950
        # received and nothing due - the shop was owed 250 and the test called
        # it settled, which is exactly the bug it was hiding.
        self.assertEqual(sale.amount_received, Decimal("700.00"))
        self.assertEqual(sale.amount_due, Decimal("250.00"))
        self.assertEqual(SaleItem.objects.filter(sale=sale).count(), 1)
        # One, not two. The credit row named the mode; it is not money, and a
        # stored payment row would inflate every sum taken over that table.
        self.assertEqual(SalePayment.objects.filter(sale=sale).count(), 1)
        self.assertEqual(
            InventoryStockLedger.objects.filter(item=self.item, event_type=InventoryStockLedger.EventType.SALE).count(),
            1,
        )
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.total_spent, Decimal("950.00"))
        # The receivable. Without this the customer owes nothing, the
        # dashboard says everyone has settled up, and the money is forgotten.
        self.assertEqual(self.customer.balance, Decimal("250.00"))
        self.assertEqual(
            CustomerLedgerEntry.objects.filter(customer=self.customer, event_type=CustomerLedgerEntry.EventType.SALE).count(),
            1,
        )

    def test_create_sale_accepts_fractional_quantity(self):
        # Sell 1.5 kg at Rs.60/kg = Rs.90; stock must decrement by exactly 1.5.
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [
                    {
                        "inventory_item_id": str(self.item.id),
                        "quantity": "1.5",
                        "unit_price": "60.00",
                    }
                ],
                "payments": [
                    {"payment_method": "CASH", "amount": "90.00"},
                ],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.content)
        sale = Sale.objects.get()
        self.assertEqual(sale.subtotal_amount, Decimal("90.00"))
        item = SaleItem.objects.get(sale=sale)
        self.assertEqual(item.quantity, Decimal("1.500"))
        self.assertEqual(item.line_total, Decimal("90.00"))
        ledger = InventoryStockLedger.objects.get(
            item=self.item,
            event_type=InventoryStockLedger.EventType.SALE,
        )
        self.assertEqual(ledger.quantity_delta, Decimal("-1.500"))

    def test_gstr3b_export_returns_rate_wise_summary(self):
        self.shop.state_code = "27"
        self.shop.gstin = "27ABCDE1234F1Z5"
        self.shop.save(update_fields=["state_code", "gstin"])
        self.item.gst_rate = Decimal("18.00")
        self.item.save(update_fields=["gst_rate"])
        self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [
                    {"inventory_item_id": str(self.item.id), "quantity": 1, "unit_price": "118.00"}
                ],
                "payments": [{"payment_method": "CASH", "amount": "118.00"}],
            },
            format="json",
        )
        today = timezone.localdate()
        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/sales/export/gstr3b/",
            {"month": today.month, "year": today.year},
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response["Content-Type"], "text/csv")
        body = response.content.decode()
        self.assertIn("Outward taxable supplies", body)
        self.assertIn("Total (3.1a)", body)
        self.assertIn("18.00", body)  # the tax rate row

    def test_gst_filing_pack_returns_zip_with_three_reports(self):
        import io
        import zipfile

        self.shop.state_code = "27"
        self.shop.gstin = "27ABCDE1234F1Z5"
        self.shop.save(update_fields=["state_code", "gstin"])
        self.item.gst_rate = Decimal("18.00")
        self.item.hsn_code = "1905"
        self.item.save(update_fields=["gst_rate", "hsn_code"])
        self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [{"inventory_item_id": str(self.item.id), "quantity": 2, "unit_price": "118.00"}],
                "payments": [{"payment_method": "CASH", "amount": "236.00"}],
            },
            format="json",
        )
        today = timezone.localdate()
        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/sales/export/gst-pack/",
            {"month": today.month, "year": today.year},
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response["Content-Type"], "application/zip")
        archive = zipfile.ZipFile(io.BytesIO(response.content))
        names = archive.namelist()
        self.assertEqual(len(names), 3)
        self.assertTrue(any(n.startswith("GSTR1_") for n in names))
        self.assertTrue(any(n.startswith("GSTR3B_") for n in names))
        hsn_name = next(n for n in names if n.startswith("HSN_summary_"))
        hsn = archive.read(hsn_name).decode()
        self.assertIn("1905", hsn)  # the HSN code appears in the summary

    def test_gst_filing_pack_blocks_cashier(self):
        cashier = PlatformUser.objects.create_user(
            email="cashier2@example.com", password="secret", full_name="Cashier"
        )
        ShopMembership.objects.create(
            user=cashier, shop=self.shop, role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
        )
        client = APIClient()
        client.force_authenticate(user=cashier)
        response = client.get(
            f"/api/v1/shops/{self.shop.id}/sales/export/gst-pack/",
            {"month": 1, "year": 2026},
        )
        self.assertEqual(response.status_code, 403, response.content)

    def test_gstr3b_export_blocks_cashier(self):
        cashier = PlatformUser.objects.create_user(
            email="cashier@example.com", password="secret", full_name="Cashier"
        )
        ShopMembership.objects.create(
            user=cashier, shop=self.shop, role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
        )
        client = APIClient()
        client.force_authenticate(user=cashier)
        response = client.get(
            f"/api/v1/shops/{self.shop.id}/sales/export/gstr3b/",
            {"month": 1, "year": 2026},
        )
        self.assertEqual(response.status_code, 403, response.content)

    def test_sale_computes_intra_state_gst_breakdown(self):
        self.shop.state_code = "27"
        self.shop.save(update_fields=["state_code"])
        taxed_item = InventoryItem.objects.create(
            shop=self.shop,
            name="GST Mug",
            sku="SKU-GST",
            sell_price=Decimal("118.00"),
            gst_rate=Decimal("18.00"),
            hsn_code="6912",
            price_includes_tax=True,
        )
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [
                    {
                        "inventory_item_id": str(taxed_item.id),
                        "quantity": 1,
                        "unit_price": "118.00",
                    }
                ],
                "payments": [{"payment_method": "CASH", "amount": "118.00"}],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.content)
        sale = Sale.objects.get(items__inventory_item=taxed_item)
        self.assertEqual(sale.taxable_amount, Decimal("100.00"))
        self.assertEqual(sale.tax_amount, Decimal("18.00"))
        self.assertEqual(sale.cgst_amount, Decimal("9.00"))
        self.assertEqual(sale.sgst_amount, Decimal("9.00"))
        self.assertEqual(sale.igst_amount, Decimal("0.00"))
        self.assertEqual(sale.place_of_supply_state, "27")
        line = sale.items.get(inventory_item=taxed_item)
        self.assertEqual(line.gst_rate, Decimal("18.00"))
        self.assertEqual(line.hsn_snapshot, "6912")
        self.assertEqual(line.tax_amount, Decimal("18.00"))

    def test_list_sales_for_shop(self):
        sale = Sale.objects.create(
            shop=self.shop,
            actor_user=self.user,
            receipt_number="S-DEMO0001",
            subtotal_amount=Decimal("500.00"),
            total_amount=Decimal("500.00"),
            amount_received=Decimal("500.00"),
            amount_due=Decimal("0.00"),
            payment_mode=Sale.PaymentMode.CASH,
            customer_name_snapshot="Walk-in",
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
        )
        SaleItem.objects.create(
            sale=sale,
            inventory_item=self.item,
            name_snapshot="Cotton Shirt",
            sku_snapshot="SKU-001",
            quantity=1,
            unit_price=Decimal("500.00"),
            line_total=Decimal("500.00"),
        )
        SalePayment.objects.create(
            sale=sale,
            shop=self.shop,
            actor_user=self.user,
            payment_method=SalePayment.PaymentMethod.CASH,
            amount=Decimal("500.00"),
            occurred_at=timezone.now(),
        )

        response = self.client.get(f"/api/v1/shops/{self.shop.id}/sales/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json()), 1)

    def test_sales_summary_hides_advanced_fields_for_growth_plan(self):
        self.shop.settings_json = {"plan_tier": "growth"}
        self.shop.save(update_fields=["settings_json", "updated_at"])
        Sale.objects.create(
            shop=self.shop,
            actor_user=self.user,
            receipt_number="S-GROWTH0001",
            subtotal_amount=Decimal("500.00"),
            total_amount=Decimal("500.00"),
            amount_received=Decimal("350.00"),
            amount_due=Decimal("150.00"),
            payment_mode=Sale.PaymentMode.SPLIT,
            customer_name_snapshot="Walk-in",
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
        )

        response = self.client.get(f"/api/v1/shops/{self.shop.id}/sales/summary/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["total_sales"], 1)
        self.assertEqual(response.data["gross_revenue"], "500.00")
        self.assertIsNone(response.data["outstanding_revenue"])
        self.assertIsNone(response.data["average_ticket"])

    def test_sales_summary_keeps_advanced_fields_for_pro_plan(self):
        self.shop.settings_json = {"plan_tier": "pro"}
        self.shop.save(update_fields=["settings_json", "updated_at"])
        Sale.objects.create(
            shop=self.shop,
            actor_user=self.user,
            receipt_number="S-PRO0001",
            subtotal_amount=Decimal("500.00"),
            total_amount=Decimal("500.00"),
            amount_received=Decimal("350.00"),
            amount_due=Decimal("150.00"),
            payment_mode=Sale.PaymentMode.SPLIT,
            customer_name_snapshot="Walk-in",
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
        )

        response = self.client.get(f"/api/v1/shops/{self.shop.id}/sales/summary/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["gross_revenue"], "500.00")
        self.assertEqual(response.data["outstanding_revenue"], "150.00")
        self.assertEqual(response.data["average_ticket"], "500.00")

    def _create_postgres_primary_control(self, domain: str, *, epoch: int = 4):
        return MigrationDomainControl.objects.create(
            shop=self.shop,
            domain=domain,
            write_master=MigrationWriteMaster.POSTGRES,
            bridge_mode=MigrationBridgeMode.FIREBASE_TO_POSTGRES,
            cutover_status=MigrationCutoverStatus.POSTGRES_PRIMARY,
            current_epoch=epoch,
            shadow_reads_enabled=True,
        )

    def test_sale_command_is_idempotent(self):
        for domain in [
            MigrationDomain.SALES,
            MigrationDomain.PAYMENTS,
            MigrationDomain.STOCK_LEDGER,
            MigrationDomain.CUSTOMER_LEDGER,
        ]:
            self._create_postgres_primary_control(domain)

        payload = {
            "command_id": "cmd-sale-001",
            "base_domain_epoch": 4,
            "source_surface": "flutter_pos",
            "sale": {
                "customer_id": str(self.customer.id),
                "discount_amount": "50.00",
                "items": [
                    {
                        "inventory_item_id": str(self.item.id),
                        "quantity": 2,
                        "unit_price": "500.00",
                    }
                ],
                "payments": [
                    {
                        "payment_method": "CASH",
                        "amount": "950.00",
                    }
                ],
            },
        }

        first = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/commands/",
            payload,
            format="json",
        )
        second = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/commands/",
            payload,
            format="json",
        )

        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 200)
        self.assertFalse(first.json()["duplicate"])
        self.assertTrue(second.json()["duplicate"])
        self.assertEqual(Sale.objects.count(), 1)
        self.assertEqual(SaleCommandReceipt.objects.count(), 1)

    def test_sale_command_rejects_legacy_write_owner(self):
        MigrationDomainControl.objects.create(
            shop=self.shop,
            domain=MigrationDomain.SALES,
            write_master=MigrationWriteMaster.FIREBASE,
            bridge_mode=MigrationBridgeMode.COMPARE_ONLY,
            cutover_status=MigrationCutoverStatus.LEGACY,
            current_epoch=1,
            shadow_reads_enabled=True,
        )

        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/commands/",
            {
                "command_id": "cmd-sale-blocked",
                "base_domain_epoch": 1,
                "sale": {
                    "items": [
                        {
                            "inventory_item_id": str(self.item.id),
                            "quantity": 1,
                            "unit_price": "500.00",
                        }
                    ],
                    "payments": [
                        {
                            "payment_method": "CASH",
                            "amount": "500.00",
                        }
                    ],
                },
            },
            format="json",
        )

        self.assertEqual(response.status_code, 409)

    def test_sale_command_rejects_stale_epoch(self):
        for domain in [
            MigrationDomain.SALES,
            MigrationDomain.PAYMENTS,
            MigrationDomain.STOCK_LEDGER,
        ]:
            self._create_postgres_primary_control(domain, epoch=7)

        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/commands/",
            {
                "command_id": "cmd-sale-stale",
                "base_domain_epoch": 3,
                "sale": {
                    "items": [
                        {
                            "inventory_item_id": str(self.item.id),
                            "quantity": 1,
                            "unit_price": "500.00",
                        }
                    ],
                    "payments": [
                        {
                            "payment_method": "CASH",
                            "amount": "500.00",
                        }
                    ],
                },
            },
            format="json",
        )

        self.assertEqual(response.status_code, 409)

    def test_direct_sale_create_is_blocked_when_sales_control_is_legacy(self):
        MigrationDomainControl.objects.create(
            shop=self.shop,
            domain=MigrationDomain.SALES,
            write_master=MigrationWriteMaster.FIREBASE,
            bridge_mode=MigrationBridgeMode.COMPARE_ONLY,
            cutover_status=MigrationCutoverStatus.LEGACY,
            current_epoch=1,
            shadow_reads_enabled=True,
        )

        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [
                    {
                        "inventory_item_id": str(self.item.id),
                        "quantity": 1,
                        "unit_price": "500.00",
                    }
                ],
                "payments": [
                    {
                        "payment_method": "CASH",
                        "amount": "500.00",
                    }
                ],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 409)

    def test_sale_void_reverses_inventory_and_customer_balances(self):
        sale = Sale.objects.create(
            shop=self.shop,
            actor_user=self.user,
            customer=self.customer,
            receipt_number="S-VOID001",
            subtotal_amount=Decimal("500.00"),
            total_amount=Decimal("500.00"),
            amount_received=Decimal("0.00"),
            amount_due=Decimal("500.00"),
            payment_mode=Sale.PaymentMode.CREDIT,
            customer_name_snapshot="Ayaan Retail",
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
        )
        SaleItem.objects.create(
            sale=sale,
            inventory_item=self.item,
            quantity=1,
            unit_price=Decimal("500.00"),
            line_total=Decimal("500.00"),
        )
        self.customer.balance = Decimal("500.00")
        self.customer.total_spent = Decimal("500.00")
        self.customer.save()

        response = self.client.patch(f"/api/v1/shops/{self.shop.id}/sales/{sale.id}/void/")
        
        self.assertEqual(response.status_code, 200)
        sale.refresh_from_db()
        self.assertEqual(sale.status, Sale.Status.VOID)
        
        # Verify customer ledger reversed
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.balance, Decimal("0.00"))
        self.assertEqual(self.customer.total_spent, Decimal("0.00"))
        
        # Verify inventory reversed
        ledger = InventoryStockLedger.objects.filter(item=self.item, event_type=InventoryStockLedger.EventType.RETURN).first()
        self.assertIsNotNone(ledger)
        self.assertEqual(ledger.quantity_delta, 1)

    def test_sale_gst_summary_endpoint(self):
        self.shop.state_code = "27"
        self.shop.save()
        
        taxed_item = InventoryItem.objects.create(
            shop=self.shop,
            name="GST Mug",
            sell_price=Decimal("118.00"),
            gst_rate=Decimal("18.00"),
            hsn_code="6912",
            price_includes_tax=True,
        )
        
        # Create an intra-state sale
        self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [{"inventory_item_id": str(taxed_item.id), "quantity": 1, "unit_price": "118.00"}],
                "payments": [{"payment_method": "CASH", "amount": "118.00"}],
            },
            format="json",
        )
        
        response = self.client.get(f"/api/v1/shops/{self.shop.id}/sales/summary/gst/")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        self.assertEqual(data["taxable_amount"], "100.00")
        self.assertEqual(data["cgst_amount"], "9.00")
        self.assertEqual(data["sgst_amount"], "9.00")
        
        # Verify B2C small and HSN summary lists
        self.assertEqual(len(data["b2c_small"]), 1)
        self.assertEqual(float(data["b2c_small"][0]["items__gst_rate"]), 18.0)
        self.assertEqual(float(data["b2c_small"][0]["taxable_amount"]), 100.0)
        
        self.assertEqual(len(data["hsn_summary"]), 1)
        self.assertEqual(data["hsn_summary"][0]["items__hsn_snapshot"], "6912")
        self.assertEqual(float(data["hsn_summary"][0]["tax_amount"]), 18.0)

    def test_sale_inter_state_place_of_supply(self):
        self.shop.state_code = "27"
        self.shop.save()
        
        taxed_item = InventoryItem.objects.create(
            shop=self.shop,
            name="GST Mug",
            sell_price=Decimal("118.00"),
            gst_rate=Decimal("18.00"),
            price_includes_tax=True,
        )
        
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "place_of_supply_state": "29",  # Karnataka (Inter-state from 27)
                "items": [{"inventory_item_id": str(taxed_item.id), "quantity": 1, "unit_price": "118.00"}],
                "payments": [{"payment_method": "CASH", "amount": "118.00"}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        sale = Sale.objects.get(receipt_number=response.json()["receipt_number"])
        self.assertEqual(sale.place_of_supply_state, "29")
        self.assertEqual(sale.igst_amount, Decimal("18.00"))
        self.assertEqual(sale.cgst_amount, Decimal("0.00"))


class PerItemDiscountTests(TestCase):
    """A cashier can discount one line of a multi-item bill; the sale-level
    discount still applies on top of what remains."""

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="disc@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Disc Shop", slug="disc-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.a = InventoryItem.objects.create(
            shop=self.shop, name="Item A", sku="A1", sell_price=Decimal("100.00")
        )
        self.b = InventoryItem.objects.create(
            shop=self.shop, name="Item B", sku="B1", sell_price=Decimal("100.00")
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_per_item_discount_applies_only_to_that_line(self):
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [
                    {
                        "inventory_item_id": str(self.a.id),
                        "quantity": 1,
                        "unit_price": "100.00",
                        "discount": "20.00",
                    },
                    {
                        "inventory_item_id": str(self.b.id),
                        "quantity": 1,
                        "unit_price": "100.00",
                    },
                ],
                "payments": [{"payment_method": "CASH", "amount": "10.00"}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)
        sale = Sale.objects.get()
        a_item = sale.items.get(name_snapshot="Item A")
        b_item = sale.items.get(name_snapshot="Item B")
        self.assertEqual(a_item.line_discount, Decimal("20.00"))
        self.assertEqual(b_item.line_discount, Decimal("0.00"))

    def test_per_item_discount_is_capped_at_the_line_total(self):
        # Rs.500 off a Rs.100 line can only take Rs.100 — it must never spill
        # over and discount the rest of the bill.
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [
                    {
                        "inventory_item_id": str(self.a.id),
                        "quantity": 1,
                        "unit_price": "100.00",
                        "discount": "500.00",
                    },
                    {
                        "inventory_item_id": str(self.b.id),
                        "quantity": 1,
                        "unit_price": "100.00",
                    },
                ],
                "payments": [{"payment_method": "CASH", "amount": "100.00"}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)
        sale = Sale.objects.get()
        self.assertEqual(
            sale.items.get(name_snapshot="Item A").line_discount, Decimal("100.00")
        )
        self.assertEqual(sale.total_amount, Decimal("100.00"))
        self.assertEqual(sale.amount_due, Decimal("0.00"))

    def test_sale_discount_stacks_on_top_of_item_discount(self):
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "discount_amount": "30.00",
                "items": [
                    {
                        "inventory_item_id": str(self.a.id),
                        "quantity": 1,
                        "unit_price": "100.00",
                        "discount": "20.00",
                    },
                    {
                        "inventory_item_id": str(self.b.id),
                        "quantity": 1,
                        "unit_price": "100.00",
                    },
                ],
                "payments": [{"payment_method": "CASH", "amount": "10.00"}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)
        sale = Sale.objects.get()
        total_line_discount = sum(i.line_discount for i in sale.items.all())
        # 20 item-level + 30 sale-level spread over the remaining 80/100.
        self.assertEqual(total_line_discount, Decimal("50.00"))
        self.assertGreater(sale.items.get(name_snapshot="Item A").line_discount, Decimal("20.00"))


class PerItemDiscountTotalsTests(TestCase):
    """Regression: a per-item discount must reduce what the customer OWES.
    It previously only tagged line_discount, so a Rs.100 item discount on a
    Rs.300 bill left total=300 and turned the discount into a Rs.100 'due'."""

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="tot@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Tot Shop", slug="tot-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Woolen Caps Kids", sku="W1", sell_price=Decimal("100.00")
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def _line(self, discount=None):
        line = {
            "inventory_item_id": str(self.item.id),
            "quantity": 1,
            "unit_price": "100.00",
        }
        if discount is not None:
            line["discount"] = discount
        return line

    def test_item_discount_reduces_total_and_leaves_no_due(self):
        # 3 x Rs.100 = Rs.300, Rs.100 off one line, pay Rs.200 -> nothing due.
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [self._line("100.00"), self._line(), self._line()],
                "payments": [{"payment_method": "UPI", "amount": "200.00"}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)
        sale = Sale.objects.get()
        self.assertEqual(sale.subtotal_amount, Decimal("300.00"))
        self.assertEqual(sale.total_amount, Decimal("200.00"))
        self.assertEqual(sale.discount_amount, Decimal("100.00"))
        self.assertEqual(sale.amount_received, Decimal("200.00"))
        self.assertEqual(sale.amount_due, Decimal("0.00"))

    def test_paying_full_gross_over_an_item_discount_is_rejected(self):
        # Rs.300 tendered on a Rs.200 bill must not be silently accepted.
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [self._line("100.00"), self._line(), self._line()],
                "payments": [{"payment_method": "UPI", "amount": "300.00"}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400, response.content)

    def test_item_and_bill_discount_combine_into_stored_discount(self):
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "discount_amount": "50.00",
                "items": [self._line("100.00"), self._line(), self._line()],
                "payments": [{"payment_method": "CASH", "amount": "150.00"}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)
        sale = Sale.objects.get()
        self.assertEqual(sale.total_amount, Decimal("150.00"))
        self.assertEqual(sale.discount_amount, Decimal("150.00"))
        self.assertEqual(sale.amount_due, Decimal("0.00"))
        # Stored discount must equal what the lines actually absorbed.
        self.assertEqual(
            sum(i.line_discount for i in sale.items.all()), Decimal("150.00")
        )


class SaleItemOrderingTests(TestCase):
    """Receipt lines must come back in the order the cashier rang them up.

    Regression: every line of a sale is inserted in one tight loop, so
    auto_now_add gave them the same created_at and ordering by it returned an
    arbitrary order — receipts listed items in neither entry nor alphabetical
    order.
    """

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="order@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Order Shop", slug="order-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        # Deliberately NOT alphabetical, so alphabetical ordering would fail.
        self.names = ["Zeta", "Alpha", "Mango", "Beta", "Kiwi", "Delta", "Omega"]

    def _create_sale(self):
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [
                    {"name": n, "quantity": 1, "unit_price": "10.00"}
                    for n in self.names
                ],
                "payments": [{"payment_method": "CASH", "amount": "70.00"}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)
        return response

    def test_items_are_stored_with_their_entry_position(self):
        self._create_sale()
        sale = Sale.objects.get()
        ordered = list(sale.items.order_by("position").values_list("name_snapshot", flat=True))
        self.assertEqual(ordered, self.names)

    def test_sale_detail_returns_items_in_entry_order(self):
        self._create_sale()
        sale = Sale.objects.get()
        detail = self.client.get(f"/api/v1/shops/{self.shop.id}/sales/{sale.id}/")
        self.assertEqual(detail.status_code, 200, detail.content)
        self.assertEqual([i["name"] for i in detail.json()["items"]], self.names)

    def test_sale_list_returns_items_in_entry_order(self):
        self._create_sale()
        listing = self.client.get(f"/api/v1/shops/{self.shop.id}/sales/")
        self.assertEqual(listing.status_code, 200, listing.content)
        rows = listing.json()
        rows = rows["results"] if isinstance(rows, dict) else rows
        self.assertEqual([i["name"] for i in rows[0]["items"]], self.names)


class TallyExportTests(TestCase):
    """A Tally voucher that doesn't balance is rejected on import — or worse,
    imported wrong. Debits must equal credits on every voucher."""

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="tally@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Tally Shop", slug="tally-shop", gstin="24ABCDE1234F1Z5"
        )
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Shirt", sku="S1", sell_price=Decimal("118.00"),
            gst_rate=Decimal("18.00"),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def _sale(self, amount="118.00"):
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [
                    {
                        "inventory_item_id": str(self.item.id),
                        "quantity": 1,
                        "unit_price": amount,
                    }
                ],
                "payments": [{"payment_method": "CASH", "amount": amount}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)

    def _export(self):
        response = self.client.get(
            f"/api/v1/shops/{self.shop.id}/sales/tally-export/"
        )
        self.assertEqual(response.status_code, 200, response.content)
        return response

    def test_export_is_well_formed_tally_xml(self):
        self._sale()
        response = self._export()
        self.assertEqual(response["Content-Type"], "application/xml")
        self.assertIn("attachment;", response["Content-Disposition"])

        body = response.content.decode()
        root = ET.fromstring(body)
        self.assertEqual(root.tag, "ENVELOPE")
        self.assertEqual(root.findtext("./HEADER/TALLYREQUEST"), "Import Data")
        self.assertEqual(len(root.findall(".//VOUCHER")), 1)

    def test_every_voucher_balances(self):
        self._sale()
        self._sale("236.00")
        root = ET.fromstring(self._export().content.decode())
        vouchers = root.findall(".//VOUCHER")
        self.assertEqual(len(vouchers), 2)
        for voucher in vouchers:
            total = sum(
                Decimal(entry.findtext("AMOUNT"))
                for entry in voucher.findall("ALLLEDGERENTRIES.LIST")
            )
            self.assertEqual(
                total,
                Decimal("0.00"),
                f"voucher {voucher.findtext('VOUCHERNUMBER')} does not balance",
            )

    def test_debit_is_negative_and_credit_positive(self):
        self._sale()
        root = ET.fromstring(self._export().content.decode())
        entries = root.findall(".//ALLLEDGERENTRIES.LIST")
        debits = [e for e in entries if e.findtext("ISDEEMEDPOSITIVE") == "Yes"]
        credits = [e for e in entries if e.findtext("ISDEEMEDPOSITIVE") == "No"]
        self.assertTrue(debits and credits)
        # Tally's sign convention: reversing this silently flips every entry.
        for entry in debits:
            self.assertLess(Decimal(entry.findtext("AMOUNT")), 0)
        for entry in credits:
            self.assertGreater(Decimal(entry.findtext("AMOUNT")), 0)

    def test_tax_is_posted_to_its_own_ledgers(self):
        self._sale()
        body = self._export().content.decode()
        self.assertIn("Output CGST", body)
        self.assertIn("Output SGST", body)
        self.assertIn("Sales Account", body)

    def test_voided_sales_are_excluded(self):
        self._sale()
        sale = Sale.objects.get()
        self.client.patch(
            f"/api/v1/shops/{self.shop.id}/sales/{sale.id}/void/", {}, format="json"
        )
        root = ET.fromstring(self._export().content.decode())
        # A refunded bill in the CA's books would overstate revenue.
        self.assertEqual(len(root.findall(".//VOUCHER")), 0)

    def test_a_customer_name_with_an_ampersand_does_not_break_the_xml(self):
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "customer_name": "Ram & Sons <Traders>",
                "items": [
                    {
                        "inventory_item_id": str(self.item.id),
                        "quantity": 1,
                        "unit_price": "118.00",
                    }
                ],
                "payments": [{"payment_method": "CASH", "amount": "118.00"}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)
        root = ET.fromstring(self._export().content.decode())
        self.assertEqual(
            root.findtext(".//PARTYLEDGERNAME"), "Ram & Sons <Traders>"
        )

    def test_staff_cannot_export_the_books(self):
        staff = PlatformUser.objects.create_user(
            email="staff-tally@example.com", password="secret", full_name="Staff"
        )
        ShopMembership.objects.create(
            user=staff,
            shop=self.shop,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
        )
        client = APIClient()
        client.force_authenticate(user=staff)
        response = client.get(f"/api/v1/shops/{self.shop.id}/sales/tally-export/")
        self.assertEqual(response.status_code, 403)


class StaffPerformanceTests(TestCase):
    """Attribution decides who gets credit (and blame) for a shop's takings, so
    it must never invent a split it can't justify."""

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="perf-owner@example.com", password="secret", full_name="Owner Ben"
        )
        self.staff = PlatformUser.objects.create_user(
            email="perf-staff@example.com", password="secret", full_name="Staff Sam"
        )
        self.shop = Shop.objects.create(name="Perf Shop", slug="perf-shop")
        for user, role in ((self.owner, ShopMembership.Role.OWNER),
                           (self.staff, ShopMembership.Role.STAFF)):
            ShopMembership.objects.create(
                user=user, shop=self.shop, role=role,
                status=ShopMembership.Status.ACTIVE,
            )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Shirt", sku="S1", sell_price=Decimal("100.00")
        )

    def _sell(self, user, amount="100.00"):
        client = APIClient()
        client.force_authenticate(user=user)
        response = client.post(
            f"/api/v1/shops/{self.shop.id}/sales/",
            {
                "items": [{
                    "inventory_item_id": str(self.item.id),
                    "quantity": 1,
                    "unit_price": amount,
                }],
                "payments": [{"payment_method": "CASH", "amount": amount}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)

    def _report(self, user=None):
        client = APIClient()
        client.force_authenticate(user=user or self.owner)
        response = client.get(
            f"/api/v1/shops/{self.shop.id}/sales/staff-performance/"
        )
        return response

    def test_splits_takings_by_who_sold(self):
        self._sell(self.owner, "100.00")
        self._sell(self.staff, "250.00")
        self._sell(self.staff, "150.00")

        response = self._report()
        self.assertEqual(response.status_code, 200, response.content)
        rows = {r["name"]: r for r in response.json()}

        self.assertEqual(rows["Staff Sam"]["sale_count"], 2)
        self.assertEqual(Decimal(rows["Staff Sam"]["gross"]), Decimal("400.00"))
        self.assertEqual(rows["Owner Ben"]["sale_count"], 1)

    def test_ordered_by_takings(self):
        self._sell(self.owner, "100.00")
        self._sell(self.staff, "900.00")
        names = [r["name"] for r in self._report().json()]
        self.assertEqual(names[0], "Staff Sam")

    def test_average_ticket_is_per_person(self):
        self._sell(self.staff, "100.00")
        self._sell(self.staff, "300.00")
        row = self._report().json()[0]
        self.assertEqual(Decimal(row["average_ticket"]), Decimal("200.00"))

    def test_voided_sales_do_not_count_towards_anyone(self):
        self._sell(self.staff, "500.00")
        sale = Sale.objects.get()
        client = APIClient()
        client.force_authenticate(user=self.owner)
        client.patch(
            f"/api/v1/shops/{self.shop.id}/sales/{sale.id}/void/", {}, format="json"
        )
        # A refunded sale must not leave someone credited for revenue the shop
        # gave back.
        self.assertEqual(self._report().json(), [])

    def test_a_cashier_cannot_see_everyone_takings(self):
        self._sell(self.staff)
        response = self._report(user=self.staff)
        self.assertEqual(response.status_code, 403, response.content)

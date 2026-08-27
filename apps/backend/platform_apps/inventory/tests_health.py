from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.common.query import DEFAULT_LIST_LIMIT
from platform_apps.customers.models import Customer
from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class DataHealthTests(TestCase):
    """The rules here exist three times — Dart, TypeScript and Python — and an
    owner who cleans up on one surface must not be told there is still a
    problem on another."""

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="health@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Health Shop", slug="health-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/shops/{self.shop.id}/reports/data-health/"

    def _item(self, name, *, sku="", size="", stock=0, sell="100.00"):
        item = InventoryItem.objects.create(
            shop=self.shop, name=name, sku=sku, size=size, sell_price=Decimal(sell)
        )
        if stock:
            InventoryStockLedger.objects.create(
                shop=self.shop,
                item=item,
                event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
                quantity_delta=Decimal(str(stock)),
                occurred_at=timezone.now(),
            )
        return item

    def _scan(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 200, response.content[:2000])
        return response.json()

    # --- the bug this endpoint exists to fix ------------------------------

    def test_scans_past_the_list_endpoint_row_cap(self):
        # The browser version read /inventory/, which slices to 200 rows, so a
        # larger catalog was silently half-scanned while the page claimed a
        # full sweep. Build more than the cap, all duplicates of one product.
        count = DEFAULT_LIST_LIMIT + 40
        for _ in range(count):
            self._item("Chadda", stock=1)

        body = self._scan()
        self.assertEqual(body["scanned_items"], count)
        self.assertEqual(body["duplicate_groups"][0]["copies"], count)
        self.assertEqual(body["duplicate_row_count"], count - 1)

    # --- duplicate rules ---------------------------------------------------

    def test_two_products_can_no_longer_share_a_code(self):
        """This used to be a duplicate for the scan to find. It is now
        impossible to create, which is the better outcome - and the case
        differs on purpose, because the index is case-folded and a scan
        resolves ABC-1 and abc-1 to the same thing."""
        from django.db import IntegrityError, transaction

        self._item("Cotton Shirt", sku="ABC-1")
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                self._item("cotton shirt (new)", sku="abc-1")

    def test_does_not_merge_different_sizes_of_one_garment(self):
        # S and XL are different products. Merging them destroys the size
        # breakdown and produces one row with impossible stock.
        self._item("Kurta", size="S")
        self._item("Kurta", size="XL")
        self.assertEqual(self._scan()["duplicate_groups"], [])

    def test_matches_on_name_and_size_without_a_sku(self):
        self._item("Kurta", size="S")
        self._item(" kurta ", size="s")
        self.assertEqual(len(self._scan()["duplicate_groups"]), 1)

    def test_different_skus_are_never_grouped(self):
        self._item("Same Name", sku="A")
        self._item("Same Name", sku="B")
        self.assertEqual(self._scan()["duplicate_groups"], [])

    def test_nameless_rows_without_a_sku_are_ignored(self):
        self._item("")
        self._item("   ")
        self.assertEqual(self._scan()["duplicate_groups"], [])

    def test_keeps_the_copy_with_the_most_stock(self):
        thin = self._item("Cap", stock=2)
        fat = self._item("Cap", stock=40)
        group = self._scan()["duplicate_groups"][0]
        self.assertEqual(group["keeper"]["id"], str(fat.id))
        self.assertEqual([d["id"] for d in group["duplicates"]], [str(thin.id)])

    def test_combines_stock_across_every_copy(self):
        for qty in (3, 4, 5):
            self._item("Cap", stock=qty)
        group = self._scan()["duplicate_groups"][0]
        self.assertEqual(Decimal(group["combined_stock"]), Decimal("12.000"))
        self.assertEqual(group["copies"], 3)

    def test_worst_group_first(self):
        for _ in range(2):
            self._item("Pair")
        for _ in range(3):
            self._item("Triple")
        self.assertEqual(self._scan()["duplicate_groups"][0]["name"], "Triple")

    def test_counts_extra_rows_not_groups(self):
        for _ in range(3):
            self._item("Cap")
        body = self._scan()
        self.assertEqual(body["duplicate_row_count"], 2)
        self.assertEqual(body["total_issues"], 2)

    # --- the other checks --------------------------------------------------

    def test_flags_negative_stock(self):
        item = self._item("Oversold", stock=2)
        InventoryStockLedger.objects.create(
            shop=self.shop,
            item=item,
            event_type=InventoryStockLedger.EventType.SALE,
            quantity_delta=Decimal("-5"),
            occurred_at=timezone.now(),
        )
        self.assertEqual(len(self._scan()["negative_stock"]), 1)

    def test_flags_a_zero_price_that_would_ring_up_free(self):
        self._item("Free", sell="0.00")
        self.assertEqual(len(self._scan()["missing_price"]), 1)

    def test_does_not_flag_a_priced_item(self):
        self._item("Priced", sell="0.01")
        self.assertEqual(self._scan()["missing_price"], [])

    def test_flags_a_debtor_with_no_reachable_number(self):
        Customer.objects.create(
            shop=self.shop, name="Owes", phone="", balance=Decimal("500.00")
        )
        self.assertEqual(len(self._scan()["customers_without_phone"]), 1)

    def test_ignores_a_walk_in_with_no_number_who_owes_nothing(self):
        Customer.objects.create(
            shop=self.shop, name="Walk-in", phone="", balance=Decimal("0.00")
        )
        self.assertEqual(self._scan()["customers_without_phone"], [])

    def test_accepts_a_full_mobile_number(self):
        Customer.objects.create(
            shop=self.shop, name="Owes", phone="9876543210", balance=Decimal("500.00")
        )
        self.assertEqual(self._scan()["customers_without_phone"], [])

    def test_a_clean_shop_is_healthy(self):
        self._item("A", sku="A")
        self._item("B", sku="B")
        body = self._scan()
        self.assertTrue(body["is_healthy"])
        self.assertEqual(body["total_issues"], 0)

    def test_another_shops_data_is_not_scanned(self):
        other = Shop.objects.create(name="Other", slug="other-health")
        InventoryItem.objects.create(shop=other, name="Theirs")
        InventoryItem.objects.create(shop=other, name="Theirs")
        self.assertEqual(self._scan()["duplicate_groups"], [])

from __future__ import annotations

import csv
import io
import zipfile
from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from platform_apps.customers.models import Customer
from platform_apps.inventory.models import InventoryItem
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class ShopCsvExportTests(TestCase):
    """The readable version of "get my data out".

    JSON is right for re-importing and wrong for a shopkeeper: the owner who
    most needs their data out is the least likely to be able to read it.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="csv@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="CSV Shop", slug="csv-shop")
        ShopMembership.objects.create(
            user=self.owner, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        InventoryItem.objects.create(
            shop=self.shop, name="कुर्ता", sku="K-1", sell_price=Decimal("499.50")
        )
        Customer.objects.create(
            shop=self.shop, name="Ramesh", phone="9876543210",
            balance=Decimal("1200.00"),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.url = reverse("shop-data-export", args=[self.shop.id])

    def _zip(self):
        response = self.client.get(self.url, {"output": "csv"})
        self.assertEqual(response.status_code, 200)
        return response, zipfile.ZipFile(io.BytesIO(response.content))

    def test_returns_a_zip_of_spreadsheets(self):
        response, bundle = self._zip()

        self.assertEqual(response["Content-Type"], "application/zip")
        self.assertIn(".zip", response["Content-Disposition"])
        self.assertIn("inventory.csv", bundle.namelist())
        self.assertIn("customers.csv", bundle.namelist())

    def test_the_shop_record_is_not_lost(self):
        """It is an object rather than a list, so it needs its own handling."""
        _, bundle = self._zip()

        self.assertIn("shop.csv", bundle.namelist())
        text = bundle.read("shop.csv").decode("utf-8-sig")
        self.assertIn("CSV Shop", text)

    def test_rows_carry_real_values_not_python_reprs(self):
        _, bundle = self._zip()
        rows = list(csv.DictReader(
            io.StringIO(bundle.read("inventory.csv").decode("utf-8-sig"))
        ))

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["name"], "कुर्ता")
        # A Decimal rendered by repr would read "Decimal('499.50')".
        self.assertEqual(rows[0]["sell_price"], "499.50")

    def test_devanagari_survives_for_excel(self):
        """Without the byte-order mark Excel on Windows shows mojibake, which
        for this audience makes the file useless."""
        _, bundle = self._zip()
        raw = bundle.read("inventory.csv")

        self.assertTrue(raw.startswith(b"\xef\xbb\xbf"))
        self.assertIn("कुर्ता", raw.decode("utf-8-sig"))

    def test_json_remains_the_default(self):
        response = self.client.get(self.url)

        self.assertEqual(response["Content-Type"], "application/json")

    def test_still_owner_only(self):
        staff = PlatformUser.objects.create_user(
            email="csv-staff@example.com", password="secret", full_name="Staff"
        )
        ShopMembership.objects.create(
            user=staff, shop=self.shop,
            role=ShopMembership.Role.MANAGER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client.force_authenticate(user=staff)

        self.assertEqual(
            self.client.get(self.url, {"output": "csv"}).status_code, 403
        )

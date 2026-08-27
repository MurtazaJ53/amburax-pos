"""Codes issued so a label can be printed.

The rule that matters is uniqueness. Nothing in the schema enforces it and
the till resolves a scan by taking the first matching item, so a duplicate is
not untidy data - it is the wrong product rung up at the counter, silently.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem
from platform_apps.inventory.sku_views import format_sku, next_free_number
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class SkuHelpers(TestCase):
    def test_a_code_is_padded_so_it_sorts_in_the_order_issued(self):
        self.assertEqual(format_sku(1), "SK00001")
        self.assertEqual(format_sku(42), "SK00042")

    def test_a_shop_with_no_codes_starts_at_one(self):
        self.assertEqual(next_free_number(set()), 1)

    def test_counting_continues_past_the_highest_issued(self):
        self.assertEqual(next_free_number({"SK00001", "SK00007"}), 8)

    def test_gaps_are_not_filled(self):
        """A reused number puts an old printed label onto a new product."""
        self.assertEqual(next_free_number({"SK00009"}), 10)

    def test_codes_that_are_not_ours_are_ignored_when_counting(self):
        # A manufacturer's EAN says nothing about how many we have issued.
        self.assertEqual(next_free_number({"8901234567890", "RICE-01"}), 1)

    def test_a_longer_code_of_ours_still_counts(self):
        self.assertEqual(next_free_number({"SK123456"}), 123457)


class GenerateSkusTests(TestCase):
    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="owner@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Label Shop", slug="label-shop")
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.url = reverse("inventory-generate-skus", args=[self.shop.id])

    def _item(self, name, *, sku="", barcode="", shop=None):
        return InventoryItem.objects.create(
            shop=shop or self.shop,
            name=name,
            sku=sku,
            barcode=barcode,
            sell_price=Decimal("100"),
        )

    def _post(self, payload=None):
        return self.client.post(self.url, payload or {}, format="json")

    # --- what it assigns -------------------------------------------------

    def test_a_product_with_no_code_gets_one(self):
        item = self._item("Woolen Caps Kids")
        response = self._post()
        self.assertEqual(response.status_code, 200, response.content)
        item.refresh_from_db()
        self.assertEqual(item.sku, "SK00001")
        self.assertEqual(response.data["assigned_count"], 1)

    def test_every_code_in_one_run_is_different(self):
        for name in ["A Gents Socks", "A Kids Socks", "A Ladies Socks"]:
            self._item(name)
        self._post()
        skus = list(
            InventoryItem.objects.filter(shop=self.shop).values_list("sku", flat=True)
        )
        self.assertEqual(len(skus), len(set(skus)))

    def test_a_product_that_already_has_a_sku_is_left_alone(self):
        item = self._item("Rice", sku="RICE-01")
        self._post()
        item.refresh_from_db()
        self.assertEqual(item.sku, "RICE-01")

    def test_a_product_with_a_barcode_is_left_alone(self):
        """It can already be printed, and its barcode is the real one."""
        item = self._item("Cola", barcode="8901234567890")
        self._post()
        item.refresh_from_db()
        self.assertEqual(item.sku, "")

    # --- uniqueness, the rule that matters -------------------------------

    def test_it_will_not_reuse_a_code_typed_in_by_hand(self):
        # Otherwise two products scan as one, and the till picks the first.
        self._item("Old Stock", sku="SK00001")
        item = self._item("New Stock")
        self._post()
        item.refresh_from_db()
        self.assertNotEqual(item.sku, "SK00001")

    def test_it_will_not_collide_with_an_existing_barcode(self):
        self._item("Imported", barcode="SK00001")
        item = self._item("Fresh")
        self._post()
        item.refresh_from_db()
        self.assertNotEqual(item.sku.upper(), "SK00001")

    def test_a_code_that_differs_only_in_case_still_counts_as_taken(self):
        self._item("Lower", sku="sk00001")
        item = self._item("Fresh")
        self._post()
        item.refresh_from_db()
        self.assertNotEqual(item.sku.upper(), "SK00001")

    def test_running_it_twice_does_not_renumber_anything(self):
        item = self._item("Socks")
        self._post()
        item.refresh_from_db()
        first = item.sku

        second = self._post()
        item.refresh_from_db()
        self.assertEqual(item.sku, first)
        self.assertEqual(second.data["assigned_count"], 0)

    # --- scope -----------------------------------------------------------

    def test_only_the_chosen_products_are_given_codes(self):
        chosen = self._item("Chosen")
        other = self._item("Other")
        self._post({"item_ids": [str(chosen.id)]})
        chosen.refresh_from_db()
        other.refresh_from_db()
        self.assertTrue(chosen.sku)
        self.assertEqual(other.sku, "")

    def test_another_shops_products_are_untouched(self):
        other_shop = Shop.objects.create(name="Other", slug="other-label-shop")
        theirs = self._item("Theirs", shop=other_shop)
        self._post()
        theirs.refresh_from_db()
        self.assertEqual(theirs.sku, "")

    def test_it_reports_what_is_still_without_a_code(self):
        self._item("One")
        response = self._post()
        self.assertEqual(response.data["remaining_without_code"], 0)

    def test_a_malformed_selection_is_refused(self):
        self.assertEqual(self._post({"item_ids": "nope"}).status_code, 400)

    # --- who may do it ---------------------------------------------------

    def test_a_cashier_cannot_rewrite_product_codes(self):
        """It changes what a scan at the till resolves to."""
        cashier = PlatformUser.objects.create_user(
            email="cashier@example.com", password="secret", full_name="Cashier"
        )
        ShopMembership.objects.create(
            user=cashier,
            shop=self.shop,
            role=ShopMembership.Role.CASHIER,
            status=ShopMembership.Status.ACTIVE,
        )
        client = APIClient()
        client.force_authenticate(user=cashier)
        self.assertIn(client.post(self.url, {}, format="json").status_code, (403, 404))


class AutoCodeAtSaveTests(TestCase):
    """Choosing the code when the row is written, not before.

    The browser used to ask what the next code would be and send it back with
    the form. Between those two moments somebody else could save a product and
    take it, and the second save carried a duplicate - which makes a scan ring
    up the wrong product.
    """

    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="auto@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Auto Shop", slug="auto-code-shop")
        ShopMembership.objects.create(
            user=self.owner, shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.url = reverse("inventory-list", args=[self.shop.id])

    def _create(self, name, sku):
        return self.client.post(
            self.url, {"name": name, "sell_price": "10.00", "sku": sku}, format="json"
        )

    def test_asking_for_a_code_gets_a_real_one(self):
        response = self._create("Rice", "__auto__")
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(
            InventoryItem.objects.get(shop=self.shop, name="Rice").sku, "SK00001"
        )

    def test_two_products_saved_in_turn_never_share_a_code(self):
        """The race, closed. Both forms could have been holding SK00001."""
        self._create("First", "__auto__")
        self._create("Second", "__auto__")
        codes = list(
            InventoryItem.objects.filter(shop=self.shop).values_list("sku", flat=True)
        )
        self.assertEqual(len(codes), len(set(codes)))
        self.assertEqual(sorted(codes), ["SK00001", "SK00002"])

    def test_a_typed_code_is_kept_exactly(self):
        self._create("Rice", "MY-OWN-CODE")
        self.assertEqual(
            InventoryItem.objects.get(shop=self.shop, name="Rice").sku, "MY-OWN-CODE"
        )

    def test_a_typed_code_that_is_taken_is_refused_by_name(self):
        """An IntegrityError would surface as "an internal server error",
        which tells the person who typed it nothing."""
        self._create("Rice", "SHARED")
        response = self._create("Dal", "SHARED")
        self.assertEqual(response.status_code, 400, response.content)
        self.assertIn("Rice", str(response.data))

    def test_a_blank_code_stays_blank(self):
        self._create("No code", "")
        self.assertEqual(
            InventoryItem.objects.get(shop=self.shop, name="No code").sku, ""
        )

    def test_the_placeholder_is_never_stored(self):
        self._create("Rice", "__auto__")
        self.assertFalse(
            InventoryItem.objects.filter(shop=self.shop, sku="__auto__").exists()
        )

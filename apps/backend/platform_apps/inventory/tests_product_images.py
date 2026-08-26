"""Product photos: what leaves the list, and what a save must not destroy.

The picture used to be read back inside every product list, so opening Stock -
or the till, which loads the same list - downloaded every photo of every
product in one response that must never be cached. It is served from its own
address now.

Moving it created a hazard worth pinning: the edit form posts every field it
holds, so a write-only field that treated "absent" as "empty" would delete the
photo every time somebody corrected a price.
"""
from __future__ import annotations

import base64
from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from platform_apps.inventory.image_views import MAX_IMAGE_BYTES, parse_data_uri
from platform_apps.inventory.models import InventoryItem
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser

PIXEL = base64.b64encode(b"\xff\xd8\xff\xe0 stand-in bytes").decode()
JPEG = f"data:image/jpeg;base64,{PIXEL}"


class ParseDataUriTests(TestCase):
    def test_a_jpeg_is_read(self):
        parsed = parse_data_uri(JPEG)
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed[0], "image/jpeg")

    def test_an_svg_is_refused(self):
        """It is a document that can carry script, not a picture."""
        self.assertIsNone(parse_data_uri("data:image/svg+xml;base64,PHN2Zz4="))

    def test_something_that_is_not_an_image_is_refused(self):
        self.assertIsNone(parse_data_uri("data:text/html;base64,PHNjcmlwdD4="))
        self.assertIsNone(parse_data_uri("https://example.com/cat.png"))
        self.assertIsNone(parse_data_uri(""))

    def test_undecodable_text_is_no_picture_rather_than_a_crash(self):
        # A broken row must not turn a product page into a 500.
        self.assertIsNone(parse_data_uri("data:image/png;base64,!!!not base64!!!"))


class ProductImageTests(TestCase):
    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="owner@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Pic Shop", slug="pic-shop")
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.item = InventoryItem.objects.create(
            shop=self.shop,
            name="Basmati Rice",
            sell_price=Decimal("80"),
            image_data=JPEG,
        )
        self.image_url = reverse(
            "inventory-item-image", args=[self.shop.id, self.item.id]
        )
        self.detail_url = reverse("inventory-detail", args=[self.shop.id, self.item.id])
        self.list_url = reverse("inventory-list", args=[self.shop.id])

    # --- what the list carries -------------------------------------------

    def test_the_list_does_not_carry_the_picture(self):
        """The whole point: megabytes of base64 stop travelling."""
        response = self.client.get(self.list_url)
        self.assertEqual(response.status_code, 200, response.content)
        self.assertNotIn("image_data", response.json()[0])

    def test_the_list_says_whether_there_is_a_picture(self):
        # So the screen can choose between an image and the fallback initial
        # without fetching a picture to discover there is none.
        rows = self.client.get(self.list_url).json()
        self.assertIs(rows[0]["has_image"], True)

    def test_a_product_with_no_picture_says_so(self):
        InventoryItem.objects.create(
            shop=self.shop, name="No Photo", sell_price=Decimal("10")
        )
        rows = self.client.get(self.list_url).json()
        by_name = {row["name"]: row for row in rows}
        self.assertIs(by_name["No Photo"]["has_image"], False)

    # --- serving it -------------------------------------------------------

    def test_the_picture_is_served_as_an_image(self):
        response = self.client.get(self.image_url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "image/jpeg")

    def test_it_may_be_cached_by_the_browser_but_not_by_anyone_else(self):
        response = self.client.get(self.image_url)
        self.assertIn("private", response["Cache-Control"])
        self.assertIn("max-age=", response["Cache-Control"])

    def test_a_second_request_is_answered_without_the_body(self):
        """The reason this endpoint exists. Without it, every photo comes
        down again as soon as the cache expires."""
        first = self.client.get(self.image_url)
        second = self.client.get(self.image_url, HTTP_IF_NONE_MATCH=first["ETag"])
        self.assertEqual(second.status_code, 304)
        self.assertFalse(second.content)

    def test_a_product_without_a_picture_is_not_found(self):
        bare = InventoryItem.objects.create(
            shop=self.shop, name="Bare", sell_price=Decimal("5")
        )
        url = reverse("inventory-item-image", args=[self.shop.id, bare.id])
        self.assertEqual(self.client.get(url).status_code, 404)

    def test_another_shops_picture_cannot_be_fetched(self):
        other = Shop.objects.create(name="Other", slug="other-pic-shop")
        theirs = InventoryItem.objects.create(
            shop=other, name="Theirs", sell_price=Decimal("5"), image_data=JPEG
        )
        url = reverse("inventory-item-image", args=[self.shop.id, theirs.id])
        self.assertEqual(self.client.get(url).status_code, 404)

    # --- saving -----------------------------------------------------------

    def test_saving_without_the_picture_field_keeps_the_picture(self):
        """The hazard. The edit form posts every field it holds, so treating
        absent as empty would delete the photo on every price correction."""
        response = self.client.patch(
            self.detail_url, {"sell_price": "95.00"}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.item.refresh_from_db()
        self.assertEqual(self.item.image_data, JPEG)

    def test_sending_an_empty_picture_clears_it(self):
        response = self.client.patch(self.detail_url, {"image_data": ""}, format="json")
        self.assertEqual(response.status_code, 200, response.content)
        self.item.refresh_from_db()
        self.assertEqual(self.item.image_data, "")

    def test_a_new_picture_replaces_the_old_one(self):
        other = "data:image/png;base64," + base64.b64encode(b"different").decode()
        self.client.patch(self.detail_url, {"image_data": other}, format="json")
        self.item.refresh_from_db()
        self.assertEqual(self.item.image_data, other)

    def test_something_that_is_not_an_image_is_refused(self):
        response = self.client.patch(
            self.detail_url,
            {"image_data": "data:text/html;base64,PHNjcmlwdD4="},
            format="json",
        )
        self.assertEqual(response.status_code, 400, response.content)

    def test_an_oversized_picture_is_refused(self):
        # There was no cap at all. The browser resizes before upload, but the
        # API did not care what a direct caller stored in a column that then
        # travels with every backup of the table the till reads.
        huge = "data:image/jpeg;base64," + ("A" * MAX_IMAGE_BYTES)
        response = self.client.patch(
            self.detail_url, {"image_data": huge}, format="json"
        )
        self.assertEqual(response.status_code, 400, response.content)

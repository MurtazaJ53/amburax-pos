"""What a shop may put on its own receipt.

Both fields end up on a printed document, so what is accepted matters more
than usual: a colour reaches a style attribute, and a logo is echoed back on
every settings read.
"""
from __future__ import annotations

from django.test import TestCase
from rest_framework.test import APIClient

from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.shops.settings_views import MAX_LOGO_BYTES
from platform_apps.users.models import PlatformUser

PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg=="


class ReceiptBrandingTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="brand@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Brand Shop", slug="brand-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/shops/{self.shop.id}/settings/"

    def _patch(self, payload):
        return self.client.patch(self.url, payload, format="json")

    # --- colour ----------------------------------------------------------

    def test_a_hex_colour_is_saved(self):
        response = self._patch({"brand_color": "#0369A1"})
        self.assertEqual(response.status_code, 200, response.content)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.brand_color, "#0369A1")

    def test_the_short_hex_form_is_accepted(self):
        self.assertEqual(self._patch({"brand_color": "#0AF"}).status_code, 200)

    def test_anything_that_is_not_a_colour_is_refused(self):
        """It reaches a style attribute on a printed document."""
        for bad in ["red", "0369A1", "#12345", "red; background:url(x)", "javascript:x"]:
            response = self._patch({"brand_color": bad})
            self.assertEqual(response.status_code, 400, f"{bad}: {response.content}")
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.brand_color, "")

    def test_clearing_the_colour_is_allowed(self):
        self.shop.brand_color = "#0369A1"
        self.shop.save(update_fields=["brand_color"])
        self.assertEqual(self._patch({"brand_color": ""}).status_code, 200)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.brand_color, "")

    # --- logo ------------------------------------------------------------

    def test_an_image_is_saved(self):
        response = self._patch({"logo_data": PNG})
        self.assertEqual(response.status_code, 200, response.content)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.logo_data, PNG)

    def test_something_that_is_not_an_image_is_refused(self):
        for bad in ["https://example.com/logo.png", "data:text/html,<script>", "hello"]:
            response = self._patch({"logo_data": bad})
            self.assertEqual(response.status_code, 400, f"{bad}: {response.content}")

    def test_an_oversized_image_is_refused(self):
        """It is resized before upload, so a huge one means the picker was
        bypassed rather than a shopkeeper with a big picture."""
        payload = "data:image/png;base64," + ("A" * MAX_LOGO_BYTES)
        response = self._patch({"logo_data": payload})
        self.assertEqual(response.status_code, 400, response.content)

    def test_both_come_back_on_a_read(self):
        self._patch({"brand_color": "#0369A1", "logo_data": PNG})
        body = self.client.get(self.url).json()
        self.assertEqual(body["brand_color"], "#0369A1")
        self.assertEqual(body["logo_data"], PNG)

    def test_a_shop_starts_with_neither(self):
        body = self.client.get(self.url).json()
        self.assertEqual(body["brand_color"], "")
        self.assertEqual(body["logo_data"], "")

    def test_another_shops_branding_cannot_be_written(self):
        other = Shop.objects.create(name="Other", slug="other-brand-shop")
        response = self.client.patch(
            f"/api/v1/shops/{other.id}/settings/",
            {"brand_color": "#000000"},
            format="json",
        )
        self.assertIn(response.status_code, (403, 404))
        other.refresh_from_db()
        self.assertEqual(other.brand_color, "")

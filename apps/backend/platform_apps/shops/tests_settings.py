from __future__ import annotations

from django.test import TestCase
from rest_framework.test import APIClient

from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class ShopSettingsTests(TestCase):
    """These values print on every receipt and feed the GST return, so a bad
    one is worse than a missing one."""

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="settings@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Settings Shop", slug="settings-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/shops/{self.shop.id}/settings/"

    def test_reads_the_current_details(self):
        body = self.client.get(self.url).json()
        self.assertEqual(body["name"], "Settings Shop")
        self.assertEqual(body["currency_code"], "INR")

    def test_updates_a_column_field(self):
        response = self.client.patch(self.url, {"name": "New Name"}, format="json")
        self.assertEqual(response.status_code, 200, response.content)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.name, "New Name")

    def test_updates_a_settings_blob_field(self):
        self.client.patch(self.url, {"upi_vpa": "shop@okaxis"}, format="json")
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.settings_json["upi_vpa"], "shop@okaxis")

    def test_a_partial_update_leaves_other_fields_alone(self):
        self.client.patch(self.url, {"tagline": "Best prices"}, format="json")
        self.client.patch(self.url, {"footer": "Thank you"}, format="json")
        body = self.client.get(self.url).json()
        self.assertEqual(body["tagline"], "Best prices")
        self.assertEqual(body["footer"], "Thank you")

    def test_the_shop_name_cannot_be_blanked(self):
        # An empty name would print an empty receipt header.
        response = self.client.patch(self.url, {"name": "   "}, format="json")
        self.assertEqual(response.status_code, 400, response.content)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.name, "Settings Shop")

    def test_a_malformed_gstin_is_rejected(self):
        # A wrong GSTIN on a filed return is a compliance problem, not a typo.
        response = self.client.patch(self.url, {"gstin": "NOT-A-GSTIN"}, format="json")
        self.assertEqual(response.status_code, 400, response.content)

    def test_a_valid_gstin_is_stored_uppercased(self):
        response = self.client.patch(
            self.url, {"gstin": "27aabcn8921r1zx"}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.gstin, "27AABCN8921R1ZX")

    def test_gstin_may_be_cleared_for_an_unregistered_shop(self):
        self.shop.gstin = "27AABCN8921R1ZX"
        self.shop.save(update_fields=["gstin"])
        response = self.client.patch(self.url, {"gstin": ""}, format="json")
        self.assertEqual(response.status_code, 200, response.content)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.gstin, "")

    def test_a_malformed_upi_id_is_rejected(self):
        # A broken pay link fails silently at the counter, which is worse than
        # having no link at all.
        response = self.client.patch(self.url, {"upi_vpa": "not-a-vpa"}, format="json")
        self.assertEqual(response.status_code, 400, response.content)

    def test_settings_are_shared_not_per_device(self):
        # The whole point: a second device reads what the first one saved.
        self.client.patch(
            self.url, {"name": "Shared Name", "upi_vpa": "shop@okicici"}, format="json"
        )
        other = APIClient()
        other.force_authenticate(user=self.user)
        body = other.get(self.url).json()
        self.assertEqual(body["name"], "Shared Name")
        self.assertEqual(body["upi_vpa"], "shop@okicici")

    def test_a_cashier_can_read_but_not_change(self):
        staff = PlatformUser.objects.create_user(
            email="settings-staff@example.com", password="secret", full_name="Staff"
        )
        ShopMembership.objects.create(
            user=staff,
            shop=self.shop,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
        )
        client = APIClient()
        client.force_authenticate(user=staff)
        self.assertEqual(client.get(self.url).status_code, 200)
        self.assertEqual(
            client.patch(self.url, {"name": "Hacked"}, format="json").status_code, 403
        )

    def test_a_stranger_cannot_read_the_shop(self):
        stranger = PlatformUser.objects.create_user(
            email="stranger@example.com", password="secret", full_name="Stranger"
        )
        client = APIClient()
        client.force_authenticate(user=stranger)
        self.assertEqual(client.get(self.url).status_code, 403)


class ShopBusinessTypeSettingsTests(TestCase):
    """Phase 4: the business type and its flags are changeable after signup.

    The type is chosen in the first thirty seconds a shopkeeper spends with the
    product, long before they know what the words mean. If getting it wrong
    needed a support call, most would simply live with the wrong one.
    """

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="btype@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(
            name="Type Shop",
            slug="type-shop",
            settings_json={"business_type": "retail", "plan_tier": "starter"},
        )
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/shops/{self.shop.id}/settings/"

    # --- reading ----------------------------------------------------------

    def test_reads_the_type_and_its_resolved_flags(self):
        body = self.client.get(self.url).json()
        self.assertEqual(body["business_type"], "retail")
        # Resolved from the type, not read from an empty override map.
        self.assertIs(body["features"]["product_variants"], True)
        self.assertIs(body["features"]["weight_selling"], False)

    def test_only_shop_editable_flags_are_exposed(self):
        body = self.client.get(self.url).json()
        self.assertNotIn("advanced_ops", body["features"])
        self.assertNotIn("expenses", body["features"])

    # --- changing the type ------------------------------------------------

    def test_changing_the_type_moves_the_flags_with_it(self):
        response = self.client.patch(
            self.url, {"business_type": "grocery"}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual(body["business_type"], "grocery")
        self.assertIs(body["features"]["weight_selling"], True)
        self.assertIs(body["features"]["product_variants"], False)

    def test_an_unknown_type_is_rejected_not_silently_reset(self):
        response = self.client.patch(
            self.url, {"business_type": "cafe"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("business_type", response.json())
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.settings_json["business_type"], "retail")

    def test_deferred_types_are_still_accepted(self):
        """Pharmacy and restaurant are deferred from signup, not invalid. A
        shop already carrying one must not be unable to save its settings."""
        for deferred in ("pharmacy", "restaurant"):
            response = self.client.patch(
                self.url, {"business_type": deferred}, format="json"
            )
            self.assertEqual(response.status_code, 200, deferred)

    # --- changing the flags -----------------------------------------------

    def test_a_flag_can_be_turned_on_against_the_type_default(self):
        response = self.client.patch(
            self.url, {"features": {"weight_selling": True}}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertIs(response.json()["features"]["weight_selling"], True)

    def test_a_flag_can_be_turned_off_against_the_type_default(self):
        response = self.client.patch(
            self.url, {"features": {"product_variants": False}}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertIs(response.json()["features"]["product_variants"], False)

    def test_an_override_survives_a_later_change_of_type(self):
        """The regression that would make the toggle feel broken: switch a flag
        off, correct the business type, and find the flag back on."""
        self.client.patch(
            self.url, {"features": {"weight_selling": False}}, format="json"
        )
        response = self.client.patch(
            self.url, {"business_type": "grocery"}, format="json"
        )
        self.assertIs(response.json()["features"]["weight_selling"], False)

    # --- the free upgrade -------------------------------------------------

    def test_a_plan_feature_cannot_be_granted_through_settings(self):
        """The attack this endpoint exists to refuse: a starter shop toggling
        itself into paid features."""
        response = self.client.patch(
            self.url, {"features": {"advanced_ops": True}}, format="json"
        )
        self.assertEqual(response.status_code, 400, response.content)
        self.shop.refresh_from_db()
        self.assertIs(self.shop.enabled_features["advanced_ops"], False)

    def test_a_plan_feature_smuggled_beside_a_valid_one_takes_both_down(self):
        response = self.client.patch(
            self.url,
            {"features": {"weight_selling": True, "expenses": True}},
            format="json",
        )
        self.assertEqual(response.status_code, 400, response.content)
        self.shop.refresh_from_db()
        self.assertIs(self.shop.enabled_features["expenses"], False)
        # The valid half must not have been applied either — a partially
        # accepted write is harder to reason about than a rejected one.
        self.assertIs(self.shop.enabled_features["weight_selling"], False)

    def test_a_string_false_is_rejected_rather_than_coerced(self):
        """'false' is truthy in Python, so coercing would switch the feature ON
        while the shopkeeper watched themselves turn it off."""
        response = self.client.patch(
            self.url, {"features": {"product_variants": "false"}}, format="json"
        )
        self.assertEqual(response.status_code, 400, response.content)

    def test_a_non_object_features_payload_is_rejected(self):
        response = self.client.patch(
            self.url, {"features": ["weight_selling"]}, format="json"
        )
        self.assertEqual(response.status_code, 400, response.content)

    # --- who may do it ----------------------------------------------------

    def test_a_cashier_cannot_change_the_shop_type(self):
        cashier = PlatformUser.objects.create_user(
            email="cashier@example.com", password="secret", full_name="Cashier"
        )
        ShopMembership.objects.create(
            user=cashier,
            shop=self.shop,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
        )
        client = APIClient()
        client.force_authenticate(user=cashier)
        response = client.patch(
            self.url, {"business_type": "grocery"}, format="json"
        )
        self.assertEqual(response.status_code, 403)

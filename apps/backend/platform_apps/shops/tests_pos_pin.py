"""The counter PIN, which until now verified nothing.

`pos_pin_hash` has existed on ShopMembership since migration 0010 and Team
settings could write it. Nothing ever read it back. The web route returned
`role: cashier` to anyone who posted four digits, so the lock screen was
decoration.
"""
from __future__ import annotations

from django.contrib.auth.hashers import make_password
from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class PosPinVerifyTests(TestCase):
    def setUp(self):
        cache.clear()
        self.user = PlatformUser.objects.create_user(
            email="cashier@example.com", password="secret", full_name="Cashier"
        )
        self.shop = Shop.objects.create(name="Pin Shop", slug="pin-shop")
        self.membership = ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
            pos_pin_hash=make_password("4321"),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    @property
    def url(self):
        return f"/api/v1/shops/{self.shop.id}/pos-pin/verify/"

    def test_the_correct_pin_is_accepted(self):
        response = self.client.post(self.url, {"pin": "4321"}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertIs(response.data["verified"], True)
        self.assertEqual(response.data["role"], ShopMembership.Role.STAFF)

    def test_a_wrong_pin_is_refused(self):
        """The whole point. This used to return 200."""
        response = self.client.post(self.url, {"pin": "0000"}, format="json")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.data["code"], "pin_invalid")

    def test_an_empty_pin_is_refused(self):
        response = self.client.post(self.url, {"pin": ""}, format="json")
        self.assertEqual(response.status_code, 401)

    def test_a_missing_pin_field_is_refused(self):
        response = self.client.post(self.url, {}, format="json")
        self.assertEqual(response.status_code, 401)

    def test_the_stored_hash_is_never_returned(self):
        response = self.client.post(self.url, {"pin": "4321"}, format="json")
        self.assertNotIn("pos_pin_hash", response.data)
        self.assertNotIn("4321", str(response.data))

    def test_a_pin_that_was_never_set_says_so_rather_than_wrong(self):
        """A cashier at a lock screen nobody configured must be told that, not
        told their PIN is wrong — they would retype it forever."""
        self.membership.pos_pin_hash = ""
        self.membership.save(update_fields=["pos_pin_hash"])

        response = self.client.post(self.url, {"pin": "4321"}, format="json")
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["code"], "pin_not_set")

    def test_an_anonymous_caller_gets_nothing(self):
        """The PIN reopens a session; it cannot create one."""
        anon = APIClient()
        response = anon.post(self.url, {"pin": "4321"}, format="json")
        self.assertIn(response.status_code, (401, 403))

    def test_a_pin_is_not_valid_on_a_shop_the_user_has_no_membership_on(self):
        other = Shop.objects.create(name="Other Shop", slug="other-shop")
        response = self.client.post(
            f"/api/v1/shops/{other.id}/pos-pin/verify/", {"pin": "4321"}, format="json"
        )
        self.assertEqual(response.status_code, 403)

    def test_another_users_pin_does_not_unlock_this_membership(self):
        """The hash is per-membership. Sharing one PIN across a shop would make
        the audit trail meaningless."""
        colleague = PlatformUser.objects.create_user(
            email="other@example.com", password="secret", full_name="Other"
        )
        ShopMembership.objects.create(
            user=colleague,
            shop=self.shop,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
            pos_pin_hash=make_password("9999"),
        )
        response = self.client.post(self.url, {"pin": "9999"}, format="json")
        self.assertEqual(response.status_code, 401)

    def test_a_disabled_member_cannot_unlock(self):
        self.membership.status = ShopMembership.Status.DISABLED
        self.membership.save(update_fields=["status"])
        response = self.client.post(self.url, {"pin": "4321"}, format="json")
        self.assertEqual(response.status_code, 403)

    def test_a_failed_attempt_is_written_to_the_audit_trail(self):
        from platform_apps.audit.models import WorkspaceAuditEvent

        self.client.post(self.url, {"pin": "0000"}, format="json")
        self.assertTrue(
            WorkspaceAuditEvent.objects.filter(
                shop=self.shop, event_type="pos_pin.verify.failed"
            ).exists()
        )

    def test_the_audit_entry_does_not_record_the_attempted_pin(self):
        from platform_apps.audit.models import WorkspaceAuditEvent

        self.client.post(self.url, {"pin": "8675"}, format="json")
        event = WorkspaceAuditEvent.objects.filter(
            shop=self.shop, event_type="pos_pin.verify.failed"
        ).first()
        # Logging the guess would put a near-miss of the real PIN in a table
        # more people can read than can read the hash.
        self.assertNotIn("8675", str(event.__dict__))


class PosPinThrottleTests(TestCase):
    """Ten thousand combinations is nothing without a rate limit.

    Deliberately run against the REAL configured rate rather than an
    override_settings one. An earlier draft overrode REST_FRAMEWORK to 3/min
    and fired 8 requests; the override silently did not reach DRF's cached
    api_settings, the real 10/min applied, 8 never tripped it, and the test
    passed while proving nothing about the deployed configuration.
    """

    #: Comfortably above DEFAULT_THROTTLE_RATES["pos_pin"], so this fails if
    #: the rate is removed, misspelt, or raised without anyone noticing.
    ATTEMPTS = 15

    def setUp(self):
        cache.clear()
        self.user = PlatformUser.objects.create_user(
            email="brute@example.com", password="secret", full_name="Cashier"
        )
        self.shop = Shop.objects.create(name="Brute Shop", slug="brute-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
            pos_pin_hash=make_password("4321"),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/shops/{self.shop.id}/pos-pin/verify/"

    def test_repeated_guesses_are_eventually_refused(self):
        statuses = [
            self.client.post(self.url, {"pin": "0000"}, format="json").status_code
            for _ in range(self.ATTEMPTS)
        ]
        self.assertIn(429, statuses, f"No rate limit applied: {statuses}")

    def test_the_limit_is_not_bypassable_with_a_forwarded_header(self):
        """Per-user, so rotating a client IP buys an attacker nothing."""
        statuses = []
        for index in range(self.ATTEMPTS):
            statuses.append(
                self.client.post(
                    self.url,
                    {"pin": "0000"},
                    format="json",
                    HTTP_X_FORWARDED_FOR=f"10.0.0.{index}",
                ).status_code
            )
        self.assertIn(429, statuses, f"Throttle bypassed by header: {statuses}")

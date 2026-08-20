"""The dev impersonation backdoor must need two switches, not one.

DevHeaderAuthentication signs in whoever an HTTP header names, as a platform
admin if X-Dev-Platform-Admin says so. It was gated on DEBUG alone — and the
website sent those headers on every production request, sourced from
bh_user_role, a cookie that is deliberately not httpOnly so the browser can
read it. Anyone could edit it.

That made production safe by exactly one setting. Turning DEBUG on to
investigate something would have handed platform admin to any visitor willing
to edit a cookie, and created the admin account for them on the spot.
"""
from __future__ import annotations

from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from platform_apps.users.models import PlatformUser


class DevHeaderAuthenticationTests(TestCase):
    """`/api/v1/session/` reflects whoever the request authenticated as."""

    URL = "/api/v1/session/"

    def setUp(self):
        self.client = APIClient()

    @override_settings(DEBUG=True, ALLOW_DEV_HEADER_AUTH=True)
    def test_it_works_when_both_switches_are_on(self):
        """Local development must still be usable — otherwise the guard just
        gets reverted the first time it gets in someone's way."""
        response = self.client.get(
            self.URL, HTTP_X_DEV_USER_EMAIL="dev@example.com"
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertTrue(
            PlatformUser.objects.filter(email="dev@example.com").exists()
        )

    @override_settings(DEBUG=True, ALLOW_DEV_HEADER_AUTH=False)
    def test_debug_alone_is_not_enough(self):
        """The regression that matters: DEBUG flipped on in production must not
        be sufficient on its own."""
        response = self.client.get(
            self.URL, HTTP_X_DEV_USER_EMAIL="attacker@example.com"
        )
        self.assertIn(response.status_code, (401, 403))
        self.assertFalse(
            PlatformUser.objects.filter(email="attacker@example.com").exists(),
            "A rejected dev header still created the account it named.",
        )

    @override_settings(DEBUG=False, ALLOW_DEV_HEADER_AUTH=True)
    def test_the_flag_alone_is_not_enough_either(self):
        response = self.client.get(
            self.URL, HTTP_X_DEV_USER_EMAIL="attacker@example.com"
        )
        self.assertIn(response.status_code, (401, 403))
        self.assertFalse(
            PlatformUser.objects.filter(email="attacker@example.com").exists()
        )

    @override_settings(DEBUG=False, ALLOW_DEV_HEADER_AUTH=False)
    def test_production_settings_refuse_platform_admin_escalation(self):
        """The full attack: claim to be a platform admin and see what happens."""
        response = self.client.get(
            self.URL,
            HTTP_X_DEV_USER_EMAIL="attacker@example.com",
            HTTP_X_DEV_PLATFORM_ADMIN="true",
        )
        self.assertIn(response.status_code, (401, 403))
        self.assertFalse(
            PlatformUser.objects.filter(
                email="attacker@example.com", is_platform_admin=True
            ).exists(),
            "Header-claimed platform admin was granted.",
        )

    def test_the_default_settings_have_the_flag_off(self):
        """A deployment that never heard of ALLOW_DEV_HEADER_AUTH must be safe
        by omission, not by remembering to set something."""
        from django.conf import settings

        self.assertFalse(getattr(settings, "ALLOW_DEV_HEADER_AUTH", False))

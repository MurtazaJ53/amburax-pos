"""A broken cache must not take sign-in down with it.

On 20 Aug 2026 Redis was unreachable and /session/token/ answered 500 for
everyone: DRF counts throttle hits in the Django cache, the cache raised, and
the exception surfaced as a server error on the login endpoint. The thing
guarding the door had become the thing blocking it.
"""
from __future__ import annotations

from unittest import mock

from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from platform_apps.users.models import PlatformUser
from platform_apps.users.token_views import LoginRateThrottle


class ThrottleFailsOpenTests(TestCase):
    def setUp(self):
        PlatformUser.objects.create_user(
            email="owner@example.com", password="secret12345", full_name="Owner"
        )
        self.client = APIClient()

    def _login(self, password="secret12345"):
        return self.client.post(
            reverse("session-token-obtain"),
            {"email": "owner@example.com", "password": password},
            format="json",
        )

    def test_sign_in_works_when_the_throttle_cache_is_dead(self):
        """The exact production failure, as a test."""
        with mock.patch(
            "rest_framework.throttling.SimpleRateThrottle.allow_request",
            side_effect=ConnectionError("Error 10061 connecting to 127.0.0.1:6379"),
        ):
            response = self._login()

        # Before the fix this was 500 and nobody could sign in.
        self.assertEqual(response.status_code, 200, response.data)
        self.assertIn("access", response.data)

    def test_the_outage_is_logged_rather_than_swallowed(self):
        """Degrading quietly is how a temporary outage becomes a permanent hole."""
        with mock.patch(
            "rest_framework.throttling.SimpleRateThrottle.allow_request",
            side_effect=ConnectionError("cache down"),
        ):
            with self.assertLogs("platform_apps.users.token_views", level="ERROR") as logs:
                self._login()

        self.assertTrue(
            any("Brute-force protection is OFF" in line for line in logs.output),
            logs.output,
        )

    def test_a_working_cache_still_throttles(self):
        """Failing open must not mean never limiting."""
        throttle = LoginRateThrottle()
        self.assertEqual(throttle.rate, "5/min")

        # Six wrong passwords against a live cache: the sixth is refused.
        codes = [self._login(password="wrong").status_code for _ in range(6)]
        self.assertIn(429, codes, codes)

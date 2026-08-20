"""MFA has to be enforced where the authority is, not where the page renders.

It was checked only in the website's server-guards, which gate whether a React
page renders. The Django views behind them checked one boolean —
is_platform_admin — so anyone holding a platform-admin token could suspend a
shop with curl and never touch a second factor.

A token is exactly what MFA is supposed to survive: a device left signed in, a
token copied off one, or one forged against a weak signing key.
"""
from __future__ import annotations

from datetime import timedelta

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.shops.models import Shop
from platform_apps.users.models import PlatformUser


class PlatformAdminMfaEnforcementTests(TestCase):
    def setUp(self):
        self.admin = PlatformUser.objects.create_user(
            email="admin@example.com", password="secret", full_name="Admin"
        )
        self.admin.is_platform_admin = True
        self.admin.mfa_totp_secret = "JBSWY3DPEHPK3PXP"
        self.admin.mfa_totp_enabled_at = timezone.now() - timedelta(days=30)
        self.admin.mfa_totp_last_verified_at = timezone.now()
        self.admin.save()

        self.shop = Shop.objects.create(name="Target", slug="target-shop")
        self.client = APIClient()
        self.client.force_authenticate(user=self.admin)

    @property
    def suspend_url(self):
        return f"/api/v1/platform/shops/{self.shop.id}/suspend/"

    def test_a_freshly_verified_admin_can_suspend(self):
        """The guard must not break the job it protects."""
        response = self.client.post(self.suspend_url, {"reason": "test"}, format="json")
        self.assertEqual(response.status_code, 200, response.content)

    def test_a_stale_verification_is_refused(self):
        """The attack: a token taken from a device signed in this morning."""
        self.admin.mfa_totp_last_verified_at = timezone.now() - timedelta(hours=8)
        self.admin.save(update_fields=["mfa_totp_last_verified_at"])

        response = self.client.post(self.suspend_url, {"reason": "test"}, format="json")

        self.assertEqual(response.status_code, 403)
        self.shop.refresh_from_db()
        self.assertNotEqual(self.shop.status, Shop.Status.SUSPENDED)

    def test_an_admin_who_never_verified_is_refused(self):
        self.admin.mfa_totp_last_verified_at = None
        self.admin.save(update_fields=["mfa_totp_last_verified_at"])

        response = self.client.post(self.suspend_url, {"reason": "test"}, format="json")

        self.assertEqual(response.status_code, 403)

    def test_an_admin_with_no_mfa_at_all_is_refused_and_told_why(self):
        """"Not set up yet" is the state this exists to refuse, so it must not
        pass silently — and the message has to say what to do."""
        self.admin.mfa_totp_secret = ""
        self.admin.mfa_totp_enabled_at = None
        self.admin.save()

        response = self.client.post(self.suspend_url, {"reason": "test"}, format="json")

        self.assertEqual(response.status_code, 403)
        self.assertIn("multi-factor", str(response.data).lower())

    def test_a_non_admin_is_still_refused(self):
        ordinary = PlatformUser.objects.create_user(
            email="nobody@example.com", password="secret", full_name="Nobody"
        )
        client = APIClient()
        client.force_authenticate(user=ordinary)

        response = client.post(self.suspend_url, {"reason": "test"}, format="json")

        self.assertEqual(response.status_code, 403)

    def test_reading_the_shop_list_does_not_require_fresh_mfa(self):
        """An admin who cannot look at a dashboard without re-authenticating
        will find a way to stop being an admin."""
        self.admin.mfa_totp_last_verified_at = timezone.now() - timedelta(days=2)
        self.admin.save(update_fields=["mfa_totp_last_verified_at"])

        response = self.client.get("/api/v1/platform/shops/")

        self.assertEqual(response.status_code, 200, response.content)

    def test_every_destructive_platform_endpoint_is_covered(self):
        """The guard is only worth having if it is on all four. Adding a fifth
        mutating view and forgetting it would reopen the hole silently."""
        from platform_apps.common.permissions import IsVerifiedPlatformAdmin
        from platform_apps.platform_admin import views

        for name in (
            "PlatformShopSuspendView",
            "PlatformShopActivateView",
            "PlatformShopApproveView",
            "PlatformShopPlanView",
        ):
            view = getattr(views, name)
            self.assertIn(
                IsVerifiedPlatformAdmin,
                view.permission_classes,
                f"{name} can be called without fresh MFA.",
            )

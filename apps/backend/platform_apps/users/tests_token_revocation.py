"""Revoking a session must actually stop the token working.

The previous behaviour is what these tests exist to prevent returning: the
revoke endpoint wrote REVOKED onto a database row, reported "Signed out N
device(s)", and the device's JWT carried on authenticating for the rest of its
life. A security control that reports success without enforcing is worse than
no control, because the owner stops looking for the phone.
"""
from __future__ import annotations

from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from platform_apps.shops.models import Shop, ShopMembership, WorkspaceAccessSession
from platform_apps.users.jwt_auth import issue_tokens, revoke_user_tokens
from platform_apps.users.models import PlatformUser


class TokenRevocationTests(TestCase):
    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="owner@example.com", password="secret", full_name="Owner"
        )
        self.staff = PlatformUser.objects.create_user(
            email="staff@example.com", password="secret", full_name="Staff"
        )
        self.shop = Shop.objects.create(
            name="Demo Shop", slug="demo-shop", settings_json={"plan_tier": "pro"}
        )
        for user, role in ((self.owner, ShopMembership.Role.OWNER),
                           (self.staff, ShopMembership.Role.STAFF)):
            ShopMembership.objects.create(
                user=user,
                shop=self.shop,
                role=role,
                status=ShopMembership.Status.ACTIVE,
            )
        self.session = WorkspaceAccessSession.objects.create(
            shop=self.shop,
            user=self.staff,
            app_instance_id="device-1",
            device_label="Staff phone",
            status=WorkspaceAccessSession.Status.ACTIVE,
        )

    def _as(self, user):
        """A client authenticating with a real bearer token, not force_authenticate.

        force_authenticate bypasses JWTAuthentication entirely, so a test using
        it would pass even with the revocation check deleted.
        """
        client = APIClient()
        token = issue_tokens(user)["access"]
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        return client

    @property
    def _probe(self):
        """An endpoint gated on authentication alone.

        Deliberately not a shop-scoped one: a 403 from a role check would look
        identical to a 401 from revocation, and the test would pass for the
        wrong reason.
        """
        return reverse("session-bootstrap")

    def test_a_valid_token_works(self):
        self.assertEqual(self._as(self.staff).get(self._probe).status_code, 200)

    def test_revoking_tokens_stops_an_already_issued_token(self):
        client = self._as(self.staff)
        self.assertEqual(client.get(self._probe).status_code, 200)

        revoke_user_tokens(self.staff)

        # Same token, same client. It was valid a line ago.
        self.assertEqual(client.get(self._probe).status_code, 401)

    def test_revoke_all_endpoint_stops_the_revoked_device(self):
        staff_client = self._as(self.staff)
        self.assertEqual(staff_client.get(self._probe).status_code, 200)

        response = self._as(self.owner).post(
            reverse("workspace-sessions-revoke-all", args=[self.shop.id]),
            {},
            format="json",
        )
        self.assertEqual(response.status_code, 200)

        # This is the assertion the old implementation could not pass.
        self.assertEqual(staff_client.get(self._probe).status_code, 401)

    def test_a_refresh_token_cannot_buy_a_way_back_in(self):
        # Otherwise being signed out is a formality: the access token is
        # rejected and the client quietly swaps its refresh token for a new one.
        refresh = issue_tokens(self.staff)["refresh"]
        revoke_user_tokens(self.staff)

        response = APIClient().post(
            reverse("session-token-refresh"), {"refresh": refresh}, format="json"
        )
        self.assertEqual(response.status_code, 401)

    def test_a_fresh_login_after_revocation_works(self):
        # Revocation must not lock the person out permanently — signing in
        # again mints a token at the new version.
        revoke_user_tokens(self.staff)

        response = APIClient().post(
            reverse("session-token-obtain"),
            {"email": "staff@example.com", "password": "secret"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)

        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")
        self.assertEqual(client.get(self._probe).status_code, 200)

    def test_revoking_one_user_does_not_touch_another(self):
        owner_client = self._as(self.owner)
        revoke_user_tokens(self.staff)
        self.assertEqual(owner_client.get(self._probe).status_code, 200)

    def test_a_token_minted_before_the_claim_existed_still_works(self):
        # Deploying this must not sign out every shop at once. A token with no
        # "tv" claim counts as version 0, which matches a user who has never
        # been revoked.
        import jwt as pyjwt
        from django.conf import settings

        payload = pyjwt.decode(
            issue_tokens(self.staff)["access"],
            settings.SECRET_KEY,
            algorithms=["HS256"],
            issuer="business-hub",
        )
        del payload["tv"]
        legacy = pyjwt.encode(payload, settings.SECRET_KEY, algorithm="HS256")

        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {legacy}")
        self.assertEqual(client.get(self._probe).status_code, 200)

        # ...and is revocable from then on, like any other.
        revoke_user_tokens(self.staff)
        self.assertEqual(client.get(self._probe).status_code, 401)

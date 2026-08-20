"""JWT signing must be rotatable even though SECRET_KEY is not.

SECRET_KEY signs every API token AND encrypts customer phone numbers through
django_cryptography. The encryption half makes it unrotatable, so production is
stuck on an 11-character key — and every signed-in user, down to the lowest
cashier, holds a valid HS256 token that can be brute-forced offline against it.
Recovering the key means minting a token for any user id, platform admin
included.

PyJWT has nothing to do with django_cryptography, so this half decouples with
no data migration at all.
"""
from __future__ import annotations

import jwt
import pytest
from django.conf import settings
from django.test import TestCase, override_settings

from platform_apps.users.jwt_auth import decode_token, issue_tokens
from platform_apps.users.models import PlatformUser

STRONG = "a-long-random-signing-key-that-is-not-the-secret-key-0123456789"
OTHER = "a-different-long-random-signing-key-9876543210-abcdefghijklmnop"


class JwtSigningKeyTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="signer@example.com", password="secret", full_name="Owner"
        )

    @override_settings(JWT_SIGNING_KEY=STRONG)
    def test_tokens_are_signed_with_the_dedicated_key(self):
        token = issue_tokens(self.user)["access"]

        decoded = jwt.decode(
            token, STRONG, algorithms=["HS256"], issuer="business-hub"
        )
        self.assertEqual(decoded["sub"], str(self.user.id))

    @override_settings(JWT_SIGNING_KEY=STRONG)
    def test_the_weak_secret_key_no_longer_verifies_new_tokens(self):
        """The whole point: SECRET_KEY's strength stops being what protects the
        API."""
        token = issue_tokens(self.user)["access"]

        with self.assertRaises(jwt.InvalidTokenError):
            jwt.decode(
                token,
                settings.SECRET_KEY,
                algorithms=["HS256"],
                issuer="business-hub",
            )

    @override_settings(JWT_SIGNING_KEY=STRONG)
    def test_a_token_signed_with_the_old_key_is_still_accepted(self):
        """A rotation must not sign every shop out at the moment of deploy."""
        legacy = jwt.encode(
            {
                "sub": str(self.user.id),
                "email": self.user.email,
                "token_type": "access",
                "iss": "business-hub",
                "exp": 9999999999,
                "tv": 0,
            },
            settings.SECRET_KEY,
            algorithm="HS256",
        )

        payload = decode_token(legacy, expected_type="access")

        self.assertEqual(payload["sub"], str(self.user.id))

    @override_settings(JWT_SIGNING_KEY=STRONG)
    def test_a_token_signed_with_neither_key_is_rejected(self):
        """The fallback must widen what is accepted by exactly one key, not
        turn verification into a formality."""
        forged = jwt.encode(
            {
                "sub": str(self.user.id),
                "token_type": "access",
                "iss": "business-hub",
                "exp": 9999999999,
            },
            OTHER,
            algorithm="HS256",
        )

        with self.assertRaises(jwt.InvalidTokenError):
            decode_token(forged, expected_type="access")

    @override_settings(JWT_SIGNING_KEY=STRONG)
    def test_an_expired_token_reports_expiry_not_a_bad_signature(self):
        """Trying the second key must not turn "your session ended" into "not
        our token" — the client would fall through instead of refreshing."""
        expired = jwt.encode(
            {
                "sub": str(self.user.id),
                "token_type": "access",
                "iss": "business-hub",
                "exp": 1,
            },
            STRONG,
            algorithm="HS256",
        )

        with self.assertRaises(jwt.ExpiredSignatureError):
            decode_token(expired, expected_type="access")

    def test_it_falls_back_to_secret_key_when_unset(self):
        """Existing deployments must keep working with no new env var."""
        self.assertTrue(settings.JWT_SIGNING_KEY)
        token = issue_tokens(self.user)["access"]
        payload = decode_token(token, expected_type="access")
        self.assertEqual(payload["sub"], str(self.user.id))

    @override_settings(JWT_SIGNING_KEY=STRONG)
    def test_refresh_tokens_use_the_new_key_too(self):
        """A refresh token still signed with the weak key would leave the long
        -lived credential exactly as forgeable as before."""
        refresh = issue_tokens(self.user)["refresh"]

        decoded = jwt.decode(
            refresh, STRONG, algorithms=["HS256"], issuer="business-hub"
        )
        self.assertEqual(decoded["token_type"], "refresh")

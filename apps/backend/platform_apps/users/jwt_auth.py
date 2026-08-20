"""Self-contained JWT auth (HS256, signed with Django SECRET_KEY).

Lives alongside the Firebase adapter: both use ``Authorization: Bearer <token>``,
but our tokens are HS256-signed with SECRET_KEY while Firebase tokens are
RS256-signed by Google. [JWTAuthentication] only claims a token whose signature
verifies against our secret and returns ``None`` otherwise, so the Firebase
authenticator still gets its turn. This gives sync clients a token flow that
works without a live Firebase project.
"""

from __future__ import annotations

import uuid
import os
from datetime import datetime, timedelta, timezone

import jwt
from django.conf import settings
from django.contrib.auth import get_user_model
from django.db.models import F
from rest_framework import authentication, exceptions

User = get_user_model()

_ALGORITHM = "HS256"
_ISSUER = "business-hub"
#: Short, because a leaked access token cannot be individually withdrawn — only
#: the whole account can be (see revoke_user_tokens). Twelve hours covers a
#: full trading day, so a shop that opens and closes never refreshes mid-sale,
#: and a token copied off a device is worthless by the next morning.
#:
#: This was 365 days. Shortening it was only safe once the counter app learned
#: to renew on a 401; before that, any reduction would have logged every till
#: out at the moment the token expired.
ACCESS_TOKEN_LIFETIME = timedelta(
    hours=int(os.getenv("ACCESS_TOKEN_LIFETIME_HOURS", "12"))
)

#: Long, because this is what keeps a shopkeeper signed in between days. It is
#: exchanged for a new pair on every use and is revocable through the same
#: token_version check, so its length is not the exposure the access token's
#: length was.
REFRESH_TOKEN_LIFETIME = timedelta(
    days=int(os.getenv("REFRESH_TOKEN_LIFETIME_DAYS", "180"))
)


def _encode(*, user, token_type: str, lifetime: timedelta) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user.id),
        "email": user.email,
        "token_type": token_type,
        "iss": _ISSUER,
        "iat": int(now.timestamp()),
        "exp": int((now + lifetime).timestamp()),
        "jti": uuid.uuid4().hex,
        # The user's revocation counter at the moment of minting. Authentication
        # compares this against the stored value, so bumping the stored value
        # invalidates every token issued before the bump.
        "tv": int(getattr(user, "token_version", 0) or 0),
    }
    # Signed with JWT_SIGNING_KEY, which defaults to SECRET_KEY but can be set
    # to something long and random independently. See the settings note: the
    # encryption half of SECRET_KEY makes it unrotatable, and an 11-character
    # key signing tokens is brute-forceable offline from any cashier's token.
    return jwt.encode(payload, settings.JWT_SIGNING_KEY, algorithm=_ALGORITHM)


def issue_tokens(user) -> dict[str, object]:
    """Return an access+refresh token pair for ``user``."""
    return {
        "access": _encode(user=user, token_type="access", lifetime=ACCESS_TOKEN_LIFETIME),
        "refresh": _encode(user=user, token_type="refresh", lifetime=REFRESH_TOKEN_LIFETIME),
        "token_type": "Bearer",
        "expires_in": int(ACCESS_TOKEN_LIFETIME.total_seconds()),
    }


def _decode_with_either_key(token: str) -> dict:
    """Verify against the current signing key, then the old one.

    Rotating JWT_SIGNING_KEY invalidates every token signed with the previous
    value. Accepting the old key too means a rotation does not sign every shop
    out at the moment of deploy — tokens minted before the change keep working
    until they expire on their own.

    When JWT_SIGNING_KEY is unset the two are the same string and this is a
    single attempt, so nothing is weakened by the fallback existing. Once the
    old key is genuinely retired, drop SECRET_KEY from the list; leaving a
    known-weak key permanently accepted would waste the whole point of moving
    away from it.
    """
    options = {"require": ["exp", "sub", "token_type"]}
    keys = [settings.JWT_SIGNING_KEY]
    if settings.SECRET_KEY != settings.JWT_SIGNING_KEY:
        keys.append(settings.SECRET_KEY)

    last_error: jwt.InvalidTokenError | None = None
    for key in keys:
        try:
            return jwt.decode(
                token,
                key,
                algorithms=[_ALGORITHM],
                issuer=_ISSUER,
                # "tv" is deliberately NOT required. Tokens minted before that
                # claim existed are still legitimately signed, and rejecting
                # them outright would sign out every shop at deploy time. They
                # are treated as version 0, so the first revocation invalidates
                # them like any other.
                options=options,
            )
        except jwt.ExpiredSignatureError:
            # Expiry is not a key problem — trying the other key cannot help,
            # and swallowing it would turn "your session ended" into "not our
            # token", which makes the client fall through to another
            # authenticator instead of refreshing.
            raise
        except jwt.InvalidTokenError as exc:
            last_error = exc
    raise last_error or jwt.InvalidTokenError("Token could not be verified.")


def decode_token(token: str, *, expected_type: str) -> dict:
    """Decode one of *our* tokens or raise AuthenticationFailed.

    Raises ``InvalidTokenError`` (subclass) when the token is not ours so callers
    can distinguish "not my token" from "my token but bad".
    """
    payload = _decode_with_either_key(token)
    if payload.get("token_type") != expected_type:
        # Not the token we expected here (e.g. an access token at the refresh
        # endpoint). Raise the jwt error type so callers treat it like any other
        # invalid token (JWTAuthentication falls through; refresh view -> 401).
        raise jwt.InvalidTokenError("Wrong token type.")
    return payload


def token_version_matches(user, payload: dict) -> bool:
    """Whether this token was minted before the user's access was withdrawn.

    A token with no ``tv`` claim predates the field and counts as version 0, so
    existing sessions survive the deploy and are revocable from then on.
    """
    return int(payload.get("tv", 0) or 0) == int(getattr(user, "token_version", 0) or 0)


def revoke_user_tokens(user) -> None:
    """Withdraw every token this user currently holds.

    Deliberately account-wide rather than per-device: the token is minted at
    login, which never learns which device asked, so there is nothing in it to
    revoke selectively. Signing a person out of all their devices when an admin
    revokes one is a wider action than requested, but it is the safe direction
    to err — and it is strictly better than the previous behaviour, which
    revoked nothing at all.
    """
    type(user).objects.filter(pk=user.pk).update(token_version=F("token_version") + 1)


class JWTAuthentication(authentication.BaseAuthentication):
    keyword = "Bearer"

    def authenticate(self, request):
        header = authentication.get_authorization_header(request).split()
        if not header or header[0].lower() != self.keyword.lower().encode():
            return None
        if len(header) != 2:
            return None
        token = header[1].decode()

        try:
            payload = decode_token(token, expected_type="access")
        except jwt.ExpiredSignatureError as exc:
            # Signature verified => it is our token, just expired.
            raise exceptions.AuthenticationFailed("Access token has expired.") from exc
        except jwt.InvalidTokenError:
            # Not our token (e.g. a Firebase ID token) — let the next authenticator try.
            return None

        try:
            user = User.objects.get(pk=payload["sub"])
        except (User.DoesNotExist, ValueError, KeyError) as exc:
            raise exceptions.AuthenticationFailed("User for token not found.") from exc
        if not user.is_active:
            raise exceptions.AuthenticationFailed("User is inactive.")
        if not token_version_matches(user, payload):
            # Signed, unexpired, and withdrawn. This is the check that makes
            # "sign out all devices" mean something on the server rather than
            # being a request the client is trusted to honour.
            raise exceptions.AuthenticationFailed("Session was signed out.")
        return (user, token)

    def authenticate_header(self, request):
        return self.keyword

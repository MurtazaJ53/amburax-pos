"""Verify a counter PIN against the stored hash.

The PIN is a screen lock, not a way in. A shift changes hands and the till
should not need a full email-and-password sign-in at the counter — but until
now nothing on the server would tell you whether four digits were the right
four digits. The membership carried a ``pos_pin_hash``, settings could write
it, and no code path ever read it back. The web route accepted any four digits
and returned ``role: cashier``.

So this is the missing half. It answers one question — does this PIN match the
signed-in user's membership on this shop — and nothing else. It cannot create a
session, and it will not tell an anonymous caller anything.
"""
from __future__ import annotations

import logging

from django.contrib.auth.hashers import check_password
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.throttling import UserRateThrottle
from rest_framework.views import APIView

from platform_apps.audit.services import create_workspace_audit_event
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

logger = logging.getLogger(__name__)


class PosPinThrottle(UserRateThrottle):
    """A four-digit PIN is ten thousand guesses, which a script clears in
    seconds. The rate is what turns a trivial space into an impractical one.

    Scoped per user rather than per IP: every till in a shop shares one public
    address, so an IP-scoped limit would let one attacker lock out an entire
    shop's counters — and would count a busy shop's honest re-locks as an
    attack.

    Unlike sign-in, this one fails CLOSED. If the cache is unreachable we
    cannot count attempts, and an uncounted PIN endpoint is an open brute-force
    window. The cost of failing closed is that a cashier signs in with their
    password instead, which is an inconvenience; the cost of failing open is an
    unlimited guessing oracle against a four-digit secret.
    """

    # The rate lives in DEFAULT_THROTTLE_RATES so an operator can tune it
    # without a deploy. A missing key raises at startup, which is the right
    # direction to fail for the thing guarding a four-digit secret.
    scope = "pos_pin"

    def allow_request(self, request, view):
        try:
            return super().allow_request(request, view)
        except Exception:
            logger.error(
                "POS PIN throttle cache unavailable — refusing the unlock. Sign "
                "in with a password until the cache is reachable.",
                exc_info=True,
            )
            return False


class PosPinVerifyView(APIView):
    """POST {"pin": "1234"} -> 200 if it matches this user's membership."""

    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [PosPinThrottle]

    def post(self, request, shop_id):
        # STAFF is the floor: every role that works a counter has at least this.
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.STAFF
        )

        pin = request.data.get("pin") if isinstance(request.data, dict) else None
        pin = str(pin or "").strip()

        if not membership.pos_pin_hash:
            # Deliberately distinguished from a wrong PIN. This is not a secret
            # — the membership serialiser already reports has_pos_pin — and a
            # cashier staring at a lock screen nobody set up needs to be told
            # that, not told their PIN is wrong.
            return Response(
                {
                    "detail": "No counter PIN has been set for you on this shop. "
                    "An owner or admin can set one in Team settings.",
                    "code": "pin_not_set",
                },
                status=status.HTTP_409_CONFLICT,
            )

        if not pin or not check_password(pin, membership.pos_pin_hash):
            create_workspace_audit_event(
                shop=membership.shop,
                actor_user=request.user,
                actor_role=membership.role,
                category="security",
                event_type="pos_pin.verify.failed",
                entity_type="shop_membership",
                entity_id=str(membership.id),
                entity_label=membership.email or str(request.user),
                summary="A counter PIN unlock was refused.",
                source_surface="backend_api",
            )
            return Response(
                {"detail": "That PIN is not correct.", "code": "pin_invalid"},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        return Response(
            {
                "verified": True,
                "shop_id": str(membership.shop_id),
                "role": membership.role,
            },
            status=status.HTTP_200_OK,
        )

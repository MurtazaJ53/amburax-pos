from __future__ import annotations

from datetime import timedelta

from django.conf import settings
from django.utils import timezone
from rest_framework.permissions import BasePermission


class IsPlatformAdminUser(BasePermission):
    """Read access to platform-admin surfaces."""

    message = "Platform admin access is required."

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.is_platform_admin)


#: How long an MFA verification counts as fresh for a destructive action.
#: Short on purpose: this is the window in which a stolen device or token can
#: suspend a shop. Long enough that an admin working through several shops is
#: not re-prompted constantly.
MFA_FRESHNESS = timedelta(
    minutes=int(getattr(settings, "PLATFORM_ADMIN_MFA_FRESHNESS_MINUTES", 30))
)


def _last_mfa_verification(user):
    """The most recent MFA verification this user completed, or None.

    Read from OUR database rather than from a header or cookie, because the
    caller is exactly who this is defending against.
    """
    moments = []
    if user.mfa_totp_enabled and user.mfa_totp_last_verified_at:
        moments.append(user.mfa_totp_last_verified_at)

    passkey_verified_at = (
        user.passkeys.filter(is_active=True, last_verified_at__isnull=False)
        .order_by("-last_verified_at")
        .values_list("last_verified_at", flat=True)
        .first()
    )
    if passkey_verified_at:
        moments.append(passkey_verified_at)

    return max(moments) if moments else None


class IsVerifiedPlatformAdmin(BasePermission):
    """Platform admin, with MFA actually completed recently.

    MFA was enforced only in the website's page-rendering layer
    (apps/admin_web/src/lib/server-guards.ts). The Django views behind it
    checked one boolean — is_platform_admin — and nothing else. So anyone
    holding a platform-admin bearer token could suspend a shop, reinstate one,
    or change a plan with curl, and MFA never entered the picture.

    That matters because a token is exactly the thing MFA is supposed to
    survive: a device left signed in, a token copied off one, or a token forged
    against a weak signing key. In every one of those cases the attacker has
    the token and has never touched the second factor.

    Applied to the DESTRUCTIVE platform endpoints only. Listing shops stays on
    IsPlatformAdminUser, because an admin who cannot look at a dashboard
    without re-authenticating will find a way to stop being an admin.

    Freshness comes from our own columns — mfa_totp_last_verified_at, and
    passkey last_verified_at — never from a request header or cookie, since the
    caller is who this is defending against.
    """

    message = (
        "This action needs a fresh multi-factor verification. "
        "Verify in Security, then try again."
    )

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated and user.is_platform_admin):
            return False

        if not (user.mfa_totp_enabled or user.passkey_enabled):
            # A platform admin with no second factor at all cannot perform
            # destructive actions. Deliberately not a silent pass: "they have
            # not set it up yet" is the state this is designed to refuse.
            self.message = (
                "Set up multi-factor authentication in Security before using "
                "platform admin actions."
            )
            return False

        verified_at = _last_mfa_verification(user)
        if verified_at is None:
            return False
        return timezone.now() - verified_at <= MFA_FRESHNESS

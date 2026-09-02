"""Self-serve password reset.

`POST /api/v1/session/password-reset/`          - ask for a link (unauthenticated)
`POST /api/v1/session/password-reset/confirm/`  - spend the link (unauthenticated)

Two rules shape everything here.

The first is that asking must not tell a stranger who has an account. Typing
somebody else's email into this form is free, so the reply is the same
sentence whether or not the address is on the system.

The second is that the reply must be true. A shop owner locked out of their
own till needs to know whether an email is actually on its way, so a send that
fails says so plainly rather than reporting a cheerful 200 for a message that
never left. The raw token is never in the response - a stranger who could read
it off the screen would not need the email at all, and that is the enumeration
hole wearing a helpful face.
"""
from __future__ import annotations

import logging
import os
import secrets
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.utils import timezone
from rest_framework import serializers, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle
from rest_framework.views import APIView

from platform_apps.common.emailer import send_password_reset_email
from platform_apps.users.models import PasswordResetToken

logger = logging.getLogger(__name__)

User = get_user_model()

#: Said to everyone who asks, account or not.
ACCEPTED_MESSAGE = (
    "If an account exists for that email, a reset link is on its way. "
    "Check your inbox, and the spam folder."
)

#: Said when the mailer told us it did not send. Deliberately about the mail
#: system rather than the account, because it is reached only when mail is
#: broken for everybody.
UNDELIVERED_MESSAGE = (
    "We could not send the reset email just now, so nothing has been sent. "
    "This is a problem on our side, not with your account. Please try again "
    "shortly, or contact support to have the password reset for you."
)


class _FailOpenAnonThrottle(AnonRateThrottle):
    """Rate limit, but never let the limiter take the door off its hinges.

    Same reasoning as sign-in (see token_views.LoginRateThrottle): when the
    cache is unreachable, counting stops and the request proceeds, logged at
    ERROR. A shopkeeper who cannot reset a password because Redis is down is
    locked out just as thoroughly as one who forgot it.
    """

    def allow_request(self, request, view):
        try:
            return super().allow_request(request, view)
        except Exception:
            logger.error(
                "Password-reset throttle cache unavailable - allowing the "
                "request and counting nothing.",
                exc_info=True,
            )
            return True


class PasswordResetRequestThrottle(_FailOpenAnonThrottle):
    # Low on purpose: this endpoint sends mail to an address the caller chose,
    # so an open one is a way to post junk to strangers from our domain.
    rate = "5/hour"


class PasswordResetConfirmThrottle(_FailOpenAnonThrottle):
    # Guessing a 43-character token is hopeless, but a slow ceiling costs a
    # real user nothing.
    rate = "20/hour"


class PasswordResetRequestSerializer(serializers.Serializer):
    email = serializers.EmailField()


class PasswordResetConfirmSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=255, trim_whitespace=True)
    password = serializers.CharField(
        min_length=8, write_only=True, style={"input_type": "password"}
    )


def _ttl_label() -> str:
    hours = int(PasswordResetToken.TTL / timedelta(hours=1))
    return "1 hour" if hours == 1 else f"{hours} hours"


def issue_password_reset(user) -> tuple[PasswordResetToken, str]:
    """Mint a reset token for `user` and retire any earlier live ones.

    Returns the row and the raw token. Only the hash goes to the database, so
    this is the last moment the raw value exists anywhere but the email.
    """
    raw_token = secrets.token_urlsafe(32)
    now = timezone.now()
    with transaction.atomic():
        # An older link stops working the moment a newer one is asked for.
        # Otherwise every "I didn't get it, send another" leaves another key
        # under another doormat.
        PasswordResetToken.objects.filter(
            user=user, used_at__isnull=True, expires_at__gt=now
        ).update(used_at=now)
        reset = PasswordResetToken.objects.create(
            user=user,
            token_hash=PasswordResetToken.hash_token(raw_token),
            expires_at=now + PasswordResetToken.TTL,
        )
    return reset, raw_token


def build_reset_link(raw_token: str) -> str:
    frontend_url = os.getenv("FRONTEND_URL", "http://localhost:3000").rstrip("/")
    return f"{frontend_url}/reset-password?token={raw_token}"


class PasswordResetRequestView(APIView):
    """POST {email} -> the same 200 for every caller, or a plain failure."""

    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_classes = [PasswordResetRequestThrottle]

    def post(self, request):
        serializer = PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data["email"].strip().lower()

        user = User.objects.filter(email__iexact=email, is_active=True).first()
        if user is None:
            # No account, nothing to send, and no hint that this was the
            # branch taken. Logged so an operator can still see the attempt.
            logger.info("Password reset asked for an address with no active account.")
            return Response({"detail": ACCEPTED_MESSAGE}, status=status.HTTP_200_OK)

        reset, raw_token = issue_password_reset(user)
        result = send_password_reset_email(
            to=user.email,
            reset_link=build_reset_link(raw_token),
            ttl_label=_ttl_label(),
        )
        reset.delivery_status = (result.get("status") or "")[:64]
        reset.save(update_fields=["delivery_status", "updated_at"])

        if not result.get("ok"):
            # The honest branch. Nothing arrived, so do not say it did - and
            # burn the token, since a link nobody received is only a liability.
            #
            # Yes, this reply differs from the unknown-email reply, and a
            # determined prober could read existence out of that difference.
            # It is reachable only while mail is broken for every account, and
            # the alternative is telling a locked-out shopkeeper to keep
            # checking an inbox that will never receive anything.
            PasswordResetToken.objects.filter(pk=reset.pk).update(used_at=timezone.now())
            logger.error(
                "Password reset email was NOT sent (status=%s error=%s)",
                result.get("status"),
                result.get("error"),
            )
            return Response(
                {"detail": UNDELIVERED_MESSAGE, "email_sent": False},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        # Deliberately the same body, byte for byte, as the unknown-address
        # reply above. An "email_sent": true here would have been a free
        # membership check: send it to an address, read the flag, learn
        # whether that person banks with us.
        return Response({"detail": ACCEPTED_MESSAGE}, status=status.HTTP_200_OK)


class PasswordResetConfirmView(APIView):
    """POST {token, password} -> a password the sign-in endpoint accepts."""

    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_classes = [PasswordResetConfirmThrottle]

    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        raw_token = serializer.validated_data["token"]
        password = serializer.validated_data["password"]

        reset = (
            PasswordResetToken.objects.select_related("user")
            .filter(token_hash=PasswordResetToken.hash_token(raw_token))
            .first()
        )
        # One sentence for missing, spent and expired alike: which of the
        # three it was is not the visitor's business, and the fix is the same.
        if reset is None or not reset.is_live() or not reset.user.is_active:
            return Response(
                {"detail": "That reset link is no longer valid. Please request a new one."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user = reset.user
        try:
            validate_password(password, user=user)
        except DjangoValidationError as exc:
            return Response(
                {"password": list(exc.messages)}, status=status.HTTP_400_BAD_REQUEST
            )

        with transaction.atomic():
            # Spend the token first, and only if it is still unspent, so two
            # simultaneous clicks cannot both go through.
            spent = PasswordResetToken.objects.filter(
                pk=reset.pk, used_at__isnull=True
            ).update(used_at=timezone.now())
            if not spent:
                return Response(
                    {
                        "detail": "That reset link has already been used. "
                        "Please request a new one."
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            user.set_password(password)
            # Whoever knew the old password may be the reason for this reset,
            # so every issued token stops working too. Without this, an
            # intruder's session survives the reset that was meant to end it.
            user.token_version = (user.token_version or 0) + 1
            user.save(update_fields=["password", "token_version"])

        logger.info("Password reset completed for user %s", user.pk)
        return Response(
            {
                "detail": "Your password has been changed. You can sign in with it now.",
                "email": user.email,
            },
            status=status.HTTP_200_OK,
        )

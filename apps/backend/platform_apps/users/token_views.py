"""Token endpoints for the self-contained JWT flow."""

from __future__ import annotations

import logging

import jwt
from django.contrib.auth import authenticate, get_user_model
from rest_framework import permissions, serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.throttling import AnonRateThrottle

from platform_apps.users.jwt_auth import (
    decode_token,
    issue_tokens,
    token_version_matches,
)

logger = logging.getLogger(__name__)


class LoginRateThrottle(AnonRateThrottle):
    """Rate-limit sign-in, but never let the limiter take sign-in down.

    DRF throttles count attempts in the Django cache, which in production is
    Redis. When Redis was unreachable this raised, and the exception surfaced
    as a 500 on /session/token/ — nobody could sign in at all, because the
    thing protecting the door had become the thing blocking it. Measured, not
    theorised: that is exactly what happened on 20 Aug 2026.

    So it fails OPEN. A cache outage means attempts stop being counted, which
    briefly removes brute-force protection; the alternative is a total sign-in
    outage for every shop. For a POS, a shopkeeper locked out of their own till
    is the worse failure, and an unavailable cache is a condition the operator
    can see and fix, whereas a locked-out shop just stops trading.

    The failure is logged at ERROR so it cannot pass silently — degrading
    quietly is how a temporary outage becomes a permanent hole.
    """

    rate = '5/min'

    def allow_request(self, request, view):
        try:
            return super().allow_request(request, view)
        except Exception:
            logger.error(
                "Login throttle cache unavailable — allowing the request and "
                "counting nothing. Brute-force protection is OFF until the "
                "cache is reachable.",
                exc_info=True,
            )
            return True

User = get_user_model()


class TokenObtainSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, style={"input_type": "password"})


class TokenRefreshSerializer(serializers.Serializer):
    refresh = serializers.CharField(write_only=True)


class SessionTokenObtainView(APIView):
    """POST email + password -> {access, refresh}."""

    authentication_classes: list = []
    permission_classes = [permissions.AllowAny]
    throttle_classes = [LoginRateThrottle]

    def post(self, request):
        serializer = TokenObtainSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data["email"].strip().lower()
        password = serializer.validated_data["password"]

        user = authenticate(request, username=email, password=password)
        if user is None:
            # Fall back to an explicit lookup so a case/whitespace mismatch on the
            # email doesn't read as a wrong password.
            candidate = User.objects.filter(email__iexact=email).first()
            if candidate is None or not candidate.check_password(password):
                return Response(
                    {"detail": "Invalid email or password."},
                    status=status.HTTP_401_UNAUTHORIZED,
                )
            user = candidate
        if not user.is_active:
            return Response({"detail": "User is inactive."}, status=status.HTTP_403_FORBIDDEN)

        return Response(issue_tokens(user), status=status.HTTP_200_OK)


class SessionTokenRefreshView(APIView):
    """POST a refresh token -> a fresh {access, refresh} pair."""

    authentication_classes: list = []
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = TokenRefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            payload = decode_token(serializer.validated_data["refresh"], expected_type="refresh")
        except jwt.InvalidTokenError:
            return Response(
                {"detail": "Invalid or expired refresh token."},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        user = User.objects.filter(pk=payload["sub"], is_active=True).first()
        if user is None:
            return Response(
                {"detail": "User for token not found."}, status=status.HTTP_401_UNAUTHORIZED
            )
        if not token_version_matches(user, payload):
            # Without this the refresh token is a way back in after being signed
            # out: the access token would be rejected, and the client would
            # quietly trade its refresh token for a working one.
            return Response(
                {"detail": "Session was signed out."},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        return Response(issue_tokens(user), status=status.HTTP_200_OK)

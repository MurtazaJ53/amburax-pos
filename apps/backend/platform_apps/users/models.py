from __future__ import annotations

import hashlib
from datetime import timedelta

from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils import timezone

from platform_apps.common.models import SourceTrackedModel, UUIDStampedModel
from platform_apps.users.managers import PlatformUserManager


class PlatformUser(SourceTrackedModel, AbstractUser):
    username = None
    email = models.EmailField(unique=True)
    full_name = models.CharField(max_length=255, blank=True)
    firebase_uid = models.CharField(max_length=128, blank=True, null=True, unique=True)
    timezone = models.CharField(max_length=64, default="Asia/Kolkata")
    is_platform_admin = models.BooleanField(default=False)
    mfa_totp_secret = models.CharField(max_length=64, blank=True)
    mfa_totp_pending_secret = models.CharField(max_length=64, blank=True)
    mfa_totp_enabled_at = models.DateTimeField(blank=True, null=True)
    mfa_totp_last_verified_at = models.DateTimeField(blank=True, null=True)

    #: Bumped whenever this user's access must be withdrawn. Every token carries
    #: the value it was minted with, and authentication rejects any token whose
    #: value has fallen behind — which is what makes a token revocable at all.
    #:
    #: Without this the only way out of an issued token was waiting for it to
    #: expire. "Sign out all devices" wrote a REVOKED row that nothing read, so
    #: it reported success while the token kept working.
    token_version = models.PositiveIntegerField(default=0)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS: list[str] = []

    objects = PlatformUserManager()

    @property
    def mfa_totp_enabled(self) -> bool:
        return bool(self.mfa_totp_secret and self.mfa_totp_enabled_at)

    @property
    def passkey_enabled(self) -> bool:
        return self.passkeys.filter(is_active=True).exists()

    def __str__(self) -> str:
        return self.full_name or self.email


class UserPasskeyCredential(UUIDStampedModel):
    user = models.ForeignKey(
        PlatformUser,
        on_delete=models.CASCADE,
        related_name="passkeys",
    )
    label = models.CharField(max_length=255, blank=True)
    credential_id = models.CharField(max_length=255, unique=True)
    public_key_spki = models.TextField()
    cose_algorithm = models.IntegerField(default=-7)
    sign_count = models.PositiveBigIntegerField(default=0)
    transports_json = models.JSONField(default=list, blank=True)
    aaguid = models.CharField(max_length=36, blank=True)
    last_verified_at = models.DateTimeField(blank=True, null=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["-is_active", "-last_verified_at", "-updated_at", "label"]
        indexes = [
            models.Index(fields=["user", "is_active"]),
            models.Index(fields=["user", "updated_at"]),
        ]

    def __str__(self) -> str:
        return self.label or self.credential_id


class PasswordResetToken(UUIDStampedModel):
    """One outstanding "forgot password" link.

    Only a hash of the token is stored. The raw value exists in exactly two
    places: the email that was sent, and the link the person clicks. A dump of
    this table therefore hands an attacker nothing usable — which matters more
    here than anywhere else in the schema, because a reset token is a way to
    take over an account without knowing its password.

    A token is spent by `used_at`, not by deletion, so a second click on the
    same link is refused rather than silently starting a fresh reset.
    """

    #: How long a link stays good. Long enough to survive a slow inbox, short
    #: enough that a forwarded email stops being a key by the next morning.
    TTL = timedelta(hours=1)

    user = models.ForeignKey(
        PlatformUser,
        on_delete=models.CASCADE,
        related_name="password_reset_tokens",
    )
    token_hash = models.CharField(max_length=64, unique=True, db_index=True)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(blank=True, null=True)
    #: What the mailer reported. Kept so an operator can answer "did it
    #: actually go out?" without guessing from logs.
    delivery_status = models.CharField(max_length=64, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "-created_at"])]

    @staticmethod
    def hash_token(raw_token: str) -> str:
        return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()

    def is_live(self, *, now=None) -> bool:
        now = now or timezone.now()
        return self.used_at is None and self.expires_at > now

    def __str__(self) -> str:
        return f"Password reset for {self.user_id} (expires {self.expires_at:%Y-%m-%d %H:%M})"

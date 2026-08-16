from __future__ import annotations

from django.contrib.auth.models import AbstractUser
from django.db import models

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

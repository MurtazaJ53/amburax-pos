from __future__ import annotations

from datetime import timedelta

from django.utils import timezone
from rest_framework import serializers

from platform_apps.shops.models import ShopMembership
from platform_apps.shops.roles import (
    get_membership_role_label,
    get_membership_role_product_profile,
    get_membership_role_summary,
)
from platform_apps.users.mfa import (
    MFA_CHALLENGE_WINDOW_SECONDS,
    MFA_ISSUER_LABEL,
    build_totp_otpauth_uri,
    format_totp_secret,
    generate_totp_secret,
    verify_totp_code,
)
from platform_apps.users.models import PlatformUser, UserPasskeyCredential
from platform_apps.users.webauthn import (
    WEBAUTHN_VERIFY_WINDOW_SECONDS,
    build_mfa_security_stamp,
    build_passkey_authentication_options,
    build_passkey_registration_options,
    build_passkey_summary,
    delete_passkey_credential,
    register_passkey_credential,
    verify_passkey_assertion,
)


class SessionUserSerializer(serializers.ModelSerializer):
    mfa_totp_enabled = serializers.SerializerMethodField()
    passkey_enabled = serializers.SerializerMethodField()
    passkey_count = serializers.SerializerMethodField()
    mfa_security_stamp = serializers.SerializerMethodField()

    class Meta:
        model = PlatformUser
        fields = (
            "id",
            "email",
            "full_name",
            "firebase_uid",
            "timezone",
            "is_platform_admin",
            "mfa_totp_enabled",
            "mfa_totp_enabled_at",
            "mfa_totp_last_verified_at",
            "passkey_enabled",
            "passkey_count",
            "mfa_security_stamp",
        )

    def get_mfa_totp_enabled(self, obj):
        return obj.mfa_totp_enabled

    def get_passkey_enabled(self, obj):
        return build_passkey_summary(obj)["passkey_enabled"]

    def get_passkey_count(self, obj):
        return build_passkey_summary(obj)["passkey_count"]

    def get_mfa_security_stamp(self, obj):
        return build_mfa_security_stamp(obj)


class MembershipShopSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    name = serializers.CharField()
    slug = serializers.CharField()
    currency_code = serializers.CharField()
    timezone = serializers.CharField()
    is_active = serializers.BooleanField()
    plan_tier = serializers.CharField()
    enabled_features = serializers.DictField(
        child=serializers.BooleanField(),
    )
    # Everything a receipt needs to identify the shop it came from. Without
    # these the POS fell back to a placeholder GSTIN baked into the component,
    # so a real bill could carry somebody else's tax number.
    region_code = serializers.CharField()
    gstin = serializers.CharField()
    logo_data = serializers.CharField()
    brand_color = serializers.CharField()
    business_phone = serializers.SerializerMethodField()
    # Needed so the web can put a one-tap UPI pay link in khata reminders, the
    # same as the phone does. Public payee id, not a secret.
    upi_vpa = serializers.SerializerMethodField()

    def get_business_phone(self, obj):
        return obj.settings_json.get("business_phone", "")

    def get_upi_vpa(self, obj):
        return obj.settings_json.get("upi_vpa", "")


class SessionMembershipSerializer(serializers.ModelSerializer):
    shop = serializers.SerializerMethodField()
    role_label = serializers.SerializerMethodField()
    role_summary = serializers.SerializerMethodField()
    role_profile = serializers.SerializerMethodField()

    class Meta:
        model = ShopMembership
        fields = (
            "id",
            "role",
            "role_label",
            "role_summary",
            "role_profile",
            "status",
            "permissions_version",
            "permissions_json",
            "shop",
        )

    def get_shop(self, obj):
        return MembershipShopSerializer(obj.shop).data

    def get_role_label(self, obj):
        return get_membership_role_label(obj.role)

    def get_role_summary(self, obj):
        return get_membership_role_summary(obj.role)

    def get_role_profile(self, obj):
        return get_membership_role_product_profile(obj.role)


class UserMfaStatusSerializer(serializers.Serializer):
    totp_enabled = serializers.BooleanField()
    totp_pending_enrollment = serializers.BooleanField()
    enabled_at = serializers.DateTimeField(allow_null=True)
    last_verified_at = serializers.DateTimeField(allow_null=True)
    passkey_enabled = serializers.BooleanField()
    passkey_count = serializers.IntegerField()
    passkey_last_verified_at = serializers.DateTimeField(allow_null=True)
    security_stamp = serializers.CharField()
    issuer_label = serializers.CharField()
    account_label = serializers.CharField()
    challenge_window_seconds = serializers.IntegerField()
    pending_manual_secret = serializers.CharField(allow_blank=True)
    pending_otpauth_uri = serializers.CharField(allow_blank=True)


class UserMfaEnrollSerializer(serializers.Serializer):
    def save(self, *, user: PlatformUser) -> dict[str, object]:
        if not user.mfa_totp_enabled and not user.mfa_totp_pending_secret:
            user.mfa_totp_pending_secret = generate_totp_secret()
            user.save(update_fields=["mfa_totp_pending_secret", "updated_at"])

        return build_user_mfa_status_payload(user)


class UserMfaVerifySerializer(serializers.Serializer):
    purpose = serializers.ChoiceField(choices=["enroll", "challenge"])
    code = serializers.CharField(max_length=16)

    def validate(self, attrs):
        user: PlatformUser = self.context["user"]
        purpose = attrs["purpose"]
        secret = (
            user.mfa_totp_pending_secret
            if purpose == "enroll"
            else user.mfa_totp_secret
        )
        if not secret:
            raise serializers.ValidationError(
                {"purpose": "No matching MFA secret is ready for verification."}
            )
        if not verify_totp_code(secret=secret, code=attrs["code"]):
            raise serializers.ValidationError({"code": "Invalid authentication code."})
        return attrs

    def save(self, *, user: PlatformUser) -> dict[str, object]:
        purpose = self.validated_data["purpose"]
        now = timezone.now()
        updated_fields = ["mfa_totp_last_verified_at", "updated_at"]
        user.mfa_totp_last_verified_at = now

        if purpose == "enroll":
            user.mfa_totp_secret = user.mfa_totp_pending_secret
            user.mfa_totp_pending_secret = ""
            user.mfa_totp_enabled_at = now
            updated_fields.extend(
                ["mfa_totp_secret", "mfa_totp_pending_secret", "mfa_totp_enabled_at"]
            )

        user.save(update_fields=updated_fields)
        return {
            "status": build_user_mfa_status_payload(user),
            "verified_at": now,
            "verified_until": now + timedelta(seconds=MFA_CHALLENGE_WINDOW_SECONDS),
        }


class UserMfaDisableSerializer(serializers.Serializer):
    code = serializers.CharField(max_length=16)

    def validate(self, attrs):
        user: PlatformUser = self.context["user"]
        if not user.mfa_totp_enabled or not user.mfa_totp_secret:
            raise serializers.ValidationError(
                {"code": "No active MFA secret is enabled for this account."}
            )
        if not verify_totp_code(secret=user.mfa_totp_secret, code=attrs["code"]):
            raise serializers.ValidationError({"code": "Invalid authentication code."})
        return attrs

    def save(self, *, user: PlatformUser) -> dict[str, object]:
        user.mfa_totp_secret = ""
        user.mfa_totp_pending_secret = ""
        user.mfa_totp_enabled_at = None
        user.mfa_totp_last_verified_at = None
        user.save(
            update_fields=[
                "mfa_totp_secret",
                "mfa_totp_pending_secret",
                "mfa_totp_enabled_at",
                "mfa_totp_last_verified_at",
                "updated_at",
            ]
        )
        return build_user_mfa_status_payload(user)


class UserPasskeyCredentialSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserPasskeyCredential
        fields = (
            "id",
            "label",
            "credential_id",
            "cose_algorithm",
            "sign_count",
            "transports_json",
            "aaguid",
            "last_verified_at",
            "is_active",
            "created_at",
            "updated_at",
        )


class UserPasskeyRegistrationBeginSerializer(serializers.Serializer):
    def save(self, *, user: PlatformUser) -> dict[str, object]:
        return build_passkey_registration_options(user=user)


class UserPasskeyRegistrationFinishSerializer(serializers.Serializer):
    challenge_token = serializers.CharField()
    credential_id = serializers.CharField(max_length=255)
    client_data_json = serializers.CharField()
    attestation_object = serializers.CharField()
    transports = serializers.ListField(
        child=serializers.CharField(max_length=32),
        required=False,
        allow_empty=True,
    )
    label = serializers.CharField(required=False, allow_blank=True, max_length=255)

    def save(self, *, user: PlatformUser) -> UserPasskeyCredential:
        return register_passkey_credential(
            user=user,
            challenge_token=self.validated_data["challenge_token"],
            credential_id=self.validated_data["credential_id"],
            client_data_json=self.validated_data["client_data_json"],
            attestation_object=self.validated_data["attestation_object"],
            transports=self.validated_data.get("transports") or [],
            label=self.validated_data.get("label", ""),
        )


class UserPasskeyAssertionBeginSerializer(serializers.Serializer):
    def save(self, *, user: PlatformUser) -> dict[str, object]:
        if not user.passkeys.filter(is_active=True).exists():
            raise serializers.ValidationError(
                {"passkeys": "No active passkeys are registered for this account yet."}
            )
        return build_passkey_authentication_options(user=user)


class UserPasskeyAssertionFinishSerializer(serializers.Serializer):
    challenge_token = serializers.CharField()
    credential_id = serializers.CharField(max_length=255)
    client_data_json = serializers.CharField()
    authenticator_data = serializers.CharField()
    signature = serializers.CharField()

    def save(self, *, user: PlatformUser) -> dict[str, object]:
        result = verify_passkey_assertion(
            user=user,
            challenge_token=self.validated_data["challenge_token"],
            credential_id=self.validated_data["credential_id"],
            client_data_json=self.validated_data["client_data_json"],
            authenticator_data=self.validated_data["authenticator_data"],
            signature=self.validated_data["signature"],
        )
        result["status"] = build_user_mfa_status_payload(user)
        return result


class UserPasskeyDeleteSerializer(serializers.Serializer):
    passkey_id = serializers.UUIDField()

    def save(self, *, user: PlatformUser) -> UserPasskeyCredential:
        return delete_passkey_credential(
            user=user,
            passkey_id=self.validated_data["passkey_id"],
        )


def build_user_mfa_status_payload(user: PlatformUser) -> dict[str, object]:
    account_label = user.email
    pending_secret = user.mfa_totp_pending_secret.strip()
    passkey_summary = build_passkey_summary(user)
    return {
        "totp_enabled": user.mfa_totp_enabled,
        "totp_pending_enrollment": bool(pending_secret),
        "enabled_at": user.mfa_totp_enabled_at,
        "last_verified_at": user.mfa_totp_last_verified_at,
        "passkey_enabled": passkey_summary["passkey_enabled"],
        "passkey_count": passkey_summary["passkey_count"],
        "passkey_last_verified_at": passkey_summary["passkey_last_verified_at"],
        "security_stamp": build_mfa_security_stamp(user),
        "issuer_label": MFA_ISSUER_LABEL,
        "account_label": account_label,
        "challenge_window_seconds": max(
            MFA_CHALLENGE_WINDOW_SECONDS,
            WEBAUTHN_VERIFY_WINDOW_SECONDS,
        ),
        "pending_manual_secret": format_totp_secret(pending_secret) if pending_secret else "",
        "pending_otpauth_uri": (
            build_totp_otpauth_uri(secret=pending_secret, account_label=account_label)
            if pending_secret
            else ""
        ),
    }

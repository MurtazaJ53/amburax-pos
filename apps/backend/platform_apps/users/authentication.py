from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

import firebase_admin
from django.conf import settings
from django.contrib.auth import get_user_model
from django.utils.text import slugify
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials, firestore
from rest_framework import authentication, exceptions

from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.shops.roles import normalize_membership_role


User = get_user_model()


@lru_cache(maxsize=1)
def get_firebase_app():
    try:
        return firebase_admin.get_app()
    except ValueError:
        pass

    service_account_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
    if service_account_path:
        service_account = Path(service_account_path)
    else:
        service_account = (settings.BASE_DIR.parent.parent / "service-account.json").resolve()
        if not service_account.exists():
            service_account = None

    if service_account and service_account.exists():
        return firebase_admin.initialize_app(credentials.Certificate(str(service_account)))

    if os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
        return firebase_admin.initialize_app()

    return None


def bootstrap_memberships_from_firestore(user: User) -> None:
    if not user.firebase_uid:
        return

    app = get_firebase_app()
    if app is None:
        return

    db = firestore.client(app=app)
    user_doc = db.collection("users").document(user.firebase_uid).get()
    if not user_doc.exists:
        return

    user_payload = user_doc.to_dict() or {}
    shop_source_id = user_payload.get("shopId")
    if not shop_source_id:
        return

    shop_doc = db.collection("shops").document(shop_source_id).get()
    shop_payload = shop_doc.to_dict() if shop_doc.exists else {}

    is_shop_owner = str(shop_payload.get("ownerId") or "") == user.firebase_uid
    role = normalize_membership_role(
        user_payload.get("role"),
        is_shop_owner=is_shop_owner,
    )

    base_slug = slugify(shop_payload.get("name") or shop_source_id)[:36] or "shop"
    slug_candidate = f"{base_slug}-{str(shop_source_id)[:8]}".lower()
    shop, _ = Shop.objects.get_or_create(
        source_system="firebase",
        source_id=str(shop_source_id),
        defaults={
            "name": shop_payload.get("name") or f"Shop {shop_source_id}",
            "slug": slug_candidate,
            "legal_name": shop_payload.get("legalName") or "",
            "invite_code": shop_payload.get("inviteCode") or "",
            "settings_json": shop_payload.get("settings") or {},
            "owner_user": user if is_shop_owner else None,
            "source_shop_id": str(shop_source_id),
            "source_path": f"shops/{shop_source_id}",
        },
    )

    if shop.owner_user_id is None and is_shop_owner:
        shop.owner_user = user
        shop.save(update_fields=["owner_user", "updated_at"])

    membership, created = ShopMembership.objects.get_or_create(
        user=user,
        shop=shop,
        defaults={
            "role": role,
            "status": ShopMembership.Status.ACTIVE,
            "email": user.email,
            "phone": user_payload.get("phone") or "",
            "permissions_json": user_payload.get("permissions") or {},
            "source_system": "firebase",
            "source_id": str(user_doc.id),
            "source_shop_id": str(shop_source_id),
            "source_path": f"shops/{shop_source_id}/staff/{user.firebase_uid}",
        },
    )

    if not created:
        updated_fields: list[str] = []
        next_status = ShopMembership.Status.ACTIVE
        next_email = user.email or ""
        next_phone = user_payload.get("phone") or ""
        next_permissions = user_payload.get("permissions") or {}

        if membership.role != role:
            membership.role = role
            updated_fields.append("role")
        if membership.status != next_status:
            membership.status = next_status
            updated_fields.append("status")
        if membership.email != next_email:
            membership.email = next_email
            updated_fields.append("email")
        if membership.phone != next_phone:
            membership.phone = next_phone
            updated_fields.append("phone")
        if membership.permissions_json != next_permissions:
            membership.permissions_json = next_permissions
            updated_fields.append("permissions_json")

        if updated_fields:
            updated_fields.append("updated_at")
            membership.save(update_fields=updated_fields)


def _sync_user_from_claims(claims: dict) -> User:
    firebase_uid = claims["uid"]
    email = claims.get("email") or f"{firebase_uid}@firebase.local"
    full_name = claims.get("name") or ""

    user = User.objects.filter(firebase_uid=firebase_uid).first() or User.objects.filter(email=email).first()
    created = False
    if user is None:
        user = User(
            firebase_uid=firebase_uid,
            email=email,
            full_name=full_name,
            source_system="firebase",
            source_id=firebase_uid,
            source_path=f"users/{firebase_uid}",
        )
        created = True

    updated_fields: list[str] = []
    if user.firebase_uid != firebase_uid:
        user.firebase_uid = firebase_uid
        updated_fields.append("firebase_uid")
    if user.email != email:
        user.email = email
        updated_fields.append("email")
    if full_name and user.full_name != full_name:
        user.full_name = full_name
        updated_fields.append("full_name")
    if created:
        user.set_unusable_password()
        updated_fields.append("password")

    if updated_fields:
        updated_fields.append("updated_at")
        user.save(update_fields=updated_fields)

    bootstrap_memberships_from_firestore(user)
    return user


class FirebaseAuthentication(authentication.BaseAuthentication):
    keyword = "Bearer"

    def authenticate(self, request):
        header = authentication.get_authorization_header(request).decode("utf-8")
        if not header or not header.startswith(f"{self.keyword} "):
            return None

        token = header[len(self.keyword) + 1 :].strip()
        app = get_firebase_app()
        if app is None:
            raise exceptions.AuthenticationFailed("Firebase authentication is not configured on this backend.")

        try:
            claims = firebase_auth.verify_id_token(token, app=app)
        except Exception as exc:  # pragma: no cover - external provider errors
            raise exceptions.AuthenticationFailed("Invalid Firebase token.") from exc

        user = _sync_user_from_claims(claims)
        return (user, claims)


class DevHeaderAuthentication(authentication.BaseAuthentication):
    """Sign in as anyone, from an HTTP header. Local development only.

    This is an impersonation backdoor by design: it will create and sign in any
    user the header names, as a platform admin if X-Dev-Platform-Admin says so.
    That is fine on a laptop and catastrophic anywhere else.

    It used to be gated on DEBUG alone, which meant one settings mistake stood
    between production and instant admin-for-anyone — and the website was
    sending those headers on every request, sourced from a cookie the browser
    can edit. Two independent switches now have to be wrong at once, and the
    second is never set in any deployed environment.
    """

    def authenticate(self, request):
        if not settings.DEBUG:
            return None
        if not getattr(settings, "ALLOW_DEV_HEADER_AUTH", False):
            return None

        email = request.headers.get("X-Dev-User-Email")
        if not email:
            return None

        user, _ = User.objects.get_or_create(
            email=email,
            defaults={
                "full_name": request.headers.get("X-Dev-User-Name", ""),
                "is_platform_admin": request.headers.get("X-Dev-Platform-Admin", "").lower() in {"1", "true", "yes"},
                "source_system": "dev-header",
                "source_id": email,
                "source_path": "dev-header",
            },
        )
        if not user.password:
            user.set_unusable_password()
            user.save(update_fields=["password"])
        return (user, {"auth_source": "dev-header"})

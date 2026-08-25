"""Shop settings: the details that appear on every receipt and GST return.

Until now these lived only in each device's local database — the mobile app's
`saveShopDocument` wrote to Drift and pushed nothing, and the web had no
endpoint to call. So a shop's name, GSTIN and UPI id were per-device: they were
lost on reinstall, and two devices could disagree about what the receipt says.
"""
from __future__ import annotations

import re

from django.core.exceptions import ImproperlyConfigured
from django.utils import timezone
from rest_framework import exceptions, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.audit.services import create_workspace_audit_event
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403
from platform_apps.shops.plans import (
    BUSINESS_TYPES,
    GST_REGISTRATION_TYPES,
    PLAN_FEATURE_KEYS,
)

# 15 chars: 2 state digits, 10-char PAN, entity digit, 'Z', checksum.
GSTIN_PATTERN = re.compile(r"^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$")
# Anything@bank — same shape the app and the receipt QR builder accept.
UPI_PATTERN = re.compile(r"^[a-zA-Z0-9.\-_]{1,256}@[a-zA-Z]{2,64}$")

#: Free-text values kept in settings_json rather than as columns.
BLOB_FIELDS = (
    "tagline",
    "footer",
    "business_phone",
    "business_email",
    "address",
    "invoice_prefix",
    "upi_vpa",
)

#: Real columns on the Shop row.
COLUMN_FIELDS = (
    "name",
    "legal_name",
    "currency_code",
    "timezone",
    "region_code",
    "gstin",
    "state_code",
    "logo_data",
    "brand_color",
)

#: A logo is a data URI held in a row and re-sent on every settings read, so
#: it is capped. The client resizes to a receipt-sized image long before this,
#: which makes anything larger a sign the cap is being probed rather than a
#: shopkeeper with a big picture.
MAX_LOGO_BYTES = 120_000


#: The only feature flags a shopkeeper may set on themselves.
#:
#: Deliberately the business-type flags and nothing else. These describe how a
#: shop sells — by weight, in variants, always with a GSTIN — so the owner is
#: the right person to decide them. The plan's flags are decided by what has
#: been paid for, and letting this endpoint write those would hand every
#: workspace a free upgrade through a settings toggle. The guard is not the
#: tuple itself but the assertion below it, because a tuple is easy to extend
#: by accident and the mistake would be invisible until an audit.
FEATURE_TOGGLE_FIELDS = (
    "weight_selling",
    "product_variants",
    "gstin_on_every_bill",
)

_overlap = set(FEATURE_TOGGLE_FIELDS) & PLAN_FEATURE_KEYS
if _overlap:
    raise ImproperlyConfigured(
        f"Plan-gated features exposed as shop-editable toggles: {sorted(_overlap)}. "
        "That is a free upgrade for every workspace — remove them from "
        "FEATURE_TOGGLE_FIELDS."
    )


def serialise(shop) -> dict:
    blob = shop.settings_json or {}
    payload = {field: getattr(shop, field, "") or "" for field in COLUMN_FIELDS}
    payload.update({field: str(blob.get(field, "") or "") for field in BLOB_FIELDS})
    payload["id"] = str(shop.id)
    payload["slug"] = shop.slug
    payload["business_type"] = shop.business_type
    # Top-level, deliberately NOT inside payload["features"]: that map is the
    # override-able one, and whether a shop may charge GST is a statutory fact,
    # not a preference. Clients read this to hide the GST return buttons rather
    # than discovering the restriction from a 403.
    payload["gst_registration_type"] = shop.gst_registration_type
    # Resolved, not raw. The stored override map is usually empty — the answer
    # comes from the shop's type and plan — so echoing the raw map back would
    # show a shopkeeper every switch in the off position while the feature was
    # in fact on.
    features = shop.enabled_features
    payload["features"] = {
        field: bool(features.get(field, False)) for field in FEATURE_TOGGLE_FIELDS
    }
    return payload


class ShopSettingsView(APIView):
    """Read or update the shop's own details."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.STAFF
        )
        return Response(serialise(membership.shop))

    def patch(self, request, shop_id):
        # These print on every receipt and feed the GST return, so this is an
        # owner/admin decision rather than a cashier's.
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.ADMIN
        )
        shop = membership.shop
        before = serialise(shop)

        data = request.data if isinstance(request.data, dict) else {}
        errors: dict[str, str] = {}

        name = data.get("name")
        if name is not None and not str(name).strip():
            # A blank shop name would print an empty receipt header.
            errors["name"] = "The shop name cannot be empty."

        gstin = data.get("gstin")
        if gstin:
            candidate = str(gstin).strip().upper()
            if not GSTIN_PATTERN.match(candidate):
                errors["gstin"] = (
                    "That is not a valid 15-character GSTIN. Leave it blank if the "
                    "shop is not registered."
                )

        upi = data.get("upi_vpa")
        if upi:
            if not UPI_PATTERN.match(str(upi).strip()):
                # A malformed id produces a pay link that silently fails at the
                # counter, which is worse than having no link at all.
                errors["upi_vpa"] = "That is not a valid UPI ID (e.g. name@bank)."

        business_type = data.get("business_type")
        if business_type is not None:
            candidate = str(business_type).strip().lower()
            if candidate not in BUSINESS_TYPES:
                # Deliberately an error rather than the silent coercion to
                # "other" that signup performs. Signup coerces because a
                # half-typed value must not block a shop being created at all;
                # here the value came from a dropdown the shopkeeper was just
                # looking at, so an unknown one is a bug, and quietly resetting
                # their shop's type would hide it.
                errors["business_type"] = (
                    f"'{business_type}' is not a business type we recognise."
                )

        gst_registration_type = data.get("gst_registration_type")
        if gst_registration_type is not None:
            candidate = str(gst_registration_type).strip().lower()
            if candidate not in GST_REGISTRATION_TYPES:
                errors["gst_registration_type"] = (
                    f"'{gst_registration_type}' is not a GST registration type "
                    "we recognise."
                )

        brand_color = data.get("brand_color")
        if brand_color:
            candidate = str(brand_color).strip()
            # A hex colour or nothing. Anything else reaches a style attribute
            # on a printed document, and "red; background:url(...)" is not a
            # colour.
            if not re.fullmatch(r"#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})", candidate):
                errors["brand_color"] = "Expected a hex colour such as #0369A1."

        logo_data = data.get("logo_data")
        if logo_data:
            candidate = str(logo_data).strip()
            if not candidate.startswith("data:image/"):
                errors["logo_data"] = "Expected an image."
            elif len(candidate.encode("utf-8")) > MAX_LOGO_BYTES:
                errors["logo_data"] = (
                    "That image is too large. It is resized before upload, so this "
                    "usually means it did not go through the picker."
                )

        features = data.get("features")
        if features is not None:
            if not isinstance(features, dict):
                errors["features"] = "Expected an object of feature name to true/false."
            else:
                for key, value in features.items():
                    if key not in FEATURE_TOGGLE_FIELDS:
                        # Names the offending key. A shopkeeper will never see
                        # this; whoever is probing the endpoint for a free
                        # upgrade should get a flat no rather than a silent
                        # ignore that leaves them guessing it worked.
                        errors[f"features.{key}"] = (
                            "That feature cannot be changed from shop settings."
                        )
                    elif not isinstance(value, bool):
                        # A JSON string "false" is truthy in Python, so coercing
                        # would switch a feature ON when the caller asked for it
                        # to be off.
                        errors[f"features.{key}"] = "Expected true or false."

        if errors:
            raise exceptions.ValidationError(errors)

        changed_columns: list[str] = []
        for field in COLUMN_FIELDS:
            if field in data:
                value = str(data[field] or "").strip()
                if field == "gstin":
                    value = value.upper()
                if getattr(shop, field) != value:
                    setattr(shop, field, value)
                    changed_columns.append(field)

        blob = dict(shop.settings_json or {})
        blob_changed = False
        for field in BLOB_FIELDS:
            if field in data:
                value = str(data[field] or "").strip()
                if blob.get(field) != value:
                    blob[field] = value
                    blob_changed = True

        if business_type is not None:
            candidate = str(business_type).strip().lower()
            if blob.get("business_type") != candidate:
                blob["business_type"] = candidate
                blob_changed = True

        if gst_registration_type is not None:
            candidate = str(gst_registration_type).strip().lower()
            if blob.get("gst_registration_type") != candidate:
                blob["gst_registration_type"] = candidate
                # When this changed matters: bills before it are Tax Invoices
                # and bills after are Bills of Supply, and an accountant
                # reconciling a year will need the boundary.
                blob["gst_registration_changed_at"] = timezone.now().isoformat()
                blob_changed = True

        if isinstance(features, dict):
            overrides = blob.get("enabled_features")
            overrides = dict(overrides) if isinstance(overrides, dict) else {}
            features_changed = False
            for field in FEATURE_TOGGLE_FIELDS:
                if field not in features:
                    continue
                # Written even when it equals today's resolved answer. The
                # stored value is an override, and its whole job is to keep
                # meaning what the shopkeeper said after the layer underneath
                # changes — a grocer who switches weight_selling off must stay
                # off if they later correct their business type.
                if overrides.get(field) is not features[field]:
                    overrides[field] = features[field]
                    features_changed = True
            if features_changed:
                blob["enabled_features"] = overrides
                blob_changed = True

        if blob_changed:
            shop.settings_json = blob
            changed_columns.append("settings_json")

        if changed_columns:
            shop.save(update_fields=changed_columns + ["updated_at"])

        after = serialise(shop)
        if changed_columns:
            create_workspace_audit_event(
                shop=shop,
                actor_user=request.user,
                actor_role=membership.role,
                category="shop",
                event_type="shop.settings.updated",
                entity_type="shop",
                entity_id=shop.id,
                entity_label=shop.name,
                summary=f"Updated shop settings for {shop.name}.",
                source_surface="backend_api",
                before=before,
                after=after,
            )
        return Response(after)

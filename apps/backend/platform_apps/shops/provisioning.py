"""Shop provisioning — create an isolated workspace for a new owner.

Used by self-serve registration and reusable by any admin/seed path. Everything
happens in one transaction so a shop is never half-created, and it writes an
audit event so provisioning is traceable.
"""
from __future__ import annotations

import secrets

from django.db import transaction
from django.utils.text import slugify

from platform_apps.audit.services import create_workspace_audit_event
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.shops.plans import BUSINESS_TYPES

# A new shop starts with NO feature overrides. It used to start with a map of
# eight keys, which read like defaults but were not: five of them
# (inventory/pos/customers/history/team) are not feature keys at all and nothing
# ever read them, and the other three were wiped moments later by
# Subscription.start_trial, which strips every plan-owned key when it sets the
# tier. Defaults now come from the shop's plan and business type, resolved live
# in build_enabled_features, so this map holds only what a shopkeeper has
# actually chosen to change. The key is still written, as an empty dict, because
# billing only rewrites the override map when it finds one.
NO_FEATURE_OVERRIDES: dict[str, bool] = {}

# The list itself now lives in plans.py, next to the flags each type turns on,
# so a type can never be accepted here but unknown to the thing that decides
# what it means. Pharmacy and restaurant stay VALID — any shop already carrying
# one keeps it, and dropping them would silently rewrite those rows to "other".
# They are removed from the signup dropdowns instead, because the app does not
# yet do what choosing them implies: batch and expiry tracking for a pharmacy (a
# licensing matter, not a convenience), and tables/orders for a restaurant.
# Both are planned; offering them before they exist misleads at the first
# screen a shopkeeper ever sees.
VALID_BUSINESS_TYPES = frozenset(BUSINESS_TYPES)


def _unique_slug(base: str) -> str:
    """A URL-safe, globally-unique slug derived from the business name."""
    root = slugify(base) or "shop"
    root = root[:40]
    candidate = root
    # Collisions are rare; a short random suffix guarantees uniqueness without
    # an unbounded counter scan.
    while Shop.objects.filter(slug=candidate).exists():
        candidate = f"{root}-{secrets.token_hex(3)}"
    return candidate


@transaction.atomic
def provision_shop(
    *,
    owner,
    business_name: str,
    business_type: str = "retail",
    state_code: str = "",
    gstin: str = "",
    currency_code: str = "INR",
    timezone: str = "Asia/Kolkata",
    plan_tier: str = "starter",
    owner_phone: str = "",
    source_surface: str = "registration",
) -> tuple[Shop, ShopMembership]:
    """Create a shop, its owner membership, defaults, and an audit trail.

    Returns (shop, owner_membership). Atomic: on any failure nothing is written.
    """
    normalized_type = (business_type or "retail").strip().lower()
    if normalized_type not in VALID_BUSINESS_TYPES:
        normalized_type = "other"

    shop = Shop.objects.create(
        owner_user=owner,
        name=business_name.strip(),
        slug=_unique_slug(business_name),
        gstin=(gstin or "").strip().upper(),
        state_code=(state_code or "").strip(),
        currency_code=currency_code or "INR",
        timezone=timezone or "Asia/Kolkata",
        settings_json={
            "plan_tier": plan_tier or "starter",
            "business_type": normalized_type,
            "enabled_features": dict(NO_FEATURE_OVERRIDES),
            "onboarding_completed": False,
            "business_phone": (owner_phone or "").strip(),
        },
        source_system=source_surface,
    )

    # Every new workspace starts on a full-Pro trial; the subscription is the
    # source of truth for the tier from here on.
    from platform_apps.billing.models import Subscription

    Subscription.start_trial(shop)
    shop.refresh_from_db(fields=["settings_json"])

    membership = ShopMembership.objects.create(
        user=owner,
        shop=shop,
        role=ShopMembership.Role.OWNER,
        status=ShopMembership.Status.ACTIVE,
        email=getattr(owner, "email", ""),
        phone=(owner_phone or "").strip(),
        source_system=source_surface,
    )

    create_workspace_audit_event(
        shop=shop,
        actor_user=owner,
        actor_role=ShopMembership.Role.OWNER,
        category="workspace",
        event_type="shop_provisioned",
        entity_type="shop",
        entity_id=str(shop.id),
        entity_label=shop.name,
        summary=f"Shop '{shop.name}' provisioned via {source_surface}.",
        source_surface=source_surface,
    )

    return shop, membership

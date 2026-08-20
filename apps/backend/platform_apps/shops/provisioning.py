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

# Sensible defaults for a brand-new shop; the owner can change these later.
DEFAULT_FEATURES: dict[str, bool] = {
    "inventory": True,
    "pos": True,
    "customers": True,
    "history": True,
    "team": True,
    "attendance": True,
    "expenses": True,
    "advanced_ops": True,
}

# Pharmacy and restaurant stay VALID — any shop already carrying one keeps it,
# and dropping them here would silently rewrite those rows to "other". They are
# removed from the signup dropdowns instead, because the app does not yet do
# what choosing them implies: batch and expiry tracking for a pharmacy (a
# licensing matter, not a convenience), and tables/orders for a restaurant.
# Both are planned; offering them before they exist misleads at the first
# screen a shopkeeper ever sees.
VALID_BUSINESS_TYPES = {
    "retail",
    "wholesale",
    "service",
    "restaurant",
    "pharmacy",
    "grocery",
    "other",
}


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
            "enabled_features": DEFAULT_FEATURES,
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

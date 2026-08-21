from __future__ import annotations

from typing import Any

DEFAULT_PLAN_TIER = "growth"
PLAN_TIERS = ("starter", "growth", "pro")

DEFAULT_BUSINESS_TYPE = "retail"

#: Business types a shop may carry. Pharmacy and restaurant stay valid so any
#: shop already holding one keeps it, even though signup no longer offers them
#: (see provisioning.VALID_BUSINESS_TYPES for why).
BUSINESS_TYPES = (
    "retail",
    "wholesale",
    "service",
    "restaurant",
    "pharmacy",
    "grocery",
    "other",
)


#: How the shop is registered under GST. Decides whether it may charge tax at
#: all — not a preference, a statutory fact.
#:
#: composition (s.10 CGST Act, goods turnover under 1.5cr — much of this
#: product's market) CANNOT collect GST, issues a "Bill of Supply" rather than
#: a "Tax Invoice", must carry the declaration "Composition taxable person, not
#: eligible to collect tax on supplies", and files CMP-08 quarterly and GSTR-4
#: annually instead of GSTR-1 and GSTR-3B.
#:
#: unregistered shops charge no GST either; they differ from composition only
#: in the wording on the bill.
DEFAULT_GST_REGISTRATION_TYPE = "regular"
GST_REGISTRATION_TYPES = ("regular", "composition", "unregistered")


def normalize_gst_registration_type(value: Any) -> str:
    """Coerce to a known registration type, defaulting to regular.

    Falls back to "regular" rather than to a catch-all, unlike
    normalize_business_type: there is no neutral member here, and regular is
    the status every existing shop already implicitly has. Deriving the default
    rather than storing it is what makes this back-compatible with no
    migration and nothing to backfill.
    """
    candidate = str(value or "").strip().lower()
    if candidate in GST_REGISTRATION_TYPES:
        return candidate
    return DEFAULT_GST_REGISTRATION_TYPE


def collects_gst(registration_type: Any) -> bool:
    """Whether this shop may charge GST to a customer at all."""
    return normalize_gst_registration_type(registration_type) == "regular"


def normalize_plan_tier(value: Any) -> str:
    candidate = str(value or "").strip().lower()
    if candidate in PLAN_TIERS:
        return candidate
    return DEFAULT_PLAN_TIER


def normalize_business_type(value: Any) -> str:
    candidate = str(value or "").strip().lower()
    if candidate in BUSINESS_TYPES:
        return candidate
    return "other"


def build_plan_features(plan_tier: str) -> dict[str, bool]:
    """The features the *subscription* decides. Money, not shop character."""
    normalized_tier = normalize_plan_tier(plan_tier)
    return {
        "expenses": normalized_tier in {"growth", "pro"},
        "attendance": normalized_tier in {"growth", "pro"},
        "supplier_directory": normalized_tier in {"growth", "pro"},
        "purchase_workflow": normalized_tier == "pro",
        "advanced_reports": normalized_tier == "pro",
        "multi_branch": normalized_tier == "pro",
        "finance_summary": normalized_tier == "pro",
        "advanced_ops": normalized_tier == "pro",
    }


#: The keys ``build_plan_features`` owns. Billing strips exactly these from a
#: shop's override map when the tier changes, so a stale override cannot keep
#: granting a paid feature after a downgrade. Derived here rather than repeated
#: in billing: a plan key added in one place and forgotten in the other would
#: hand out a paid feature permanently, and nothing would report it.
PLAN_FEATURE_KEYS: frozenset[str] = frozenset(build_plan_features(DEFAULT_PLAN_TIER))


def build_business_type_features(business_type: str) -> dict[str, bool]:
    """The features the *kind of shop* decides. Character, not money.

    Deliberately never plan-gated. A grocer weighing loose dal is not using a
    premium feature, they are using the only way their shop sells anything; a
    downgrade that switched it off would stop them trading. For the same reason
    these keys are absent from PLAN_FEATURE_KEYS, so billing never strips a
    shopkeeper's override of them.

    Defaults only. Every one is overridable, because the type is chosen in the
    first thirty seconds a shopkeeper ever spends with the product, long before
    they know what the words mean.
    """
    normalized = normalize_business_type(business_type)
    return {
        # Loose goods priced by weight at the counter.
        "weight_selling": normalized == "grocery",
        # Size/colour variants under one product — a garment shop's whole stock
        # model, meaningless to someone selling one SKU per line.
        "product_variants": normalized == "retail",
        # Wholesale sells B2B, where the buyer needs a GSTIN on every invoice to
        # claim input credit. Retail mostly sells to people who have none.
        "gstin_on_every_bill": normalized == "wholesale",
    }


def build_enabled_features(
    plan_tier: str,
    overrides: dict[str, Any] | None = None,
    business_type: str | None = None,
) -> dict[str, bool]:
    """Resolve every feature flag for a shop.

    Three layers, lowest first: what the shop's type implies, what the plan
    pays for, and what the shopkeeper has explicitly chosen. The override wins
    outright — Settings must be able to contradict both of the layers below it,
    or a shop that picked the wrong type at signup needs a support call to fix
    a checkbox.
    """
    features: dict[str, bool] = build_business_type_features(business_type)
    features.update(build_plan_features(plan_tier))

    if overrides:
        for key, value in overrides.items():
            features[str(key)] = bool(value)

    return features

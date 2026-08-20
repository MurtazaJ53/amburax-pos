"""Pure unit tests for shop plan utilities (no DB required).

``normalize_plan_tier`` and ``build_enabled_features`` are pure functions.
"""
from __future__ import annotations

import pytest

from platform_apps.shops.plans import (
    BUSINESS_TYPES,
    DEFAULT_PLAN_TIER,
    PLAN_FEATURE_KEYS,
    PLAN_TIERS,
    build_business_type_features,
    build_enabled_features,
    build_plan_features,
    normalize_business_type,
    normalize_plan_tier,
)


# ---------------------------------------------------------------------------
# normalize_plan_tier
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("tier", PLAN_TIERS)
def test_valid_tier_passes_through(tier):
    assert normalize_plan_tier(tier) == tier


@pytest.mark.parametrize("bad", ["", None, "enterprise", "FREE", "basic", 0, {}, []])
def test_unknown_tier_returns_default(bad):
    assert normalize_plan_tier(bad) == DEFAULT_PLAN_TIER


def test_case_insensitive():
    assert normalize_plan_tier("STARTER") == "starter"
    assert normalize_plan_tier("Growth") == "growth"
    assert normalize_plan_tier("PRO") == "pro"


def test_whitespace_stripped():
    assert normalize_plan_tier("  pro  ") == "pro"


# ---------------------------------------------------------------------------
# build_enabled_features — starter
# ---------------------------------------------------------------------------

def test_starter_has_no_premium_features():
    features = build_enabled_features("starter")
    assert features["expenses"] is False
    assert features["attendance"] is False
    assert features["supplier_directory"] is False
    assert features["purchase_workflow"] is False
    assert features["advanced_reports"] is False
    assert features["multi_branch"] is False
    assert features["finance_summary"] is False
    assert features["advanced_ops"] is False


# ---------------------------------------------------------------------------
# build_enabled_features — growth
# ---------------------------------------------------------------------------

def test_growth_has_operational_features():
    features = build_enabled_features("growth")
    assert features["expenses"] is True
    assert features["attendance"] is True
    assert features["supplier_directory"] is True


def test_growth_lacks_pro_only_features():
    features = build_enabled_features("growth")
    assert features["purchase_workflow"] is False
    assert features["advanced_reports"] is False
    assert features["multi_branch"] is False


# ---------------------------------------------------------------------------
# build_enabled_features — pro
# ---------------------------------------------------------------------------

def test_pro_has_all_features():
    """Pro unlocks every feature the *plan* sells.

    Scoped to PLAN_FEATURE_KEYS rather than every key in the resolved map,
    because the map now also carries business-type flags, and those describe
    what kind of shop this is — paying more does not make a garment shop start
    weighing things.
    """
    features = build_enabled_features("pro")
    for key in PLAN_FEATURE_KEYS:
        assert features[key] is True, f"Expected {key} to be enabled on pro"


# ---------------------------------------------------------------------------
# build_enabled_features — overrides
# ---------------------------------------------------------------------------

def test_override_can_disable_a_feature_on_pro():
    features = build_enabled_features("pro", overrides={"expenses": False})
    assert features["expenses"] is False
    # Other features unaffected
    assert features["attendance"] is True


def test_override_can_enable_a_feature_on_starter():
    features = build_enabled_features("starter", overrides={"expenses": True})
    assert features["expenses"] is True


def test_override_with_none_treats_as_default():
    """normalize_plan_tier('unknown') returns DEFAULT_PLAN_TIER, not crash."""
    features = build_enabled_features(None)  # type: ignore[arg-type]
    assert isinstance(features, dict)
    # None -> DEFAULT_PLAN_TIER ('growth') -> growth features
    assert features["expenses"] is True  # growth has expenses


def test_all_returned_keys_are_known():
    """No surprise keys added without updating FEATURE_LABELS."""
    from platform_apps.shops.permissions import FEATURE_LABELS
    features = build_enabled_features("pro")
    for key in features:
        assert key in FEATURE_LABELS, f"Unexpected feature key: {key}"


# ---------------------------------------------------------------------------
# business type -> feature defaults
# ---------------------------------------------------------------------------

BUSINESS_TYPE_KEYS = ("weight_selling", "product_variants", "gstin_on_every_bill")


@pytest.mark.parametrize("btype", BUSINESS_TYPES)
def test_valid_business_type_passes_through(btype):
    assert normalize_business_type(btype) == btype


@pytest.mark.parametrize("bad", ["", None, "cafe", "SALON", 0, {}, []])
def test_unknown_business_type_becomes_other(bad):
    assert normalize_business_type(bad) == "other"


def test_business_type_normalisation_matches_plan_tier_behaviour():
    assert normalize_business_type("  GROCERY ") == "grocery"


@pytest.mark.parametrize(
    "btype,expected_on",
    [
        ("grocery", "weight_selling"),
        ("retail", "product_variants"),
        ("wholesale", "gstin_on_every_bill"),
    ],
)
def test_each_type_turns_on_exactly_its_own_flag(btype, expected_on):
    """A type switching on someone else's flag is the failure that makes the
    whole layer pointless — every shop would look identical again."""
    features = build_business_type_features(btype)
    for key in BUSINESS_TYPE_KEYS:
        assert features[key] is (key == expected_on), key


@pytest.mark.parametrize("btype", ["service", "other", "pharmacy", "restaurant"])
def test_types_without_a_flag_get_none_of_them(btype):
    features = build_business_type_features(btype)
    assert not any(features[key] for key in BUSINESS_TYPE_KEYS)


def test_business_type_flags_are_not_plan_gated():
    """The regression that would stop a grocer trading: a lapsed subscription
    must not switch off selling by weight."""
    for tier in PLAN_TIERS:
        features = build_enabled_features(tier, business_type="grocery")
        assert features["weight_selling"] is True, tier


def test_plan_features_do_not_depend_on_business_type():
    for btype in BUSINESS_TYPES:
        features = build_enabled_features("starter", business_type=btype)
        assert features["advanced_ops"] is False, btype


def test_override_beats_the_business_type_default():
    """Phase 4 rests on this: Settings must be able to contradict the type
    chosen in the first thirty seconds of signup."""
    features = build_enabled_features(
        "pro", overrides={"weight_selling": True}, business_type="retail"
    )
    assert features["weight_selling"] is True

    features = build_enabled_features(
        "pro", overrides={"product_variants": False}, business_type="retail"
    )
    assert features["product_variants"] is False


def test_business_type_defaults_to_a_usable_shop_when_omitted():
    """Every existing caller passes no business_type. It must not explode, and
    it must not silently hand out flags."""
    features = build_enabled_features("pro")
    for key in BUSINESS_TYPE_KEYS:
        assert features[key] is False, key


# ---------------------------------------------------------------------------
# PLAN_FEATURE_KEYS — the contract billing strips against
# ---------------------------------------------------------------------------

def test_plan_feature_keys_match_what_the_plan_actually_decides():
    assert PLAN_FEATURE_KEYS == frozenset(build_plan_features("pro"))
    assert PLAN_FEATURE_KEYS == frozenset(build_plan_features("starter"))


def test_business_type_flags_are_absent_from_plan_feature_keys():
    """If one of these ever entered the strip list, billing would silently
    reset a shopkeeper's setting on every tier change."""
    for key in BUSINESS_TYPE_KEYS:
        assert key not in PLAN_FEATURE_KEYS, key


def test_every_resolved_key_is_either_plan_or_business_type():
    """Nothing appears in the resolved map that neither layer owns, so no key
    can escape both the strip list and the type defaults."""
    features = build_enabled_features("pro", business_type="grocery")
    accounted = PLAN_FEATURE_KEYS | set(BUSINESS_TYPE_KEYS)
    assert set(features) == accounted

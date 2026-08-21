from __future__ import annotations

from rest_framework import exceptions

from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.shops.plans import normalize_plan_tier

ROLE_ORDER = {
    ShopMembership.Role.VIEWER: 10,
    # Operational staff — same coarse level; day-to-day fine-grained differences
    # are expressed via each role's permission set (permissions_json).
    ShopMembership.Role.CASHIER: 20,
    ShopMembership.Role.SALES_STAFF: 20,
    ShopMembership.Role.INVENTORY_STAFF: 20,
    ShopMembership.Role.STAFF: 20,
    # Functional specialists.
    ShopMembership.Role.ACCOUNTANT: 25,
    ShopMembership.Role.HR: 25,
    ShopMembership.Role.SUPERVISOR: 28,
    # Management.
    ShopMembership.Role.MANAGER: 30,
    ShopMembership.Role.ADMIN: 30,
    ShopMembership.Role.OWNER: 40,
}

# Roles an owner/manager may assign, ordered. Owner can assign anything below
# owner; manager/admin can assign anything strictly below their own rank.
_ASSIGNABLE_BY_OWNER = [
    ShopMembership.Role.ADMIN,
    ShopMembership.Role.MANAGER,
    ShopMembership.Role.SUPERVISOR,
    ShopMembership.Role.ACCOUNTANT,
    ShopMembership.Role.HR,
    ShopMembership.Role.CASHIER,
    ShopMembership.Role.SALES_STAFF,
    ShopMembership.Role.INVENTORY_STAFF,
    ShopMembership.Role.STAFF,
    ShopMembership.Role.VIEWER,
]

FEATURE_LABELS = {
    "expenses": "Expenses",
    "attendance": "Attendance",
    "supplier_directory": "Supplier directory",
    "purchase_workflow": "Purchase workflow",
    "advanced_reports": "Advanced reports",
    "multi_branch": "Multi-branch visibility",
    "finance_summary": "Finance summary",
    "advanced_ops": "Advanced ops",
    # Business-type flags. Present so the 403 message reads as a sentence, but
    # nothing gates on these today — they describe how a shop sells, and a shop
    # that cannot use them simply does not see them.
    "weight_selling": "Selling by weight",
    "product_variants": "Product variants",
    "gstin_on_every_bill": "GSTIN on every bill",
}


def get_membership_or_403(user, shop_id, minimum_role: str = ShopMembership.Role.VIEWER) -> ShopMembership:
    membership = (
        ShopMembership.objects.select_related("shop")
        .filter(user=user, shop_id=shop_id, status=ShopMembership.Status.ACTIVE)
        .first()
    )
    if membership is None:
        raise exceptions.PermissionDenied("You do not have access to this shop.")

    # A suspended shop blocks every member (owner included) at this one gate.
    if membership.shop.status == Shop.Status.SUSPENDED:
        raise exceptions.PermissionDenied(
            "This shop is suspended. Contact the platform administrator."
        )

    if ROLE_ORDER[membership.role] < ROLE_ORDER[minimum_role]:
        raise exceptions.PermissionDenied("Your role does not allow this action.")

    return membership


def can_assign_workspace_role(actor_role: str, target_role: str) -> bool:
    return _can_act_on_role(actor_role, target_role)


def can_manage_workspace_membership(actor_role: str, target_role: str) -> bool:
    return _can_act_on_role(actor_role, target_role)


def _can_act_on_role(actor_role: str, target_role: str) -> bool:
    """An actor may assign/manage any role that is strictly below their own
    rank and is itself assignable (never OWNER). Owner may assign anything
    below owner."""
    if actor_role not in ROLE_ORDER or target_role not in ROLE_ORDER:
        return False
    if target_role == ShopMembership.Role.OWNER:
        return False  # ownership changes go through the dedicated transfer flow
    if target_role not in _ASSIGNABLE_BY_OWNER:
        return False
    return ROLE_ORDER[actor_role] > ROLE_ORDER[target_role]


def ensure_workspace_role_assignment_or_403(actor_membership: ShopMembership, target_role: str) -> None:
    if can_assign_workspace_role(actor_membership.role, target_role):
        return

    raise exceptions.PermissionDenied(
        "Your workspace role cannot assign that target role."
    )


def ensure_workspace_membership_management_or_403(
    actor_membership: ShopMembership,
    target_membership: ShopMembership,
) -> None:
    if actor_membership.shop_id != target_membership.shop_id:
        raise exceptions.PermissionDenied("You cannot manage memberships outside your workspace.")

    if actor_membership.user_id == target_membership.user_id:
        raise exceptions.PermissionDenied("You cannot change your own workspace role or status here.")

    if can_manage_workspace_membership(actor_membership.role, target_membership.role):
        return

    raise exceptions.PermissionDenied(
        "Your workspace role cannot manage that membership."
    )


def ensure_workspace_ownership_transfer_or_403(
    actor_membership: ShopMembership,
    target_membership: ShopMembership,
) -> None:
    if actor_membership.shop_id != target_membership.shop_id:
        raise exceptions.PermissionDenied("You cannot transfer ownership outside your workspace.")

    if actor_membership.role != ShopMembership.Role.OWNER:
        raise exceptions.PermissionDenied("Only the current workspace owner can transfer ownership.")

    if actor_membership.user_id == target_membership.user_id:
        raise exceptions.PermissionDenied("Choose another active member to receive workspace ownership.")

    if target_membership.role == ShopMembership.Role.OWNER:
        raise exceptions.PermissionDenied("That membership already owns the workspace.")

    if target_membership.status != ShopMembership.Status.ACTIVE:
        raise exceptions.PermissionDenied("Transfer ownership only to an active workspace member.")


def ensure_workspace_access_session_management_or_403(
    actor_membership: ShopMembership,
    target_session,
) -> None:
    if actor_membership.shop_id != target_session.shop_id:
        raise exceptions.PermissionDenied("You cannot manage sessions outside your workspace.")

    target_role = getattr(target_session, "membership_role_snapshot", "") or ShopMembership.Role.STAFF

    if actor_membership.user_id == target_session.user_id:
        if actor_membership.role in {ShopMembership.Role.OWNER, ShopMembership.Role.ADMIN}:
            return
        raise exceptions.PermissionDenied("You cannot manage this workspace session.")

    if actor_membership.role == ShopMembership.Role.OWNER:
        return

    if actor_membership.role == ShopMembership.Role.ADMIN and target_role in {
        ShopMembership.Role.STAFF,
        ShopMembership.Role.VIEWER,
    }:
        return

    raise exceptions.PermissionDenied("Your workspace role cannot manage that device session.")


def can_assign_workspace_pulse_signal(
    actor_membership: ShopMembership,
    target_membership: ShopMembership,
) -> bool:
    if actor_membership.shop_id != target_membership.shop_id:
        return False

    if target_membership.status != ShopMembership.Status.ACTIVE:
        return False

    if actor_membership.user_id == target_membership.user_id:
        return actor_membership.role in {
            ShopMembership.Role.OWNER,
            ShopMembership.Role.ADMIN,
        }

    return can_manage_workspace_membership(actor_membership.role, target_membership.role)


def has_feature_enabled(membership: ShopMembership, feature_key: str) -> bool:
    return membership.shop.enabled_features.get(feature_key) is True


def ensure_gst_returns_allowed_or_403(membership: ShopMembership) -> None:
    """Refuse GSTR-1 / GSTR-3B to a shop that must not file them.

    A composition dealer files CMP-08 quarterly and GSTR-4 annually; filing
    GSTR-1 would be wrong, and handing their accountant a GSTR-1 export
    invites exactly that. An unregistered shop files nothing at all.

    Deliberately NOT a feature flag in plans.py. Everything in that map is
    overridable from Settings by design, and billing strips keys from it on a
    tier change — a statutory restriction that a checkbox or a downgrade can
    clear is a bug waiting to happen. This is not a default; it is a fact about
    the shop.

    The message names the right form, because the person who hits this is
    usually the shopkeeper's accountant looking for something to file.
    """
    registration = membership.shop.gst_registration_type
    if registration == "composition":
        raise exceptions.PermissionDenied(
            "A composition dealer files CMP-08 quarterly and GSTR-4 annually, "
            "not GSTR-1 or GSTR-3B. Use the quarterly turnover figures instead."
        )
    if registration == "unregistered":
        raise exceptions.PermissionDenied(
            "This shop is not registered for GST, so there are no GST returns "
            "to file."
        )


def ensure_feature_enabled_or_403(membership: ShopMembership, feature_key: str) -> None:
    if has_feature_enabled(membership, feature_key):
        return

    plan_label = normalize_plan_tier(membership.shop.plan_tier).title()
    feature_label = FEATURE_LABELS.get(feature_key, feature_key.replace("_", " ").title())
    raise exceptions.PermissionDenied(
        f"{feature_label} is not available on the {plan_label} plan for this workspace."
    )

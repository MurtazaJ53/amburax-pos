import type { ShopMembership } from "@/lib/types";

export type WorkspaceRole = ShopMembership["role"] | null;

export function canManageWorkspace(role: WorkspaceRole) {
  return role === "owner" || role === "admin";
}

export function canAccessPaymentsWorkspace(role: WorkspaceRole) {
  return canManageWorkspace(role);
}

export function canTransferWorkspaceOwnership(role: WorkspaceRole) {
  return role === "owner";
}

/** Whether this member is allowed to see what stock cost to buy.
 *
 *  Mirrors InventoryViewMixin.can_view_costs on the server, which gates on
 *  role >= ADMIN. The server sends cost_price as null to everyone below that
 *  — the same null it sends when no cost has ever been entered — so the
 *  screen cannot tell the two apart from the payload alone. Without this,
 *  a cashier gets told to "add a cost price" for items whose cost they are
 *  not permitted to know.
 */
export function canViewCosts(role: WorkspaceRole) {
  return canManageWorkspace(role);
}

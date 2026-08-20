import { cache } from "react";

import type {
  AttendanceSession,
  AttendanceSummaryPayload,
  Customer,
  CustomerSummaryPayload,
  DashboardSnapshot,
  ERPNextDocumentLink,
  ERPNextHealthPayload,
  ERPNextMetaPayload,
  ERPNextPocSummary,
  ERPNextPurchaseMirror,
  ERPNextShopBinding,
  ERPNextSupplierMirror,
  ERPNextSupplierPaymentMirror,
  ERPNextSyncState,
  Expense,
  ExpenseSummaryPayload,
  InventoryItem,
  InventorySummaryPayload,
  MigrationBridgeReceipt,
  MigrationControlEvent,
  MigrationDomainControl,
  MigrationGoLiveCheckpointEvent,
  MigrationGoLiveReadiness,
  MigrationJobRun,
  MigrationLaunchCheckpointEvent,
  MigrationPhaseCheckpointEvent,
  MigrationPhaseReadiness,
  MigrationPilotReadiness,
  MigrationPilotShopScorecard,
  MigrationPilotSignoff,
  MigrationReconciliationEvent,
  MigrationRetirementReadiness,
  MigrationRolloutCheckpointEvent,
  MigrationRolloutReadiness,
  MigrationShadowSummary,
  MigrationShopCheckpointEvent,
  MigrationStats,
  MigrationSteadyStateCheckpointEvent,
  MigrationSteadyStateReadiness,
  PaymentSummaryPayload,
  PlatformAuditListPayload,
  PlatformMetricsPayload,
  PlatformShopListPayload,
  PlatformShopPayload,
  Sale,
  SalePaymentRecord,
  SalesSummaryPayload,
  SessionPayload,
  ShopDomainState,
  ShopMembership,
  ShopPlanRequestPayload,
  UserMfaStatusPayload,
  UserPasskeyCredentialPayload,
  WorkspaceAccessSessionPayload,
  WorkspaceAuditEventPayload,
  WorkspacePulseSignal,
  WorkspacePulseSnapshot,
  WorkspaceTeamMemberPayload,
} from "@/lib/types";

/* ------------------------------------------------------------------ */
/*  Low-level helpers                                                  */
/* ------------------------------------------------------------------ */

type FetchOptions = {
  query?: Record<string, string | undefined>;
};

type MutationOptions = {
  method?: "POST" | "PATCH" | "PUT" | "DELETE";
  body?: unknown;
};

import { cookies } from "next/headers";
import { redirect } from "next/navigation";

/**
 * An upstream (Django) response that was not ok, carrying the status as a
 * number.
 *
 * Callers used to recognise an expired session by searching the message text
 * for "(401)". That silently failed for every other rejection the API can
 * return — 403, and 429 from DRF's AnonRateThrottle, which a signed-out
 * browser reaches after 100 requests in an hour. The page then threw instead
 * of redirecting, and the visitor got a bare "This page couldn't load".
 */
export class ApiError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}



const API_BASE_URL =
  process.env.BUSINESS_HUB_API_BASE_URL?.replace(/\/$/, "") ?? "http://127.0.0.1:8000/api/v1";

/** Whether to send the X-Dev-* impersonation headers. Opt-in, never inferred.
 *
 *  Deliberately its own variable rather than a NODE_ENV check: a production
 *  build run locally is still local, and a dev build could be deployed. The
 *  question "may this request impersonate a user" deserves an explicit answer
 *  from whoever configured the environment, not a guess from the bundler. */
const ALLOW_DEV_HEADERS = process.env.BUSINESS_HUB_ALLOW_DEV_HEADERS === "1";

async function buildHeaders(): Promise<Headers> {
  const headers = new Headers({
    Accept: "application/json",
  });

  try {
    const cookieStore = await cookies();
    const token = cookieStore.get("bh_access_token")?.value;
    if (token) {
      headers.set("Authorization", `Bearer ${token}`);
    }
    // X-Dev-* headers are an impersonation channel: DevHeaderAuthentication on
    // the backend will mint and sign in ANY user named by them, as a platform
    // admin if X-Dev-Platform-Admin says so.
    //
    // They used to be sent on every production request, sourced from
    // bh_user_role — a cookie that is deliberately NOT httpOnly, so the browser
    // can read it, and therefore so can anyone who opens devtools and edits it.
    // Django ignored them because DEBUG is False in production, which made this
    // safe by exactly one setting. The day DEBUG is turned on to investigate
    // something, any visitor could hand themselves platform admin by editing
    // one cookie, and a brand-new admin account would be created on the spot.
    //
    // Now they require an explicit opt-in that no production environment sets,
    // so a DEBUG mistake alone is no longer enough.
    if (ALLOW_DEV_HEADERS) {
      const userEmail = cookieStore.get("bh_user_email")?.value;
      if (userEmail) {
        headers.set("X-Dev-User-Email", userEmail);
      }
      const userRole = cookieStore.get("bh_user_role")?.value;
      if (userRole === "platform_admin") {
        headers.set("X-Dev-Platform-Admin", "true");
      }
    }
  } catch {
    // In environments where cookies() is outside request context
  }

  // Same gate as the cookie path above. These three were the older mechanism
  // and were NOT behind any check at all, so leaving them open would have made
  // the fix above cosmetic.
  if (ALLOW_DEV_HEADERS) {
    const devEmail = process.env.BUSINESS_HUB_DEV_USER_EMAIL?.trim();
    if (devEmail && !headers.has("X-Dev-User-Email")) {
      headers.set("X-Dev-User-Email", devEmail);
    }

    const devName = process.env.BUSINESS_HUB_DEV_USER_NAME?.trim();
    if (devName) {
      headers.set("X-Dev-User-Name", devName);
    }

    const devPlatformAdmin = process.env.BUSINESS_HUB_DEV_PLATFORM_ADMIN?.trim();
    if (devPlatformAdmin && !headers.has("X-Dev-Platform-Admin")) {
      headers.set("X-Dev-Platform-Admin", devPlatformAdmin);
    }
  }

  return headers;
}

export async function apiFetch<T>(path: string, options: FetchOptions = {}): Promise<T> {
  const url = new URL(`${API_BASE_URL}${path}`);
  if (options.query) {
    for (const [key, value] of Object.entries(options.query)) {
      if (value) {
        url.searchParams.set(key, value);
      }
    }
  }

  const headers = await buildHeaders();
  const response = await fetch(url, {
    headers,
    cache: "no-store",
  });

  if (!response.ok) {
    const body = await response.text();
    throw new ApiError(
      response.status,
      `Business Hub API request failed (${response.status}) for ${path}: ${body}`,
    );
  }

  return response.json() as Promise<T>;
}

export async function apiMutation<T>(path: string, options: MutationOptions = {}): Promise<T> {
  const url = new URL(`${API_BASE_URL}${path}`);
  const headers = await buildHeaders();
  const init: RequestInit = {
    method: options.method ?? "POST",
    headers,
    cache: "no-store",
  };

  if (options.body !== undefined) {
    headers.set("Content-Type", "application/json");
    init.body = JSON.stringify(options.body);
  }

  const response = await fetch(url, init);
  const bodyText = await response.text();

  if (!response.ok) {
    throw new ApiError(
      response.status,
      `Business Hub API mutation failed (${response.status}) for ${path}: ${bodyText}`,
    );
  }

  if (!bodyText) {
    return undefined as T;
  }

  return JSON.parse(bodyText) as T;
}

/* ------------------------------------------------------------------ */
/*  Session & auth                                                     */
/* ------------------------------------------------------------------ */

/**
 * Map a failed session probe to the reason shown on /login.
 *
 * Every authenticated page awaits getSession() first, so whatever happens
 * here decides what the visitor sees. Anything other than a redirect is a
 * blank "This page couldn't load" with the cause hidden in a container log,
 * which is what the droplet was serving. So: no session, no page — go to
 * /login and say why.
 */
/**
 * redirect() and notFound() signal by throwing an error whose `digest` names
 * the action. Checking the digest avoids importing Next's internal
 * isRedirectError, which is not part of the public API.
 */
function isControlFlowError(error: unknown): boolean {
  const digest = (error as { digest?: unknown } | null)?.digest;
  return typeof digest === "string" && /^NEXT_(REDIRECT|NOT_FOUND|HTTP_ERROR)/.test(digest);
}

function loginReasonFor(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.status === 401 || error.status === 403) return "expired";
    if (error.status === 429) return "throttled";
    return "upstream";
  }
  // fetch() itself threw: the API is unreachable from this server.
  return "offline";
}

export const getSession = cache(async (): Promise<SessionPayload> => {
  try {
    return await apiFetch<SessionPayload>("/session/");
  } catch (error) {
    // redirect() signals by throwing; never swallow or reclassify it.
    if (isControlFlowError(error)) throw error;
    redirect(`/login?reason=${loginReasonFor(error)}`);
  }
});

export const getUserMfaStatus = cache(async (): Promise<UserMfaStatusPayload> => {
  return apiFetch<UserMfaStatusPayload>("/session/mfa/");
});

export const getUserPasskeys = cache(async (): Promise<UserPasskeyCredentialPayload[]> => {
  return apiFetch<UserPasskeyCredentialPayload[]>("/session/passkeys/");
});

/* ------------------------------------------------------------------ */
/*  Shop / workspace                                                   */
/* ------------------------------------------------------------------ */

export const getMemberships = cache(async (): Promise<ShopMembership[]> => {
  return apiFetch<ShopMembership[]>("/shops/");
});

export const getShopPlanRequests = cache(async (shopId: string): Promise<ShopPlanRequestPayload[]> => {
  return apiFetch<ShopPlanRequestPayload[]>(`/shops/${shopId}/plan-requests/`);
});

export const getWorkspaceTeamMembers = cache(
  async (shopId: string): Promise<WorkspaceTeamMemberPayload[]> => {
    return apiFetch<WorkspaceTeamMemberPayload[]>(`/shops/${shopId}/team/`);
  },
);

export const getWorkspaceAuditEvents = cache(
  async (
    shopId: string,
    query?: { q?: string; category?: string; actorRole?: string; eventType?: string },
  ): Promise<WorkspaceAuditEventPayload[]> => {
    return apiFetch<WorkspaceAuditEventPayload[]>(`/shops/${shopId}/audit/`, {
      query: {
        q: query?.q,
        category: query?.category,
        actor_role: query?.actorRole,
        event_type: query?.eventType,
      },
    });
  },
);

export const getWorkspaceAccessSessions = cache(
  async (shopId: string): Promise<WorkspaceAccessSessionPayload[]> => {
    return apiFetch<WorkspaceAccessSessionPayload[]>(`/shops/${shopId}/sessions/`);
  },
);

/* ------------------------------------------------------------------ */
/*  Inventory                                                          */
/* ------------------------------------------------------------------ */

export const getInventory = cache(async (shopId: string, query?: string): Promise<InventoryItem[]> => {
  return apiFetch<InventoryItem[]>(`/shops/${shopId}/inventory/`, {
    query: {
      q: query,
    },
  });
});

export const getInventorySummary = cache(async (shopId: string): Promise<InventorySummaryPayload> => {
  return apiFetch<InventorySummaryPayload>(`/shops/${shopId}/inventory/summary/`);
});

export const getShopDomainState = cache(
  async (shopId: string, domain: string): Promise<ShopDomainState> => {
    return apiFetch<ShopDomainState>(`/shops/${shopId}/domain-state/${domain}/`);
  },
);

/* ------------------------------------------------------------------ */
/*  Dashboard / Pulse                                                  */
/* ------------------------------------------------------------------ */

export const getDashboardSnapshot = cache(async (shopId: string): Promise<DashboardSnapshot> => {
  return apiFetch<DashboardSnapshot>(`/shops/${shopId}/projections/dashboard/`);
});

export const getWorkspacePulse = cache(async (shopId: string): Promise<WorkspacePulseSnapshot> => {
  return apiFetch<WorkspacePulseSnapshot>(`/shops/${shopId}/projections/pulse/`);
});

export const getWorkspacePulseSignals = cache(
  async (shopId: string, status?: string): Promise<WorkspacePulseSignal[]> => {
    return apiFetch<WorkspacePulseSignal[]>(`/shops/${shopId}/projections/pulse/signals/`, {
      query: { status },
    });
  },
);

/* ------------------------------------------------------------------ */
/*  Customers                                                          */
/* ------------------------------------------------------------------ */

export const getCustomers = cache(async (shopId: string, query?: string): Promise<Customer[]> => {
  return apiFetch<Customer[]>(`/shops/${shopId}/customers/`, {
    query: {
      q: query,
    },
  });
});

export const getCustomerSummary = cache(async (shopId: string): Promise<CustomerSummaryPayload> => {
  return apiFetch<CustomerSummaryPayload>(`/shops/${shopId}/customers/summary/`);
});

/* ------------------------------------------------------------------ */
/*  Expenses                                                           */
/* ------------------------------------------------------------------ */

export const getExpenses = cache(async (shopId: string, query?: string): Promise<Expense[]> => {
  return apiFetch<Expense[]>(`/shops/${shopId}/expenses/`, {
    query: {
      q: query,
    },
  });
});

export const getExpenseSummary = cache(async (shopId: string, query?: string): Promise<ExpenseSummaryPayload> => {
  return apiFetch<ExpenseSummaryPayload>(`/shops/${shopId}/expenses/summary/`, {
    query: {
      q: query,
    },
  });
});

/* ------------------------------------------------------------------ */
/*  Attendance                                                         */
/* ------------------------------------------------------------------ */

export const getAttendanceSessions = cache(
  async (shopId: string, query?: { dateFrom?: string; dateTo?: string }): Promise<AttendanceSession[]> => {
    return apiFetch<AttendanceSession[]>(`/shops/${shopId}/attendance/`, {
      query: {
        date_from: query?.dateFrom,
        date_to: query?.dateTo,
      },
    });
  },
);

export const getAttendanceSummary = cache(
  async (
    shopId: string,
    query?: { dateFrom?: string; dateTo?: string; today?: string },
  ): Promise<AttendanceSummaryPayload> => {
    return apiFetch<AttendanceSummaryPayload>(`/shops/${shopId}/attendance/summary/`, {
      query: {
        date_from: query?.dateFrom,
        date_to: query?.dateTo,
        today: query?.today,
      },
    });
  },
);

/* ------------------------------------------------------------------ */
/*  Sales                                                              */
/* ------------------------------------------------------------------ */

export const getSales = cache(
  async (
    shopId: string,
    query?: { q?: string; dateFrom?: string; dateTo?: string; customerId?: string },
  ): Promise<Sale[]> => {
    return apiFetch<Sale[]>(`/shops/${shopId}/sales/`, {
      query: {
        q: query?.q,
        date_from: query?.dateFrom,
        date_to: query?.dateTo,
        customer_id: query?.customerId,
      },
    });
  },
);

export const getSalesSummary = cache(async (shopId: string): Promise<SalesSummaryPayload> => {
  return apiFetch<SalesSummaryPayload>(`/shops/${shopId}/sales/summary/`);
});

/* ------------------------------------------------------------------ */
/*  Payments                                                           */
/* ------------------------------------------------------------------ */

export const getPayments = cache(
  async (
    shopId: string,
    query?: { saleId?: string; dateFrom?: string; dateTo?: string },
  ): Promise<SalePaymentRecord[]> => {
    return apiFetch<SalePaymentRecord[]>(`/shops/${shopId}/payments/`, {
      query: {
        sale_id: query?.saleId,
        date_from: query?.dateFrom,
        date_to: query?.dateTo,
      },
    });
  },
);

export const getPaymentSummary = cache(async (shopId: string): Promise<PaymentSummaryPayload> => {
  return apiFetch<PaymentSummaryPayload>(`/shops/${shopId}/payments/summary/`);
});

/* ------------------------------------------------------------------ */
/*  Migration                                                          */
/* ------------------------------------------------------------------ */

export const getMigrationControls = cache(async (): Promise<MigrationDomainControl[]> => {
  return apiFetch<MigrationDomainControl[]>("/migration/domains/");
});

export const getMigrationJobRuns = cache(async (): Promise<MigrationJobRun[]> => {
  return apiFetch<MigrationJobRun[]>("/migration/jobs/");
});

export const getMigrationBridgeReceipts = cache(async (): Promise<MigrationBridgeReceipt[]> => {
  return apiFetch<MigrationBridgeReceipt[]>("/migration/bridge-receipts/");
});

export const getMigrationControlEvents = cache(async (): Promise<MigrationControlEvent[]> => {
  return apiFetch<MigrationControlEvent[]>("/migration/activity/");
});

export const getMigrationShopCheckpointEvents = cache(
  async (): Promise<MigrationShopCheckpointEvent[]> => {
    return apiFetch<MigrationShopCheckpointEvent[]>("/migration/pilot-shop-checkpoints/");
  },
);

export const getMigrationPhaseCheckpointEvents = cache(
  async (): Promise<MigrationPhaseCheckpointEvent[]> => {
    return apiFetch<MigrationPhaseCheckpointEvent[]>("/migration/phase-checkpoints/");
  },
);

export const getMigrationLaunchCheckpointEvents = cache(
  async (): Promise<MigrationLaunchCheckpointEvent[]> => {
    return apiFetch<MigrationLaunchCheckpointEvent[]>("/migration/launch-checkpoints/");
  },
);

export const getMigrationGoLiveCheckpointEvents = cache(
  async (): Promise<MigrationGoLiveCheckpointEvent[]> => {
    return apiFetch<MigrationGoLiveCheckpointEvent[]>("/migration/go-live-checkpoints/");
  },
);

export const getMigrationRolloutCheckpointEvents = cache(
  async (): Promise<MigrationRolloutCheckpointEvent[]> => {
    return apiFetch<MigrationRolloutCheckpointEvent[]>("/migration/rollout-checkpoints/");
  },
);

export const getMigrationSteadyStateCheckpointEvents = cache(
  async (): Promise<MigrationSteadyStateCheckpointEvent[]> => {
    return apiFetch<MigrationSteadyStateCheckpointEvent[]>("/migration/steady-state-checkpoints/");
  },
);

export const getMigrationShadowSummaries = cache(async (): Promise<MigrationShadowSummary[]> => {
  return apiFetch<MigrationShadowSummary[]>("/migration/shadow-summaries/");
});

export const getMigrationPilotReadiness = cache(async (): Promise<MigrationPilotReadiness[]> => {
  return apiFetch<MigrationPilotReadiness[]>("/migration/pilot-readiness/");
});

export const getMigrationPilotSignoff = cache(async (): Promise<MigrationPilotSignoff[]> => {
  return apiFetch<MigrationPilotSignoff[]>("/migration/pilot-signoff/");
});

export const getMigrationPilotShopScorecards = cache(
  async (): Promise<MigrationPilotShopScorecard[]> => {
    return apiFetch<MigrationPilotShopScorecard[]>("/migration/pilot-shop-scorecards/");
  },
);

export const getMigrationPhaseReadiness = cache(async (): Promise<MigrationPhaseReadiness> => {
  return apiFetch<MigrationPhaseReadiness>("/migration/phase-readiness/");
});

export const getMigrationRetirementReadiness = cache(
  async (): Promise<MigrationRetirementReadiness> => {
    return apiFetch<MigrationRetirementReadiness>("/migration/retirement-readiness/");
  },
);

export const getMigrationGoLiveReadiness = cache(
  async (): Promise<MigrationGoLiveReadiness> => {
    return apiFetch<MigrationGoLiveReadiness>("/migration/go-live-readiness/");
  },
);

export const getMigrationRolloutReadiness = cache(
  async (): Promise<MigrationRolloutReadiness> => {
    return apiFetch<MigrationRolloutReadiness>("/migration/rollout-readiness/");
  },
);

export const getMigrationSteadyStateReadiness = cache(
  async (): Promise<MigrationSteadyStateReadiness> => {
    return apiFetch<MigrationSteadyStateReadiness>("/migration/steady-state-readiness/");
  },
);

export const getMigrationReconciliationEvents = cache(
  async (): Promise<MigrationReconciliationEvent[]> => {
    return apiFetch<MigrationReconciliationEvent[]>("/migration/reconciliation/");
  },
);

/* ------------------------------------------------------------------ */
/*  ERPNext                                                            */
/* ------------------------------------------------------------------ */

export const getERPNextMeta = cache(async (): Promise<ERPNextMetaPayload> => {
  return apiFetch<ERPNextMetaPayload>("/erpnext/meta/");
});

export const getERPNextHealth = cache(async (): Promise<ERPNextHealthPayload> => {
  return apiFetch<ERPNextHealthPayload>("/erpnext/health/");
});

export const getERPNextBinding = cache(async (shopId: string): Promise<ERPNextShopBinding> => {
  return apiFetch<ERPNextShopBinding>(`/shops/${shopId}/erpnext/binding/`);
});

export const getERPNextSyncState = cache(async (shopId: string): Promise<ERPNextSyncState> => {
  return apiFetch<ERPNextSyncState>(`/shops/${shopId}/erpnext/sync-state/`);
});

export const getERPNextPocSummary = cache(async (shopId: string): Promise<ERPNextPocSummary> => {
  return apiFetch<ERPNextPocSummary>(`/shops/${shopId}/erpnext/poc-summary/`);
});

export const getERPNextSuppliers = cache(async (shopId: string): Promise<ERPNextSupplierMirror[]> => {
  return apiFetch<ERPNextSupplierMirror[]>(`/shops/${shopId}/erpnext/suppliers/`);
});

export const getERPNextPurchases = cache(async (shopId: string): Promise<ERPNextPurchaseMirror[]> => {
  return apiFetch<ERPNextPurchaseMirror[]>(`/shops/${shopId}/erpnext/purchases/`);
});

export const getERPNextSupplierPayments = cache(
  async (shopId: string): Promise<ERPNextSupplierPaymentMirror[]> => {
    return apiFetch<ERPNextSupplierPaymentMirror[]>(`/shops/${shopId}/erpnext/supplier-payments/`);
  },
);

export const getERPNextDocumentLinks = cache(async (shopId: string): Promise<ERPNextDocumentLink[]> => {
  return apiFetch<ERPNextDocumentLink[]>(`/shops/${shopId}/erpnext/document-links/`);
});

/* ------------------------------------------------------------------ */
/*  Platform Administration (Phase 3)                                  */
/* ------------------------------------------------------------------ */

export const getPlatformShops = cache(
  async (query?: {
    status?: string;
    plan?: string;
    q?: string;
    page?: string;
  }): Promise<PlatformShopListPayload> => {
    return apiFetch<PlatformShopListPayload>("/platform/shops/", {
      query: {
        status: query?.status,
        plan: query?.plan,
        q: query?.q,
        page: query?.page,
      },
    });
  },
);

export const getPlatformShopDetail = cache(
  async (shopId: string): Promise<PlatformShopPayload> => {
    return apiFetch<PlatformShopPayload>(`/platform/shops/${shopId}/`);
  },
);

export const getPlatformAuditEvents = cache(
  async (query?: {
    shop_id?: string;
    action?: string;
    actor_email?: string;
    q?: string;
    page?: string;
  }): Promise<PlatformAuditListPayload> => {
    return apiFetch<PlatformAuditListPayload>("/platform/audit/", {
      query: {
        shop_id: query?.shop_id,
        action: query?.action,
        actor_email: query?.actor_email,
        q: query?.q,
        page: query?.page,
      },
    });
  },
);

export const getPlatformMetrics = cache(async (): Promise<PlatformMetricsPayload> => {
  return apiFetch<PlatformMetricsPayload>("/platform/metrics/");
});

/* ------------------------------------------------------------------ */
/*  Utility helpers                                                    */
/* ------------------------------------------------------------------ */

export function resolveActiveShop(session: SessionPayload): ShopMembership | null {
  if (!session.active_shop_id) {
    return session.memberships[0] ?? null;
  }

  return (
    session.memberships.find((membership) => membership.shop.id === session.active_shop_id) ??
    session.memberships[0] ??
    null
  );
}

export function buildMigrationStats(
  controls: MigrationDomainControl[],
  jobs: MigrationJobRun[],
  receipts: MigrationBridgeReceipt[],
  readiness: MigrationPilotReadiness[],
  events: MigrationReconciliationEvent[],
): MigrationStats {
  return {
    totalControls: controls.length,
    postgresPrimaryDomains: controls.filter((control) => control.write_master === "postgres").length,
    activeBridgeDomains: controls.filter((control) => control.bridge_mode !== "disabled").length,
    bridgeReceipts: receipts.length,
    pilotReadyDomains: readiness.filter((item) => item.ready_for_pilot).length,
    openCriticalEvents: events.filter(
      (event) => event.severity === "critical" && ["open", "acknowledged"].includes(event.status),
    ).length,
    openStaleEpochEvents: events.filter(
      (event) => event.issue_code === "stale_bridge_epoch" && ["open", "acknowledged"].includes(event.status),
    ).length,
    runningJobs: jobs.filter((job) => job.status === "running").length,
  };
}

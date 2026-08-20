export type BusinessHubPlanTier = "starter" | "growth" | "pro";

export type SessionUser = {
  id: string;
  email: string;
  full_name: string;
  firebase_uid: string;
  timezone: string;
  is_platform_admin: boolean;
  mfa_totp_enabled: boolean;
  mfa_totp_enabled_at: string | null;
  mfa_totp_last_verified_at: string | null;
  passkey_enabled: boolean;
  passkey_count: number;
  mfa_security_stamp: string;
};

export type UserMfaStatusPayload = {
  totp_enabled: boolean;
  totp_pending_enrollment: boolean;
  enabled_at: string | null;
  last_verified_at: string | null;
  passkey_enabled: boolean;
  passkey_count: number;
  passkey_last_verified_at: string | null;
  security_stamp: string;
  issuer_label: string;
  account_label: string;
  challenge_window_seconds: number;
  pending_manual_secret: string;
  pending_otpauth_uri: string;
};

export type UserPasskeyCredentialPayload = {
  id: string;
  label: string;
  credential_id: string;
  cose_algorithm: number;
  sign_count: number;
  transports_json: string[];
  aaguid: string;
  last_verified_at: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type UserPasskeyBeginPayload = {
  challenge_token: string;
  options: {
    challenge: string;
    rp?: {
      id: string;
      name: string;
    };
    user?: {
      id: string;
      name: string;
      displayName: string;
    };
    pubKeyCredParams?: Array<{
      type: "public-key";
      alg: number;
    }>;
    timeout?: number;
    attestation?: "none" | string;
    authenticatorSelection?: {
      residentKey?: "preferred" | "required" | "discouraged";
      userVerification?: "preferred" | "required" | "discouraged";
    };
    excludeCredentials?: Array<{
      type: "public-key";
      id: string;
      transports?: string[];
    }>;
    rpId?: string;
    userVerification?: "preferred" | "required" | "discouraged";
    allowCredentials?: Array<{
      type: "public-key";
      id: string;
      transports?: string[];
    }>;
  };
};

export type UserPasskeyVerifyPayload = {
  credential: UserPasskeyCredentialPayload;
  status: UserMfaStatusPayload;
  verified_at: string;
  verified_until: string;
};

export type UserMfaVerifyPayload = {
  status: UserMfaStatusPayload;
  verified_at: string;
  verified_until: string;
};

export type ShopMembership = {
  id: string;
  role: "owner" | "admin" | "staff" | "viewer";
  role_label: string;
  role_summary: string;
  role_profile: "owner_control" | "store_admin" | "daily_operator" | "read_only";
  status: "active" | "invited" | "disabled";
  permissions_version: number;
  permissions_json: Record<string, unknown>;
  shop: {
    id: string;
    name: string;
    slug: string;
    currency_code: string;
    timezone: string;
    is_active: boolean;
    plan_tier: BusinessHubPlanTier;
    enabled_features: Record<string, boolean>;
    business_phone?: string;
    upi_vpa?: string;
  };
};

export type ShopPlanRequestPayload = {
  id: string;
  current_plan_tier: BusinessHubPlanTier;
  requested_plan_tier: BusinessHubPlanTier;
  status: "open" | "in_review" | "resolved" | "closed";
  request_note: string;
  context_json: Record<string, unknown>;
  requested_by_name: string;
  created_at: string;
  updated_at: string;
};

export type WorkspaceTeamMemberPayload = {
  id: string;
  member_name: string;
  member_email: string;
  phone: string;
  role: "owner" | "admin" | "staff" | "viewer";
  role_label: string;
  role_summary: string;
  role_profile: "owner_control" | "store_admin" | "daily_operator" | "read_only";
  status: "active" | "invited" | "disabled";
  permissions_version: number;
  permissions_json: Record<string, unknown>;
  is_current_user: boolean;
  can_manage: boolean;
  created_at: string;
  updated_at: string;
};

export type WorkspaceOwnershipTransferPayload = {
  shop_id: string;
  shop_name: string;
  previous_owner_membership_id: string;
  previous_owner_email: string;
  previous_owner_name: string;
  previous_owner_role: "admin" | "staff" | "viewer";
  previous_owner_role_label: string;
  new_owner_membership_id: string;
  new_owner_email: string;
  new_owner_name: string;
  transferred_at: string;
};

export type WorkspaceAuditEventPayload = {
  id: string;
  shop: string;
  shop_name: string;
  actor_user: string | null;
  actor_name: string | null;
  actor_role: "owner" | "admin" | "staff" | "viewer" | "";
  category: "workspace" | "inventory" | "customer" | "sale" | "payment";
  event_type: string;
  entity_type: string;
  entity_id: string;
  entity_label: string;
  summary: string;
  source_surface: string;
  before_json: Record<string, unknown>;
  after_json: Record<string, unknown>;
  metadata_json: Record<string, unknown>;
  occurred_at: string;
  created_at: string;
  updated_at: string;
};

export type WorkspaceAccessSessionPayload = {
  id: string;
  member_name: string;
  member_email: string;
  membership_role_snapshot: "owner" | "admin" | "staff" | "viewer";
  role_label: string;
  status: "active" | "revoked";
  device_label: string;
  platform_name: string;
  package_name: string;
  app_version: string;
  build_number: string;
  release_channel: string;
  release_tag: string;
  last_seen_at: string | null;
  revoked_at: string | null;
  revoke_reason: string;
  wipe_requested: boolean;
  wipe_requested_at: string | null;
  wipe_acknowledged_at: string | null;
  trust_score: number;
  trust_level: "trusted" | "review" | "risky" | "blocked" | string;
  trust_summary: string;
  trust_reasons: string[];
  metadata_json: Record<string, unknown>;
  can_manage: boolean;
  created_at: string;
  updated_at: string;
};

export type SessionPayload = {
  user: SessionUser;
  memberships: ShopMembership[];
  active_shop_id: string | null;
};

export type InventoryItem = {
  id: string;
  name: string;
  sku: string;
  barcode: string;
  category: string;
  subcategory: string;
  size: string;
  description: string;
  sell_price: string;
  status: string;
  tombstone: boolean;
  source_meta_json: Record<string, unknown>;
  stock_on_hand: number;
  cost_price: string | null;
  supplier_id: string | null;
  last_purchase_date: string | null;
  created_at?: string;
};

export type InventorySummaryPayload = {
  total_items: number;
  available_items: number;
  low_stock_items: number;
  out_of_stock_items: number;
  categories: number;
  projected_sell_value: string | null;
};

export type ShopDomainState = {
  shop_id: string;
  domain: string;
  control_present: boolean;
  write_master: "firebase" | "postgres";
  bridge_mode: "disabled" | "compare_only" | "firebase_to_postgres" | "postgres_to_firebase";
  cutover_status: "legacy" | "pilot" | "ready" | "postgres_primary";
  current_epoch: number;
  shadow_reads_enabled: boolean;
  is_enabled: boolean;
  can_write_on_postgres_surface: boolean;
  pilot_signoff_status:
    | "blocked"
    | "ready_for_cutover"
    | "monitoring"
    | "production_safe"
    | "rollback_recommended"
    | null;
  pilot_signoff_summary: string | null;
  pilot_recommended_action: string | null;
  pilot_latest_verify_result: string | null;
};

export type DashboardLowStockItem = {
  id: string;
  inventory_item_id: string | null;
  item_name: string;
  sku: string;
  category: string;
  stock_on_hand: number;
  sell_price: string;
  severity_rank: number;
  refreshed_at: string;
};

export type DashboardSnapshot = {
  id: string;
  shop: string;
  inventory_items_count: number;
  active_inventory_items_count: number;
  category_count: number;
  low_stock_items_count: number;
  out_of_stock_items_count: number;
  projected_sell_value: string | null;
  customer_count: number;
  active_credit_customers_count: number;
  total_outstanding_balance: string | null;
  total_lifetime_spend: string | null;
  sales_count: number;
  gross_revenue: string | null;
  outstanding_revenue: string | null;
  payment_count: number;
  total_collected: string | null;
  credit_payment_count: number;
  digital_payment_count: number;
  last_sale_at: string | null;
  refreshed_at: string;
  metadata_json: Record<string, unknown>;
  low_stock_preview: DashboardLowStockItem[];
};

export type WorkspacePulseHeadline = {
  title: string;
  body: string;
  route: string;
  cta_label: string;
  tone: "critical" | "danger" | "warning" | "info" | "healthy" | string;
};

export type WorkspacePulseTask = {
  code: string;
  priority: "critical" | "high" | "medium" | "low" | string;
  tone: "danger" | "warning" | "info" | "healthy" | string;
  title: string;
  body: string;
  route: string;
  cta_label: string;
  count: number;
  metadata_json: Record<string, unknown>;
};

export type WorkspacePulseAnomaly = {
  code: string;
  severity: "critical" | "warning" | "info" | string;
  title: string;
  body: string;
  route: string;
  cta_label: string;
  metric_value: string;
  metadata_json: Record<string, unknown>;
};

export type WorkspacePulseSnapshot = {
  refreshed_at: string;
  headline: WorkspacePulseHeadline;
  stats: {
    open_task_count: number;
    critical_anomaly_count: number;
    warning_anomaly_count: number;
    stale_session_count: number;
    wipe_pending_count: number;
    open_plan_request_count: number;
    low_stock_count: number;
  };
  tasks: WorkspacePulseTask[];
  anomalies: WorkspacePulseAnomaly[];
};

export type WorkspacePulseSignal = {
  id: string;
  signal_kind: "task" | "anomaly";
  code: string;
  status: "open" | "acknowledged" | "resolved";
  signal_level: string;
  signal_rank: number;
  tone: string;
  title: string;
  body: string;
  route: string;
  cta_label: string;
  metric_value: string;
  count: number;
  first_detected_at: string;
  last_detected_at: string;
  last_snapshot_refreshed_at: string;
  assigned_membership_id: string | null;
  assigned_member_name: string | null;
  assigned_member_role: "owner" | "admin" | "staff" | "viewer" | null;
  assigned_at: string | null;
  assigned_by_name: string | null;
  acknowledged_at: string | null;
  acknowledged_by_name: string | null;
  is_escalated: boolean;
  escalated_at: string | null;
  escalated_by_name: string | null;
  escalation_note: string;
  follow_up_note: string;
  resolved_at: string | null;
  resolved_by_name: string | null;
  resolution_note: string;
  metadata_json: Record<string, unknown>;
  created_at: string;
  updated_at: string;
};

export type Customer = {
  id: string;
  name: string;
  phone: string;
  email?: string;
  total_spent?: string;
  balance?: string;
  notes?: string;
  status?: string;
  tombstone?: boolean;
  source_meta_json?: Record<string, unknown>;
  address?: string;
  credit_limit?: number;
  balance_amount?: number;
  total_spend?: number;
  last_order_at?: string;
  created_at?: string;
  is_active?: boolean;
};

export type CustomerSummaryPayload = {
  total_customers: number;
  active_credit_customers: number;
  total_outstanding_balance: string;
  total_lifetime_spend: string | null;
};

export type Expense = {
  id: string;
  category: string;
  amount: string;
  description: string;
  payment_method: "CASH" | "UPI" | "BANK" | "CARD" | "OTHER";
  payment_reference: string;
  expense_date: string;
  tombstone: boolean;
  actor_name: string | null;
};

export type ExpenseSummaryPayload = {
  total_entries: number;
  total_amount: string;
  unique_categories: number;
  biggest_category: string | null;
};

export type AttendanceSession = {
  id: string;
  membership_id: string;
  member_name: string;
  member_role: string;
  session_date: string;
  clock_in_at: string | null;
  clock_out_at: string | null;
  status: "PRESENT" | "ABSENT" | "HALF_DAY" | "LEAVE";
  total_hours: string | null;
  overtime_hours: string;
  bonus_amount: string;
  note: string;
  tombstone: boolean;
};

export type AttendanceSummaryPayload = {
  total_sessions: number;
  present_count: number;
  leave_count: number;
  active_workers_today: number;
};

export type SaleItem = {
  id: string;
  inventory_item_id: string | null;
  name: string;
  sku: string;
  size: string;
  quantity: number;
  unit_price: string;
  unit_cost: string | null;
  line_total: string;
  is_return: boolean;
};

export type SalePayment = {
  id: string;
  payment_method: "CASH" | "UPI" | "BANK" | "CARD" | "CREDIT" | "OTHER";
  amount: string;
  reference_code: string;
  note: string;
  occurred_at: string;
};

export type Sale = {
  id: string;
  receipt_number: string;
  customer_id: string | null;
  customer_name: string;
  customer_phone: string;
  subtotal_amount: string;
  discount_amount: string;
  total_amount: string;
  amount_received: string;
  amount_due: string;
  payment_mode: string;
  footer_note: string;
  note: string;
  sale_date: string;
  occurred_at: string;
  status: string;
  tombstone: boolean;
  source_meta_json: Record<string, unknown>;
  actor_name: string | null;
  item_count: number;
  payment_count: number;
  items: SaleItem[];
  payments: SalePayment[];
};

export type SalePaymentRecord = {
  id: string;
  sale_id: string;
  receipt_number: string;
  customer_name: string;
  sale_total_amount: string;
  payment_method: "CASH" | "UPI" | "BANK" | "CARD" | "CREDIT" | "OTHER";
  amount: string;
  reference_code: string;
  note: string;
  occurred_at: string;
  actor_name: string | null;
};

export type SalesSummaryPayload = {
  total_sales: number;
  gross_revenue: string;
  outstanding_revenue: string | null;
  average_ticket: string | null;
};

export type PaymentSummaryPayload = {
  payment_count: number;
  total_collected: string | null;
  credit_count: number | null;
  digital_payment_count: number | null;
};

export type MigrationDomainControl = {
  id: string;
  shop: string;
  shop_name: string;
  shop_slug: string;
  domain: string;
  write_master: "firebase" | "postgres";
  bridge_mode: "disabled" | "compare_only" | "firebase_to_postgres" | "postgres_to_firebase";
  cutover_status: "legacy" | "pilot" | "ready" | "postgres_primary";
  current_epoch: number;
  shadow_reads_enabled: boolean;
  is_enabled: boolean;
  last_backfill_at: string | null;
  last_shadow_verified_at: string | null;
  metadata_json: Record<string, unknown>;
  notes: string;
  created_at: string;
  updated_at: string;
};

export type MigrationJobRun = {
  id: string;
  shop: string | null;
  shop_name: string | null;
  domain: string;
  job_type: "backfill" | "shadow_compare" | "bridge_replay" | "projection_refresh";
  status: "queued" | "running" | "succeeded" | "failed";
  actor_user: string | null;
  actor_name: string | null;
  trace_id: string;
  rows_scanned: number;
  rows_written: number;
  rows_skipped: number;
  mismatch_count: number;
  error_message: string;
  payload_json: Record<string, unknown>;
  started_at: string | null;
  finished_at: string | null;
  created_at: string;
  updated_at: string;
};

export type MigrationBridgeReceipt = {
  id: string;
  shop: string;
  shop_name: string;
  domain: string;
  origin_system: string;
  origin_event_id: string;
  command_type: string;
  entity_type: string;
  entity_id: string;
  base_domain_epoch: number;
  payload_json: Record<string, unknown>;
  applied_at: string;
  created_at: string;
  updated_at: string;
};

export type MigrationControlEvent = {
  id: string;
  control: string;
  shop: string;
  shop_name: string;
  domain: string;
  event_type: string;
  actor_user: string | null;
  actor_name: string | null;
  result: string;
  from_cutover_status: string;
  to_cutover_status: string;
  from_write_master: string;
  to_write_master: string;
  summary: string;
  metadata_json: Record<string, unknown>;
  occurred_at: string;
  created_at: string;
  updated_at: string;
};

export type MigrationShopCheckpointEvent = {
  id: string;
  shop: string;
  shop_name: string;
  shop_slug: string;
  actor_user: string | null;
  actor_name: string | null;
  decision:
    | "approved_for_cutover"
    | "hold_for_monitoring"
    | "rollback_escalated";
  overall_status_snapshot:
    | "blocked"
    | "ready_for_cutover"
    | "monitoring"
    | "production_safe"
    | "rollback_recommended";
  summary: string;
  recommended_action_snapshot: string;
  metadata_json: Record<string, unknown>;
  occurred_at: string;
  created_at: string;
  updated_at: string;
};

export type MigrationPhaseCheckpointEvent = {
  id: string;
  phase: string;
  actor_user: string | null;
  actor_name: string | null;
  decision:
    | "approved_for_next_phase"
    | "hold_for_monitoring"
    | "rollback_escalated";
  overall_status_snapshot:
    | "blocked"
    | "monitoring"
    | "ready_for_phase_exit"
    | "rollback_recommended";
  summary: string;
  recommended_action_snapshot: string;
  metadata_json: Record<string, unknown>;
  occurred_at: string;
  created_at: string;
  updated_at: string;
};

export type MigrationLaunchCheckpointEvent = {
  id: string;
  phase: string;
  actor_user: string | null;
  actor_name: string | null;
  decision:
    | "approved_for_launch"
    | "hold_for_hardening"
    | "rollback_to_phase4";
  overall_status_snapshot:
    | "blocked"
    | "monitoring"
    | "ready_for_launch"
    | "retirement_complete"
    | "rollback_recommended";
  summary: string;
  recommended_action_snapshot: string;
  metadata_json: Record<string, unknown>;
  occurred_at: string;
  created_at: string;
  updated_at: string;
};

export type MigrationGoLiveCheckpointEvent = {
  id: string;
  phase: string;
  actor_user: string | null;
  actor_name: string | null;
  decision:
    | "execute_go_live"
    | "remain_in_hypercare"
    | "handoff_to_steady_state"
    | "rollback_launch";
  overall_status_snapshot:
    | "blocked"
    | "ready_for_go_live"
    | "hypercare_active"
    | "steady_state"
    | "rollback_recommended";
  summary: string;
  recommended_action_snapshot: string;
  metadata_json: Record<string, unknown>;
  occurred_at: string;
  created_at: string;
  updated_at: string;
};

export type MigrationRolloutCheckpointEvent = {
  id: string;
  phase: string;
  actor_user: string | null;
  actor_name: string | null;
  decision:
    | "advance_rollout_wave"
    | "hold_rollout_wave"
    | "scale_tuning_active"
    | "complete_rollout"
    | "rollback_shop_wave";
  overall_status_snapshot:
    | "blocked"
    | "wave_ready"
    | "rollout_active"
    | "scale_tuning"
    | "completed"
    | "rollback_recommended";
  summary: string;
  recommended_action_snapshot: string;
  metadata_json: Record<string, unknown>;
  occurred_at: string;
  created_at: string;
  updated_at: string;
};

export type MigrationSteadyStateCheckpointEvent = {
  id: string;
  phase: string;
  actor_user: string | null;
  actor_name: string | null;
  decision:
    | "accept_steady_state"
    | "hold_for_improvement"
    | "architecture_review_required"
    | "incident_stabilization_active";
  overall_status_snapshot:
    | "blocked"
    | "steady_state_ready"
    | "operating_normally"
    | "improvement_window"
    | "architecture_review_required"
    | "incident_stabilization"
    | "rollback_recommended";
  summary: string;
  recommended_action_snapshot: string;
  metadata_json: Record<string, unknown>;
  occurred_at: string;
  created_at: string;
  updated_at: string;
};

export type MigrationShadowSummary = {
  shop: string;
  shop_name: string;
  shop_slug: string;
  domain: string;
  write_master: "firebase" | "postgres";
  bridge_mode: "disabled" | "compare_only" | "firebase_to_postgres" | "postgres_to_firebase";
  current_epoch: number;
  last_shadow_verified_at: string | null;
  latest_compare_status: "queued" | "running" | "succeeded" | "failed" | null;
  latest_compare_at: string | null;
  latest_compare_mismatches: number;
  latest_compare_trace_id: string | null;
  open_events: number;
  open_critical_events: number;
  open_stale_epoch_events: number;
};

export type MigrationPilotReadiness = {
  control_id: string;
  shop: string;
  shop_name: string;
  shop_slug: string;
  domain: string;
  cutover_status: "legacy" | "pilot" | "ready" | "postgres_primary";
  write_master: "firebase" | "postgres";
  bridge_mode: "disabled" | "compare_only" | "firebase_to_postgres" | "postgres_to_firebase";
  current_epoch: number;
  shadow_reads_enabled: boolean;
  last_backfill_at: string | null;
  last_shadow_verified_at: string | null;
  latest_compare_status: "queued" | "running" | "succeeded" | "failed" | null;
  latest_compare_at: string | null;
  latest_compare_mismatches: number;
  latest_compare_trace_id: string | null;
  open_events: number;
  open_critical_events: number;
  open_stale_epoch_events: number;
  ready_for_pilot: boolean;
  recommended_next_status: "legacy" | "pilot" | "ready" | "postgres_primary";
  blocking_reasons: string[];
  warnings: string[];
};

export type MigrationPilotSignoff = {
  control_id: string;
  shop: string;
  shop_name: string;
  shop_slug: string;
  domain: string;
  cutover_status: "legacy" | "pilot" | "ready" | "postgres_primary";
  write_master: "firebase" | "postgres";
  current_epoch: number;
  signoff_status:
    | "blocked"
    | "ready_for_cutover"
    | "monitoring"
    | "production_safe"
    | "rollback_recommended";
  latest_verify_result: string | null;
  latest_verified_at: string | null;
  latest_compare_status: "queued" | "running" | "succeeded" | "failed" | null;
  latest_compare_mismatches: number;
  open_critical_events: number;
  open_stale_epoch_events: number;
  ready_for_pilot: boolean;
  summary: string;
  recommended_action: string;
  blocking_reasons: string[];
  warnings: string[];
};

export type MigrationPilotShopScorecard = {
  shop: string;
  shop_name: string;
  shop_slug: string;
  overall_status:
    | "blocked"
    | "ready_for_cutover"
    | "monitoring"
    | "production_safe"
    | "rollback_recommended";
  recommended_action: string;
  summary: string;
  missing_domains: string[];
  production_safe_domains: number;
  ready_for_cutover_domains: number;
  monitoring_domains: number;
  blocked_domains: number;
  rollback_recommended_domains: number;
  domains: MigrationPilotSignoff[];
};

export type MigrationPhaseReadinessShop = {
  shop: string;
  shop_name: string;
  shop_slug: string;
  overall_status:
    | "blocked"
    | "ready_for_cutover"
    | "monitoring"
    | "production_safe"
    | "rollback_recommended";
  recommended_action: string;
  summary: string;
  latest_checkpoint_decision:
    | "approved_for_cutover"
    | "hold_for_monitoring"
    | "rollback_escalated"
    | null;
  latest_checkpoint_overall_status: string | null;
  latest_checkpoint_at: string | null;
};

export type MigrationPhaseReadiness = {
  phase: string;
  overall_status:
    | "blocked"
    | "monitoring"
    | "ready_for_phase_exit"
    | "rollback_recommended";
  pilot_shop_count: number;
  approved_for_cutover_count: number;
  hold_for_monitoring_count: number;
  rollback_escalated_count: number;
  shops_without_checkpoint: number;
  production_safe_shop_count: number;
  ready_for_cutover_shop_count: number;
  monitoring_shop_count: number;
  blocked_shop_count: number;
  rollback_recommended_shop_count: number;
  recommended_action: string;
  summary: string;
  shops: MigrationPhaseReadinessShop[];
};

export type MigrationRetirementDomainSnapshot = {
  domain: string;
  present: boolean;
  write_master: "firebase" | "postgres" | null;
  bridge_mode:
    | "disabled"
    | "compare_only"
    | "firebase_to_postgres"
    | "postgres_to_firebase"
    | null;
  cutover_status:
    | "legacy"
    | "pilot"
    | "ready"
    | "postgres_primary"
    | null;
};

export type MigrationRetirementShopScorecard = {
  shop: string;
  shop_name: string;
  shop_slug: string;
  overall_status:
    | "blocked"
    | "monitoring"
    | "ready_for_launch"
    | "rollback_recommended";
  recommended_action: string;
  summary: string;
  missing_domains: string[];
  postgres_primary_domains: number;
  firebase_primary_domains: number;
  active_bridge_domains: number;
  compare_only_domains: number;
  blocked_domains: number;
  open_events: number;
  open_critical_events: number;
  domains: MigrationRetirementDomainSnapshot[];
};

export type MigrationRetirementReadiness = {
  phase: string;
  overall_status:
    | "blocked"
    | "monitoring"
    | "ready_for_launch"
    | "retirement_complete"
    | "rollback_recommended";
  shop_count: number;
  ready_for_launch_shop_count: number;
  monitoring_shop_count: number;
  blocked_shop_count: number;
  rollback_recommended_shop_count: number;
  latest_launch_decision:
    | "approved_for_launch"
    | "hold_for_hardening"
    | "rollback_to_phase4"
    | null;
  latest_launch_status_snapshot: string | null;
  latest_launch_at: string | null;
  recommended_action: string;
  summary: string;
  shops: MigrationRetirementShopScorecard[];
};

export type MigrationGoLiveReadiness = {
  phase: string;
  overall_status:
    | "blocked"
    | "ready_for_go_live"
    | "hypercare_active"
    | "steady_state"
    | "rollback_recommended";
  shop_count: number;
  ready_for_launch_shop_count: number;
  monitoring_shop_count: number;
  blocked_shop_count: number;
  rollback_recommended_shop_count: number;
  latest_launch_decision:
    | "approved_for_launch"
    | "hold_for_hardening"
    | "rollback_to_phase4"
    | null;
  latest_launch_status_snapshot: string | null;
  latest_launch_at: string | null;
  latest_go_live_decision:
    | "execute_go_live"
    | "remain_in_hypercare"
    | "handoff_to_steady_state"
    | "rollback_launch"
    | null;
  latest_go_live_status_snapshot: string | null;
  latest_go_live_at: string | null;
  recommended_action: string;
  summary: string;
  shops: MigrationRetirementShopScorecard[];
};

export type MigrationRolloutReadiness = {
  phase: string;
  overall_status:
    | "blocked"
    | "wave_ready"
    | "rollout_active"
    | "scale_tuning"
    | "completed"
    | "rollback_recommended";
  shop_count: number;
  ready_for_launch_shop_count: number;
  monitoring_shop_count: number;
  blocked_shop_count: number;
  rollback_recommended_shop_count: number;
  latest_go_live_decision:
    | "execute_go_live"
    | "remain_in_hypercare"
    | "handoff_to_steady_state"
    | "rollback_launch"
    | null;
  latest_go_live_status_snapshot: string | null;
  latest_go_live_at: string | null;
  latest_rollout_decision:
    | "advance_rollout_wave"
    | "hold_rollout_wave"
    | "scale_tuning_active"
    | "complete_rollout"
    | "rollback_shop_wave"
    | null;
  latest_rollout_status_snapshot: string | null;
  latest_rollout_at: string | null;
  recommended_action: string;
  summary: string;
  shops: MigrationRetirementShopScorecard[];
};

export type MigrationSteadyStateReadiness = {
  phase: string;
  overall_status:
    | "blocked"
    | "steady_state_ready"
    | "operating_normally"
    | "improvement_window"
    | "architecture_review_required"
    | "incident_stabilization"
    | "rollback_recommended";
  shop_count: number;
  ready_for_launch_shop_count: number;
  monitoring_shop_count: number;
  blocked_shop_count: number;
  rollback_recommended_shop_count: number;
  latest_rollout_decision:
    | "advance_rollout_wave"
    | "hold_rollout_wave"
    | "scale_tuning_active"
    | "complete_rollout"
    | "rollback_shop_wave"
    | null;
  latest_rollout_status_snapshot: string | null;
  latest_rollout_at: string | null;
  latest_steady_state_decision:
    | "accept_steady_state"
    | "hold_for_improvement"
    | "architecture_review_required"
    | "incident_stabilization_active"
    | null;
  latest_steady_state_status_snapshot: string | null;
  latest_steady_state_at: string | null;
  rollout_completed: boolean;
  steady_state_accepted: boolean;
  improvement_window_active: boolean;
  architecture_review_active: boolean;
  incident_stabilization_active: boolean;
  recommended_action: string;
  summary: string;
  shops: MigrationRetirementShopScorecard[];
};

export type MigrationPilotPreparationResult = {
  control_id: string;
  shop: string;
  shop_name: string;
  domain: string;
  jobs: MigrationJobRun[];
  readiness: MigrationPilotReadiness;
};

export type MigrationPilotVerificationResult = {
  control_id: string;
  shop: string;
  shop_name: string;
  domain: string;
  verification_job: MigrationJobRun;
  cutover_status: "legacy" | "pilot" | "ready" | "postgres_primary";
  write_master: "firebase" | "postgres";
  latest_compare_status: "queued" | "running" | "succeeded" | "failed" | null;
  latest_compare_mismatches: number;
  open_critical_events: number;
  open_stale_epoch_events: number;
  healthy: boolean;
  requires_rollback: boolean;
  operational_verdict:
    | "production_safe"
    | "monitoring"
    | "rollback_recommended";
  summary: string;
};

export type MigrationReconciliationEvent = {
  id: string;
  shop: string;
  shop_name: string;
  domain: string;
  severity: "info" | "warning" | "critical";
  status: "open" | "acknowledged" | "resolved" | "ignored";
  issue_code: string;
  entity_type: string;
  entity_id: string;
  source_reference: string;
  expected_master: string;
  observed_source: string;
  occurred_at: string;
  mismatch_payload_json: Record<string, unknown>;
  note: string;
  resolver_user: string | null;
  resolver_name: string | null;
  resolved_at: string | null;
  resolution_note: string;
  created_at: string;
  updated_at: string;
};

export type MigrationStats = {
  totalControls: number;
  postgresPrimaryDomains: number;
  activeBridgeDomains: number;
  bridgeReceipts: number;
  pilotReadyDomains: number;
  openCriticalEvents: number;
  openStaleEpochEvents: number;
  runningJobs: number;
};

export type ERPNextMetaPayload = {
  configured: boolean;
  base_url: string;
  site_name: string;
  verify_ssl: boolean;
  timeout_seconds: number;
  has_api_key: boolean;
  has_api_secret: boolean;
  is_mock_mode: boolean;
  mock_state_path: string;
  cycle_beat_enabled: boolean;
  cycle_beat_minutes: number;
  cycle_beat_limit: number;
  recommendation?: string;
};

export type ERPNextHealthPayload = {
  status: string;
  configured: boolean;
  base_url: string;
  site_name: string;
  reachable: boolean;
  authenticated: boolean;
  error?: string;
  status_code?: number | null;
  payload?: Record<string, unknown> | null;
  logged_user?: string;
  ping?: string;
};

export type ERPNextShopBinding = {
  id: string;
  shop_id: string;
  is_enabled: boolean;
  environment: "sandbox" | "live";
  site_url_override: string;
  company: string;
  warehouse: string;
  selling_price_list: string;
  cost_center: string;
  customer_group: string;
  supplier_group: string;
  currency_code: string;
  item_sync_enabled: boolean;
  customer_sync_enabled: boolean;
  stock_sync_enabled: boolean;
  sales_posting_enabled: boolean;
  payment_posting_enabled: boolean;
  purchase_sync_enabled: boolean;
  metadata_json: Record<string, unknown>;
  last_verified_at: string | null;
  last_health_status: string;
  last_error_message: string;
  last_health_payload_json: Record<string, unknown>;
  created_at: string;
  updated_at: string;
};

export type ERPNextSyncCursor = {
  id: string;
  shop_id: string;
  domain: string;
  direction: "pull" | "push";
  status: string;
  last_remote_modified_at: string | null;
  last_remote_cursor: string;
  last_started_at: string | null;
  last_finished_at: string | null;
  last_result_count: number;
  last_error_message: string;
  metadata_json: Record<string, unknown>;
  created_at: string;
  updated_at: string;
};

export type ERPNextDocumentLink = {
  id: string;
  shop_id: string;
  local_domain: string;
  local_object_id: string;
  remote_doctype: string;
  remote_name: string;
  direction: "pull" | "push";
  sync_status: string;
  last_synced_at: string | null;
  last_error_message: string;
  metadata_json: Record<string, unknown>;
  created_at: string;
  updated_at: string;
};

export type ERPNextSyncState = {
  binding: ERPNextShopBinding | null;
  cursors: ERPNextSyncCursor[];
  document_link_counts: {
    total: number;
    linked: number;
    pending: number;
    failed: number;
  };
};

export type ERPNextPocSummary = {
  shop_id: string;
  shop_slug: string;
  binding: {
    present: boolean;
    enabled: boolean;
    environment: string;
    company: string;
    warehouse: string;
    health_status: string;
    last_verified_at: string | null;
  };
  local_counts: {
    inventory_items: number;
    customers: number;
    sales: number;
    payments: number;
    erpnext_suppliers: number;
    erpnext_purchases: number;
    erpnext_purchase_orders: number;
    erpnext_purchase_receipts: number;
    erpnext_purchase_invoices: number;
    erpnext_purchase_returns: number;
    erpnext_supplier_payments: number;
  };
  cursor_status: {
    total: number;
    idle: number;
    running: number;
    failed: number;
    succeeded: number;
  };
  document_links: {
    total: number;
    linked: number;
    pending: number;
    failed: number;
  };
  recommendation: string;
};

export type ERPNextSupplierMirror = {
  id: string;
  shop_id: string;
  remote_name: string;
  supplier_name: string;
  supplier_group: string;
  supplier_type: string;
  phone: string;
  email: string;
  status: string;
  last_remote_modified_at: string | null;
  last_synced_at: string | null;
  metadata_json: Record<string, unknown>;
  created_at: string;
  updated_at: string;
};

export type ERPNextPurchaseMirror = {
  id: string;
  shop_id: string;
  supplier_id: string | null;
  supplier_name: string;
  remote_doctype: string;
  remote_name: string;
  supplier_remote_name: string;
  posting_date: string | null;
  warehouse: string;
  currency_code: string;
  grand_total: string;
  status: string;
  docstatus: number;
  item_count: number;
  is_return: boolean;
  return_against_remote_name: string;
  items_json: Record<string, unknown>[];
  metadata_json: Record<string, unknown>;
  last_remote_modified_at: string | null;
  last_synced_at: string | null;
  created_at: string;
  updated_at: string;
};

export type ERPNextSupplierPaymentMirror = {
  id: string;
  shop_id: string;
  supplier_id: string | null;
  supplier_name: string;
  remote_doctype: string;
  remote_name: string;
  supplier_remote_name: string;
  posting_date: string | null;
  payment_type: string;
  mode_of_payment: string;
  reference_no: string;
  currency_code: string;
  paid_amount: string;
  received_amount: string;
  docstatus: number;
  status: string;
  metadata_json: Record<string, unknown>;
  last_remote_modified_at: string | null;
  last_synced_at: string | null;
  created_at: string;
  updated_at: string;
};

export type PlatformShopStatus = "pending" | "active" | "suspended";

export type PlatformShopPayload = {
  id: string;
  name: string;
  slug: string;
  legal_name: string;
  currency_code: string;
  timezone: string;
  region_code: string;
  is_active: boolean;
  status: PlatformShopStatus;
  status_display: string;
  status_reason: string;
  plan_tier: BusinessHubPlanTier;
  owner_email: string | null;
  owner_name: string | null;
  member_count: number;
  created_at: string;
  updated_at: string;
};

export type PlatformShopListPayload = {
  count: number;
  next: string | null;
  previous: string | null;
  results: PlatformShopPayload[];
};

export type PlatformAuditEventPayload = {
  id: string;
  action: string;
  reason: string;
  actor_user: string | null;
  actor_name: string | null;
  actor_email: string | null;
  shop: string | null;
  shop_name: string | null;
  shop_slug: string | null;
  before_json: Record<string, unknown>;
  after_json: Record<string, unknown>;
  metadata_json: Record<string, unknown>;
  ip_address: string | null;
  created_at: string;
};

export type PlatformAuditListPayload = {
  count: number;
  next: string | null;
  previous: string | null;
  results: PlatformAuditEventPayload[];
};

export type PlatformMetricsPayload = {
  total_shops: number;
  active_shops: number;
  pending_shops: number;
  suspended_shops: number;
  total_users: number;
  starter_shops: number;
  growth_shops: number;
  pro_shops: number;
  shops_created_last_30d: number;
  open_plan_requests: number;
};

/* ------------------------------------------------------------------ */
/*  Day Close & Cash Reconciliation Types                              */
/* ------------------------------------------------------------------ */

export type DayCloseDenomination = {
  count2000: number;
  count500: number;
  count200: number;
  count100: number;
  count50: number;
  count20: number;
  count10: number;
  coins: number;
};

export type DayCloseRecord = {
  id: string;
  shop_id: string;
  cashier_user_id: string;
  cashier_name: string;
  opened_at: string;
  closed_at: string;
  opening_float: number;
  system_cash_sales: number;
  system_cash_expenses: number;
  system_cash_withdrawals: number;
  expected_cash_in_drawer: number;
  actual_physical_cash: number;
  variance_amount: number;
  variance_reason: string;
  denominations: DayCloseDenomination;
  status: "open" | "reconciled" | "audited";
  notes: string;
};

/* ------------------------------------------------------------------ */
/*  Suppliers & Inward Purchases Types                                */
/* ------------------------------------------------------------------ */

export type Supplier = {
  id: string;
  name: string;
  phone: string;
  email: string;
  address: string;
  gstin: string;
  outstanding_balance: number;
  payment_terms: string;
  created_at: string;
};

export type PurchaseOrderItem = {
  id: string;
  product_id: string;
  product_name: string;
  sku: string;
  quantity: number;
  unit_cost: number;
  gst_rate: number;
  total_amount: number;
};

export type PurchaseOrder = {
  id: string;
  order_number: string;
  supplier_id: string;
  supplier_name: string;
  status: "draft" | "ordered" | "received" | "cancelled";
  items: PurchaseOrderItem[];
  subtotal: number;
  tax_amount: number;
  total_amount: number;
  paid_amount: number;
  notes: string;
  created_at: string;
  received_at: string | null;
};

/* ------------------------------------------------------------------ */
/*  In-Shop Team Chat & Messaging Types                               */
/* ------------------------------------------------------------------ */

export type ChatChannel = {
  id: string;
  name: string;
  description: string;
  is_private: boolean;
  unread_count: number;
  last_message_at: string | null;
};

export type ChatAttachment = {
  id: string;
  file_name: string;
  file_type: string;
  file_size: number;
  file_url: string;
  thumbnail_url?: string;
};

export type ChatMessage = {
  id: string;
  channel_id: string;
  sender_id: string;
  sender_name: string;
  sender_email: string;
  content: string;
  attachments?: ChatAttachment[];
  created_at: string;
};

/* ------------------------------------------------------------------ */
/*  Web POS Cart & Payment Engine Types                               */
/* ------------------------------------------------------------------ */

export type CartItem = {
  id: string;
  product_id: string;
  name: string;
  sku: string;
  barcode: string;
  unit_price: number;
  cost_price: number;
  tax_rate: number;
  quantity: number;
  discount_amount: number;
  total_price: number;
  available_stock: number;
  /** Carried from the product so the line can say "1.25 kg" rather than
   *  "1.25", which on a weighed line is the difference between a price a
   *  customer can check and a number they cannot. */
  unit?: string;
};

export type SplitPaymentTender = {
  cash: number;
  card: number;
  upi: number;
  khata_due: number;
  card_ref?: string;
  upi_ref?: string;
};

export type UpiQrConfig = {
  vpa: string;
  payee_name: string;
  amount: number;
  transaction_note: string;
  transaction_ref: string;
};

/* ------------------------------------------------------------------ */
/*  Reports & Financial Analytics Types                               */
/* ------------------------------------------------------------------ */

export type ProfitLossReportPayload = {
  period_start: string;
  period_end: string;
  gross_sales: number;
  discounts: number;
  net_sales: number;
  cogs: number;
  gross_profit: number;
  gross_margin_percent: number;
  operating_expenses: {
    rent: number;
    salaries: number;
    utilities: number;
    supplies: number;
    other: number;
    total: number;
  };
  net_profit: number;
  net_margin_percent: number;
  taxes_collected: {
    cgst: number;
    sgst: number;
    igst: number;
    total: number;
  };
};

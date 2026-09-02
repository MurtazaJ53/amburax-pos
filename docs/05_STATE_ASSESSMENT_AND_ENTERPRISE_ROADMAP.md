# Business Hub — State Assessment & Enterprise/White-Label Roadmap

_Dated 2026-07-22. A current-state read of the **active app** (`apps/mobile_flutter` +
`apps/backend`), the forward roadmap, and how to evolve into a premium white-label platform.
Complements the planning docs in `docs/02_ROADMAP_AND_REMAINING.md` and
`docs/03_IMPROVEMENTS_AND_NEW_FEATURES.md` — this one reflects where we actually are today._

---

## 0. Where we left off (exact)

- **Branch:** `feat/universal-import`, **11 commits ahead of `main`, all pushed, none merged.**
  The merge to `main` is blocked by the permission classifier and needs a human to run it.
- **Working tree:** clean except the new `docs/mca-submission/` pack (uncommitted).
- **This session's theme:** six **silent data-integrity** bugs found and fixed — none of them
  crashed, they just quietly did the wrong thing. That pattern is the single most important
  finding for how we test going forward.
- **Test rig:** the Django backend runs locally on SQLite, seeded demo data, reached from the
  device over an `adb reverse` USB tunnel. The signed APK builds and runs on a physical device.

### The six bugs fixed this session (all pushed, not yet on `main`)
| Fix | Why it mattered |
|-----|-----------------|
| Own XLSX reader | The `excel` package crashed on real exports — import was unusable |
| Content-Length on POST | dart:io sent chunked bodies; the server discarded them → every POST field "missing". **Verified fixed on-device.** |
| Backend boots from clean install | `django-cryptography` unpinned → resolved to a 2021 version that imports a Django-5-removed module; a fresh `pip install` produced a dead server |
| History "Attention" signal | Counted self-healing transient failures as alarm-red "needs review" |
| Import keeps real dates | `DateTime.tryParse` is ISO-only → every dd/MM/yyyy date silently became "today", rewriting trading history |
| Re-import no longer duplicates | Sales used `Map.hashCode` (identity) for IDs → re-importing a file doubled revenue |
| Khata opening balances | Imported dues showed a balance with an empty ledger; added provenance + a backfill |
| Pilot readiness gating | A till that briefly lost signal could be blocked from opening a shift |

---

## 1. What is implemented (grounded)

**Scale:** ~50,900 lines Dart (mobile, 10 feature modules, 232 passing tests) + ~29,800 lines
Python (backend, 16 apps, 116 test files).

- **POS:** quick-key grid, barcode + weight-barcode parsing, split payments, discounts, UPI QR on
  receipts, thermal + PDF printing, cash-drawer kick, biometric manager override.
- **Inventory:** event-sourced stock ledger (fractional-safe), procurement → auto stock increment
  + supplier payables, cost/sell separation.
- **Customers / khata:** credit ledger with running balance, encrypted phone + blind-index search,
  WhatsApp reminders with embedded UPI link, opening-balance provenance.
- **GST:** CGST/SGST/IGST, HSN summaries, one-tap GSTR-1 + GSTR-3B filing pack (ZIP), P&L.
- **Sync:** offline-first Drift/SQLite → idempotent `commerce_outbox` → push with backoff +
  dead-letter queue; upsert-merge pull (no data loss).
- **Import:** universal CSV/XLSX engine with auto type-detection, own XLSX reader, robust date
  parsing, content-derived IDs (no dup), duplicate-cleanup + khata backfill tools.
- **Security/RBAC:** roles owner/admin/staff/viewer via `get_membership_or_403`; row-level
  multi-tenancy; encrypted PII; JWT (HS256) coexisting with Firebase RS256.
- **Ops:** Docker Compose prod, pgbouncer, Celery/Redis, Channels, OpenTelemetry, CI → signed APK.

---

## 2. What is incomplete or missing

| Area | Status | Note |
|------|--------|------|
| **Hosted backend** | ❌ Not deployed | Sync only works over local/USB tunnel. **This is the top blocker** — multi-device, staff accounts, and the JWT cutover all depend on it. |
| **Firebase → JWT auth cutover** | 🟡 Partial | Backend JWT built + tested; mobile still authenticates with Firebase tokens. Migration not executed. |
| **Leaked service-account key** | ❌ Not rotated | Purged from git history, but the credential itself must be rotated in the Firebase console (user-owned). |
| **`business-hub-release.jks` backup** | ❌ Not backed up | **Irreversible risk** — lose it and you can never update the app on Play Store. |
| **Offline soak test** | ❌ Not run | 50 offline fractional sales → reconnect → verify. The machinery is built + unit-tested; the end-to-end run is pending. |
| **Suppliers on mobile** | ❌ No local store | Supplier import unsupported on-device; backend has the model. |
| **Multi-language UI** | ❌ Not started | English only. |
| **Desktop shell** | 🟡 Wraps legacy | Tauri app wraps the deprecated React build; CSP is `null`. Retire or re-point. |
| **`admin_web` (Next.js)** | ❓ Unverified | Present but not verified this cycle. |
| **`dev.sqlite3`** | ⚠ Dead | Undecryptable after the key rotation — every read throws. Delete it. |

---

## 3. Improvements to make (design / architecture / performance / security / usability)

### Architecture & correctness
- **Testing philosophy shift.** All six bugs this session were silent *correctness* faults, not
  crashes. Add **property-based / golden tests** around money, dates, GST totals, and sync
  idempotency — assert the numbers are right, not merely that nothing throws.
- **Sync contract test-suite.** Codify the no-loss / no-duplication guarantee as an automated
  integration test against a real backend (currently proven by reasoning + unit tests + one
  on-device check).
- **Retire the desktop-wraps-legacy coupling.** It's the last hard dependency on the deprecated
  app; either drop desktop or point it at the active surface.

### Performance
- **Server-computed projections** exist; add **response caching** for dashboard reads and
  **pagination** everywhere a list can grow (history, ledgers).
- **DB indexing audit** as data grows: confirm composite indexes on every `(shop, …)` hot path.
- **Mobile cold-start budget**: measure and cap first-frame time; lazy-load heavy modules.

### Security
- **Rotate the leaked key** and complete the JWT cutover (removes the Firebase dependency).
- **Restore Tauri CSP** before shipping desktop; declare a minimal capability allowlist.
- **Enforce `DJANGO_SECRET_KEY`, `BLIND_INDEX_PEPPER`** in prod (already guarded — verify in the
  deploy pipeline).
- **Rate-limit auth + command endpoints** (django-ratelimit is present — apply it).
- **Audit log surfacing:** the `audit` app exists; expose an owner-visible activity trail.

### Usability
- **Import summary + undo** (partially there) — always show "N imported, N updated, N skipped, N
  undated" and offer a one-tap undo of the last import batch.
- **Empty/first-run onboarding** — guided setup (shop details, first item, first sale).
- **Offline status clarity** — a persistent, honest sync indicator (queued / syncing / rejected).

---

## 4. Simplify / modernize / optimize

- **Delete dead weight:** `dev.sqlite3` (undecryptable), stray root APKs/`.jks` duplicates,
  `temp-run48-logs.zip`, `keystore.base64.txt` if unused. Keep the repo lean.
- **Pin all backend deps** (done for the crypto/channels set — audit the rest).
- **Consolidate the 80+ `docs/` files.** Much is migration-phase planning; archive superseded
  material so the README stays the ground truth.
- **One config surface:** the many `--dart-define` flags should collapse into a small number of
  build flavors (dev / staging / prod) — see §7 white-label flavors.

---

## 5. Standout / competitive features (increase product value)

- **True offline-first** (local store authoritative, not cache) — most competitors stall offline.
- **GST-native**: one-tap GSTR-1/3B filing pack is a real time-saver few SME tools ship.
- **Event-sourced, fractional stock** — correct for by-weight retail; auditable history.
- **Khata + WhatsApp UPI reminders** — collections workflow tuned to Indian retail.
- **Encrypted-but-searchable PII** (blind index) — privacy without losing phone lookup.
- **Opportunities to differentiate further:** on-device analytics (best-sellers, dead stock,
  reorder points), staff performance, low-stock auto-purchase drafts, and a customer-facing
  digital receipt / loyalty layer.

---

## 6. Technical debt & risks to address first

| Item | Risk | Action |
|------|------|--------|
| Keystore not backed up | **Irreversible** loss of Play Store update ability | Back up `business-hub-release.jks` off-machine **today** |
| Leaked Firebase key live | Credential compromise | Rotate in console |
| No hosted backend | Blocks the entire multi-device roadmap | Deploy managed Postgres + API |
| Sync only unit-tested E2E | Correctness regressions ship silently | Run the 50-sale soak test; add sync integration suite |
| 11 commits stranded off `main` | Work not in the trunk | Merge (needs you) |
| Tauri CSP null / wraps legacy | Desktop attack surface | Fix CSP or retire desktop |
| Docs sprawl | Onboarding friction | Archive superseded docs |

---

## 7. Prioritized roadmap

Priority key: **P0** now · **P1** high · **P2** medium · **P3** low.
Complexity: **S** hours · **M** days · **L** 1–2 weeks · **XL** multi-week.

| # | Item | Pri | Cx | Depends on | Notes |
|---|------|-----|----|-----------|-------|
| 1 | Back up release keystore; rotate leaked key | P0 | S | You (console/off-machine) | Irreversible risk first |
| 2 | Merge `feat/universal-import` → `main` | P0 | S | You (permission) | Get 11 commits into trunk |
| 3 | Delete dead `dev.sqlite3` + stray artifacts | P0 | S | — | Repo hygiene |
| 4 | **Deploy hosted backend** (managed Postgres + API + pgbouncer) | P1 | L | 1 | Unblocks everything below |
| 5 | Run the 50-sale offline soak test | P1 | M | 4 | Prove sync in anger |
| 6 | Complete Firebase → JWT auth cutover | P1 | L | 4 | Removes Firebase dependency |
| 7 | Sync integration test-suite (no loss/dup) | P1 | M | 4 | Lock the core guarantee |
| 8 | Suppliers on mobile (local store + import) | P2 | M | — | Close the import gap |
| 9 | Owner activity/audit trail UI | P2 | M | — | `audit` app exists |
| 10 | Dashboard caching + list pagination | P2 | M | 4 | Perf as data grows |
| 11 | Onboarding / first-run flow | P2 | M | — | Adoption |
| 12 | Multi-language (i18n) | P3 | L | — | Market reach |
| 13 | On-device analytics (dead stock, reorder) | P3 | L | 4 | Differentiation |
| 14 | Retire/re-point desktop; fix Tauri CSP | P3 | M | — | Or drop entirely |

**Recommended order:** 1 → 2 → 3 (housekeeping, all quick), then **4 is the pivot** — the hosted
backend gates 5, 6, 7, 10, 13. Do 4 next, then lock correctness (5, 7) before adding surface area
(8, 9, 11), then reach features (12, 13), then desktop cleanup (14).

### Risks & mitigations for the roadmap
- **Auth cutover breaks live sessions (item 6).** Mitigate: dual-accept Firebase + JWT during a
  transition window (the backend already does); migrate device-by-device; keep a rollback build.
- **Hosted deploy exposes new attack surface (item 4).** Mitigate: enforce secrets, TLS,
  rate-limits, and a WAF; the Content-Length fix already removed the chunked-body foot-gun.
- **Sync regressions ship silently.** Mitigate: item 7 as a CI gate; property tests on money/dates.
- **Scope creep on features.** Mitigate: keep the P0/P1 correctness+deploy work ahead of any P3.

---

## 8. Evolving into a premium, enterprise-grade, white-label platform

The foundation is already here: the backend is **row-level multi-tenant** (`Shop` = tenant,
`ShopMembership` = role, `settings_json` = per-tenant flags, plan tiers exist). White-label is an
*extension of what's built*, not a rewrite.

### White-label specifics (the actual "white-label" work)
- **Per-tenant branding:** logo, color palette, app/business name, receipt footer — driven from
  `Shop.settings_json`, themable at runtime on mobile.
- **Build flavors:** Flutter flavors (dev/staging/prod + optional per-brand) replacing the sprawl
  of `--dart-define` flags; a reproducible white-label build pipeline.
- **Tenant provisioning & onboarding:** self-serve shop creation, invite staff, plan selection —
  an admin/console flow (extend `admin_web`).
- **Plan tiers & entitlements:** gate features by plan via the existing `settings_json`/plan
  fields (starter/pro/enterprise); enforce server-side.
- **Billing & subscriptions:** integrate a payment/subscription provider; usage metering per tenant.
- **Custom domains / tenant routing** for the admin surface.

### UI / UX
- A **design-system-driven** themable UI (tokens for color/spacing/type) so a brand swap is a
  config change. Keep the mobile+tablet, India-first patterns already established.
- Accessibility pass (contrast, focus, screen-reader labels), and a polished empty/onboarding state.

### Architecture & scalability
- Managed Postgres for horizontal shard-by-tenant scaling. Note that Citus is
  **not** running: the image was pinned in `docker-compose.prod.yml`, which the
  droplet does not use, and no table was ever distributed. Sharding is a
  deliberate future migration, not a switch already flipped.
- Async everything heavy via Celery; server-computed projections + read caching.
- Event-sourced core makes audit, replay, and analytics natural — lean into it.
- Consider an event/outbox stream (e.g. per-tenant) for integrations and webhooks.

### Security & compliance
- Complete JWT auth; add MFA (fields exist), passkeys (present), and SSO for enterprise tenants.
- Tenant data isolation tests as a permanent CI gate; per-tenant encryption keys for the highest tier.
- Audit trail surfaced to owners; data export + deletion for compliance (DPDP Act / GDPR-style).
- Secrets management, TLS, rate-limiting, WAF; rotate the leaked key now.

### Performance
- Read caching, pagination, index audits (as in §3); cold-start budget on mobile; CDN for admin.
- Load-test per-tenant hot paths before enterprise SLAs.

### Developer experience & maintainability
- Build flavors + one-command local stack (backend + tunnel already scripted this session).
- Expand CI to run backend + mobile tests + a sync integration gate on every PR.
- Archive superseded docs; keep the README the single ground truth.
- Property/golden tests as the standard for money/date/GST/sync (the session's lesson).

### Future-proofing & integrations
- **Public API + webhooks** for third-party integrations (accounting, e-invoicing portals).
- **ERPNext interoperability** (the `erpnext` app is a start) for tenants who outgrow the app.
- **e-Invoicing / IRP** integration as GST mandates expand to smaller businesses.
- **Payment gateway + UPI deep integration** beyond QR (collect, reconcile).
- **Analytics/BI**: demand forecasting, reorder automation, cohort/loyalty analytics.
- **Offline-first as a platform capability** other verticals can reuse — the real differentiator.

---

## 9. The one-paragraph recommendation

Do the three P0 housekeeping items today (keystore backup, key rotation, merge to `main`), then
treat **the hosted backend as the pivot of the entire next phase** — it unblocks multi-device,
the auth cutover, real sync verification, and analytics. Before adding new surface area, lock the
core guarantee with a sync integration suite and the soak test, because this session proved the
failure mode here is *silent wrong data*, not crashes. The white-label platform is a natural
extension of the existing multi-tenant core: brand via `settings_json`, gate via plan tiers,
provision via an extended admin console — no rewrite required.

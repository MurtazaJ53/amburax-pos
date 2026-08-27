# Business Hub — Improvements & New-Feature Suggestions

> **Superseded by `/FUTURE.md` (27 August 2026).** This file is kept for
> its history and is no longer maintained; roughly forty commits of work
> landed after it was last updated.

_2026-07-19. Ideas, prioritized by value vs. effort. These are proposals for discussion, not committed work._

Legend: **Effort** S/M/L · **Impact** ⭐–⭐⭐⭐ · tagged _[quick win]_ where value/effort is best.

---

## 1. Polish on what already exists (highest ROI)

| Idea | Effort | Impact | Note |
|------|--------|--------|------|
| **Batch import writes in one Drift transaction** | S | ⭐⭐ | Hundreds of rows now write one-by-one; wrap in a transaction → seconds not minutes. _[quick win]_ |
| **Import summary + undo** | M | ⭐⭐ | "312 added, 40 updated, 5 skipped (why)" + a rollback of the last import. |
| **Download templates from the card** already exists — add **column-help tooltips** | S | ⭐ | Tell users what each field means. _[quick win]_ |
| **Receipt: show UPI QR on the printed/PDF bill** | S | ⭐⭐ | You already generate the QR on screen; also embed it on the receipt so customers pay from a paper bill. _[quick win]_ |
| **Low-stock → one-tap reorder** | M | ⭐⭐ | From a low-stock item, pre-fill a Purchase to its last supplier at last cost. Ties inventory→purchases together. |
| **Barcode-to-item quick add** | S | ⭐⭐ | Scanning an unknown barcode offers "Add this as a new product". _[quick win]_ |

## 2. Indian-retail market fit (stickiness)

| Idea | Effort | Impact |
|------|--------|--------|
| **WhatsApp catalog / order-taking** | L | ⭐⭐⭐ | Let a shop share its catalog and take orders over WhatsApp — huge in kirana/B2B. |
| **Khata reminders automation** | M | ⭐⭐⭐ | Scheduled WhatsApp "you owe ₹X" nudges for credit customers, with a UPI pay link. Directly drives collections. |
| **UPI payment auto-reconcile** | L | ⭐⭐⭐ | Match incoming UPI (via a payment gateway/webhook or SMS parsing) to open bills so "did you pay?" disappears entirely. |
| **e-Invoice / e-Way bill** (for B2B over threshold) | L | ⭐⭐ | IRN generation via GSP once shops cross the turnover limit. |
| **GST filing assist** | M | ⭐⭐⭐ | You already export GSTR-1/3B CSV; add a monthly "filing pack" (summary + CSVs + HSN report) e-mailed to the shop's CA. Accountants pull shops onto your app. |
| **Multi-language UI** (Hindi, Gujarati, Tamil, …) | M | ⭐⭐⭐ | The app is India-first; localized UI massively widens the market. |
| **Loose-goods scale integration** | M | ⭐⭐ | You parse weight barcodes; add live Bluetooth weighing-scale reading for counters without label printers. |

## 3. Growth & retention features

| Idea | Effort | Impact |
|------|--------|--------|
| **Loyalty / points & coupons** | M | ⭐⭐ | Phone-number based points; redeem at POS. Cheap to build, strong retention. |
| **Customer analytics** | M | ⭐⭐ | Top customers, lapsed customers (haven't bought in 30d), basket size — you already have the ledger data. |
| **Simple CRM campaigns** | M | ⭐⭐ | "Send offer to customers who bought category X" over WhatsApp. |
| **Staff performance** | S | ⭐ | Sales-per-cashier from `actor_user` on sales — already captured. _[quick win]_ |

## 4. Reliability, security & trust

| Idea | Effort | Impact |
|------|--------|--------|
| **Finish the sync soak + conflict UI** | M | ⭐⭐⭐ | The engine exists; add a visible "3 items pending / synced" indicator and a conflict-resolution screen. Trust = adoption. |
| **Audit trail UI** | S | ⭐⭐ | Backend already logs audit events; surface "who voided/discounted/deleted what" for owners. |
| **Encrypted local DB** | M | ⭐⭐ | The Drift SQLite holds customer PII; encrypt it at rest (SQLCipher). |
| **Role-scoped mobile UI** | S | ⭐⭐ | Backend RBAC blocks a cashier from P&L/suppliers; also **hide** those tabs in the app for staff. _[quick win]_ |
| **Session/device management** | M | ⭐ | Owner can see + revoke logged-in devices (backend has access sessions). |

## 5. Monetization / plans (you already have a plan-tier system)

- **Enforce tiers in-app** with upgrade prompts (Starter→Growth→Pro) — the feature flags exist server-side; make the paywall visible and tasteful.
- **Add-on billing** for premium: GST filing pack, WhatsApp automation, multi-branch.
- **Free-trial → conversion** analytics.

## 6. Platform / technical

| Idea | Effort | Impact |
|------|--------|--------|
| **JWT-only auth** (drop server Firebase) | S | ⭐⭐ | Simpler, no secret to manage; recommended. |
| **Replace/wrap the `excel` package** | M | ⭐ | It crashes on many real files (we wrap it); a sturdier reader or CSV-first flow removes a whole bug class. |
| **Background sync worker** (WorkManager) | M | ⭐⭐ | Sync even when the app is closed. |
| **Web/desktop parity** | L | ⭐ | `apps/admin_web` + `apps/desktop` exist but aren't verified — a back-office web dashboard for owners is valuable. |
| **App-size diet** | S | ⭐ | Debug APK is ~195 MB; ship `--split-per-abi` release (~30–50 MB). _[quick win]_ |

---

## 7. My top-5 if you want a shortlist
1. **Khata WhatsApp reminders + UPI pay link** — directly makes shops money (collections). ⭐⭐⭐
2. **GST monthly filing pack for CAs** — accountant-driven distribution. ⭐⭐⭐
3. **Multi-language UI** — unlocks the real India market. ⭐⭐⭐
4. **Sync status + conflict UI** (finish the offline story) — trust. ⭐⭐⭐
5. **Batch import + role-scoped mobile UI** — quick wins that make today's features feel finished. ⭐⭐

---

_Discussion welcome — pick a theme and I'll turn it into a concrete build plan with tests._

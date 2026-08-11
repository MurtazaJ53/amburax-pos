# Business Hub — frontend build specification

Everything needed to build the web front end from scratch, independent of the
current implementation. Written 9 August 2026 against a backend of 86
endpoints.

The design is deliberately not specified. What follows is *what each screen
must do, what data it has, and what it must never do* — the constraints a
design has to satisfy, not the design itself.

---

## 1. Non-negotiable architecture

Four rules. Breaking any of them is a security or correctness bug, not a style
choice, and each has already caused a real incident in this project.

### 1.1 No credential ever reaches browser code

Every call to the backend is made **server-side** by a proxy route that reads
the session token from an **HTTP-only cookie** and attaches it. Browser
JavaScript never holds a token and never talks to the backend directly.

- The backend URL lives in `BUSINESS_HUB_API_BASE_URL`, server-side only.
- **Never prefix it `NEXT_PUBLIC_`.** That inlines it into the bundle served to
  every visitor. A deleted config file once declared exactly that, and a
  deployment using it would have started, passed its health check, and silently
  talked to localhost for every request.

### 1.2 The Content-Security-Policy blocks external origins

`default-src 'self'`. No CDN scripts, no external stylesheets, **no webfont
URLs**. Fonts must be self-hosted or bundled at build time; a `@import` from a
font CDN was silently blocked and the whole site rendered in a fallback face
until someone checked the console.

Charts must be drawn inline (SVG/Canvas) or use a bundled library — not a CDN.

### 1.3 Server components cannot use client hooks

A module marked `"use client"` makes **every one of its exports** client-only.
A server component importing from it compiles cleanly and fails at runtime.
This took every page to a 500 once.

Keep shared values (locale list, translation table, formatters) in a module with
no `"use client"` directive, and provide both a hook (`useT`) and a server
function (`getServerT`) over the same data.

### 1.4 Money is never a float

All money and quantities arrive from the API as **strings** (DRF serialises
`Decimal` that way). Parse for arithmetic, never store as float, and format at
the edge. `0.1 + 0.2` is how a shop's books go wrong.

---

## 2. Audience and priorities

Two very different users share one interface.

| | Counter staff | Owner |
|---|---|---|
| Device | Phone or tablet, one hand, standing | Laptop, sitting |
| Session | Seconds, under pressure, customer waiting | Minutes, considered |
| Priority | Speed, large touch targets, no mis-taps | Density, comparison, export |

The POS screen belongs to the first. Everything else belongs to the second.
A control that overlays the POS product grid is a mis-tap mid-sale with a
customer watching — this is why quick settings live in the header and not on a
floating button.

---

## 3. Screen inventory

40 routes. Grouped by job, with the data each needs.

### 3.1 Public — no session

| Route | Purpose | Notes |
|---|---|---|
| `/login` | Email + password, or staff PIN | Accepts `?reason=expired\|throttled\|upstream\|offline` and must show it |
| `/register` | Create a shop | Name, email, password, mobile, GSTIN (optional) |
| `/invite/[token]` | Accept a team invitation | Preview shows shop + role before accepting |
| `/khata/[token]` | **Customer statement** | The only page a customer sees. No sign-in, no nav, `noindex`. Must NOT redirect to login |

### 3.2 Selling

| Route | Purpose | Key states |
|---|---|---|
| `/pos` | Ring up a sale | Empty cart · searching · payment · receipt |
| `/sales` | Bill history | List · detail · void · **return** |
| `/day-book` | Roj Mel — Jama and Udhaar | Per date, with a copyable summary |

**POS is the most demanding screen.** It needs: product search matching name,
SKU **and barcode**; a scan path (USB scanner types into the search field —
never steal focus from it); a cart with per-line quantity and discount;
payment split across cash/UPI/card/bank/credit; and a receipt with print and
share.

### 3.3 Stock

| Route | Purpose |
|---|---|
| `/inventory` | Catalogue: name, SKU, barcode, category, size, price, HSN, GST rate, unit, reorder level, photo |
| `/labels` | Barcode price labels — pick items, counts, sheet format, print |
| `/transfers` | Move stock between the owner's shops |
| `/purchase-orders` | Raise orders, email suppliers, book in deliveries |
| `/purchases` | Recorded purchases |
| `/suppliers` | Supplier directory and payables |
| `/data-health` | Duplicate and missing-data scan, with merge |

### 3.4 Customers and credit

| Route | Purpose |
|---|---|
| `/customers` | Directory, balances, per-customer ledger |
| *(within customers)* | Khata collection: debtor list, reminders, bulk collection round |

### 3.5 Money and reporting

| Route | Purpose |
|---|---|
| `/insights` | Business pulse: best sellers, cash flow, dead stock, reorder |
| `/reports` | Profit & loss, GST summary |
| `/tally` | GSTR-1, GSTR-3B, Tally voucher export |
| `/expenses` | Non-stock outgoings |
| `/payments` | Payments taken against sales |
| `/billing` | Plan, invoices, checkout |

### 3.6 People and administration

| Route | Purpose |
|---|---|
| `/team` | Members, roles, invitations |
| `/attendance` | Staff clock in/out |
| `/security` | MFA enrolment, passkeys |
| `/sessions` | Signed-in devices, revoke, remote wipe |
| `/audit` | Who did what |
| `/settings` | Shop details, GSTIN, UPI VPA, loyalty |
| `/import` | Spreadsheet import (CSV and XLSX) |
| `/notifications` | Alert history |

### 3.7 Operator-only — not for shopkeepers

`/platform`, `/platform/shops`, `/platform/shops/[id]`, `/platform/metrics`,
`/platform/audit`, `/migration`, `/erpnext`.

Visible only when `session.user.is_platform_admin`. **Do not translate these** —
they are used by whoever runs the service.

---

## 4. Every screen must handle five states

Most bugs found in this project were a missing state, not a wrong calculation.

1. **Loading** — first paint, no data yet
2. **Empty** — succeeded, nothing to show. Must say *what to do next*, not just "no data"
3. **Error** — failed. Say what went wrong and how to fix it. Never a bare code
4. **Partial** — some data, some missing (e.g. cost price absent). See §6
5. **Forbidden** — role or plan does not allow it. Explain which, don't just hide

---

## 5. Roles and permissions

Eleven roles in five ranks. The interface must reflect them; the backend
enforces them regardless.

| Rank | Roles |
|---|---|
| 40 | `owner` |
| 30 | `admin`, `manager` |
| 28 | `supervisor` |
| 25 | `accountant`, `hr` |
| 20 | `cashier`, `sales_staff`, `inventory_staff`, `staff` |
| 10 | `viewer` |

**Rule: hide an action a role cannot perform rather than showing it disabled or
letting it fail.** A button that can only produce a 403 is worse than no button.

Minimum ranks that matter:

| Action | Minimum |
|---|---|
| View reports, POS, customers | staff (20) |
| Process a return | staff (20) |
| Dead stock, cost prices | manager (30) |
| Stock transfers, purchase orders | manager (30) |
| Data export | owner (40) |
| Ownership transfer | owner (40) |

## 5.1 Plan gates

Eight feature flags arrive on `session.memberships[].shop.enabled_features`.

| Flag | Tier |
|---|---|
| `expenses`, `attendance`, `supplier_directory` | Growth and Pro |
| `purchase_workflow`, `advanced_reports`, `multi_branch`, `finance_summary`, `advanced_ops` | Pro only |

A gated feature should show what it is and how to get it — not vanish.

---

## 6. Business rules that shape the interface

These are not implementation details. Contradicting them makes the product
wrong.

### 6.1 Unknown is a valid answer

Where an item has no recorded cost, **profit and stock valuation cannot be
computed**. The interface must show "unknown", never a number that silently
excludes those lines. A confidently wrong profit figure is more dangerous than
a gap, because the owner makes buying decisions on it.

The API signals this: `estimated_total: null`, `valued_at: "cost" | "sale_price"`.
Render the distinction.

### 6.2 Stock is derived, and traceable

There is no quantity column. Every quantity is the sum of an append-only
ledger. Anywhere a stock number appears, **the events behind it should be
reachable**. Corrections are new entries, never edits.

### 6.3 Money received ≠ value sold

The day book keeps Jama (received) and Udhaar (given on credit) side by side
deliberately. Never total them into one revenue figure — a day of strong sales
and weak collection is exactly what an owner needs to notice.

### 6.4 Silence is a feature

Alerts fire only when there is something to say. A healthy shop gets no morning
stock alert and a day with no trade gets no evening summary. Do not add "all
good" confirmations.

### 6.5 Offline is not an error state

The counter app bills with no network. The web app currently assumes
connectivity, but must never present a queued or syncing state as a failure.

### 6.6 Some words stay in English

GST, GSTIN, SKU, UPI, POS, PIN, CSV. Indian shopkeepers use these in English;
translating them produces something nobody says.

---

## 7. API contract

65 proxy routes, all `/api/...`, all server-side. Shape:

- **Success** — the backend payload verbatim
- **Failure** — `{ "error": "<sentence>" }` with the upstream status
- Money and quantities are **strings**
- Ids are UUID strings

The proxy must forward the backend's own message. "only 3 in stock, cannot send
5" is worth showing; "Backend returned 400" is not.

### 7.1 Session

`GET /api/auth/session` → `{ user, memberships[], active_shop_id }`

Each membership carries `role`, `role_label`, `permissions_json`, and
`shop { id, name, currency_code, timezone, plan_tier, enabled_features,
gstin, upi_vpa }`.

**Everything the interface needs to decide what to show is in this payload.**
Fetch it once server-side per page; do not re-fetch per component.

### 7.2 Route groups

| Group | Routes |
|---|---|
| Auth | `login`, `logout`, `register`, `join`, `pin`, `session` |
| Selling | `sales`, `sales/[id]/void`, returns *(backend ready, no UI yet)* |
| Stock | `inventory`, `inventory/[id]`, `inventory/[id]/adjust-stock`, `transfers`, `transfers/[id]/receive|cancel` |
| Buying | `purchase-orders`, `.../receive`, `.../send`, `purchases`, `suppliers` |
| Customers | `customers`, `customers/[id]/ledger`, `khata/debtors`, `khata/remind/[id]`, `customers/[id]/statement-link`, `customers/statement-links/bulk`, `loyalty` |
| Reports | `reports/{best-sellers,cash-flow,dead-stock,reorder-list,data-health,day-book,profit-loss,gst-summary,gstr1,tally-export,staff-performance}` |
| Admin | `team`, `invites`, `settings`, `attendance`, `expenses`, `notifications`, `security/passkeys/*`, `billing/*`, `export`, `import` |

---

## 8. Design tokens

The current palette is derived from the Android app so the two surfaces match.
A redesign may replace the values; **it must keep the token names**, because
every component references them.

**Structure:** `--bg-app`, `--bg-base`, `--bg-soft`, `--surface`,
`--surface-strong`, `--surface-muted`, `--border-soft`, `--border`,
`--border-strong`

**Text:** `--text-primary`, `--text-secondary`, `--text-tertiary`,
`--text-disabled`

**Brand:** `--primary`, `--primary-hover`, `--primary-light`, `--primary-dark`,
`--accent`, `--accent-hover`, `--accent-light`

**Semantic:** `--success`, `--warning`, `--error`, `--info`, each with
`-light`, `-dark` and `-strong` variants. `-strong` is the text-on-tint colour
and must meet contrast on a 10% tint of its own hue.

**Domain:** `--revenue`, `--expense`, `--inventory`, `--customer`

### 8.1 Theme

Light, dark and follow-system. The resolved theme is applied by an inline
script **before hydration**, so there is no flash of the wrong theme. Any
redesign must keep that, and must set `suppressHydrationWarning` on `<html>`
because the server's value legitimately differs from the client's.

### 8.2 Typography

Fonts must be bundled — the CSP blocks font CDNs. Indian scripts
(Devanagari, Gujarati) must render correctly; verify with real product names,
not Lorem.

---

## 9. Internationalisation

Three languages: English, Hindi, Gujarati. Locale is stored in the `bh_locale`
cookie and read **server-side** so the first paint is already correct.

- One dictionary, one flat key space
- The mobile app's reviewed translations take precedence on a key collision
- Language switching must not require a reload
- **Test with Gujarati product names**; they are longer than English and break
  fixed-width layouts

---

## 10. What is missing today

An honest list, so a rebuild does not reproduce the gaps.

| Gap | Notes |
|---|---|
| **Returns UI** | Backend complete (18 tests). Needs: pick a bill, choose lines and quantities, choose refund method (cash/UPI/card/bank/khata/exchange) |
| **Stocktake** | Not built either side |
| Camera scanning | Web only, `BarcodeDetector`, hidden where unsupported |
| Offline support | None on the web |
| `set-state-in-effect` | 25 warnings: client fetching in effects. A rebuild should fetch server-side and pass data down |

---

## 11. Acceptance checklist

A rebuilt front end is finished when all of these hold.

- [ ] No API token in any browser bundle — grep the build output
- [ ] No external origin in any network request
- [ ] Every page returns 307 to `/login` signed out, never 500
- [ ] `/khata/[token]` renders **without** a session and does not redirect
- [ ] Every screen handles all five states of §4
- [ ] Actions a role cannot perform are hidden, not disabled
- [ ] Profit shows "unknown" where cost is missing
- [ ] Gujarati product names render and do not break layout
- [ ] Theme resolves before first paint, no flash
- [ ] Money never passes through a float
- [ ] `pnpm smoke <url>` passes: every route, no 5xx

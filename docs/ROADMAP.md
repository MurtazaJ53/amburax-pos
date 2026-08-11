# Remaining work and future scope

Last reviewed 9 August 2026.

Written to be honest rather than encouraging. Anything marked **not started**
has no implementation behind it, and the estimates are the ones I would defend,
not the ones that sound good.

---

## Where the project actually stands

| | |
|---|---|
| Backend tests | 670 passing |
| Counter app tests | 327 passing, `flutter analyze` clean |
| Admin web tests | 98 passing, 70 routes smoke-checked, `tsc` clean |
| Outstanding lint | 0 errors, 25 warnings (`set-state-in-effect`, audited — see eslint.config.mjs) |
| Surfaces | Android counter app + admin web, both shipping. An iOS target builds in CI but has never run on a device. See [platform-targets.md](platform-targets.md) |
| Live to users | **No.** Reachable only through an SSH tunnel |
| Deployed | Yes — the droplet now runs current code and all migrations |

The product is feature-complete for a first shop. It is not launched, and the
gap between those two states is almost entirely operational.

---

## 1. Blocking launch

Nothing here is engineering. All of it is the owner's to do, and until it is
done nobody outside the tunnel can use the product.

### Buy a domain — the single biggest blocker

The admin site binds to `127.0.0.1:3001` on the droplet. Without a hostname
there is no HTTPS, no certificate, and no way for a shopkeeper to reach it.
Everything else on this page is polish by comparison.

Once a domain exists, roughly twenty minutes of work: two A records → certbot →
an nginx server block proxying to `127.0.0.1:3001` → replace
`DJANGO_ALLOWED_HOSTS=*` with the real hostnames → add the origin to
`DJANGO_CSRF_TRUSTED_ORIGINS` → restart the API → `pnpm smoke https://domain`.

The backend currently answers on `api.indianwasteportal.com`, a hostname
belonging to an unrelated project. It works, but it is visible in the address
bar during payment flows and should move to a Business Hub domain at the same
time.

### ~~Deploy what is already built~~ — done 9 August 2026

The droplet was repointed from the frozen `BUSINESS-HUB` archive to the
current repository, rebuilt, and all pending migrations applied. Verified by
running the alerts command against it, which reported three shops checked.

One task remains here: add the hourly cron entry for scheduled alerts. See
`apps/admin_web/DEPLOY.md`.

### Set RESEND_API_KEY

Not set on the droplet, so nothing the product sends actually leaves it.
Scheduled alerts appear in-app only, khata reminders cannot email, and
purchase orders cannot reach a supplier. One environment variable unblocks all
three, and it is the highest-value configuration change outstanding.

### Rotate the exposed credentials

Two passwords were exposed during development — one in a screenshot, one pasted
into a chat window — and `POSTGRES_PASSWORD` is sitting in the droplet's
`/root/.bash_history`.

The Android signing keystore that leaked into git history is **not** among
these: it is an old one, superseded by a key that was never committed. The
Firebase service-account key never leaked at all, despite an earlier note in
this project claiming otherwise.

### Before any Play Store release

Back up `business-hub-release.jks` somewhere off the development machine. Lose
it after publishing and no update to that app can ever be shipped — Google
cannot recover it.

---

## 2. Engineering worth doing next

Ordered by value per day of work. Shipped since the last review and removed
from this list: the reorder list now subtracts stock both on order and in
transit; the day book (Roj Mel) and the 09:00/21:00 scheduled alerts cover the
daily closing summary; purchase orders can be emailed to suppliers; the shop's
data exports as spreadsheets as well as JSON.

### Import reconciliation should say which rows failed

A partially failed spreadsheet import reports a count, not which rows were
rejected or why. For a shop importing two thousand products from a legacy
system, a count is close to useless.
**1–2 days.**

### Stocktake mode

A guided physical count: scan the shelves, see counted against expected, post
one reconciled set of adjustments with a variance report. Today a stocktake
means correcting items one at a time, which nobody will do for a whole shop.
**3–5 days.**

### Returns and exchanges

The ledger already has a `return` event type, but there is no flow for taking
goods back against an original bill — particularly an exchange for a different
size, which is routine in garment retail.
**3–5 days.**

### Supplier price history

Purchase orders capture quoted versus billed rates. Tracking that over time
shows which supplier is quietly raising prices — information a shop currently
has no way to see.
**2–3 days.**

---

## 3. Future scope

Real possibilities, none started, none committed to.

### WhatsApp Business API

Reminders currently open WhatsApp with a prepared message the owner must press
send on. Bulk collection is therefore a guided walk, not an automated send. A
Business API integration would deliver templated reminders and receipts
directly, with delivery receipts.

Blocked on business decisions, not code: a Meta business account, template
approval, and a per-message cost.

### UPI payment reconciliation

A UPI payment is currently recorded because the cashier says it happened.
Matching against a gateway's settlement feed would confirm the money arrived
and flag the ones that did not.

### Offline-capable web app

The website assumes connectivity. A service worker plus local persistence would
let a laptop at the counter behave like the phone. Substantial work, and only
worth it if shops actually run the web POS during trading — which no evidence
currently suggests.

### Demand forecasting

Enough sales history will eventually exist to suggest reorder quantities from
real velocity and seasonality rather than a fixed level. Only honest after a
shop has a year of clean data, and it must show its reasoning: no shopkeeper
will spend money on a number they cannot interrogate.

### Customer-facing ordering

The khata statement page proves customers will open a link from their shop. The
same pattern could carry an order-ahead page for regulars — a kirana's monthly
list, placed from home.

### Windows desktop client

Verified feasible and costed at 1–2 weeks, but not planned. Reasoning in
[platform-targets.md](platform-targets.md).

### iOS — scaffolded, unproven

Added 8 August 2026. The target builds in CI on a macOS runner; nobody has
ever run it on a phone, and it is unsigned. Before it can reach a device:
an Apple Developer account (99 USD/year), a certificate and profile, a Mac or
cloud Mac for testing, and App Store review. Bluetooth receipt printing does
not work there at all and would need a BLE printer and a different package
(2–3 days). Details in [platform-targets.md](platform-targets.md).

---

## 4. Deliberately not doing

Recorded so these are not repeatedly re-proposed.

| | Why |
|---|---|
| **GST e-invoicing (IRN)** | Mandatory only above ₹5 crore turnover, far above the target shop, and it needs a paid GSP account. Worth building when a customer crosses the threshold, not before |
| **macOS / Linux clients** | No demand |
| **Translating operator tooling** | The migration and reconciliation screens are used by whoever runs the service, not by shopkeepers |
| **Silencing the `set-state-in-effect` warnings** | Audited all 24: two are the canonical SSR-safe detect-then-setState, the rest are client fetching whose real fix is server-side data loading — an architectural change across ~20 components, not a lint pass. Downgraded to warnings with the reasoning recorded in eslint.config.mjs |

---

## 5. Known limitations

Not bugs — boundaries of what the product currently claims.

- **Evaluated in one shop.** One garment retailer supplied the requirements, the
  data and the testing. Enough to show it works somewhere real; not enough to
  claim it generalises. A kirana selling by weight, or a pharmacy with batch and
  expiry rules, would exercise the design differently.
- **Cost price is optional**, and several reports depend on it. Where a shop has
  not recorded costs, profit and stock valuation cannot be computed. The system
  says so rather than estimating — but the quality of financial reporting is
  bounded by data discipline the software cannot enforce.
- **Security is designed, not audited.** Encryption, blind-index lookup, role
  enforcement at one choke-point, MFA and passkeys are implemented and tested.
  No external penetration test has been carried out.
- **Migration and ERPNext tooling is lightly exercised.** Both exist and are
  wired; neither has the coverage or real-world mileage of the daily features.

# Business Hub — Roadmap & Remaining Work

> **Superseded by `/REMAINING.md` (27 August 2026).** This file is kept for
> its history and is no longer maintained; roughly forty commits of work
> landed after it was last updated.

_Last updated 2026-07-19. Companion to `01_ARCHITECTURE_AND_CAPABILITIES.md`._

Everything currently **built and tested** is in the capabilities doc. This file is the honest "what's left" — grouped by who has to do it and how big it is.

---

## A. Needs YOU (console / device / admin — I can't do these headless)

| # | Item | Why it's yours | Effort |
|---|------|----------------|--------|
| A1 | **Rotate the Firebase key** & place it (repo-root `service-account.json`, or `FIREBASE_SERVICE_ACCOUNT_PATH`, or mounted secret in prod) | Needs your GCP/Firebase console | 10 min |
| A2 | **Add 4 GitHub secrets** (`ANDROID_KEYSTORE_BASE64`, `…_PASSWORD`, `…_KEY_ALIAS`, `…_KEY_PASSWORD`) so CI publishes a **signed** APK | Repo admin | 5 min |
| A3 | **Sync soak test on device**: offline → record ~50 fractional sales → reconnect → verify all land with correct stock/totals | Needs a paired device + toggling airplane mode | 30 min |
| A4 | **On-device import run**: Settings → Import → pick the pushed `products_large.csv` etc. → confirm mapping → import; verify counts in Stock/Clients/History | Needs the PIN + tapping the file picker (I stopped to respect a private call) | 15 min |
| A5 | **Back up the signing keystore** (`business-hub-release.jks` + password) offline | If lost, you can never update the app on Play | 5 min |
| A6 | **Merge open branches**: `feat/universal-import` PR → main (auto-builds APK) | Your review | 5 min |

---

## B. Deferred features (have a clear reason, not just "not done")

| # | Item | Blocker / reason | To unblock |
|---|------|------------------|-----------|
| B1 | **Suppliers import (mobile)** | Mobile has no supplier entity/UI — suppliers are only names on purchases | Add a `Suppliers` Drift table + supplier screen, then wire the (already-built) engine schema |
| B2 | **Sales import with line items** | Universal sales import is flat (one row per bill); relational receipt+items still needs the structured Zobaze format | A two-file or grouped-rows importer |
| B3 | **Biometric prompt hardware confirm** | Code is wired (local_auth, correct API, analyze-clean) but the fingerprint flow can only be confirmed on a device | Test on device (A3/A4 session) |
| B4 | **Phone-OTP login** | Dropped if you go JWT-only; kept only if you want Firebase phone auth for merchants | Decide auth strategy (see C1) |

---

## C. Open decisions (yours to make — they change what we build)

- **C1 — Auth strategy.** Recommended: **JWT-only**, drop server-side Firebase (no secret to manage, no Google round-trip, already tested). Keep Firebase *only* if you want phone-OTP login.
- **C2 — Import priority.** Which next: supplier management + import, or sales-with-line-items, or contacts polish?
- **C3 — Distribution.** Debug APK for testing vs signed release for pilot vs Play Store internal track. (CI can do any once A2 is done.)
- **C4 — Multi-branch / franchise.** The plan tier has a `multi_branch` flag but no branch-switching UX yet — is this on the near roadmap?

---

## D. Engineering hygiene / hardening (nice, not blocking)

1. **Guard the aggregation default** — a tiny `sum_qty()` helper so a future `Sum(quantity…)` can't reintroduce the Decimal/int crash class.
2. **ERPNext stock reconcile** still `int()`-truncates fractional stock (`erpnext/services.py:786`); revisit once by-weight is fully adopted.
3. **Backend dependency pins** — a few requirements (`django-cryptography`, `channels`, `django-ratelimit`) are unpinned; pin them for reproducible CI.
4. **Excel import robustness** — we wrap the fragile `excel` package; consider replacing it or preferring CSV for large imports.
5. **Import performance** — the large-CSV path writes row-by-row via merge; batch the Drift writes in a transaction for hundreds/thousands of rows.
6. **Rate limiting / abuse** — `django-ratelimit` is a dependency; confirm it's applied to auth + command endpoints.
7. **Observability** — OpenTelemetry is wired; make sure traces/metrics export in prod (`docker-compose.prod.yml`).
8. **Backups** — Postgres backup/restore runbook for the pilot.

---

## E. Suggested delivery order (my recommendation)
1. **A2 + A6** — get CI publishing a signed APK from `main` (you're then always one click from a testable build).
2. **A4 + A3** — on-device import + sync soak (proves the two riskiest real-world flows).
3. **C1** — lock the auth decision; if JWT-only, wire the mobile login screen to `/session/token/`.
4. **B1** — suppliers management + import (rounds out procurement).
5. **D2–D5** — hardening.

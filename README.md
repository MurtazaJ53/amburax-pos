# Business Hub

Business Hub is an India-first business-management / POS platform (mobile + tablet).
It is mid-migration from a legacy React-web + Firebase stack to a **Flutter mobile app**
talking to a **Django + PostgreSQL backend**.

This README is the single source-of-truth map of the repo: what is actually here, what is
active vs. legacy, how to run the current parts, and their verified status. The large
`docs/` folder (80+ files) is mostly product/planning and migration-phase material — treat
this file as the ground truth for "what runs today."

> Status snapshot verified on **2026-07-07** (see [Verification status](#verification-status)).

> [!WARNING]
> **Secret Exposure in Git History**
> This repository previously contained hardcoded secrets (e.g., Firebase API keys in `legacy/android/app/google-services.json` and other config files). Although these have been removed and replaced with environment variables, the original values remain in the git history. You **must** immediately rotate these secrets (specifically Firebase and any service account keys) in your cloud provider consoles to ensure security.

---

## Repo map

| Path | Stack | Role | Status |
|------|-------|------|--------|
| [apps/mobile_flutter/](apps/mobile_flutter/) | Flutter / Dart, Riverpod, Drift (SQLite), go_router | **Active** — the counter app; bills with no signal | ✅ analyzes clean, 320 tests pass |
| [apps/backend/](apps/backend/) | Django 6, DRF, PostgreSQL, Celery | **Active** — authoritative for money, stock and permissions | ✅ 617 tests pass |
| [apps/admin_web/](apps/admin_web/) | Next.js 16 (App Router) | **Active** — the owner's back-office | ✅ 98 tests, 68 routes smoke-checked |

Two surfaces, deliberately — see [docs/platform-targets.md](docs/platform-targets.md)
for why there is no desktop or iOS client, and what a Windows build would cost
if one is ever wanted. The legacy React/Capacitor app, its Firebase Cloud
Functions and a Tauri desktop shell have all been removed.

The two **active** surfaces (Flutter mobile + Django backend) are the focus of this document.

---

## Architecture (current, active path)

```
┌─────────────────────────────┐         HTTPS / JSON            ┌──────────────────────────────┐
│   Flutter mobile (POS)      │   Bearer (Firebase) token or    │   Django backend (DRF)       │
│                             │   X-Dev-User-Email in debug     │                              │
│  • Riverpod state           │ ──────────────────────────────► │  /api/v1/...                 │
│  • Drift/SQLite local DB    │                                 │  15 platform_apps            │
│    (offline-first cache)    │ ◄────────────────────────────── │  command endpoints +         │
│  • Sync coordinator         │        JSON responses           │  migration control plane     │
│  • Thermal receipt printer  │                                 │                              │
└─────────────────────────────┘                                 └──────────────┬───────────────┘
                                                                                │
                                                            PostgreSQL (source of truth) / dev.sqlite3
                                                            Redis + Celery (async, pulse, ERPNext sync)
```

### Flutter mobile — [apps/mobile_flutter/lib/](apps/mobile_flutter/lib/)
- **Offline-first**: writes go to local Drift/SQLite first ([core/database/](apps/mobile_flutter/lib/core/database/)), then sync to the backend via [core/sync/mobile_sync_coordinator.dart](apps/mobile_flutter/lib/core/sync/mobile_sync_coordinator.dart).
- **Backend client**: [core/backend/backend_api_client.dart](apps/mobile_flutter/lib/core/backend/backend_api_client.dart) — base URL from `--dart-define BUSINESS_HUB_API_BASE_URL` (default `http://192.168.1.10:8000/api/v1`).
- **Feature slices** under [lib/features/](apps/mobile_flutter/lib/features/): auth, dashboard, POS (with scanner + split payment), inventory, customers, history, settings. Note several screens have a `_v3` variant — the redesigned versions (see the mobile-redesign memory).
- **Sales/payments** post as idempotent *commands* to `/sales/commands/` and `/payments/commands/`.

### Django backend — [apps/backend/](apps/backend/)
- 15 apps under [platform_apps/](apps/backend/platform_apps/): `common, health, users, shops, inventory, customers, sales, payments, expenses, attendance, projections, jobs, audit, erpnext` (+ `erpnext` execution layer).
- API mounted at `/api/v1/` (see [config/api_urls.py](apps/backend/config/api_urls.py)); full endpoint list in [apps/backend/README.md](apps/backend/README.md).
- **Auth**: Firebase bearer token → `X-Dev-User-Email` dev-header fallback (DEBUG only) → session/basic.
- **DB**: uses `DATABASE_URL` if set, else falls back to `dev.sqlite3`. Postgres is the intended production source of truth.
- **Migration control plane**: command endpoints enforce per-domain ownership — a domain must be promoted to `postgres_primary` before Django accepts writes, else `409`. This is the Firebase→Postgres cutover machinery.

---

## Running the active stack locally

### Backend (Django)
A virtualenv already exists at `apps/backend/.venv` (Django 6.0.4). From [apps/backend/](apps/backend/):

```bash
# Windows venv python: .venv/Scripts/python.exe   (POSIX: .venv/bin/python)
.venv/Scripts/python.exe manage.py migrate
.venv/Scripts/python.exe manage.py runserver 0.0.0.0:8000
```

Runs on SQLite (`dev.sqlite3`) out of the box. For Postgres + Redis, use
[apps/backend/docker-compose.yml](apps/backend/docker-compose.yml) and set `DATABASE_URL` / `REDIS_URL` in `.env`.

### Mobile (Flutter)
Flutter SDK is vendored at `.tools/flutter/`. From [apps/mobile_flutter/](apps/mobile_flutter/):

```bash
# add .tools/flutter/bin to PATH, then:
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # regenerate Drift *.g.dart
flutter analyze
flutter run --dart-define BUSINESS_HUB_API_BASE_URL=http://<your-lan-ip>:8000/api/v1
```

Point `BUSINESS_HUB_API_BASE_URL` at your machine's LAN IP (not `localhost`) so a physical
device/emulator can reach the Django server. A repo-root validation runner exists at
[scripts/mobile_flutter_validate.ps1](scripts/mobile_flutter_validate.ps1).

---

## Verification status

Last verified **2026-07-07** on this working tree (after the fixes below):

| Check | Result |
|-------|--------|
| `flutter pub get` | ✅ resolved |
| `flutter analyze` | ✅ no issues found |
| `manage.py check` | ✅ no issues |
| `manage.py makemigrations --check` | ✅ no changes detected (drift resolved) |
| `pytest` | ✅ **178 passed** |

### Resolved 2026-07-07
1. **Sales command POS regression** — the `/sales/commands/` endpoint had been switched to async Celery processing (returned `202` with no `sale` body), which broke the Flutter POS contract (it reads `sale.id` synchronously) and silently created nothing when no worker was running. Restored to **synchronous** processing returning `201` with the created sale, matching `/payments/commands/`. See [sales/views.py](apps/backend/platform_apps/sales/views.py).
2. **Missing migration** — generated [customers/migrations/0002_alter_customer_email_alter_customer_phone.py](apps/backend/platform_apps/customers/migrations/0002_alter_customer_email_alter_customer_phone.py) for the email/phone model change; no drift remains.
3. **Flutter unused import** — removed from `receipt_printer.dart`.
4. **Brand theme** — Flutter primary palette moved from indigo (`#6366F1`) to the legacy app's **sky-blue `#0EA5E9`** in [app_theme.dart](apps/mobile_flutter/lib/core/theme/app_theme.dart).

### Repo hygiene (not blocking, but this is the "mess")
- **Secrets in the tree**: `service-account.json` at the repo root (a leaked key is already flagged in project memory — rotate + remove from history), plus `.env`, `business-hub.jks`, `test.jks`.
- **Large committed binaries**: several `*.apk` (75–80 MB each), `android (2).zip` (~200 MB), `apps.zip`, `functions.zip`, `src.zip` — these bloat the repo and should move to release storage / be gitignored.
- **Doc sprawl**: `docs/` has 80+ files, ~30 of them near-duplicate "mobile pilot / release runner" variants. Consider archiving planning docs and keeping a short active set.
- **Stray logs** at root: `dev.log`, `preview.log`, `firestore-debug.log`, `tmp-*.log`, etc.

---

## Where to look next
- Backend API reference & migration-phase details: [apps/backend/README.md](apps/backend/README.md)
- Mobile app track notes: [apps/mobile_flutter/README.md](apps/mobile_flutter/README.md)
- Product / architecture / migration deep-dives: [docs/README.md](docs/README.md) (aspirational + planning; verify against code before relying on it)

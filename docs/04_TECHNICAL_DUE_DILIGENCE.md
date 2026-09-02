# Business Hub — Technical Due-Diligence Pack

_2026-07-20. Answers the five diligence asks with the **actual** stack and code._

> **Stack correction (important):** this project is **not** Node.js / React / Prisma / Sequelize.
> The active stack is **Django 6 + DRF (Python)** on the backend and **Flutter + Drift/SQLite**
> on mobile. There **is** a secondary **Tauri 2** desktop shell, but it wraps the **legacy**
> React/Vite web app (being deprecated). Firebase is **legacy auth**, mid-migration to a
> self-contained **JWT** flow. Everything below reflects reality, not the assumed stack.

---

## 1. System Architecture Overview

### Tech stack (active)
| Layer | Technology |
|-------|-----------|
| **Mobile (primary client)** | Flutter (Dart), Riverpod (state), **Drift/SQLite** (offline DB), go_router, mobile_scanner, esc_pos/blue_thermal_printer, pdf/printing, local_auth, flutter_contacts |
| **Backend (source of truth)** | **Django 6, Django REST Framework**, PostgreSQL 16 (plain; the Citus image was dropped on 2 September 2026, unused), **Celery + Redis** (async), **Channels** (realtime), OpenTelemetry |
| **Data access** | Django ORM (no Prisma/Sequelize). Migrations per app under `platform_apps/*/migrations/` |
| **Desktop (secondary)** | **Tauri 2** (`apps/desktop`) wrapping the legacy Vite `dist/` build |
| **Admin web (secondary)** | Next.js (`apps/admin_web`) |
| **Legacy (archived)** | React + Vite + Capacitor + Firebase Functions, under `legacy/` |

### Hosting / deployment
- Containerized via **`docker-compose.prod.yml`** (repo root): services = `api` (gunicorn), `celery_default`, `celery_erpnext`, `celery_beat`, `db` (Postgres 16), `redis`, **`pgbouncer`** (transaction-pooled DB connections). The `api` image is built from `apps/backend/Dockerfile` (python:3.13-slim, non-root user).
- DB URL, Redis URL, secrets injected via env (see §3). Not committed.

### Data flow (offline-first)
```
┌─────────────── Flutter mobile (offline-first) ───────────────┐
│  UI (Riverpod)                                                │
│    └─ writes → Drift/SQLite (local, instant)                  │
│         └─ enqueue idempotent command → commerce_outbox       │
│                                                               │
│  MobileSyncCoordinator                                        │
│    ├─ flushCommerceOutbox()  ──HTTPS Bearer──►  /sales/commands/   (push)
│    └─ pullFromCloud() (upsert merge) ◄──────── /…/inventory,customers,… (pull)
└───────────────────────────────────────────────────────────────┘
                         │  Authorization: Bearer <JWT | Firebase ID token>
                         ▼
┌─────────────────── Django + DRF (/api/v1) ───────────────────┐
│  Auth chain → tenant isolation guard → domain view            │
│    → computes GST / ledgers / balances → PostgreSQL (pgbouncer)│
│  Celery/Redis: pulse, projections, ERPNext sync (async)       │
└───────────────────────────────────────────────────────────────┘
```
Reads (dashboard/summaries) are **server-computed projections**; the app keeps local projections for offline. Stock is **event-sourced** (a ledger of `quantity_delta`), so quantity is always `Σ deltas` — auditable and fractional-safe.

---

## 2. Database Schema Definition

**There is no SQL dump / Prisma / Sequelize.** The schema is the **Django ORM models** (each `class Model` = a table; `ForeignKey` = FK; `Meta.indexes` = indexes). Canonical files: `apps/backend/platform_apps/*/models.py`; migrations under each app's `migrations/`.

### Multi-tenancy model (read this first)
It is **row-level multi-tenancy in one shared schema** (not schema-per-tenant). The **tenant = `Shop`**; a user joins a shop via **`ShopMembership`** (with a role). **Every domain table carries a `shop` FK**, and every shop-scoped API query is filtered by the caller's membership (see §3). There is deliberately **no cross-shop query path** in the views.

```python
# platform_apps/common/models.py  — base mixins on almost every table
class UUIDStampedModel(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    class Meta: abstract = True

class SourceTrackedModel(UUIDStampedModel):     # migration/idempotency provenance
    source_system = models.CharField(max_length=32, blank=True)
    source_id = models.CharField(max_length=128, blank=True)
    source_shop_id = models.CharField(max_length=128, blank=True)
    domain_epoch = models.PositiveIntegerField(default=1)
    class Meta: abstract = True
```

### Core tables (fields trimmed to the important ones)
```python
# users/models.py — PlatformUser (AUTH_USER_MODEL), email login
class PlatformUser(SourceTrackedModel, AbstractUser):
    username = None
    email = models.EmailField(unique=True)              # UNIQUE index
    firebase_uid = models.CharField(max_length=128, null=True, unique=True)
    is_platform_admin = models.BooleanField(default=False)
    # + MFA TOTP + passkey fields

# shops/models.py — TENANT
class Shop(SourceTrackedModel):
    owner_user = models.ForeignKey(AUTH_USER_MODEL, on_delete=SET_NULL, null=True)
    name = models.CharField(max_length=255)
    slug = models.SlugField(unique=True)                # UNIQUE
    gstin = models.CharField(max_length=15, blank=True) # GST reg
    state_code = models.CharField(max_length=2, blank=True)
    settings_json = models.JSONField(default=dict)      # plan tier + feature flags

class ShopMembership(SourceTrackedModel):               # user ↔ shop, RBAC edge
    user = models.ForeignKey(AUTH_USER_MODEL, on_delete=CASCADE, related_name="memberships")
    shop = models.ForeignKey(Shop, on_delete=CASCADE, related_name="memberships")
    role = models.CharField(choices=[owner/admin/staff/viewer])
    status = models.CharField(choices=[active/invited/disabled])

# inventory/models.py
class InventoryItem(SourceTrackedModel):
    shop = models.ForeignKey(Shop, on_delete=CASCADE, related_name="inventory_items")
    name, sku, barcode, category, size = ...
    sell_price = DecimalField(12,2); gst_rate = DecimalField(5,2); hsn_code = ...
    class Meta:
        indexes = [Index(["shop","name"]), Index(["shop","sku"]), Index(["shop","category"])]

class InventoryItemPrivate(SourceTrackedModel):         # cost is a separate, RBAC-gated row
    item = OneToOneField(InventoryItem, related_name="private")
    cost_price = DecimalField(12,2); supplier_id, last_purchase_date = ...

class InventoryStockLedger(SourceTrackedModel):         # EVENT-SOURCED stock
    shop = ForeignKey(Shop); item = ForeignKey(InventoryItem, related_name="ledger_entries")
    event_type = CharField([opening_balance/adjustment/sale/return/purchase/import/sync])
    quantity_delta = DecimalField(12,3)                 # fractional / by-weight
    unit_cost, unit_price, occurred_at = ...

# customers/models.py
class Customer(SourceTrackedModel):
    shop = ForeignKey(Shop, related_name="customers")
    name = CharField; phone = encrypt(CharField); email = encrypt(EmailField)  # PII ENCRYPTED
    balance = DecimalField(12,2); total_spent = DecimalField(12,2)
    class Meta: indexes = [Index(["shop","name"]), Index(["shop","phone"]), Index(["shop","status"])]

class CustomerLedgerEntry(SourceTrackedModel):          # khata timeline
    shop, customer(FK, related_name="ledger_entries"), actor_user
    event_type = [opening_balance/sale/payment/adjustment]
    amount_delta = DecimalField(12,2); occurred_at = ...
    class Meta: ordering=["-occurred_at"]; indexes=[Index(["shop","occurred_at"]), Index(["customer","occurred_at"])]

# sales/models.py
class Sale(SourceTrackedModel):
    shop, actor_user, customer(FK, SET_NULL)
    subtotal_amount, discount_amount, total_amount = Decimal(12,2)
    taxable_amount, tax_amount, cgst_amount, sgst_amount, igst_amount = Decimal(12,2)  # GST
    amount_received, amount_due, payment_mode, sale_date, occurred_at, status = ...

class SaleItem(SourceTrackedModel):
    sale = ForeignKey(Sale, related_name="items"); inventory_item = ForeignKey(..., SET_NULL)
    quantity = DecimalField(12,3)                       # fractional
    unit_price, unit_cost, line_total, gst_rate, cgst/sgst/igst_amount, is_return = ...

# purchases/models.py  (procurement → inventory + payables)
class Supplier(SourceTrackedModel):  shop, name, phone, gstin, balance(payable), total_purchased
class Purchase(SourceTrackedModel):  shop, supplier(FK,SET_NULL), invoice_number, total_amount, amount_paid, amount_due
class PurchaseItem(SourceTrackedModel): purchase(FK), inventory_item(FK,SET_NULL), quantity(12,3), unit_cost
class SupplierLedgerEntry(SourceTrackedModel): shop, supplier(FK), event_type[opening/purchase/payment/adjustment], amount_delta
```
_(`payments`, `expenses`, `attendance`, `audit`, `jobs` (migration control plane), `erpnext`, `projections` add their own shop-scoped tables in the same pattern.)_

**To produce a real SQL dump:** `manage.py sqlmigrate <app> <migration>` per app, or `pg_dump --schema-only` against the running Postgres.

---

## 3. Backend Middleware & Auth Code (the actual files)

### 3a. JWT verification — `platform_apps/users/jwt_auth.py`
```python
_ALGORITHM = "HS256"; _ISSUER = "business-hub"
ACCESS_TOKEN_LIFETIME = timedelta(hours=12); REFRESH_TOKEN_LIFETIME = timedelta(days=30)

def issue_tokens(user) -> dict:
    return {"access": _encode(user, "access", ACCESS_TOKEN_LIFETIME),
            "refresh": _encode(user, "refresh", REFRESH_TOKEN_LIFETIME),
            "token_type": "Bearer", "expires_in": int(ACCESS_TOKEN_LIFETIME.total_seconds())}

def decode_token(token, *, expected_type) -> dict:
    payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[_ALGORITHM],
                         issuer=_ISSUER, options={"require": ["exp","sub","token_type"]})
    if payload.get("token_type") != expected_type:
        raise jwt.InvalidTokenError("Wrong token type.")   # -> not-my-token / 401
    return payload

class JWTAuthentication(authentication.BaseAuthentication):
    keyword = "Bearer"
    def authenticate(self, request):
        header = authentication.get_authorization_header(request).split()
        if not header or header[0].lower() != self.keyword.lower().encode(): return None
        if len(header) != 2: return None
        try:
            payload = decode_token(header[1].decode(), expected_type="access")
        except jwt.ExpiredSignatureError:
            raise exceptions.AuthenticationFailed("Access token has expired.")
        except jwt.InvalidTokenError:
            return None      # not our token -> Firebase adapter gets a turn
        user = User.objects.get(pk=payload["sub"])
        if not user.is_active: raise exceptions.AuthenticationFailed("User is inactive.")
        return (user, header[1].decode())
```
Token endpoints: `POST /api/v1/session/token/` (email+password → pair) and `POST /api/v1/session/token/refresh/` (`platform_apps/users/token_views.py`).

**Auth chain** (`config/settings.py` → `REST_FRAMEWORK.DEFAULT_AUTHENTICATION_CLASSES`):
`JWTAuthentication` → `FirebaseAuthentication` (verifies Google-signed RS256 ID tokens via `firebase-admin`, `platform_apps/users/authentication.py`) → `DevHeaderAuthentication` (**DEBUG-only** `X-Dev-User-Email`) → Session → Basic. HS256(ours) vs RS256(Firebase) means the two never collide.

### 3b. Tenant isolation / routing — `platform_apps/shops/permissions.py`
Every shop-scoped view resolves the caller's membership for the URL's `shop_id` **and** enforces a minimum role. No membership → 403. This is the tenant boundary.
```python
ROLE_ORDER = {VIEWER:10, STAFF:20, ADMIN:30, OWNER:40}

def get_membership_or_403(user, shop_id, minimum_role=ShopMembership.Role.VIEWER):
    membership = (ShopMembership.objects
        .select_related("shop")
        .filter(user=user, shop_id=shop_id, status=ShopMembership.Status.ACTIVE)
        .first())
    if membership is None:
        raise exceptions.PermissionDenied("You do not have access to this shop.")
    if ROLE_ORDER[membership.role] < ROLE_ORDER[minimum_role]:
        raise exceptions.PermissionDenied("Your role does not allow this action.")
    return membership
```
Usage (RBAC example — cashier blocked from finance): `get_membership_or_403(request.user, shop_id, ShopMembership.Role.ADMIN)` in `reports.py`, `purchases/views.py`, GST exports.

### 3c. Write-gate for the migration cutover — `platform_apps/common/migration_guards.py`
Writes to a domain are refused (409) until that shop's domain is promoted to `postgres_primary` (the Firebase→Postgres cutover machinery): `assert_postgres_primary_write_enabled(shop_id=…, domain=…)`.

### 3d. DB connection manager — `config/settings.py`
Django manages pooling via **persistent connections** (`conn_max_age`), with **pgbouncer** doing transaction pooling in prod. No hand-rolled open/close.
```python
DATABASE_URL = os.getenv("DATABASE_URL")
if DATABASE_URL:
    DATABASES = {"default": dj_database_url.parse(
        DATABASE_URL,
        conn_max_age=int(os.getenv("DATABASE_CONN_MAX_AGE", "600")),   # persistent conns
        ssl_require=env_bool("DATABASE_SSL_REQUIRED", False))}
else:
    DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": BASE_DIR/"dev.sqlite3"}}
SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "dev-only-change-me")   # ⚠ MUST set in prod
```

---

## 4. Offline Sync & Local DB Logic

### 4a. Local DB (Drift/SQLite) — `apps/mobile_flutter/lib/core/database/local_database.dart`
Tables: `inventory_entries`, `inventory_private_entries`, `sales_entries`, `customer_entries`, `customer_ledger_entries`, `expenses`, `purchase_entries`, `stock_movement_entries`, `shop_settings_entries`, and the queue **`commerce_outbox`**. All writes go here first (instant, offline).

### 4b. The queue manager — `commerce_outbox` table
```
command_id (idempotency key)  shop_id  command_type(sale_create|payment_create)
domain  base_domain_epoch  payload_json  sync_status  attempt_count  last_error
created_at  updated_at  last_attempt_at  completed_at
```

### 4c. Background pusher — `lib/core/sync/mobile_sync_coordinator.dart` → `flushCommerceOutbox()`
Pulls pending entries (respecting **backoff + attempt ceiling**, overridable on manual retry), posts each as an **idempotent command**, records attempts/errors:
```dart
final entries = await _salesRepository.getPendingOutboxEntries(
    ignoreBackoff: force || triggerCommandId != null);
for (final entry in entries) {
  await _salesRepository.registerOutboxAttempt(entry.commandId);
  await _salesRepository.markOutboxSyncing(entry.commandId);
  final payload = jsonDecode(entry.payloadJson) as Map<String, dynamic>;
  switch (entry.commandType) {
    case 'sale_create':
      response = await _backendApiClient.submitSaleCommand(
          user: session.user, shopId: entry.shopId, payload: payload);
    case 'payment_create':
      response = await _backendApiClient.submitPaymentCommand(...);
  }
  // on success → markOutboxCompleted; on error → store last_error, bump attempt_count (backoff)
}
```
- **Idempotency:** each command carries a `command_id` + `base_domain_epoch`; the backend’s `SaleCommandReceipt` dedupes replays, so retries never double-post a sale.
- **Two-way:** `syncNow()` = `flushCommerceOutbox()` (push) then `pullFromCloud()` (pull). Pull is an **upsert/merge**, so it can never overwrite unsynced local edits → no data loss.
- **Triggers:** on login/session change, on each sale (`submitSale`), on a retry timer (`_outboxRetryTimer`), and manual "Sync now". Backoff tests: `test/outbox_backoff_test.dart`.
- **Flag:** `MobileRuntimeConfig.backendSyncEnabled` lets a build run purely local (sales still queue).

> **The one caveat** (already in the roadmap): the end-to-end **soak test** — 50 offline fractional sales → reconnect → verify — needs a device + live backend; the machinery + JWT auth are built and unit-tested.

---

## 5. Tauri & Package Configurations

### 5a. `apps/desktop/src-tauri/tauri.conf.json` (Tauri **2**)
```json
{
  "productName": "Business Hub", "version": "1.3.6", "identifier": "com.businesshub.erp",
  "build": { "frontendDist": "../../../dist",         // wraps the LEGACY Vite build
             "beforeBuildCommand": "npm --prefix ../.. run build" },
  "app": { "withGlobalTauri": true,
           "windows": [{ "title": "Business Hub ERP", "width": 1280, "height": 800 }],
           "security": { "csp": null } },              // ⚠ CSP DISABLED — see flags
  "bundle": { "active": true, "targets": "all", "icon": [ ... ] }
}
```
- Permissions model: Tauri 2 uses a **capabilities/ACL** system; this config is minimal (no custom allowlist declared here) and `withGlobalTauri: true` exposes the JS API broadly. Tighten before shipping desktop.

### 5b. Package manifests
- **Desktop** `apps/desktop/package.json`: deps `@tauri-apps/api@^2`, `@tauri-apps/plugin-opener@^2`; dev `@tauri-apps/cli@^2`, `vite@^6`, `typescript@~5.6`. Very light (thin shell).
- **Mobile** `apps/mobile_flutter/pubspec.yaml` (the real client manifest): `flutter_riverpod ^3.3`, `drift ^2.32` + `drift_flutter`, `go_router ^17`, `mobile_scanner ^7`, `esc_pos_utils_plus`, `blue_thermal_printer`, `pdf ^3.11` + `printing ^5.13`, `sentry_flutter ^9`, `excel ^4.0.6`, `file_picker ^8.1`, `local_auth ^3.0.2`, `flutter_contacts ^2.1`, `qr ^3.0`, `url_launcher ^6.3`.
- **Backend** `apps/backend/requirements.txt`: `Django==6.0.4`, `djangorestframework==3.17.1`, `psycopg[binary]==3.3.3`, `celery==5.6.3`, `redis==7.4.0`, `firebase-admin==7.4.0`, `channels`/`channels-redis`, `django-cryptography`, `django-ratelimit`, `PyJWT`, OpenTelemetry.

### 5c. Security / dependency flags (honest)
| Flag | Detail | Status |
|------|--------|--------|
| **Tauri CSP is `null`** | Content-Security-Policy disabled in `tauri.conf.json` | Fix before shipping desktop |
| **`SECRET_KEY` default** | falls back to `"dev-only-change-me"` | Must set `DJANGO_SECRET_KEY` in prod |
| **Leaked Firebase key** | old `service-account.json` was in git history | **Purged** (117 MB→9.6 MB); **rotate** per `SECURITY_ROTATION…md` |
| **Unpinned backend deps** | `channels`, `django-cryptography`, `django-ratelimit` unpinned | Pin for reproducible builds |
| **`excel ^4.0.6`** | crashes on some real .xlsx (we wrap it) | Prefer CSV path / replace |
| **Desktop wraps legacy app** | `frontendDist` → the archived React app | Migrate desktop to the active surface or retire |

---

### File index (open these for the raw source)
- Auth: `platform_apps/users/jwt_auth.py`, `…/authentication.py`, `…/token_views.py`, `shops/permissions.py`, `common/migration_guards.py`, `config/settings.py`
- Schema: `platform_apps/*/models.py` (+ `*/migrations/`)
- Sync: `apps/mobile_flutter/lib/core/sync/mobile_sync_coordinator.dart`, `…/core/database/local_database.dart`, `…/core/database/mobile_repository.dart`
- Configs: `apps/desktop/src-tauri/tauri.conf.json`, `apps/desktop/package.json`, `apps/mobile_flutter/pubspec.yaml`, `apps/backend/requirements.txt`, `docker-compose.prod.yml`

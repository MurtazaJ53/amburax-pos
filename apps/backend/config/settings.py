from __future__ import annotations

import os
from pathlib import Path

import dj_database_url
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")


def env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_list(name: str, default: list[str] | None = None) -> list[str]:
    raw = os.getenv(name)
    if not raw:
        return default or []
    return [item.strip() for item in raw.split(",") if item.strip()]


DEBUG = env_bool("DJANGO_DEBUG", False)
ENVIRONMENT = os.getenv("DJANGO_ENV", "development")

if ENVIRONMENT == "production":
    if not os.getenv("DATABASE_URL"):
        from django.core.exceptions import ImproperlyConfigured
        raise ImproperlyConfigured("FATAL: DATABASE_URL is not set in production.")
    if not os.getenv("RESEND_API_KEY"):
        from django.core.exceptions import ImproperlyConfigured
        raise ImproperlyConfigured("FATAL: RESEND_API_KEY is not set in production.")

# SECRET_KEY: Refuse to boot without a real key so a forgotten env var 
# can't ship an instance whose JWTs anyone could forge.
_SECRET_KEY = os.getenv("DJANGO_SECRET_KEY")
if _SECRET_KEY:
    SECRET_KEY = _SECRET_KEY
else:
    from django.core.exceptions import ImproperlyConfigured

    raise ImproperlyConfigured(
        "FATAL: DJANGO_SECRET_KEY is not set. Refusing to boot."
    )

# Pepper for blind-index hashing of searchable PII (customer phone). Falls back
# to SECRET_KEY so it always has a strong value; set a *separate*
# BLIND_INDEX_PEPPER in prod for key separation. NEVER change it once data
# exists, or existing phone hashes stop matching.
# `or` rather than a getenv default: compose passes ${BLIND_INDEX_PEPPER:-},
# which sets the variable to an EMPTY STRING when it is not in the env file.
# os.getenv returns that empty string rather than the default, so the pepper
# would silently become "" and every existing phone hash would stop matching.
BLIND_INDEX_PEPPER = os.getenv("BLIND_INDEX_PEPPER") or SECRET_KEY

# Key for the encrypted PII columns (customer phone), via django_cryptography.
#
# That library derives its encryption key from SECRET_KEY whenever this is
# unset — see django_cryptography/conf.py, `configured_data['KEY'] or
# settings.SECRET_KEY`. Which means SECRET_KEY silently does three jobs at
# once: signing JWTs, ENCRYPTING customer phones, and (through the fallback
# above) making them searchable.
#
# That coupling makes SECRET_KEY unrotatable once any customer exists. Rotating
# it does not merely break search — it makes every stored phone number
# undecryptable ciphertext, which no backup recovers, because the backup holds
# the same ciphertext.
#
# THIS DOES NOT MAKE SECRET_KEY ROTATABLE. An earlier version of this comment
# claimed it did — that setting this to the current SECRET_KEY value would hold
# the derived key steady while SECRET_KEY rotated as a signing key alone. That
# was wrong, and acting on it took production customer data offline on
# 20 Aug 2026 (readable=0 unreadable=243, recovered by restoring the old
# SECRET_KEY; no data was lost, the ciphertext was intact throughout).
#
# Why it is wrong: encrypted values are signed as well as encrypted, and the
# two halves take their keys from different places.
#
#   conf.py      encryption key <- CRYPTOGRAPHY_KEY or SECRET_KEY  (pinnable)
#   signing.py   signature key  <- settings.SECRET_KEY             (NOT pinnable)
#
# See django_cryptography/core/signing.py, where all three signer classes do
# `self.key = key or settings.SECRET_KEY` and CRYPTOGRAPHY_KEY appears nowhere.
# decrypt() calls signer.unsign() BEFORE decrypting, so a rotated SECRET_KEY
# raises BadSignature and never reaches the ciphertext at all — which is why
# pinning the encryption key alone changes nothing.
#
# So SECRET_KEY stays unrotatable while any encrypted row exists. Rotating it
# is a DATA MIGRATION, not a config change: decrypt every encrypted column
# under the old key, rotate, re-encrypt under the new one, with the database
# backed up first and the whole thing rehearsed against a scratch restore
# (scripts/go-live/restore-drill.sh) before production is touched.
#
# Setting this is still worth doing on a NEW deployment, before any customer
# exists — from then on the encryption key is explicit rather than an invisible
# side effect of SECRET_KEY.
#
# NEVER change this once data exists, for the same reason as the pepper.
CRYPTOGRAPHY_KEY = os.getenv("CRYPTOGRAPHY_KEY") or None

# The key that signs API tokens. Separate from SECRET_KEY on purpose.
#
# SECRET_KEY signs every JWT (platform_apps/users/jwt_auth.py) AND, through
# django_cryptography, encrypts customer phone numbers. The encryption half
# makes it unrotatable — see the CRYPTOGRAPHY_KEY note above — and the live
# deployment is therefore stuck on an 11-character key.
#
# That is worse than it sounds for auth. Every signed-in user, down to the
# lowest-privilege cashier, holds a valid HS256 token: a signature pair that
# can be brute-forced OFFLINE, with no rate limit, no audit trail and nothing
# touching the server. Recovering an 11-character key lets an attacker mint a
# token for any user id, including a platform admin.
#
# PyJWT has nothing to do with django_cryptography, so this half decouples
# freely. Set JWT_SIGNING_KEY to something long and random and tokens stop
# depending on SECRET_KEY's strength — no data migration, no re-encryption,
# nothing touched but the signature.
#
# Falls back to SECRET_KEY when unset so existing deployments keep working;
# jwt_auth also VERIFIES against SECRET_KEY as a fallback, so tokens minted
# before the switch stay valid until they expire rather than signing everyone
# out at deploy time.
JWT_SIGNING_KEY = os.getenv("JWT_SIGNING_KEY") or SECRET_KEY

ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", ["localhost", "127.0.0.1", "testserver"])
CORS_ALLOWED_ORIGINS = env_list("DJANGO_CORS_ALLOWED_ORIGINS")
CORS_ALLOW_ALL_ORIGINS = False
# Second switch on DevHeaderAuthentication, which signs in whoever an HTTP
# header names — as a platform admin on request. DEBUG alone used to be the
# only thing standing between that and production. Never set this in any
# deployed environment.
ALLOW_DEV_HEADER_AUTH = os.getenv("ALLOW_DEV_HEADER_AUTH", "").lower() in (
    "1",
    "true",
    "yes",
)

CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")
BUSINESS_HUB_WEBAUTHN_RP_ID = os.getenv("BUSINESS_HUB_WEBAUTHN_RP_ID", "").strip()
BUSINESS_HUB_WEBAUTHN_RP_NAME = os.getenv(
    "BUSINESS_HUB_WEBAUTHN_RP_NAME",
    "Business Hub",
).strip()
BUSINESS_HUB_WEBAUTHN_ALLOWED_ORIGINS = env_list(
    "BUSINESS_HUB_WEBAUTHN_ALLOWED_ORIGINS",
    CORS_ALLOWED_ORIGINS or ["http://localhost:3000", "http://127.0.0.1:3000"],
)

INSTALLED_APPS = [
    "channels",
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "corsheaders",
    "rest_framework",
    "platform_apps.common.apps.CommonConfig",
    "platform_apps.health.apps.HealthConfig",
    "platform_apps.users.apps.UsersConfig",
    "platform_apps.shops.apps.ShopsConfig",
    "platform_apps.platform_admin.apps.PlatformAdminConfig",
    "platform_apps.inventory.apps.InventoryConfig",
    "platform_apps.customers.apps.CustomersConfig",
    "platform_apps.sales.apps.SalesConfig",
    "platform_apps.payments.apps.PaymentsConfig",
    "platform_apps.expenses.apps.ExpensesConfig",
    "platform_apps.purchases.apps.PurchasesConfig",
    "platform_apps.attendance.apps.AttendanceConfig",
    "platform_apps.projections.apps.ProjectionsConfig",
    "platform_apps.jobs.apps.JobsConfig",
    "platform_apps.audit.apps.AuditConfig",
    "platform_apps.erpnext.apps.ERPNextConfig",
    "platform_apps.notifications.apps.NotificationsConfig",
    "platform_apps.billing.apps.BillingConfig",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    # WhiteNoise serves static files (admin, DRF browsable API) without a
    # separate web server - required when deploying to Render/Heroku-style hosts.
    # Must sit immediately after SecurityMiddleware.
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "platform_apps.common.middleware.CSPMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

DATABASE_URL = os.getenv("DATABASE_URL")
if DATABASE_URL:
    DATABASES = {
        "default": dj_database_url.parse(
            DATABASE_URL,
            # 0 = release the connection after each request. Required behind
            # PgBouncer in *transaction* pooling mode (the prod setup); keeping
            # Django connections alive there defeats the pooler and exhausts
            # Postgres. Set DATABASE_CONN_MAX_AGE>0 only if you point Django at
            # Postgres directly (no transaction-pooling PgBouncer).
            conn_max_age=int(os.getenv("DATABASE_CONN_MAX_AGE", "0")),
            ssl_require=True if ENVIRONMENT == "production" else env_bool("DATABASE_SSL_REQUIRED", False),
        )
    }
else:
    # SQLite is the local fallback only; production always sets DATABASE_URL.
    #
    # The defaults are unusable for this app. SQLite's rollback journal takes a
    # database-wide write lock, and several endpoints write during a GET — the
    # dashboard materialises its projection on first read, so creating a shop
    # and landing on the dashboard is two writes in quick succession. On the
    # threaded dev server that reliably produced "database is locked" and a 500
    # on the first page a new shop ever sees.
    #
    # WAL lets a reader and a writer coexist, and the timeout makes a competing
    # writer wait rather than fail instantly. Neither affects production.
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "dev.sqlite3",
            "OPTIONS": {
                "timeout": 30,
                "init_command": "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;",
                # Take the write lock when the transaction starts rather than
                # on its first write, so two concurrent writers queue instead
                # of one discovering the conflict half way through.
                "transaction_mode": "IMMEDIATE",
            },
        }
    }

PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.Argon2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2SHA1PasswordHasher",
    "django.contrib.auth.hashers.BCryptSHA256PasswordHasher",
]

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

SESSION_COOKIE_SECURE = not DEBUG
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"

CSRF_COOKIE_SECURE = not DEBUG
CSRF_COOKIE_HTTPONLY = True
CSRF_COOKIE_SAMESITE = "Lax"

SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "DENY"
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

LANGUAGE_CODE = "en-in"
TIME_ZONE = os.getenv("DJANGO_TIME_ZONE", "Asia/Kolkata")
USE_I18N = True
USE_TZ = True

STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
# WhiteNoise compressed storage. CompressedStaticFilesStorage (not the Manifest
# variant) is deliberate: it will not hard-fail a deploy if a template references
# a missing asset.
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedStaticFilesStorage",
    },
}
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
AUTH_USER_MODEL = "users.PlatformUser"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        # JWT first: only claims tokens signed with our SECRET_KEY, otherwise
        # returns None so the Firebase adapter still handles Firebase ID tokens.
        "platform_apps.users.jwt_auth.JWTAuthentication",
        # FirebaseAuthentication deliberately removed from the chain. Nothing
        # authenticates with Firebase any more (the Flutter app has no Firebase
        # dependency at all, and no service account ships in the image), but
        # leaving it registered meant a malformed or expired JWT fell through to
        # it and returned "Firebase authentication is not configured on this
        # backend" — a misleading error for a plain auth failure. The module
        # stays for the historical migration tooling.
        "platform_apps.users.authentication.DevHeaderAuthentication",
        "rest_framework.authentication.SessionAuthentication",
        "rest_framework.authentication.BasicAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle"
    ],
    # How many proxies sit in front of Django, so it knows which entry of
    # X-Forwarded-For is the real client.
    #
    # Left unset, DRF uses the whole header verbatim as the throttle key — and
    # the header is supplied by the caller. Anyone could hand themselves a
    # fresh bucket on every request, which made the 5/min login limit no limit
    # at all: measured at eight failed sign-ins with a rotating header and not
    # one 429, against a lockout on the sixth without it.
    #
    # 1 = the single nginx hop in front of this. Nginx appends the peer address
    # it actually observed to the end of the header, so counting from the end
    # ignores anything the client put there. With no proxy in front (local
    # runs), no header arrives and DRF falls back to REMOTE_ADDR, so this is
    # safe in both shapes.
    "NUM_PROXIES": int(os.getenv("DJANGO_NUM_PROXIES", "1")),
    "DEFAULT_THROTTLE_RATES": {
        "anon": "100/hour",
        "user": "1000/hour",
        # Public khata statements get their own bucket. On the shared "anon"
        # rate a busy shop's customers checking balances would exhaust the
        # 100/hour that also covers login and registration.
        "khata_statement": "60/hour",
        # A four-digit PIN is 10,000 guesses. This is the whole of its
        # brute-force protection, so it is tuned for a shift change (a cashier
        # mistypes once or twice) rather than for a script.
        "pos_pin": "10/min",
    },
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": int(os.getenv("API_PAGE_SIZE", "50")),
    "EXCEPTION_HANDLER": "platform_apps.common.exceptions.core_exception_handler",
}

REDIS_URL = os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0")

# Run cache + realtime + Celery in-process (no Redis server) when explicitly
# requested, or automatically under the test runner, so the suite is green
# without external infra.
import sys as _sys  # noqa: E402

_running_tests = ("pytest" in _sys.modules) or ("test" in _sys.argv)
_USE_INMEMORY_INFRA = _running_tests or os.getenv(
    "USE_INMEMORY_CHANNELS", ""
).lower() in ("1", "true", "yes")
_redis_cache = (
    REDIS_URL.startswith("redis://") or REDIS_URL.startswith("rediss://")
) and not _USE_INMEMORY_INFRA

# Three backends, because "no Redis" is not one situation but two.
#
# LocMemCache is per-PROCESS. Gunicorn runs 2 workers in production, so every
# DRF throttle counted in it was silently doubled — the 5/min login limit was
# really 10/min depending which worker answered — and max_requests recycling a
# worker wiped the counters outright. The login-throttle tests passed because
# the test runner is one process; they proved nothing about the deployment.
#
# So without Redis, production uses the DATABASE. One small table, no extra
# container, no memory on a 2 GB box, and correct across workers — which is the
# only property that matters for a rate limit. Redis would be faster and is
# still preferred when configured, but adding a container to fix a correctness
# bug is the wrong trade here.
#
# Tests keep LocMemCache: per-process is exactly right when the process is the
# whole world, and it avoids needing createcachetable in every suite.
from platform_apps.common.cache_backend import select_cache_backend  # noqa: E402

_cache_backend, _cache_location = select_cache_backend(
    redis_url=REDIS_URL,
    use_redis=_redis_cache,
    running_tests=_running_tests,
)

CACHES = {
    "default": {
        "BACKEND": _cache_backend,
        "LOCATION": _cache_location,
    }
}

# --- Subscription billing (Razorpay) -------------------------------------
# Left blank until real keys are issued; the billing module stays inert and the
# app keeps working, so nothing breaks before the merchant account exists.
RAZORPAY_KEY_ID = os.getenv("RAZORPAY_KEY_ID", "")
RAZORPAY_KEY_SECRET = os.getenv("RAZORPAY_KEY_SECRET", "")
RAZORPAY_WEBHOOK_SECRET = os.getenv("RAZORPAY_WEBHOOK_SECRET", "")

CELERY_BROKER_URL = os.getenv("CELERY_BROKER_URL", REDIS_URL)
CELERY_RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND", REDIS_URL)
# In tests/dev without infra, run tasks in-process so no broker is contacted.
if _USE_INMEMORY_INFRA:
    CELERY_TASK_ALWAYS_EAGER = True
    CELERY_TASK_EAGER_PROPAGATES = True
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_TIME_LIMIT = int(os.getenv("CELERY_TASK_TIME_LIMIT", "300"))

# Realtime channel layer. Redis is used in production/dev-with-infra, but tests
# and lightweight local runs can opt into the in-memory layer so the suite runs
# green without a Redis server (USE_INMEMORY_CHANNELS=1).
if _USE_INMEMORY_INFRA:
    CHANNEL_LAYERS = {
        "default": {"BACKEND": "channels.layers.InMemoryChannelLayer"},
    }
else:
    CHANNEL_LAYERS = {
        "default": {
            "BACKEND": "channels_redis.core.RedisChannelLayer",
            "CONFIG": {
                "hosts": [REDIS_URL],
            },
        },
    }

OTEL_SERVICE_NAME = os.getenv("OTEL_SERVICE_NAME", "business-hub-backend")

ERPNEXT_BASE_URL = os.getenv("ERPNEXT_BASE_URL", "").rstrip("/")
ERPNEXT_API_KEY = os.getenv("ERPNEXT_API_KEY", "")
ERPNEXT_API_SECRET = os.getenv("ERPNEXT_API_SECRET", "")
ERPNEXT_SITE_NAME = os.getenv("ERPNEXT_SITE_NAME", "")
ERPNEXT_VERIFY_SSL = env_bool("ERPNEXT_VERIFY_SSL", True)
ERPNEXT_TIMEOUT_SECONDS = int(os.getenv("ERPNEXT_TIMEOUT_SECONDS", "15"))
ERPNEXT_MOCK_MODE = env_bool("ERPNEXT_MOCK_MODE", False)
ERPNEXT_MOCK_STATE_PATH = os.getenv(
    "ERPNEXT_MOCK_STATE_PATH",
    str(BASE_DIR / ".erpnext-mock-state.json"),
)
ERPNEXT_CYCLE_BEAT_ENABLED = env_bool("ERPNEXT_CYCLE_BEAT_ENABLED", True)
ERPNEXT_CYCLE_BEAT_MINUTES = int(os.getenv("ERPNEXT_CYCLE_BEAT_MINUTES", "15"))
ERPNEXT_CYCLE_BEAT_LIMIT = int(os.getenv("ERPNEXT_CYCLE_BEAT_LIMIT", "100"))

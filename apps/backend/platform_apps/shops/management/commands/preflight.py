"""Check that this deployment is actually fit to face the public internet.

Every item here is something that has either already gone wrong on this
project or would go wrong silently — which is the dangerous kind. A misconfigured
`ALLOWED_HOSTS` does not crash; it serves every request happily until someone
points their own domain at the droplet. A missing cron entry does not error;
the 09:00 alerts simply never arrive and nobody notices they were promised.

The command is deliberately blunt about the difference between the two
categories:

- **FAIL** — the deployment is unsafe or a promised feature does not work.
  Do not put a real shop on it.
- **WARN** — worth fixing, but a shop can trade through it.

Run it after any change to the environment:

    docker compose -f docker-compose.demo.yml exec -T api python manage.py preflight
"""
from __future__ import annotations

from dataclasses import dataclass

from django.conf import settings
from django.core.management.base import BaseCommand

from platform_apps.common.emailer import resend_api_key, resend_from_address

FAIL = "FAIL"
WARN = "WARN"
OK = "OK"

#: Hosts that are fine locally and meaningless in production. Shipping with
#: only these means the real domain was never added.
LOCAL_HOSTS = {"localhost", "127.0.0.1", "testserver", "0.0.0.0", "[::1]"}


@dataclass(frozen=True)
class Check:
    """One finding, in the words the person fixing it needs."""

    name: str
    status: str
    detail: str
    fix: str = ""


def check_allowed_hosts(allowed_hosts: list[str]) -> Check:
    """`ALLOWED_HOSTS = ["*"]` accepts any Host header.

    Django's host validation is what stops a request arriving with a forged
    Host header being treated as legitimate — it is what password-reset links
    and absolute URLs are built from. A wildcard turns that check off entirely,
    and nothing about the site looks different afterwards.
    """
    hosts = [h.strip() for h in allowed_hosts if h.strip()]
    if not hosts:
        return Check(
            "ALLOWED_HOSTS",
            FAIL,
            "Empty, so Django will reject every request.",
            "Set DJANGO_ALLOWED_HOSTS to your domain.",
        )
    if "*" in hosts:
        return Check(
            "ALLOWED_HOSTS",
            FAIL,
            "Set to '*', which accepts a forged Host header from anyone.",
            "Set DJANGO_ALLOWED_HOSTS to your real domains, comma separated.",
        )
    real = [h for h in hosts if h.lower() not in LOCAL_HOSTS]
    if not real:
        return Check(
            "ALLOWED_HOSTS",
            WARN,
            f"Only local hosts are allowed ({', '.join(hosts)}).",
            "Add the public domain once DNS points at this droplet.",
        )
    return Check("ALLOWED_HOSTS", OK, f"Restricted to {', '.join(real)}.")


def check_debug(debug: bool) -> Check:
    """DEBUG on a public host prints settings and stack traces to strangers."""
    if debug:
        return Check(
            "DEBUG",
            FAIL,
            "On. Any error page shows the settings and traceback to the visitor.",
            "Set DJANGO_DEBUG=False and restart the api container.",
        )
    return Check("DEBUG", OK, "Off.")


MIN_KEY_LENGTH = 32


def check_jwt_signing_key(jwt_signing_key: str, secret_key: str) -> Check:
    """The key that actually authenticates API requests.

    Separate from SECRET_KEY on purpose. Every signed-in user holds a valid
    HS256 token, which is a signature pair an attacker can brute-force offline
    — no rate limit, no audit trail, nothing touching the server. So this key's
    strength, not SECRET_KEY's, is what stands between a cashier's token and a
    forged platform-admin one.
    """
    if not jwt_signing_key or jwt_signing_key == secret_key:
        return Check(
            "JWT_SIGNING_KEY",
            WARN,
            "Unset, so API tokens are signed with SECRET_KEY.",
            "Set JWT_SIGNING_KEY to a long random value. Safe to do at any "
            "time: it touches no stored data, and tokens signed with the old "
            "key keep working until they expire.",
        )
    if len(jwt_signing_key) < MIN_KEY_LENGTH:
        return Check(
            "JWT_SIGNING_KEY",
            FAIL,
            f"Shorter than {MIN_KEY_LENGTH} characters.",
            "Generate a longer one. This key is offline-brute-forceable from "
            "any user's token.",
        )
    return Check("JWT_SIGNING_KEY", OK, "Set separately, and long enough.")


def check_secret_key(
    secret_key: str, blind_index_pepper: str, jwt_signing_key: str = ""
) -> Check:
    """SECRET_KEY's length, judged by what it is still responsible for.

    THIS CHECK USED TO TELL OPERATORS TO ROTATE SECRET_KEY. Following that
    advice on 20 Aug 2026 made every stored customer phone undecryptable on the
    live API (readable=0 unreadable=243) until the old key was restored.

    SECRET_KEY cannot be rotated once encrypted rows exist. django_cryptography
    signs encrypted values with settings.SECRET_KEY (core/signing.py) and
    decrypt() verifies that signature BEFORE decrypting, so a new key raises
    BadSignature and never reaches the ciphertext. Pinning CRYPTOGRAPHY_KEY
    does not help — it only covers the encryption half. Rotating for real is a
    data migration: decrypt every encrypted column under the old key, rotate,
    re-encrypt, rehearsed against a scratch restore first.

    So a short SECRET_KEY on a deployment with customers is a WARN, not a FAIL.
    A FAIL that can only be cleared by destroying data is not a safety check;
    it is a trap, and an operator who clears it has been harmed by this file.

    It stays a FAIL when JWT_SIGNING_KEY is not set, because then SECRET_KEY is
    also signing every API token, and that IS remotely exploitable: any user's
    token is a brute-force oracle. Setting JWT_SIGNING_KEY closes that without
    touching a byte of stored data.
    """
    if not secret_key or len(secret_key) < MIN_KEY_LENGTH:
        jwt_key_is_strong = (
            jwt_signing_key
            and jwt_signing_key != secret_key
            and len(jwt_signing_key) >= MIN_KEY_LENGTH
        )
        if jwt_key_is_strong:
            return Check(
                "DJANGO_SECRET_KEY",
                WARN,
                f"Shorter than {MIN_KEY_LENGTH} characters, but API tokens are "
                "signed with JWT_SIGNING_KEY, so it no longer authenticates "
                "requests. What remains needs a database dump first.",
                "Do NOT rotate it on a deployment with customer data — that "
                "makes every encrypted phone undecryptable. Changing it "
                "requires a decrypt/re-encrypt migration.",
            )
        return Check(
            "DJANGO_SECRET_KEY",
            FAIL,
            f"Shorter than {MIN_KEY_LENGTH} characters, and it is signing API "
            "tokens, which makes it forgeable offline from any user's token.",
            "Set JWT_SIGNING_KEY to a long random value. That fixes the "
            "exploitable half WITHOUT touching stored data. Do not rotate "
            "SECRET_KEY itself if any customer exists.",
        )
    if blind_index_pepper == secret_key:
        return Check(
            "BLIND_INDEX_PEPPER",
            WARN,
            "Falls back to SECRET_KEY, so rotating that key would make every "
            "encrypted customer phone unsearchable.",
            "Set a separate BLIND_INDEX_PEPPER now, before any customer data "
            "exists. It can never be changed afterwards.",
        )
    return Check("BLIND_INDEX_PEPPER", OK, "Set separately from SECRET_KEY.")


def check_csrf_origins(
    csrf_trusted_origins: list[str], allowed_hosts: list[str]
) -> Check:
    """Browser POSTs from the admin site fail without the scheme-qualified origin."""
    origins = [o.strip() for o in csrf_trusted_origins if o.strip()]
    real_hosts = [
        h.strip()
        for h in allowed_hosts
        if h.strip() and h.strip().lower() not in LOCAL_HOSTS and h.strip() != "*"
    ]
    if real_hosts and not origins:
        return Check(
            "CSRF_TRUSTED_ORIGINS",
            WARN,
            "Empty while a public domain is configured, so form posts from the "
            "admin site will be rejected.",
            "Set DJANGO_CSRF_TRUSTED_ORIGINS to https://your-domain, with the "
            "scheme included.",
        )
    plain = [o for o in origins if o.startswith("http://")]
    if plain:
        return Check(
            "CSRF_TRUSTED_ORIGINS",
            WARN,
            f"Contains plain http origins ({', '.join(plain)}).",
            "Use https:// once the certificate is issued.",
        )
    return Check("CSRF_TRUSTED_ORIGINS", OK, f"{len(origins)} origin(s) trusted.")


def check_email(api_key: str, from_address: str) -> Check:
    """Statements, purchase orders and the daily alerts all go out by email.

    Read from the environment through the emailer's own accessors rather than
    from Django settings, so this can never report a configuration the sending
    code does not actually use.
    """
    if not api_key:
        return Check(
            "Email",
            FAIL,
            "No RESEND_API_KEY, so every statement, purchase order and alert "
            "will silently no-op.",
            "Set RESEND_API_KEY in the environment and restart the api container.",
        )
    if "resend.dev" in from_address:
        # Resend's shared sandbox sender only delivers to the address that owns
        # the account. Everything looks successful and no customer receives
        # anything, which is the worst possible failure mode for a statement.
        return Check(
            "Email",
            WARN,
            f"Sending as {from_address}, Resend's test sender, which only "
            "delivers to your own account address.",
            "Verify a domain in Resend and set RESEND_FROM to an address on it.",
        )
    return Check("Email", OK, f"Sending as {from_address}.")


def summarise(checks: list[Check]) -> tuple[int, int]:
    """How many failures and warnings, so the exit code can mean something."""
    failures = sum(1 for c in checks if c.status == FAIL)
    warnings = sum(1 for c in checks if c.status == WARN)
    return failures, warnings


def run_checks() -> list[Check]:
    """Every check, in the order they matter."""
    return [
        check_debug(bool(settings.DEBUG)),
        check_allowed_hosts(list(settings.ALLOWED_HOSTS)),
        check_jwt_signing_key(
            str(getattr(settings, "JWT_SIGNING_KEY", "")),
            str(settings.SECRET_KEY),
        ),
        check_secret_key(
            str(settings.SECRET_KEY),
            str(getattr(settings, "BLIND_INDEX_PEPPER", "")),
            str(getattr(settings, "JWT_SIGNING_KEY", "")),
        ),
        check_csrf_origins(
            list(getattr(settings, "CSRF_TRUSTED_ORIGINS", [])),
            list(settings.ALLOWED_HOSTS),
        ),
        check_email(resend_api_key(), resend_from_address()),
    ]


class Command(BaseCommand):
    help = "Check this deployment is fit to face the public internet."

    def handle(self, *args, **options):
        checks = run_checks()
        failures, warnings = summarise(checks)

        for check in checks:
            if check.status == FAIL:
                style = self.style.ERROR
            elif check.status == WARN:
                style = self.style.WARNING
            else:
                style = self.style.SUCCESS
            self.stdout.write(style(f"[{check.status:4}] {check.name}: {check.detail}"))
            if check.fix:
                self.stdout.write(f"        -> {check.fix}")

        self.stdout.write("")
        if failures:
            self.stdout.write(
                self.style.ERROR(
                    f"{failures} blocking problem(s). Do not put a real shop on "
                    "this deployment yet."
                )
            )
            # Non-zero so a deploy script can stop here rather than carrying on.
            raise SystemExit(1)
        if warnings:
            self.stdout.write(
                self.style.WARNING(
                    f"No blocking problems, {warnings} thing(s) worth fixing."
                )
            )
            return
        self.stdout.write(self.style.SUCCESS("Ready."))

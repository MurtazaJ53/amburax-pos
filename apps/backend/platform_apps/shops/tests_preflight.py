"""The preflight checks, which only earn their place if they catch things.

A check that passes a broken configuration is worse than no check at all: it
converts "I am not sure this is safe" into "the tool says it is fine", which is
how a wildcard ALLOWED_HOSTS reaches production with everyone's blessing.
"""
from __future__ import annotations

from django.test import SimpleTestCase

from platform_apps.shops.management.commands.preflight import (
    FAIL,
    OK,
    WARN,
    Check,
    check_allowed_hosts,
    check_csrf_origins,
    check_debug,
    check_email,
    check_secret_key,
    summarise,
)

GOOD_KEY = "x" * 50


class AllowedHostsTests(SimpleTestCase):
    def test_wildcard_is_blocking(self):
        # The real deployment shipped with this. It does not fail, it does not
        # log, it simply accepts a forged Host header from anyone.
        result = check_allowed_hosts(["*"])
        self.assertEqual(result.status, FAIL)
        self.assertIn("forged", result.detail)

    def test_wildcard_alongside_a_real_domain_is_still_blocking(self):
        # Adding the real domain does not undo the wildcard, and a check that
        # only looked for "is a real host present" would pass this.
        self.assertEqual(check_allowed_hosts(["app.example.com", "*"]).status, FAIL)

    def test_empty_is_blocking(self):
        self.assertEqual(check_allowed_hosts([]).status, FAIL)
        self.assertEqual(check_allowed_hosts(["  "]).status, FAIL)

    def test_only_local_hosts_warns(self):
        # Correct for a laptop, and means the domain was never added in prod.
        result = check_allowed_hosts(["localhost", "127.0.0.1", "testserver"])
        self.assertEqual(result.status, WARN)

    def test_a_real_domain_passes(self):
        result = check_allowed_hosts(["app.example.com", "127.0.0.1"])
        self.assertEqual(result.status, OK)
        self.assertIn("app.example.com", result.detail)


class DebugTests(SimpleTestCase):
    def test_debug_on_is_blocking(self):
        self.assertEqual(check_debug(True).status, FAIL)

    def test_debug_off_passes(self):
        self.assertEqual(check_debug(False).status, OK)


class SecretKeyTests(SimpleTestCase):
    def test_short_key_is_blocking(self):
        self.assertEqual(check_secret_key("short", "short").status, FAIL)

    def test_missing_key_is_blocking(self):
        self.assertEqual(check_secret_key("", "").status, FAIL)

    def test_pepper_sharing_the_secret_key_warns(self):
        # Rotating SECRET_KEY is routine; rotating the pepper permanently
        # breaks customer phone lookup. Sharing one value couples them, so a
        # normal key rotation silently destroys search.
        result = check_secret_key(GOOD_KEY, GOOD_KEY)
        self.assertEqual(result.status, WARN)
        self.assertIn("unsearchable", result.detail)

    def test_separate_pepper_passes(self):
        self.assertEqual(check_secret_key(GOOD_KEY, "y" * 50).status, OK)


class CsrfOriginTests(SimpleTestCase):
    def test_missing_origins_with_a_public_domain_warns(self):
        result = check_csrf_origins([], ["app.example.com"])
        self.assertEqual(result.status, WARN)

    def test_missing_origins_on_a_local_only_host_is_fine(self):
        # A laptop has no public domain, so there is nothing to trust yet and
        # warning here would train people to ignore the output.
        self.assertEqual(check_csrf_origins([], ["localhost"]).status, OK)

    def test_plain_http_origin_warns(self):
        result = check_csrf_origins(["http://app.example.com"], ["app.example.com"])
        self.assertEqual(result.status, WARN)

    def test_https_origin_passes(self):
        result = check_csrf_origins(["https://app.example.com"], ["app.example.com"])
        self.assertEqual(result.status, OK)


class EmailTests(SimpleTestCase):
    def test_no_api_key_is_blocking(self):
        self.assertEqual(check_email("", "shop@example.com").status, FAIL)

    def test_resend_sandbox_sender_warns(self):
        # The worst failure mode in the system: Resend accepts the message,
        # the app reports success, and nobody outside the account receives it.
        result = check_email("re_key", "Business Hub <onboarding@resend.dev>")
        self.assertEqual(result.status, WARN)
        self.assertIn("only", result.detail)

    def test_a_verified_sender_passes(self):
        self.assertEqual(check_email("re_key", "shop@amburax.com").status, OK)


class SummaryTests(SimpleTestCase):
    def test_counts_failures_and_warnings_separately(self):
        # The exit code turns on this: a deploy script must stop on a failure
        # and carry on through a warning.
        checks = [
            Check("a", FAIL, ""),
            Check("b", WARN, ""),
            Check("c", OK, ""),
            Check("d", FAIL, ""),
        ]
        self.assertEqual(summarise(checks), (2, 1))

    def test_a_clean_run_counts_nothing(self):
        self.assertEqual(summarise([Check("a", OK, "")]), (0, 0))

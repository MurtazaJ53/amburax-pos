"""Preflight must not advise an action that destroys customer data.

This check used to FAIL on a short SECRET_KEY with the remediation "Generate a
long random key and set DJANGO_SECRET_KEY". Following that on 20 Aug 2026 made
every stored customer phone undecryptable on the live API — readable=0
unreadable=243 — until the old key was restored.

SECRET_KEY cannot be rotated once encrypted rows exist: django_cryptography
verifies a signature keyed on settings.SECRET_KEY before decrypting, so a new
key raises BadSignature and never reaches the ciphertext. A FAIL that can only
be cleared by destroying data is not a safety check, it is a trap.
"""
from __future__ import annotations

from platform_apps.shops.management.commands.preflight import (
    FAIL,
    OK,
    WARN,
    check_jwt_signing_key,
    check_secret_key,
)

SHORT = "Murt@z@5253"
STRONG = "a-long-random-signing-key-well-over-thirty-two-characters-0123456789"
OTHER = "another-long-random-key-well-over-thirty-two-characters-9876543210"


def test_it_never_tells_you_to_rotate_secret_key_when_jwt_is_separate():
    """The exact sentence that caused the incident must not come back."""
    check = check_secret_key(SHORT, OTHER, STRONG)
    assert "Generate a long random key" not in (check.fix or "")
    assert "do not rotate" in (check.fix or "").lower()


def test_a_short_secret_key_with_a_strong_jwt_key_is_a_warning_not_a_block():
    """It cannot be cleared without a data migration, so blocking the deploy on
    it just teaches operators to ignore preflight."""
    assert check_secret_key(SHORT, OTHER, STRONG).status == WARN


def test_a_short_secret_key_that_still_signs_tokens_is_a_hard_failure():
    """Without JWT_SIGNING_KEY it authenticates every request, and any user's
    token is an offline brute-force oracle. That IS remotely exploitable."""
    check = check_secret_key(SHORT, OTHER, "")
    assert check.status == FAIL
    # And the remedy offered must be the safe one.
    assert "JWT_SIGNING_KEY" in (check.fix or "")


def test_a_jwt_key_equal_to_secret_key_counts_as_unset():
    """Defaulting to SECRET_KEY is the fallback, not a separate key."""
    assert check_secret_key(SHORT, OTHER, SHORT).status == FAIL
    assert check_jwt_signing_key(SHORT, SHORT).status == WARN


def test_a_long_secret_key_still_reports_on_the_pepper():
    """The original purpose of this check is preserved."""
    assert check_secret_key(STRONG, STRONG, OTHER).status == WARN
    assert check_secret_key(STRONG, OTHER, STRONG).status == OK


def test_an_unset_jwt_key_is_flagged():
    assert check_jwt_signing_key("", SHORT).status == WARN


def test_a_short_jwt_key_is_a_hard_failure():
    """This one CAN be fixed safely, so blocking on it is fair."""
    assert check_jwt_signing_key("tooshort", SHORT).status == FAIL


def test_a_strong_separate_jwt_key_passes():
    assert check_jwt_signing_key(STRONG, SHORT).status == OK

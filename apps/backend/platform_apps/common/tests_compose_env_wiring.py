"""A setting the container never receives is a setting that does not exist.

docker-compose.demo.yml lists environment variables EXPLICITLY. Putting a value
in .env does nothing unless the variable also appears in that block.

JWT_SIGNING_KEY was added to settings.py and not to the compose file. So
preflight reported it unset no matter what the operator wrote in .env, the
advice preflight gave could not be followed, and the security fix it unlocks
stayed switched off while looking like a configuration mistake.

This pins the ones that matter. It reads the compose file as text rather than
importing anything, so it fails on the repo as shipped.
"""
from __future__ import annotations

from pathlib import Path

import pytest

COMPOSE = Path(__file__).resolve().parents[4] / "docker-compose.demo.yml"

#: Settings an operator is expected to set on a real deployment. Each must be
#: readable by settings.py AND passed through by compose; either alone is a
#: silent no-op.
OPERATOR_SETTABLE = [
    "DJANGO_SECRET_KEY",
    "JWT_SIGNING_KEY",
    "CRYPTOGRAPHY_KEY",
    "BLIND_INDEX_PEPPER",
    "DJANGO_ALLOWED_HOSTS",
    "DJANGO_CSRF_TRUSTED_ORIGINS",
    "OPS_ALERT_EMAIL",
    "RESEND_API_KEY",
]

#: Deliberately NOT wired, and it must stay that way. ALLOW_DEV_HEADER_AUTH
#: turns on an endpoint that signs in whoever an HTTP header names, as a
#: platform admin on request. It exists for a laptop.
MUST_NOT_BE_WIRED = ["ALLOW_DEV_HEADER_AUTH"]


@pytest.fixture(scope="module")
def compose_text() -> str:
    assert COMPOSE.exists(), f"compose file not found at {COMPOSE}"
    return COMPOSE.read_text(encoding="utf-8")


def test_the_compose_file_is_where_we_think_it_is(compose_text):
    # A path that silently missed would make every assertion below vacuous.
    assert "business-hub" in compose_text or "api:" in compose_text


@pytest.mark.parametrize("name", OPERATOR_SETTABLE)
def test_an_operator_settable_variable_reaches_the_container(name, compose_text):
    assert f"{name}:" in compose_text, (
        f"{name} is read by settings.py but never passed through in "
        "docker-compose.demo.yml, so setting it in .env does nothing."
    )


@pytest.mark.parametrize("name", MUST_NOT_BE_WIRED)
def test_the_dev_backdoor_is_not_reachable_from_the_env_file(name, compose_text):
    assert f"{name}:" not in compose_text, (
        f"{name} must never be settable on a deployment — it enables header "
        "impersonation as platform admin."
    )


def test_backups_are_visible_to_the_alerting_container(compose_text):
    """send_ops_alerts judges backup age from inside the container. Without the
    mount it would report "no backup found" every day, and an alert that cries
    wolf daily trains the operator to ignore the sender."""
    assert "/var/backups/bhub" in compose_text


def test_the_backup_mount_is_read_only(compose_text):
    """Nothing in the API should be able to delete a backup, and an application
    container is exactly where a compromise would start."""
    assert "/var/backups/bhub:ro" in compose_text


def test_the_cache_table_is_created_before_gunicorn(compose_text):
    """DatabaseCache without its table means every throttled request 500s."""
    assert "createcachetable" in compose_text
    assert compose_text.index("createcachetable") < compose_text.index("gunicorn")

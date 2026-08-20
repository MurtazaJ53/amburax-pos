"""A rate limit that only counts within one worker is not a rate limit.

Production runs gunicorn with 2 workers and no Redis, and the cache was
LocMemCache — which is per-process. So the 5/min login limit was really 10/min,
and worker recycling wiped the counters. The throttle tests all passed, because
the test runner is one process.
"""
from __future__ import annotations

import pytest

from platform_apps.common.cache_backend import (
    DATABASE,
    LOCMEM,
    REDIS,
    select_cache_backend,
)

REDIS_URL = "redis://127.0.0.1:6379/0"


def test_redis_is_used_when_it_is_configured():
    backend, location = select_cache_backend(
        redis_url=REDIS_URL, use_redis=True, running_tests=False
    )
    assert backend == REDIS
    assert location == REDIS_URL


def test_a_deployment_without_redis_uses_the_database_not_local_memory():
    """The fix. This is the deployed configuration: USE_INMEMORY_CHANNELS=1,
    no Redis container, 2 gunicorn workers."""
    backend, _ = select_cache_backend(
        redis_url=REDIS_URL, use_redis=False, running_tests=False
    )
    assert backend == DATABASE


def test_a_deployment_without_redis_never_gets_a_per_process_cache():
    """Stated as its own assertion because this is the actual defect: any
    per-process backend in a multi-worker deployment silently multiplies every
    throttle by the worker count."""
    backend, _ = select_cache_backend(
        redis_url=REDIS_URL, use_redis=False, running_tests=False
    )
    assert backend != LOCMEM


def test_tests_keep_local_memory():
    """Per-process is right when the process is the whole world, and it saves
    every suite from needing createcachetable."""
    backend, _ = select_cache_backend(
        redis_url=REDIS_URL, use_redis=False, running_tests=True
    )
    assert backend == LOCMEM


def test_redis_wins_over_the_test_runner():
    """If someone explicitly points the suite at Redis, honour it rather than
    quietly substituting something else."""
    backend, _ = select_cache_backend(
        redis_url=REDIS_URL, use_redis=True, running_tests=True
    )
    assert backend == REDIS


@pytest.mark.parametrize("running_tests", [True, False])
def test_a_location_is_always_returned(running_tests):
    """A DatabaseCache with an empty LOCATION silently uses no table and every
    throttled request 500s."""
    _, location = select_cache_backend(
        redis_url=REDIS_URL, use_redis=False, running_tests=running_tests
    )
    assert location


def test_the_startup_command_creates_the_cache_table():
    """DatabaseCache needs its table to exist before gunicorn accepts traffic.
    Without this the first throttled request errors instead of being counted —
    which would be a worse failure than the doubled limit it replaced."""
    from pathlib import Path

    compose = Path(__file__).resolve().parents[4] / "docker-compose.demo.yml"
    assert compose.exists(), f"compose file not found at {compose}"
    text = compose.read_text(encoding="utf-8")
    assert "createcachetable" in text, (
        "docker-compose.demo.yml must run createcachetable before gunicorn, "
        "or DatabaseCache has no table to write to."
    )

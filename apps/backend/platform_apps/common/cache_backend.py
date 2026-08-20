"""Which cache backend a deployment gets, and why.

Kept as a pure function so the choice can be tested. It used to be an inline
branch in settings, which meant the only way to find out what production used
was to read it and hope — and what production used was wrong.
"""
from __future__ import annotations

REDIS = "django.core.cache.backends.redis.RedisCache"
LOCMEM = "django.core.cache.backends.locmem.LocMemCache"
DATABASE = "django.core.cache.backends.db.DatabaseCache"

CACHE_TABLE = "business_hub_cache"


def select_cache_backend(
    *, redis_url: str, use_redis: bool, running_tests: bool
) -> tuple[str, str]:
    """Return (backend dotted path, location).

    "No Redis" is not one situation but two, and conflating them is what broke
    rate limiting in production:

    LocMemCache is per-PROCESS. Gunicorn runs 2 workers, so every DRF throttle
    counted in it was silently doubled — the 5/min login limit was really
    10/min depending which worker answered — and max_requests recycling a
    worker wiped the counters outright. The throttle tests passed because the
    test runner is a single process; they proved nothing about the deployment.

    So a deployment without Redis uses the DATABASE: one small table, no extra
    container, negligible memory on a 2 GB box, and correct across workers,
    which is the only property a rate limit actually needs. Redis stays
    preferred where it exists.

    Tests keep LocMemCache — per-process is exactly right when the process is
    the whole world, and it avoids needing createcachetable in every suite.
    """
    if use_redis:
        return REDIS, redis_url
    if running_tests:
        return LOCMEM, "business-hub-test-cache"
    return DATABASE, CACHE_TABLE

"""How many requests this server can hold at once.

Config nothing tested, in the file that decides whether the box stays up. The
old worker count came from cpu_count(), which inside a container reports the
HOST's CPUs - so the number was silently wrong everywhere it ran, and the
symptom would have been the kernel killing processes rather than anything
saying so.

The important assertion here is the boring one: on a 2 vCPU container this
still returns 2. Reading the real CPU allowance is only safe if it does not
quietly raise the count on the machine already in production, where one more
Django process is most of the memory that is left.
"""
from __future__ import annotations

import runpy
import types
from pathlib import Path

import pytest

CONFIG = Path(__file__).resolve().parents[2] / "gunicorn.conf.py"


@pytest.fixture(scope="module")
def config() -> dict:
    return runpy.run_path(str(CONFIG))


def _rebind(function, **replacements):
    """The same function with some of its globals swapped.

    The config is a script, not a module, so there is nothing to monkeypatch by
    name. Rebinding its globals runs the real code against a fake environment,
    which is the point - a reimplementation here would pass while the file
    itself was wrong.
    """
    module_globals = dict(function.__globals__)
    module_globals.update(replacements)
    return types.FunctionType(
        function.__code__, module_globals, function.__name__, function.__defaults__
    )


def _workers_when_cpus(config, cpus: float) -> int:
    return _rebind(config["_default_workers"], _available_cpus=lambda: cpus)()


def _cpus_reading(config, opener) -> float:
    return _rebind(config["_available_cpus"], open=opener)()


def _reads_only(path_wanted: str, replacement: Path):
    """An opener that serves one path from a temp file and fails everything else."""
    real_open = open

    def opener(path, *args, **kwargs):
        if str(path) == path_wanted:
            return real_open(replacement, *args, **kwargs)
        raise OSError("not present on this system")

    return opener


# --- how much capacity, and at what cost --------------------------------

def test_threads_serve_more_than_workers_do(config):
    """Threads are the cheap lever and should be the bigger number.

    A blocked thread costs a stack; a worker costs a whole Django process.
    This workload waits on Postgres, so if these ever invert somebody has
    chosen the expensive way to add capacity.
    """
    assert config["threads"] > config["workers"]


def test_two_workers_on_a_two_cpu_box(config):
    # The droplet in production. This must not change: raising it spends
    # another 120-180 MB out of a 900 MB limit to serve a single shop.
    assert _workers_when_cpus(config, 2.0) == 2


def test_one_cpu_still_gets_two_workers(config):
    # A single worker means one slow request blocks the health check, and a
    # deploy then reports the site down while it is merely busy.
    assert _workers_when_cpus(config, 1.0) == 2


def test_a_large_host_does_not_get_unbounded_workers(config):
    # Memory runs out long before CPU does. This cap is the difference between
    # a busy server and one being OOM-killed.
    assert _workers_when_cpus(config, 64.0) == 4


def test_a_bigger_droplet_raises_it_without_anyone_remembering(config):
    assert _workers_when_cpus(config, 4.0) == 4


# --- reading the container's allowance, not the host's ------------------

def test_the_container_quota_is_what_is_read(config, tmp_path):
    """cgroup v2: 200000/100000 is two CPUs, whatever the host reports."""
    quota = tmp_path / "cpu.max"
    quota.write_text("200000 100000", encoding="utf-8")

    cpus = _cpus_reading(config, _reads_only("/sys/fs/cgroup/cpu.max", quota))
    assert cpus == 2.0


def test_a_fractional_share_never_rounds_down_to_nothing(config, tmp_path):
    # Half a CPU is a legitimate limit. Zero workers is not a configuration.
    quota = tmp_path / "cpu.max"
    quota.write_text("50000 100000", encoding="utf-8")

    cpus = _cpus_reading(config, _reads_only("/sys/fs/cgroup/cpu.max", quota))
    assert cpus >= 1.0


def test_an_unlimited_container_is_not_read_as_a_limit(config, tmp_path):
    """cgroup v2 writes "max" when there is no quota. int("max") throws."""
    quota = tmp_path / "cpu.max"
    quota.write_text("max 100000", encoding="utf-8")

    cpus = _cpus_reading(config, _reads_only("/sys/fs/cgroup/cpu.max", quota))
    assert cpus > 0


def test_no_cgroup_at_all_still_yields_a_number(config):
    """The config is imported at startup.

    An exception here is not a bad worker count - it is a server that does not
    boot, on a platform whose cgroup layout we guessed wrong.
    """

    def nothing_readable(path, *args, **kwargs):
        raise OSError("no cgroup filesystem")

    assert _cpus_reading(config, nothing_readable) > 0

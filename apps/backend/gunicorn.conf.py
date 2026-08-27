import os

# Binding
bind = "0.0.0.0:8000"

# Workers & Threads
#
# The old value was cpu_count() * 2 + 1. Two problems on a small box:
#   - inside a container, cpu_count() reports the HOST's CPUs, not the
#     container's share, so it over-provisions silently
#   - each gthread worker is a full Django process (~120-180 MB here), so on a
#     2 vCPU droplet that is 5 workers and most of a 900 MB limit spent on
#     idle processes
#
# The CPU count now comes from the container's own cgroup quota, which is the
# figure that was actually wrong rather than the arithmetic around it. An
# unlimited container falls back to cpu_count(); anything unreadable falls
# back to 2, because a wrong guess here costs memory this box does not have.
#
# Threads are the lever that was raised, not workers. This workload waits on
# Postgres, so a thread blocked on a query costs a stack while a worker costs
# a whole Django process. 2 x 8 serves sixteen concurrent requests for the
# same memory that 2 x 4 served eight.
def _available_cpus() -> float:
    """What this container may actually use, not what the host has."""
    try:  # cgroup v2
        with open("/sys/fs/cgroup/cpu.max", encoding="utf-8") as handle:
            quota, period = handle.read().split()
        if quota != "max":
            return max(1.0, int(quota) / int(period))
    except (OSError, ValueError):
        pass
    try:  # cgroup v1
        with open("/sys/fs/cgroup/cpu/cpu.cfs_quota_us", encoding="utf-8") as handle:
            quota = int(handle.read())
        with open("/sys/fs/cgroup/cpu/cpu.cfs_period_us", encoding="utf-8") as handle:
            period = int(handle.read())
        if quota > 0:
            return max(1.0, quota / period)
    except (OSError, ValueError):
        pass
    return float(os.cpu_count() or 2)


def _default_workers() -> int:
    """One per available CPU, floor 2, cap 4.

    Deliberately NOT cpus + 1. On the current 2 vCPU droplet this returns 2,
    which is exactly what was running before - raising it to 3 would spend
    another whole Django process out of a 900 MB limit to serve a single shop,
    and this box runs out of memory long before it runs out of CPU. The
    capacity increase here comes from threads.

    What changes is what happens on a bigger machine: the count now follows
    the container's real allowance instead of the host's core count, so moving
    to a 4 vCPU droplet raises it without anyone remembering to."""
    return max(2, min(4, int(_available_cpus())))


workers = int(os.getenv("GUNICORN_WORKERS", str(_default_workers())))
threads = int(os.getenv("GUNICORN_THREADS", "8"))
worker_class = "gthread"
# Recycle workers periodically so a slow leak cannot grow unbounded on a box
# with little headroom. The jitter stops all workers restarting together.
max_requests = 1000
max_requests_jitter = 100

# Timeout for workers
timeout = 120
keepalive = 5

# Logging
accesslog = "-"
errorlog = "-"
loglevel = os.getenv("GUNICORN_LOG_LEVEL", "info")

# OpenTelemetry configuration hooking could go here if needed in post_fork
def post_fork(server, worker):
    server.log.info("Worker spawned (pid: %s)", worker.pid)

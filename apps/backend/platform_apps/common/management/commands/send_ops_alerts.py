"""Email the operator when something is wrong, before a shopkeeper phones.

Scope, stated honestly: this runs ON the droplet, so it cannot detect the
droplet being down — if the box dies, so does this cron job. External uptime
needs an external monitor (UptimeRobot's free tier, or DigitalOcean
monitoring). What this catches is everything that degrades while the machine is
still up, which is most of what actually goes wrong: a database that stopped
answering, backups that silently stopped running, a disk filling toward the
write-stop, and billing drifting out of step.

Deduped with a state file so an ongoing problem emails once a day rather than
once an hour, and a recovery is reported so silence is never ambiguous.
"""
from __future__ import annotations

import json
import logging
import os
import shutil
import time
from datetime import timedelta
from pathlib import Path

from django.core.management.base import BaseCommand
from django.utils import timezone
from django.db import connection

from platform_apps.common.emailer import resend_api_key, send_email

logger = logging.getLogger(__name__)

STATE_FILE = Path(os.getenv("OPS_ALERT_STATE_FILE", "/tmp/bhub-ops-alerts.json"))

#: Re-send a still-active alert once a day. Hourly would train the operator to
#: filter the sender, which is the same as having no alerting at all.
REPEAT_AFTER_SECONDS = 24 * 60 * 60

#: Backups run daily. Two days without one means yesterday's failed silently.
BACKUP_STALE_HOURS = 48
BACKUP_MIN_BYTES = 10_000
#: A missed month plus a few days. The drill runs monthly, so anything
#: tighter fires because cron ran late or the box was rebooted, and an
#: alert that cries wolf on a schedule is worse than no alert at all.
DRILL_STALE_DAYS = 35
#: How far back the money reconciliation looks. Two days covers last
#: night's jobs and today's trading without re-reading a shop's history
#: every hour.
MONEY_CHECK_DAYS = 2
DISK_WARN_PERCENT = 85


def _alert_email() -> str:
    return (
        os.getenv("OPS_ALERT_EMAIL", "") or os.getenv("BOOTSTRAP_ADMIN_EMAIL", "")
    ).strip()


def _check_database() -> str | None:
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        return None
    except Exception as exc:
        return f"The database is not answering: {exc}"


def _check_backups() -> str | None:
    backup_dir = Path(os.getenv("BACKUP_DIR", "/var/backups/bhub"))
    # Recursive. backup_db.sh writes into daily/ and weekly/ subdirectories,
    # and the first version of this globbed the top level only — so it reported
    # "no backup found" while backups were running perfectly, which is worse
    # than no alerting: a daily false alarm teaches the operator to filter the
    # sender, and the real one then goes unread too.
    candidates = [
        path
        for pattern in ("**/*.sql", "**/*.dump", "**/*.sql.gz")
        for path in backup_dir.glob(pattern)
        if path.is_file()
    ]
    # Manual dumps land here; the restore drill reads them too.
    candidates += [p for p in Path("/root").glob("bhub-*.sql") if p.is_file()]
    candidates += [p for p in Path("/root").glob("bhub-*.dump") if p.is_file()]
    if not candidates:
        return f"No database backup found in {backup_dir} or /root."

    newest = max(candidates, key=lambda p: p.stat().st_mtime)
    age_hours = (time.time() - newest.stat().st_mtime) / 3600
    if age_hours > BACKUP_STALE_HOURS:
        return (
            f"The newest backup is {age_hours:.0f} hours old ({newest.name}). "
            "The backup job has stopped running."
        )
    if newest.stat().st_size < BACKUP_MIN_BYTES:
        return (
            f"The newest backup {newest.name} is only {newest.stat().st_size} "
            "bytes. It is almost certainly truncated."
        )
    return None


def _check_restore_drill() -> str | None:
    """Has anyone proved a backup restores lately?

    A backup that exists and a backup that restores are different claims, and
    only the second one matters on the day it is needed. The drill proves the
    second, writes a stamp, and runs monthly from cron.

    Watched here because a monthly manual task is a task that gets done once.
    Without this, the honest description of the drill would be "we ran it in
    August 2026" - and nobody would know that was the description.

    The threshold allows a full missed month plus a few days: this must fire
    when the job has genuinely stopped, not because a cron ran late or the
    droplet was rebooted on the wrong day. A monthly check that alarms
    spuriously gets filtered, and then the real one goes unread too.
    """
    backup_dir = Path(os.getenv("BACKUP_DIR", "/var/backups/bhub"))
    stamp = backup_dir / ".last_drill"

    if not stamp.exists():
        return (
            "No backup restore has ever been verified. Run "
            "scripts/go-live/restore-drill.sh - it restores into a throwaway "
            "database and never touches production."
        )

    try:
        last = float(stamp.read_text().strip())
    except (OSError, ValueError):
        # An unreadable stamp is not proof of a recent drill, and must not be
        # read as one. Failing toward "check it" is the whole point of this.
        return f"The restore drill stamp at {stamp} could not be read."

    age_days = (time.time() - last) / 86400
    if age_days > DRILL_STALE_DAYS:
        return (
            f"No backup restore has been verified for {age_days:.0f} days. "
            "The monthly restore drill has stopped running, so nobody knows "
            "whether these backups still restore."
        )
    return None


def _check_money_agrees() -> str | None:
    """Do the stored money figures still agree with each other?

    Deliberately a DATA check rather than a report check. A GST table that
    disagrees with its own headline is a code bug: both are computed at read
    time, so it cannot appear without a deploy and `smoke:money` catches it on
    the way out. A customer whose balance stops matching their ledger is a
    data bug, and that can appear at three in the morning from a half-finished
    import or a job that died between two writes - with no deploy involved for
    any check to hang off.

    Recent sales only. This runs hourly against live data, and a shop with
    twenty thousand bills must not be re-read every hour to answer a question
    about today. Anything older has already been examined many times over, and
    a discrepancy that has survived a week is not going to be caught sooner by
    looking again.
    """
    from platform_apps.common import reconcile
    from platform_apps.shops.models import Shop

    since = timezone.localdate() - timedelta(days=MONEY_CHECK_DAYS)
    findings: list[str] = []

    for shop in Shop.objects.all():
        problems = reconcile.shop_problems(shop, since=since, max_reported=5)
        for problem in problems:
            findings.append(f"{shop.name}: {problem}")
        if len(findings) >= 15:
            break

    if not findings:
        return None

    listed = "".join(f"\n  {finding}" for finding in findings[:15])
    return (
        "Stored money figures disagree with each other:"
        + listed
        + "\n\nThese are records contradicting other records, not a report "
        "formatting problem. Each one is a bill or a customer balance that "
        "will be wrong on a screen somebody trusts."
    )


def _check_disk() -> str | None:
    usage = shutil.disk_usage("/")
    percent = usage.used / usage.total * 100
    if percent >= DISK_WARN_PERCENT:
        free_gb = usage.free / 1_000_000_000
        return (
            f"Disk is {percent:.0f}% full ({free_gb:.1f} GB free). Postgres "
            "stops accepting writes when it fills, which stops every shop "
            "trading."
        )
    return None


def _check_billing_drift() -> str | None:
    from platform_apps.billing.models import Subscription

    stuck = [
        s
        for s in Subscription.objects.select_related("shop")
        if not s.has_paid_access()
        and s.shop.settings_json.get("plan_tier") not in (None, "starter")
    ]
    if stuck:
        return (
            f"{len(stuck)} shop(s) have lapsed but still hold paid features. "
            "expire_subscriptions may not be running."
        )
    return None


CHECKS = {
    "database": _check_database,
    "backups": _check_backups,
    "disk": _check_disk,
    "restore_drill": _check_restore_drill,
    "money": _check_money_agrees,
    "billing": _check_billing_drift,
}


def _load_state() -> dict:
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        # A missing or corrupt state file must not stop alerting — the worst it
        # can cause is a repeated alert, which is the safe direction to fail.
        return {}


def _save_state(state: dict) -> None:
    try:
        STATE_FILE.write_text(json.dumps(state))
    except Exception:
        logger.warning(
            "Could not write %s; alerts may repeat.", STATE_FILE, exc_info=True
        )


class Command(BaseCommand):
    help = "Check the deployment and email the operator about anything wrong."

    def add_arguments(self, parser):
        parser.add_argument("--dry-run", action="store_true")
        parser.add_argument(
            "--force",
            action="store_true",
            help="Send even if this alert went out recently. For testing the wiring.",
        )

    def handle(self, *args, **options):
        recipient = _alert_email()
        if not recipient:
            self.stderr.write(
                "No OPS_ALERT_EMAIL (or BOOTSTRAP_ADMIN_EMAIL) set — there is "
                "nobody to alert. Set one in the env file."
            )
            raise SystemExit(1)
        if not resend_api_key() and not options["dry_run"]:
            self.stderr.write(
                "RESEND_API_KEY is not set, so no alert could be delivered."
            )
            raise SystemExit(1)

        state = _load_state()
        now = time.time()
        problems: list[str] = []
        recovered: list[str] = []

        for name, check in CHECKS.items():
            try:
                problem = check()
            except Exception as exc:
                # A broken check is itself worth knowing about. Skipping it
                # silently would make the alerting look healthy while blind.
                problem = f"The {name} check itself failed: {exc}"

            previous = state.get(name, {})
            if problem:
                self.stdout.write(f"PROBLEM {name}: {problem}")
                last_sent = previous.get("last_sent", 0)
                due = options["force"] or (now - last_sent) > REPEAT_AFTER_SECONDS
                if due:
                    problems.append(f"{name}: {problem}")
                    state[name] = {"last_sent": now, "problem": problem}
                else:
                    state[name] = {"last_sent": last_sent, "problem": problem}
            else:
                self.stdout.write(f"ok      {name}")
                if previous.get("problem"):
                    # Report recovery, or the operator never learns whether the
                    # thing they fixed actually got fixed.
                    recovered.append(name)
                state.pop(name, None)

        if not problems and not recovered:
            self.stdout.write("Nothing to report.")
            _save_state(state)
            return

        lines: list[str] = []
        if problems:
            lines.append("Problems:")
            lines += [f"  - {p}" for p in problems]
        if recovered:
            lines.append("Recovered:")
            lines += [f"  - {name}" for name in recovered]
        body = "\n".join(lines)
        subject = (
            f"Business Hub: {len(problems)} problem(s)"
            if problems
            else "Business Hub: recovered"
        )

        self.stdout.write("\n" + body)
        if options["dry_run"]:
            self.stdout.write("\nDry run — nothing sent.")
            return

        result = send_email(
            to=recipient,
            subject=subject,
            html="<pre>" + body + "</pre>",
            text=body,
        )
        self.stdout.write(f"\nSent to {recipient}: {result.get('status', 'unknown')}")
        _save_state(state)

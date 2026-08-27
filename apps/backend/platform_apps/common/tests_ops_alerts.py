"""Alerting that never fires is the same as no alerting.

Nothing told the operator when something broke. The first sign of a failed
backup job or a lapsed-but-unlocked shop was a phone call, or nothing at all.
"""
from __future__ import annotations

import json
import time
from io import StringIO
from unittest.mock import patch

from django.core.management import call_command
from django.test import TestCase

MODULE = "platform_apps.common.management.commands.send_ops_alerts"


class OpsAlertTests(TestCase):
    def setUp(self):
        self.state_file = self.settings  # placeholder to keep linters quiet
        self._patchers = []

    def _run(self, *, state=None, checks=None, **kwargs):
        """Run the command with a temp state file and controllable checks."""
        import tempfile
        from pathlib import Path

        tmp = Path(tempfile.mkdtemp()) / "state.json"
        if state is not None:
            tmp.write_text(json.dumps(state))

        out = StringIO()
        err = StringIO()
        with patch(f"{MODULE}.STATE_FILE", tmp), patch(
            f"{MODULE}._alert_email", return_value="ops@example.com"
        ), patch(f"{MODULE}.resend_api_key", return_value="re_fake"), patch(
            f"{MODULE}.CHECKS", checks if checks is not None else {}
        ), patch(
            f"{MODULE}.send_email"
        ) as send:
            call_command("send_ops_alerts", stdout=out, stderr=err, **kwargs)
        return send, out.getvalue(), tmp

    def test_a_healthy_deployment_sends_nothing(self):
        """An alerting system that emails when nothing is wrong gets filtered,
        and then it is not alerting."""
        send, output, _ = self._run(checks={"disk": lambda: None})

        send.assert_not_called()
        self.assertIn("Nothing to report", output)

    def test_a_problem_is_emailed(self):
        send, _, _ = self._run(checks={"disk": lambda: "Disk is 97% full"})

        send.assert_called_once()
        self.assertIn("97%", send.call_args.kwargs["text"])

    def test_the_same_problem_is_not_emailed_every_hour(self):
        """It runs hourly. Repeating trains the operator to ignore the sender."""
        checks = {"disk": lambda: "Disk is 97% full"}
        _, _, state_path = self._run(checks=checks)
        recent = json.loads(state_path.read_text())

        send, _, _ = self._run(state=recent, checks=checks)

        send.assert_not_called()

    def test_a_day_old_alert_is_repeated(self):
        checks = {"disk": lambda: "Disk is 97% full"}
        stale = {"disk": {"last_sent": time.time() - 90000, "problem": "old"}}

        send, _, _ = self._run(state=stale, checks=checks)

        send.assert_called_once()

    def test_recovery_is_reported(self):
        """Otherwise silence is ambiguous — the operator never learns whether
        the thing they fixed actually got fixed."""
        previous = {"disk": {"last_sent": time.time(), "problem": "Disk is 97% full"}}

        send, _, _ = self._run(state=previous, checks={"disk": lambda: None})

        send.assert_called_once()
        self.assertIn("Recovered", send.call_args.kwargs["text"])

    def test_a_check_that_itself_explodes_is_reported_not_swallowed(self):
        """A broken check would otherwise make the alerting look healthy while
        being blind."""
        def broken():
            raise RuntimeError("boom")

        send, _, _ = self._run(checks={"disk": broken})

        send.assert_called_once()
        self.assertIn("check itself failed", send.call_args.kwargs["text"])

    def test_one_broken_check_does_not_stop_the_others(self):
        def broken():
            raise RuntimeError("boom")

        send, _, _ = self._run(
            checks={"disk": broken, "database": lambda: "DB down"}
        )

        body = send.call_args.kwargs["text"]
        self.assertIn("check itself failed", body)
        self.assertIn("DB down", body)

    def test_dry_run_sends_nothing(self):
        send, output, _ = self._run(
            checks={"disk": lambda: "Disk is 97% full"}, dry_run=True
        )

        send.assert_not_called()
        self.assertIn("Dry run", output)

    def test_it_refuses_to_run_with_nobody_to_alert(self):
        """Silently doing nothing because no recipient was configured is the
        exact failure this command exists to prevent."""
        out, err = StringIO(), StringIO()
        with patch(f"{MODULE}._alert_email", return_value=""):
            with self.assertRaises(SystemExit):
                call_command("send_ops_alerts", stdout=out, stderr=err)
        self.assertIn("nobody to alert", err.getvalue())


class BackupCheckLayoutTests(TestCase):
    """Against the directory layout backup_db.sh actually produces.

    The first version globbed the top level of BACKUP_DIR only. backup_db.sh
    writes into daily/ and weekly/, so it reported "No database backup found"
    while backups were running perfectly — and it emailed that every day. A
    daily false alarm is worse than no alerting: the operator filters the
    sender, and the real alert goes unread too.
    """

    def setUp(self):
        import tempfile
        from pathlib import Path

        self.root = Path(tempfile.mkdtemp())
        (self.root / "daily").mkdir()
        (self.root / "weekly").mkdir()

    def _check(self):
        from platform_apps.common.management.commands import send_ops_alerts

        with patch.dict("os.environ", {"BACKUP_DIR": str(self.root)}):
            return send_ops_alerts._check_backups()

    def _write(self, relative: str, size: int = 2_000_000, age_hours: float = 1):
        import os as _os

        path = self.root / relative
        path.write_bytes(b"x" * size)
        when = time.time() - age_hours * 3600
        _os.utime(path, (when, when))
        return path

    def test_a_fresh_dump_in_the_daily_subdirectory_is_found(self):
        """The exact layout on the droplet:
        /var/backups/bhub/daily/bhub-20260821-044141.dump"""
        self._write("daily/bhub-20260821-044141.dump")

        self.assertIsNone(self._check())

    def test_a_weekly_dump_counts_too(self):
        self._write("weekly/bhub-20260821-044141.dump")

        self.assertIsNone(self._check())

    def test_a_genuinely_empty_backup_dir_still_reports(self):
        """The fix must not make the check unable to fail."""
        self.assertIn("No database backup", self._check() or "")

    def test_a_stale_backup_is_still_reported(self):
        self._write("daily/old.dump", age_hours=100)

        self.assertIn("hours old", self._check() or "")

    def test_a_truncated_backup_is_still_reported(self):
        """A 200-byte dump is a failed dump wearing the right filename."""
        self._write("daily/tiny.dump", size=200)

        self.assertIn("truncated", self._check() or "")

    def test_the_newest_wins_across_subdirectories(self):
        self._write("weekly/old.dump", age_hours=200)
        self._write("daily/new.dump", age_hours=1)

        self.assertIsNone(self._check())


class RestoreDrillCheckTests(TestCase):
    """Nobody knows whether a backup restores until somebody restores one.

    The drill proves it, writes a stamp, and runs monthly from cron. This check
    watches the stamp, because a monthly manual task is a task that happens
    once - and the failure is invisible by construction: the backups keep
    being written, they just stop being proven.

    Every assertion here is about failing toward "go and check", never toward
    silence.
    """

    def setUp(self):
        import tempfile
        from pathlib import Path

        self.root = Path(tempfile.mkdtemp())

    def _check(self):
        from platform_apps.common.management.commands import send_ops_alerts

        with patch.dict("os.environ", {"BACKUP_DIR": str(self.root)}):
            return send_ops_alerts._check_restore_drill()

    def _stamp(self, age_days: float):
        (self.root / ".last_drill").write_text(
            str(time.time() - age_days * 86400), encoding="utf-8"
        )

    def test_a_recent_drill_is_quiet(self):
        self._stamp(age_days=3)
        self.assertIsNone(self._check())

    def test_a_drill_that_has_stopped_is_reported(self):
        self._stamp(age_days=90)
        message = self._check()
        self.assertIsNotNone(message)
        self.assertIn("90 days", message)

    def test_a_late_cron_run_does_not_cry_wolf(self):
        # Monthly means the stamp is routinely a month old. Alerting at 31 days
        # would fire most months, the operator would filter the sender, and the
        # real alert would go unread with it.
        self._stamp(age_days=33)
        self.assertIsNone(self._check())

    def test_never_having_run_is_reported(self):
        # The state every deployment starts in, and the one most likely to be
        # mistaken for health: no alert has ever fired, so nothing looks wrong.
        message = self._check()
        self.assertIsNotNone(message)
        self.assertIn("never", message.lower())

    def test_an_unreadable_stamp_is_not_treated_as_proof(self):
        # A stamp that cannot be parsed says nothing about when the drill last
        # ran. Reading it as "recent" would be the reassuring answer, which is
        # the failure this whole check exists to prevent.
        (self.root / ".last_drill").write_text("not a timestamp", encoding="utf-8")
        self.assertIsNotNone(self._check())

    def test_the_check_is_registered_so_it_actually_runs(self):
        # A check nobody calls is a comment. This is the assertion that would
        # have caught it being written and never wired in.
        from platform_apps.common.management.commands import send_ops_alerts

        self.assertIn("restore_drill", send_ops_alerts.CHECKS)

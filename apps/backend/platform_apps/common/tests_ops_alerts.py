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

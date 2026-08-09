from io import StringIO
from django.core.management import call_command
from django.test import TestCase


class CommandSmokeTest(TestCase):
    def test_command_runs_and_reports(self):
        out = StringIO()
        call_command("send_scheduled_alerts", stdout=out)
        self.assertIn("Checked", out.getvalue())

    def test_forced_slot_is_accepted(self):
        out = StringIO()
        call_command("send_scheduled_alerts", slot="evening", stdout=out)
        self.assertIn("Checked", out.getvalue())

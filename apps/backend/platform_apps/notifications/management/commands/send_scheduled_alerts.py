"""Send the scheduled shop alerts that are due right now.

Run hourly from cron on the droplet:

    0 * * * * cd /opt/bhub && docker compose -f docker-compose.demo.yml \\
        exec -T api python manage.py send_scheduled_alerts

Hourly rather than twice daily on purpose. Shops can sit in different
timezones, the container's clock is UTC, and a missed run should not silently
skip a day. The command works out which shops are due from each shop's own
local time and records what it sent, so running it more often than necessary
costs nothing and running it twice sends nothing twice.

A Celery beat schedule would be the tidier home for this, but the deployment
runs Celery in-process (USE_INMEMORY_CHANNELS=1) with no beat process, so cron
is the mechanism that actually exists.
"""
from django.core.management.base import BaseCommand

from platform_apps.notifications.services import run_due_alerts


class Command(BaseCommand):
    help = "Send due stock (09:00) and takings (21:00) alerts, per shop local time."

    def add_arguments(self, parser):
        parser.add_argument(
            "--slot",
            choices=["morning", "evening"],
            default="",
            help=(
                "Send this slot regardless of the hour. For testing and for "
                "catching up after an outage; the once-a-day guard still applies."
            ),
        )

    def handle(self, *args, **options):
        summary = run_due_alerts(force_slot=options["slot"])
        self.stdout.write(
            self.style.SUCCESS(
                f"Checked {summary['shops']} shop(s): "
                f"{summary['stock']} stock alert(s), "
                f"{summary['sales']} takings alert(s), "
                f"{summary['skipped']} with nothing worth sending."
            )
        )

"""Give every shop a subscription row, so billing can see it at all.

`provision_shop` starts a trial for shops created since billing landed. Shops
created before it have no Subscription row — and `expire_subscriptions`
iterates Subscription.objects, so those shops are invisible to it forever.
Worse, `_subscription_for` in the billing views creates the row lazily on first
page view, which hands a months-old shop a brand-new 30-day trial starting
today.

So the shops most likely to owe money are the ones the system cannot see.

Defaults to --dry-run's cautious sibling: it refuses to guess a trial end date.
You pass one, because only you know what each shop was promised.
"""
from __future__ import annotations

from datetime import timedelta

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from platform_apps.billing.models import Subscription
from platform_apps.shops.models import Shop


class Command(BaseCommand):
    help = "Create missing Subscription rows for shops that predate billing."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="List the shops that would get a subscription, and change nothing.",
        )
        parser.add_argument(
            "--trial-days",
            type=int,
            default=None,
            help=(
                "Days of trial remaining from today. Required unless --dry-run. "
                "Use 0 for a trial that has already ended."
            ),
        )
        parser.add_argument(
            "--from-created",
            action="store_true",
            help=(
                "Measure the trial from each shop's creation date rather than "
                "from today, so an old shop does not get a fresh trial."
            ),
        )

    def handle(self, *args, **options):
        dry_run = options["dry_run"]
        trial_days = options["trial_days"]
        from_created = options["from_created"]

        if not dry_run and trial_days is None:
            # Deliberately fatal rather than defaulted. A wrong trial_ends_at
            # either gives a shop free months or cuts one off mid-trade, and
            # neither is a decision this command should make on its own.
            raise CommandError(
                "--trial-days is required (use --dry-run first to see the shops)."
            )

        missing = [
            shop
            for shop in Shop.objects.all().order_by("created_at")
            if getattr(shop, "subscription", None) is None
        ]

        if not missing:
            self.stdout.write("Every shop already has a subscription. Nothing to do.")
            return

        self.stdout.write(f"{len(missing)} shop(s) without a subscription:")
        now = timezone.now()
        created = 0

        for shop in missing:
            if dry_run:
                self.stdout.write(
                    f"  {shop.name} (created {shop.created_at:%Y-%m-%d}) "
                    f"— tier now: {shop.settings_json.get('plan_tier')}"
                )
                continue

            base = shop.created_at if from_created else now
            ends_at = base + timedelta(days=trial_days)
            subscription = Subscription.objects.create(
                shop=shop,
                status=Subscription.Status.TRIALING,
                trial_ends_at=ends_at,
            )
            # Recompute immediately so an already-lapsed date locks the shop's
            # features now, rather than at the next cron run.
            subscription.refresh_status()
            subscription._sync_shop_plan()
            created += 1
            state = "already lapsed" if ends_at <= now else f"ends {ends_at:%Y-%m-%d}"
            self.stdout.write(f"  {shop.name} — trial {state}")

        if dry_run:
            self.stdout.write(
                "\nDry run. Re-run with --trial-days N (and optionally "
                "--from-created) to write these."
            )
        else:
            self.stdout.write(f"\nCreated {created} subscription(s).")

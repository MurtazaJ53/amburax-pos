"""Tell shopkeepers their trial is ending, before it ends.

Nothing did. days_remaining and expiringSoon existed only inside the billing
page, which is the 16th of 17 sidebar items — so a 30-day trial converted at
roughly the rate of people who happened to click "Subscription & billing".

Run hourly alongside send_scheduled_alerts. Sends at 7, 3 and 1 days out, and
once when access has actually lapsed.
"""
from __future__ import annotations

import logging

from django.core.management.base import BaseCommand
from django.utils import timezone

from platform_apps.billing.models import Subscription
from platform_apps.common.emailer import send_email
from platform_apps.notifications.models import Notification

logger = logging.getLogger(__name__)

#: Days-remaining values that get a nudge. Not every day: a daily email about
#: money is how a sender ends up in spam, and a shopkeeper who is going to pay
#: does not need reminding six times.
REMINDER_DAYS = (7, 3, 1)

LAPSED = "lapsed"


def _milestone(subscription) -> str | None:
    """Which reminder, if any, this subscription is due for right now."""
    if subscription.status in {
        Subscription.Status.EXPIRED,
        Subscription.Status.CANCELLED,
    }:
        return None
    if not subscription.has_paid_access():
        return LAPSED
    remaining = subscription.days_remaining
    return str(remaining) if remaining in REMINDER_DAYS else None


def _already_sent(subscription, milestone: str) -> bool:
    """Whether this exact nudge has gone out already.

    Keyed on the milestone, not on the day, because the command runs hourly —
    without this a shop would get the same "3 days left" email 24 times.
    """
    return Notification.objects.filter(
        shop=subscription.shop,
        metadata_json__billing_reminder=milestone,
    ).exists()


def _copy(subscription, milestone: str) -> tuple[str, str]:
    shop = subscription.shop
    if milestone == LAPSED:
        return (
            f"{shop.name}: your Business Hub plan has ended",
            "Paid features are now locked. Your data is untouched and comes "
            "back the moment you renew.",
        )
    days = int(milestone)
    day_word = "day" if days == 1 else "days"
    return (
        f"{shop.name}: {days} {day_word} left on your Business Hub trial",
        f"Your trial ends in {days} {day_word}. Choose a plan to keep expenses, "
        "attendance and reports switched on. Nothing is deleted if you don't.",
    )


class Command(BaseCommand):
    help = "Email shopkeepers whose trial or paid period is about to end."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Report what would be sent without sending or recording anything.",
        )

    def handle(self, *args, **options):
        dry_run = options["dry_run"]
        sent = 0
        skipped = 0

        queryset = Subscription.objects.select_related("shop", "shop__owner_user")
        for subscription in queryset.iterator():
            milestone = _milestone(subscription)
            if milestone is None:
                continue
            if _already_sent(subscription, milestone):
                skipped += 1
                continue

            owner = subscription.shop.owner_user
            if owner is None or not owner.email:
                # A shop with no reachable owner is a real condition, not a
                # crash — but it must not pass silently, or the first anyone
                # knows is that a customer was never told.
                logger.warning(
                    "Billing reminder %s skipped for shop %s: no owner email.",
                    milestone,
                    subscription.shop_id,
                )
                continue

            subject, body = _copy(subscription, milestone)
            self.stdout.write(f"{subscription.shop.name}: {milestone} -> {owner.email}")
            if dry_run:
                continue

            try:
                send_email(
                    to=owner.email,
                    subject=subject,
                    html=f"<p>{body}</p>",
                    text=body,
                )
            except Exception:
                # The in-app notification is still worth writing: it is the
                # half the shopkeeper sees when they next open the app, and
                # losing it because an email provider was down would make a
                # transient outage permanent.
                logger.error(
                    "Billing reminder email failed for shop %s (%s).",
                    subscription.shop_id,
                    milestone,
                    exc_info=True,
                )

            Notification.objects.create(
                recipient=owner,
                shop=subscription.shop,
                title=subject,
                message=body,
                type=Notification.Type.WARNING,
                action_url="/billing",
                metadata_json={"billing_reminder": milestone},
            )
            sent += 1

        summary = f"Sent {sent} reminder(s); {skipped} already sent."
        self.stdout.write(summary if not dry_run else f"Dry run. {summary}")

"""Scheduled alerts: a stock warning in the morning, the day's takings at night.

Two alerts, chosen deliberately. An alert that fires too often gets muted, and
then the one that mattered is missed too — so this is not a general
notification framework, it is exactly the two moments a shopkeeper asked to be
told about:

  09:00  what has run out or is about to
  21:00  what the day took

Both go only to owners and admins. Cashiers cannot act on either, and the
evening one carries the day's revenue.

Timing is per shop, in the shop's own timezone. Nine in the morning means nine
where the shop is, not nine UTC — which in India would be half past two in the
afternoon.
"""
from __future__ import annotations

import logging
from datetime import date
from decimal import Decimal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.db.models import DecimalField, F, Sum, Value
from django.db.models.functions import Coalesce
from django.utils import timezone

from platform_apps.common.emailer import send_email
from platform_apps.inventory.models import InventoryItem
from platform_apps.notifications.models import Notification
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership

logger = logging.getLogger(__name__)

_ZERO = Decimal("0")

MORNING_HOUR = 9
EVENING_HOUR = 21

#: Matches the reorder report's fallback, so the two cannot disagree about
#: what counts as low.
DEFAULT_REORDER_LEVEL = 5

#: Keys under Shop.settings_json recording the last date each alert was sent,
#: so an hourly cron cannot send the same alert twice.
MORNING_KEY = "alert_stock_last_sent"
EVENING_KEY = "alert_sales_last_sent"


def shop_local_now(shop: Shop):
    try:
        tz = ZoneInfo(shop.timezone or "Asia/Kolkata")
    except (ZoneInfoNotFoundError, ValueError):
        # A shop with a mistyped timezone should still get its alerts rather
        # than silently never being processed.
        tz = ZoneInfo("Asia/Kolkata")
    return timezone.now().astimezone(tz)


def _recipients(shop: Shop):
    """Owners and admins only.

    A cashier can do nothing about a stock warning, and the evening alert
    carries the day's revenue.
    """
    return (
        ShopMembership.objects.filter(
            shop=shop,
            status=ShopMembership.Status.ACTIVE,
            role__in=[ShopMembership.Role.OWNER, ShopMembership.Role.ADMIN],
        )
        .select_related("user")
    )


def _already_sent(shop: Shop, key: str, day: date) -> bool:
    return (getattr(shop, "settings_json", None) or {}).get(key) == day.isoformat()


def _mark_sent(shop: Shop, key: str, day: date) -> None:
    settings_json = dict(getattr(shop, "settings_json", None) or {})
    settings_json[key] = day.isoformat()
    shop.settings_json = settings_json
    shop.save(update_fields=["settings_json", "updated_at"])


def _deliver(shop: Shop, *, title: str, message: str, kind: str, url: str) -> int:
    """One in-app notification per recipient, plus an email where possible.

    The in-app record is created first and unconditionally: email may be
    unconfigured or may bounce, and the alert still has to be findable in the
    app afterwards. That is the "history for anyone who missed it" the review
    asked for, and it comes free from storing the notification.
    """
    sent = 0
    for membership in _recipients(shop):
        Notification.objects.create(
            recipient=membership.user,
            shop=shop,
            title=title,
            message=message,
            type=kind,
            action_url=url,
            metadata_json={"source": "scheduled_alert"},
        )
        sent += 1
        address = (membership.user.email or "").strip()
        if address:
            send_email(
                to=address,
                subject=f"{shop.name} — {title}",
                html=f"<div style='font-family:sans-serif'><h3>{title}</h3>"
                f"<pre style='font-family:inherit;white-space:pre-wrap'>{message}</pre></div>",
                text=message,
            )
    return sent


def build_stock_alert(shop: Shop) -> tuple[str, str] | None:
    """What has run out, and what is about to. None when there is nothing to say.

    Silence is the correct output for a healthy shop. Sending "all good" every
    morning is how an alert becomes noise and then gets muted.
    """
    rows = (
        InventoryItem.objects.filter(shop=shop, tombstone=False)
        .annotate(
            stock=Coalesce(
                Sum("ledger_entries__quantity_delta"),
                Value(_ZERO),
                output_field=DecimalField(max_digits=14, decimal_places=3),
            ),
            level=Coalesce(F("reorder_level"), Value(DEFAULT_REORDER_LEVEL)),
        )
        .filter(stock__lte=F("level"))
        .order_by("stock", "name")
    )

    out_of_stock = [r for r in rows if (r.stock or _ZERO) <= _ZERO]
    low = [r for r in rows if (r.stock or _ZERO) > _ZERO]
    if not out_of_stock and not low:
        return None

    lines = []
    if out_of_stock:
        lines.append(f"Out of stock ({len(out_of_stock)}):")
        for item in out_of_stock[:10]:
            lines.append(f"  • {item.name}")
        if len(out_of_stock) > 10:
            lines.append(f"  …and {len(out_of_stock) - 10} more")
    if low:
        if lines:
            lines.append("")
        lines.append(f"Running low ({len(low)}):")
        for item in low[:10]:
            lines.append(f"  • {item.name} — {item.stock} left")
        if len(low) > 10:
            lines.append(f"  …and {len(low) - 10} more")

    title = (
        f"{len(out_of_stock)} out of stock, {len(low)} running low"
        if out_of_stock
        else f"{len(low)} items running low"
    )
    return title, "\n".join(lines)


def build_sales_alert(shop: Shop, day: date) -> tuple[str, str] | None:
    """The day's takings. None on a day with no trade — nothing worth a message."""
    sales = Sale.objects.filter(shop=shop, sale_date=day, tombstone=False).exclude(
        status=Sale.Status.VOID
    )
    count = sales.count()
    if count == 0:
        return None

    def total(field: str) -> Decimal:
        return sales.aggregate(
            t=Coalesce(
                Sum(field),
                Value(_ZERO),
                output_field=DecimalField(max_digits=14, decimal_places=2),
            )
        )["t"] or _ZERO

    received = total("amount_received")
    due = total("amount_due")
    currency = getattr(shop, "currency_code", "INR")

    lines = [
        f"{count} bill{'' if count == 1 else 's'} today.",
        f"Received: {currency} {received:,.2f}",
    ]
    # Only mentioned when it happened: a shop with no credit sales does not
    # need a zero on the line that matters most to a shop that does.
    if due > _ZERO:
        lines.append(f"On credit (udhaar): {currency} {due:,.2f}")
    return f"Today's takings: {currency} {received:,.2f}", "\n".join(lines)


def run_due_alerts(*, force_slot: str = "") -> dict:
    """Send whatever is due right now, for every shop.

    Written to be run hourly by cron and to be safe if run more often, or
    twice, or after a missed hour: each shop records the date it last received
    each alert, so a second run in the same day sends nothing.
    """
    summary = {"stock": 0, "sales": 0, "shops": 0, "skipped": 0}

    for shop in Shop.objects.filter(status=Shop.Status.ACTIVE):
        local = shop_local_now(shop)
        summary["shops"] += 1

        morning_due = force_slot == "morning" or local.hour == MORNING_HOUR
        evening_due = force_slot == "evening" or local.hour == EVENING_HOUR

        if morning_due and not _already_sent(shop, MORNING_KEY, local.date()):
            built = build_stock_alert(shop)
            if built:
                title, message = built
                _deliver(
                    shop,
                    title=title,
                    message=message,
                    kind=Notification.Type.WARNING,
                    url="/inventory",
                )
                summary["stock"] += 1
            else:
                summary["skipped"] += 1
            # Marked either way: a healthy shop should not be re-checked every
            # hour for the rest of the day.
            _mark_sent(shop, MORNING_KEY, local.date())

        if evening_due and not _already_sent(shop, EVENING_KEY, local.date()):
            built = build_sales_alert(shop, local.date())
            if built:
                title, message = built
                _deliver(
                    shop,
                    title=title,
                    message=message,
                    kind=Notification.Type.INFO,
                    url="/day-book",
                )
                summary["sales"] += 1
            else:
                summary["skipped"] += 1
            _mark_sent(shop, EVENING_KEY, local.date())

    logger.info("Scheduled alerts: %s", summary)
    return summary

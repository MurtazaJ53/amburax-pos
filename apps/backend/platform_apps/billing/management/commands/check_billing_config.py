"""Can this deployment actually take money?

The billing code is complete — idempotent webhooks, HMAC verification, grace
periods, stacking paid periods. None of that matters if the keys are absent:
gateway.is_configured() returns False and SubscriptionCheckoutView answers 503
"contact support", which a shopkeeper reads as "this product cannot take my
money".

Reports readiness without printing a single secret value. Exit code is non-zero
when checkout would fail, so it can gate a deploy.
"""
from __future__ import annotations

from django.conf import settings
from django.core.management.base import BaseCommand

from platform_apps.billing import gateway
from platform_apps.billing.models import Subscription
from platform_apps.shops.models import Shop

OK = "[OK  ]"
FAIL = "[FAIL]"
WARN = "[WARN]"


def _present(name: str) -> bool:
    return bool(getattr(settings, name, ""))


class Command(BaseCommand):
    help = "Report whether this deployment can accept a subscription payment."

    def handle(self, *args, **options):
        blocking = 0

        def line(status: str, text: str, fix: str = "") -> None:
            self.stdout.write(f"{status} {text}")
            if fix:
                self.stdout.write(f"       -> {fix}")

        # --- credentials ---------------------------------------------------
        for name in ("RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET"):
            if _present(name):
                line(OK, f"{name}: set.")
            else:
                blocking += 1
                line(FAIL, f"{name}: missing.", f"Set {name} in the env file.")

        if gateway.is_configured():
            line(OK, "Checkout: the gateway would accept an order.")
        else:
            blocking += 1
            line(
                FAIL,
                "Checkout: disabled. Every payment attempt returns 503.",
                "Set both Razorpay keys, then re-run this.",
            )

        # --- webhook -------------------------------------------------------
        if _present("RAZORPAY_WEBHOOK_SECRET"):
            line(OK, "Webhook secret: set.")
            line(
                WARN,
                "Webhook URL: cannot be verified from here.",
                "Confirm in the Razorpay dashboard that the webhook points at "
                "https://<your-domain>/api/v1/billing/webhook/ — without it a "
                "shop that pays is never activated.",
            )
        else:
            blocking += 1
            line(
                FAIL,
                "RAZORPAY_WEBHOOK_SECRET: missing. Payments would be taken but "
                "never confirmed.",
                "Set it, and register the webhook in the Razorpay dashboard.",
            )

        # --- the shops themselves -------------------------------------------
        total = Shop.objects.count()
        missing = sum(
            1 for shop in Shop.objects.all() if getattr(shop, "subscription", None) is None
        )
        if missing:
            line(
                WARN,
                f"{missing} of {total} shop(s) have no subscription row — billing "
                "cannot see them, and opening /billing grants a fresh trial.",
                "Run: manage.py backfill_subscriptions --dry-run",
            )
        else:
            line(OK, f"All {total} shop(s) have a subscription row.")

        lapsed_but_paid = [
            s
            for s in Subscription.objects.select_related("shop")
            if not s.has_paid_access()
            and s.shop.settings_json.get("plan_tier") not in (None, "starter")
        ]
        if lapsed_but_paid:
            line(
                WARN,
                f"{len(lapsed_but_paid)} shop(s) have lapsed but still hold a paid "
                "tier.",
                "Run: manage.py expire_subscriptions --dry-run",
            )
        else:
            line(OK, "No lapsed shop is holding paid features.")

        self.stdout.write("")
        if blocking:
            self.stderr.write(
                f"{blocking} blocking problem(s). This deployment cannot take money."
            )
            raise SystemExit(1)
        self.stdout.write("Billing is wired. A shop could pay right now.")

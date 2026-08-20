from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.db import models
from django.utils import timezone

from platform_apps.billing.pricing import (
    PAID_PLAN_TIER,
    TRIAL_DAYS,
    UNPAID_PLAN_TIER,
    BillingPeriod,
    days_for,
    price_for,
)
from platform_apps.shops.models import Shop
from platform_apps.shops.plans import PLAN_FEATURE_KEYS


class Subscription(models.Model):
    """One subscription per workspace.

    `status` is the source of truth for what the shop may use; the shop's
    plan_tier is derived from it (see effective_plan_tier), so a lapsed payment
    locks paid features without any data being touched.
    """

    class Status(models.TextChoices):
        TRIALING = "trialing", "Trialing"
        ACTIVE = "active", "Active"
        # Payment window passed but we keep access for a short grace period.
        PAST_DUE = "past_due", "Past due"
        EXPIRED = "expired", "Expired"
        CANCELLED = "cancelled", "Cancelled"

    # How long paid access survives after a period ends, so a slow payment or a
    # delayed webhook never locks a shop out mid-trade.
    GRACE_DAYS = 3

    shop = models.OneToOneField(
        Shop, on_delete=models.CASCADE, related_name="subscription"
    )
    status = models.CharField(
        max_length=16, choices=Status.choices, default=Status.TRIALING
    )
    billing_period = models.CharField(
        max_length=16, choices=BillingPeriod.CHOICES, blank=True
    )
    trial_ends_at = models.DateTimeField(null=True, blank=True)
    current_period_start = models.DateTimeField(null=True, blank=True)
    current_period_end = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"{self.shop} [{self.status}]"

    # --- lifecycle ---------------------------------------------------------

    @classmethod
    def start_trial(cls, shop: Shop) -> "Subscription":
        """Give a brand-new workspace its full-Pro trial."""
        now = timezone.now()
        subscription, created = cls.objects.get_or_create(
            shop=shop,
            defaults={
                "status": cls.Status.TRIALING,
                "trial_ends_at": now + timedelta(days=TRIAL_DAYS),
            },
        )
        if created:
            # A trial is full Pro, so push the entitlement onto the shop (and
            # clear any stale per-feature overrides left by provisioning).
            subscription._sync_shop_plan()
        return subscription

    @property
    def access_until(self):
        """The moment paid access lapses (paid period end, else trial end).

        Deliberately not keyed off `status`: once a lapsed trial moves to
        past_due it is no longer TRIALING, and reading current_period_end (null
        for a never-paid shop) would collapse the grace period to nothing.
        """
        return self.current_period_end or self.trial_ends_at

    @property
    def grace_until(self):
        until = self.access_until
        return None if until is None else until + timedelta(days=self.GRACE_DAYS)

    def has_paid_access(self, at=None) -> bool:
        """True while the shop may use paid features."""
        if self.status in {self.Status.EXPIRED, self.Status.CANCELLED}:
            return False
        moment = at or timezone.now()
        until = self.grace_until
        if until is None:
            return False
        return moment <= until

    @property
    def effective_plan_tier(self) -> str:
        return PAID_PLAN_TIER if self.has_paid_access() else UNPAID_PLAN_TIER

    @property
    def days_remaining(self) -> int:
        until = self.access_until
        if until is None:
            return 0
        delta = until - timezone.now()
        return max(0, delta.days + (1 if delta.seconds else 0))

    def activate_paid_period(self, period: str, *, starting=None) -> None:
        """Apply a successful payment: extend (don't truncate) paid access."""
        now = starting or timezone.now()
        # Stack onto whatever access is still unused, so paying early never
        # costs the customer the days they already bought.
        base = now
        if self.current_period_end and self.current_period_end > now:
            base = self.current_period_end
        elif (
            self.status == self.Status.TRIALING
            and self.trial_ends_at
            and self.trial_ends_at > now
        ):
            base = self.trial_ends_at

        self.billing_period = period
        self.current_period_start = now
        self.current_period_end = base + timedelta(days=days_for(period))
        self.status = self.Status.ACTIVE
        self.cancelled_at = None
        self.save(
            update_fields=[
                "billing_period",
                "current_period_start",
                "current_period_end",
                "status",
                "cancelled_at",
                "updated_at",
            ]
        )
        self._sync_shop_plan()

    def refresh_status(self) -> str:
        """Recompute status against the clock. Returns the new status."""
        now = timezone.now()
        if self.status in {self.Status.CANCELLED, self.Status.EXPIRED}:
            return self.status

        until = self.access_until
        if until is None:
            return self.status

        new_status = self.status
        if now > until + timedelta(days=self.GRACE_DAYS):
            new_status = self.Status.EXPIRED
        elif now > until:
            new_status = self.Status.PAST_DUE

        if new_status != self.status:
            self.status = new_status
            self.save(update_fields=["status", "updated_at"])
            self._sync_shop_plan()
        return self.status

    def _sync_shop_plan(self) -> None:
        """Mirror entitlement onto the shop so feature gates keep working."""
        shop = self.shop
        settings_json = dict(shop.settings_json or {})
        tier = self.effective_plan_tier
        if settings_json.get("plan_tier") == tier:
            return
        settings_json["plan_tier"] = tier
        # A stale per-tier override map would out-rank the new tier, so drop the
        # keys the plan itself decides — and only those. Business-type flags
        # such as weight_selling are deliberately absent from PLAN_FEATURE_KEYS
        # and so survive a downgrade: a grocer who stops paying still has to be
        # able to weigh out dal.
        overrides = settings_json.get("enabled_features")
        if isinstance(overrides, dict):
            for key in PLAN_FEATURE_KEYS:
                overrides.pop(key, None)
            settings_json["enabled_features"] = overrides
        shop.settings_json = settings_json
        shop.save(update_fields=["settings_json"])  # save() clears the cache


class SubscriptionInvoice(models.Model):
    """A payment attempt / receipt for one billing period."""

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        PAID = "paid", "Paid"
        FAILED = "failed", "Failed"
        REFUNDED = "refunded", "Refunded"

    subscription = models.ForeignKey(
        Subscription, on_delete=models.CASCADE, related_name="invoices"
    )
    invoice_number = models.CharField(max_length=32, unique=True)
    billing_period = models.CharField(max_length=16, choices=BillingPeriod.CHOICES)
    # Stored in paise so totals never depend on float arithmetic.
    amount_paise = models.PositiveIntegerField()
    currency = models.CharField(max_length=8, default="INR")
    status = models.CharField(
        max_length=16, choices=Status.choices, default=Status.PENDING
    )

    provider = models.CharField(max_length=32, default="razorpay")
    provider_order_id = models.CharField(max_length=128, blank=True, db_index=True)
    provider_payment_id = models.CharField(max_length=128, blank=True, db_index=True)
    provider_payment_link_id = models.CharField(
        max_length=128, blank=True, db_index=True
    )
    payment_url = models.URLField(blank=True)

    paid_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self) -> str:
        return f"{self.invoice_number} ({self.status})"

    @property
    def amount(self) -> Decimal:
        return (Decimal(self.amount_paise) / Decimal("100")).quantize(Decimal("0.01"))

    @staticmethod
    def rupees_to_paise(amount: Decimal) -> int:
        return int((Decimal(amount) * Decimal("100")).to_integral_value())

    @classmethod
    def open_for(cls, subscription: Subscription, period: str) -> "SubscriptionInvoice":
        amount = price_for(period)
        stamp = timezone.now().strftime("%Y%m%d%H%M%S%f")[:17]
        return cls.objects.create(
            subscription=subscription,
            invoice_number=f"BH-{stamp}",
            billing_period=period,
            amount_paise=cls.rupees_to_paise(amount),
        )

    def mark_paid(self, *, provider_payment_id: str = "") -> bool:
        """Idempotent: a replayed webhook must not extend the period twice."""
        if self.status == self.Status.PAID:
            return False
        self.status = self.Status.PAID
        self.provider_payment_id = provider_payment_id or self.provider_payment_id
        self.paid_at = timezone.now()
        self.save(
            update_fields=[
                "status",
                "provider_payment_id",
                "paid_at",
                "updated_at",
            ]
        )
        return True

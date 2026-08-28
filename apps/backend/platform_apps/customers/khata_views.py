"""Khata collection: who owes money, and who has already been chased.

Udhaar (informal credit) is how most Indian small shops actually trade, and
chasing it is a weekly ritual. The only thing this has to get right is not
nudging the same person twice — a customer chased three times in a day stops
answering the phone, and the shop loses both the money and the customer.
"""
from __future__ import annotations

from decimal import Decimal

from django.db.models import Count, Sum
from django.utils import timezone
from rest_framework import exceptions, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.audit.services import create_workspace_audit_event
from platform_apps.customers.models import Customer
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

#: A shopkeeper's own rhythm: chase again once a week has passed. Mirrors
#: `KhataDebtor.isOverdue` in the mobile app.
OVERDUE_AFTER_DAYS = 7


class DebtorListView(APIView):
    """Everyone carrying a balance, biggest first.

    The list is capped; the figures above it are not.

    That split is the whole design. This screen answers two different
    questions - "how much am I owed" and "who do I chase next" - and only the
    second one is a list. Measured at a thousand debtors this endpoint took
    845ms and returned 227KB because it built, decrypted and serialised every
    single one, with no ceiling: at ten thousand it would have taken eight
    seconds and grown from there forever.

    Capping the list alone would have been worse than leaving it slow. The
    screen counts "N customers owe you" and sizes its "remind everyone" button
    from the rows it was given, so a silent cap would under-collect - the shop
    would chase the first five hundred and believe it had chased everybody.
    So every figure a shopkeeper reads now comes from the database over ALL
    debtors, and the list is explicitly marked when it does not hold them all.
    """

    permission_classes = [permissions.IsAuthenticated]

    #: A collection run is a person working down a list with a phone in their
    #: hand. Five hundred is already more than anyone gets through in a day,
    #: and it keeps the response small enough to arrive quickly.
    DEFAULT_LIMIT = 500
    MAX_LIMIT = 2000

    def get(self, request, shop_id):
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.STAFF
        )

        try:
            limit = int(request.query_params.get("limit") or self.DEFAULT_LIMIT)
        except (TypeError, ValueError):
            limit = self.DEFAULT_LIMIT
        limit = max(1, min(limit, self.MAX_LIMIT))

        owing = Customer.objects.filter(
            shop=membership.shop, tombstone=False, balance__gt=Decimal("0")
        )

        # The money figure, over everyone. Computed in the database rather than
        # summed from the page, because a total that shrinks when a list is
        # capped tells a shopkeeper they are owed less than they are.
        totals = owing.aggregate(owed=Sum("balance"), people=Count("id"))
        total_outstanding = totals["owed"] or Decimal("0.00")
        debtor_count = totals["people"] or 0

        # Also over everyone, and it cannot be a plain SQL count: "has a phone"
        # means ten digits after decryption, and the column is encrypted. One
        # column with no model instantiation is a fraction of the cost of
        # building and serialising every debtor, which is what this used to do.
        unreachable_count = sum(
            1
            for phone in owing.values_list("phone", flat=True)
            if len([ch for ch in (phone or "") if ch.isdigit()]) < 10
        )

        # id last, so two customers owing the same amount with the same name
        # keep a stable order between requests rather than swapping places.
        rows = list(owing.order_by("-balance", "name", "id")[: limit + 1])
        truncated = len(rows) > limit
        rows = rows[:limit]

        now = timezone.now()
        today = timezone.localdate()
        items = []
        for customer in rows:
            reminded_at = customer.last_reminded_at
            days_since = (
                (now - reminded_at).days if reminded_at is not None else None
            )
            phone = (customer.phone or "").strip()
            # "-" is the model's placeholder for "no number recorded".
            digits = "".join(ch for ch in phone if ch.isdigit())
            items.append(
                {
                    "id": str(customer.id),
                    "name": customer.name,
                    "phone": phone if digits else "",
                    "has_phone": len(digits) >= 10,
                    "balance": customer.balance,
                    "last_reminded_at": reminded_at,
                    "days_since_reminder": days_since,
                    # Skip these on a collection run: chasing twice in one day
                    # is how a shop loses a customer.
                    "reminded_today": (
                        reminded_at is not None
                        and timezone.localtime(reminded_at).date() == today
                    ),
                    "is_overdue": (days_since if days_since is not None else 999)
                    >= OVERDUE_AFTER_DAYS,
                }
            )

        return Response(
            {
                "overdue_after_days": OVERDUE_AFTER_DAYS,
                "total_outstanding": total_outstanding,
                "debtor_count": debtor_count,
                "unreachable_count": unreachable_count,
                # Said plainly so the screen can say it too. A list that
                # quietly stops short is how a collection run misses people.
                "showing": len(items),
                "truncated": truncated,
                "items": items,
            }
        )


class CustomerRemindView(APIView):
    """Record that a reminder went out.

    Stored server-side so the owner on the web and the cashier on the phone
    see the same "already chased today" state.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, shop_id, customer_id):
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.STAFF
        )
        customer = Customer.objects.filter(
            shop=membership.shop, pk=customer_id, tombstone=False
        ).first()
        if customer is None:
            raise exceptions.NotFound("Customer not found.")

        previous = customer.last_reminded_at
        customer.last_reminded_at = timezone.now()
        customer.save(update_fields=["last_reminded_at", "updated_at"])

        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=request.user,
            actor_role=membership.role,
            category="customers",
            event_type="customer.reminder.sent",
            entity_type="customer",
            entity_id=customer.id,
            entity_label=customer.name,
            summary=f"Recorded a payment reminder for {customer.name}.",
            source_surface="backend_api",
            before={"last_reminded_at": previous.isoformat() if previous else None},
            after={"last_reminded_at": customer.last_reminded_at.isoformat()},
        )

        return Response(
            {
                "id": str(customer.id),
                "last_reminded_at": customer.last_reminded_at,
            }
        )

"""One person, across the three tables that know about them.

The product could answer "who is on the team", "who worked today" and "who
sold the most" - each on its own screen, each from its own table - and could
not answer "how is Asha doing". That question needs a membership joined to
attendance joined to sales, and nothing joined them.

Attribution for the sales half comes from the authenticated user on each
sale, exactly as the staff-performance report does. A shop where everyone
shares one login will see the owner's name against every bill, which is the
honest answer rather than an invented split.
"""
from __future__ import annotations

from datetime import date as date_cls, timedelta
from decimal import Decimal

from django.db.models import Count, DecimalField, Sum, Value
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import exceptions, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.attendance.models import AttendanceSession
from platform_apps.sales.models import Sale
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

_ZERO = Decimal("0.00")

#: A person's history is read a month or a quarter at a time. Longer windows
#: are allowed but bounded, so one screen cannot ask for a full table scan.
MAX_RANGE_DAYS = 366 * 2


def _parse(raw, field: str, fallback: date_cls) -> date_cls:
    text = str(raw or "").strip()
    if not text:
        return fallback
    try:
        return date_cls.fromisoformat(text)
    except ValueError:
        raise exceptions.ValidationError({field: "Expected YYYY-MM-DD."})


def _money(value) -> Decimal:
    return (value or _ZERO).quantize(Decimal("0.01"))


class TeamMemberHistoryView(APIView):
    """Attendance and selling for one member, over one window."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id, membership_id):
        # Reading one person's hours and takings is a manager's job, not
        # something any signed-in staff member should be able to do about a
        # colleague.
        actor = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.MANAGER
        )
        shop = actor.shop

        member = (
            ShopMembership.objects.filter(shop=shop, pk=membership_id)
            .select_related("user")
            .first()
        )
        if member is None:
            raise exceptions.NotFound("That person is not on this shop's team.")

        today = timezone.localdate()
        date_from = _parse(
            request.query_params.get("date_from"), "date_from", today - timedelta(days=29)
        )
        date_to = _parse(request.query_params.get("date_to"), "date_to", today)
        if date_from > date_to:
            date_from, date_to = date_to, date_from
        if (date_to - date_from).days + 1 > MAX_RANGE_DAYS:
            raise exceptions.ValidationError(
                {"detail": f"Range too long. Ask for {MAX_RANGE_DAYS} days or fewer."}
            )

        sessions = AttendanceSession.objects.filter(
            shop=shop,
            membership=member,
            tombstone=False,
            session_date__gte=date_from,
            session_date__lte=date_to,
        ).order_by("-session_date")

        worked = sessions.filter(
            status__in=[
                AttendanceSession.Status.PRESENT,
                AttendanceSession.Status.HALF_DAY,
            ]
        )
        attendance_totals = worked.aggregate(
            hours=Coalesce(
                Sum("total_hours"),
                Value(_ZERO),
                output_field=DecimalField(max_digits=12, decimal_places=2),
            ),
            overtime=Coalesce(
                Sum("overtime_hours"),
                Value(_ZERO),
                output_field=DecimalField(max_digits=12, decimal_places=2),
            ),
        )
        # A bonus is paid whatever the day was marked, so it is summed over
        # every session rather than only the worked ones.
        bonus = sessions.aggregate(
            total=Coalesce(
                Sum("bonus_amount"),
                Value(_ZERO),
                output_field=DecimalField(max_digits=12, decimal_places=2),
            )
        )["total"]

        by_status = {
            row["status"]: row["count"]
            for row in sessions.values("status").annotate(count=Count("id"))
        }

        # Sales are attributed through the USER, not the membership: a sale
        # records who was signed in, and the same person can hold memberships
        # on more than one shop.
        sales = Sale.objects.filter(
            shop=shop,
            tombstone=False,
            actor_user_id=member.user_id,
            sale_date__gte=date_from,
            sale_date__lte=date_to,
        ).exclude(status=Sale.Status.VOID)
        sales_totals = sales.aggregate(
            bills=Count("id"),
            gross=Coalesce(
                Sum("total_amount"),
                Value(_ZERO),
                output_field=DecimalField(max_digits=14, decimal_places=2),
            ),
            collected=Coalesce(
                Sum("amount_received"),
                Value(_ZERO),
                output_field=DecimalField(max_digits=14, decimal_places=2),
            ),
            discount=Coalesce(
                Sum("discount_amount"),
                Value(_ZERO),
                output_field=DecimalField(max_digits=14, decimal_places=2),
            ),
        )
        bills = sales_totals["bills"] or 0
        gross = _money(sales_totals["gross"])

        present = by_status.get(AttendanceSession.Status.PRESENT, 0)
        half = by_status.get(AttendanceSession.Status.HALF_DAY, 0)
        days_worked = Decimal(present) + (Decimal(half) / 2)

        return Response(
            {
                "membership_id": str(member.id),
                "member_name": member.user.full_name or member.user.email,
                "role": member.role,
                "status": member.status,
                "has_pos_pin": bool(member.pos_pin_hash),
                "from": date_from.isoformat(),
                "to": date_to.isoformat(),
                "attendance": {
                    "present": present,
                    "half_days": half,
                    "leave": by_status.get(AttendanceSession.Status.LEAVE, 0),
                    "absent": by_status.get(AttendanceSession.Status.ABSENT, 0),
                    "days_worked": days_worked,
                    "hours": _money(attendance_totals["hours"]),
                    "overtime": _money(attendance_totals["overtime"]),
                    "bonus": _money(bonus),
                },
                "sales": {
                    "bills": bills,
                    "gross": gross,
                    "collected": _money(sales_totals["collected"]),
                    "discount_given": _money(sales_totals["discount"]),
                    # Null rather than zero when they rang nothing up: an
                    # average of no bills is not zero, it is unanswerable.
                    "average_bill": (
                        (gross / bills).quantize(Decimal("0.01")) if bills else None
                    ),
                    # Takings per day actually worked, which is the figure that
                    # compares two people fairly regardless of shift length.
                    "per_day_worked": (
                        (gross / days_worked).quantize(Decimal("0.01"))
                        if days_worked > 0
                        else None
                    ),
                },
                "recent_sessions": [
                    {
                        "id": str(session.id),
                        "session_date": session.session_date.isoformat(),
                        "status": session.status,
                        "clock_in_at": session.clock_in_at,
                        "clock_out_at": session.clock_out_at,
                        "total_hours": session.total_hours,
                        "overtime_hours": session.overtime_hours,
                        "bonus_amount": session.bonus_amount,
                        "note": session.note,
                    }
                    for session in sessions[:30]
                ],
            }
        )

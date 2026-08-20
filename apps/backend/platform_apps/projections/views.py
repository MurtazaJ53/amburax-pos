from __future__ import annotations

from zoneinfo import ZoneInfo

from django.utils import timezone

from django.core.cache import cache
from rest_framework import permissions
from rest_framework import exceptions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.audit.services import create_workspace_audit_event
from platform_apps.projections.models import ShopDashboardSnapshot
from platform_apps.projections.pulse import build_shop_pulse_snapshot, sync_shop_pulse_signals
from platform_apps.projections.serializers import (
    ShopDashboardSnapshotSerializer,
    ShopPulseSignalSerializer,
    ShopPulseSignalUpdateSerializer,
    ShopPulseSnapshotSerializer,
)
from platform_apps.projections.services import refresh_shop_dashboard_projection
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

_DASHBOARD_CACHE_TTL_SECONDS = 30
_PULSE_CACHE_TTL_SECONDS = 30


def _is_from_a_previous_day(snapshot, shop) -> bool:
    """Whether this snapshot's "today" figures are for a day that has ended.

    A snapshot with no today_date predates the field; treated as stale so the
    first read after deploy rebuilds it rather than serving zeros for figures
    the dashboard now shows prominently.

    Compared in the SHOP's timezone, not the server's. A Kolkata shop cashing
    up at 22:00 IST is still on the previous UTC day, so a UTC comparison would
    call a current snapshot stale every evening and rebuild on every request.
    """
    if snapshot.today_date is None:
        return True
    shop_tz = ZoneInfo(getattr(shop, "timezone", None) or "Asia/Kolkata")
    return snapshot.today_date != timezone.now().astimezone(shop_tz).date()


def _dashboard_cache_key(shop_id: str, *, finance_summary: bool, advanced_reports: bool) -> str:
    return (
        f"shop-dashboard:{shop_id}:"
        f"finance-{int(finance_summary)}:advanced-{int(advanced_reports)}"
    )


def _pulse_cache_key(shop_id: str) -> str:
    return f"shop-pulse:{shop_id}"


class ShopDashboardSnapshotView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(request.user, shop_id, ShopMembership.Role.VIEWER)
        refresh_requested = request.query_params.get("refresh", "").strip().lower() in {"1", "true", "yes"}
        cache_key = _dashboard_cache_key(
            str(membership.shop_id),
            finance_summary=membership.shop.enabled_features.get("finance_summary", False),
            advanced_reports=membership.shop.enabled_features.get("advanced_reports", False),
        )

        if not refresh_requested:
            cached_payload = cache.get(cache_key)
            if cached_payload is not None:
                return Response(cached_payload)

        snapshot = (
            refresh_shop_dashboard_projection(membership.shop)
            if refresh_requested
            else ShopDashboardSnapshot.objects.filter(shop=membership.shop)
            .select_related("shop")
            .prefetch_related("low_stock_preview")
            .first()
        )
        if snapshot is None or _is_from_a_previous_day(snapshot, membership.shop):
            # Rebuilt rather than served stale. Nothing refreshes projections on
            # a schedule — the deployed compose runs no Celery beat — so without
            # this a snapshot built yesterday would keep presenting yesterday's
            # takings as today's. That is a worse failure than the all-time
            # figure it replaced, because the number looks entirely plausible.
            snapshot = refresh_shop_dashboard_projection(membership.shop)

        serializer = ShopDashboardSnapshotSerializer(
            snapshot,
            context={
                "membership": membership,
            },
        )
        payload = serializer.data
        cache.set(cache_key, payload, _DASHBOARD_CACHE_TTL_SECONDS)
        return Response(payload)


class ShopPulseSnapshotView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(request.user, shop_id, ShopMembership.Role.ADMIN)
        refresh_requested = request.query_params.get("refresh", "").strip().lower() in {"1", "true", "yes"}
        cache_key = _pulse_cache_key(str(membership.shop_id))

        if not refresh_requested:
            cached_payload = cache.get(cache_key)
            if cached_payload is not None:
                return Response(cached_payload)

        snapshot = (
            refresh_shop_dashboard_projection(membership.shop)
            if refresh_requested
            else ShopDashboardSnapshot.objects.filter(shop=membership.shop)
            .select_related("shop")
            .prefetch_related("low_stock_preview")
            .first()
        )
        if snapshot is None or _is_from_a_previous_day(snapshot, membership.shop):
            # Rebuilt rather than served stale. Nothing refreshes projections on
            # a schedule — the deployed compose runs no Celery beat — so without
            # this a snapshot built yesterday would keep presenting yesterday's
            # takings as today's. That is a worse failure than the all-time
            # figure it replaced, because the number looks entirely plausible.
            snapshot = refresh_shop_dashboard_projection(membership.shop)

        full_pulse = build_shop_pulse_snapshot(
            membership.shop,
            dashboard_snapshot=snapshot,
            signal_limit=None,
        )
        sync_shop_pulse_signals(
            membership.shop,
            pulse_snapshot=full_pulse,
            now=snapshot.refreshed_at,
        )
        pulse = build_shop_pulse_snapshot(
            membership.shop,
            dashboard_snapshot=snapshot,
        )
        serializer = ShopPulseSnapshotSerializer(pulse)
        payload = serializer.data
        cache.set(cache_key, payload, _PULSE_CACHE_TTL_SECONDS)
        return Response(payload)


class ShopPulseSignalListView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(request.user, shop_id, ShopMembership.Role.ADMIN)
        snapshot = (
            ShopDashboardSnapshot.objects.filter(shop=membership.shop)
            .select_related("shop")
            .prefetch_related("low_stock_preview")
            .first()
        )
        if snapshot is None or _is_from_a_previous_day(snapshot, membership.shop):
            # Rebuilt rather than served stale. Nothing refreshes projections on
            # a schedule — the deployed compose runs no Celery beat — so without
            # this a snapshot built yesterday would keep presenting yesterday's
            # takings as today's. That is a worse failure than the all-time
            # figure it replaced, because the number looks entirely plausible.
            snapshot = refresh_shop_dashboard_projection(membership.shop)
        full_pulse = build_shop_pulse_snapshot(
            membership.shop,
            dashboard_snapshot=snapshot,
            signal_limit=None,
        )
        signals = sync_shop_pulse_signals(
            membership.shop,
            pulse_snapshot=full_pulse,
            now=snapshot.refreshed_at,
        )
        status_filter = request.query_params.get("status", "").strip().lower()
        if status_filter in {"open", "acknowledged", "resolved"}:
            signals = [signal for signal in signals if signal.status == status_filter]
        serializer = ShopPulseSignalSerializer(signals, many=True)
        return Response(serializer.data)


class ShopPulseSignalDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, shop_id, signal_id):
        membership = get_membership_or_403(request.user, shop_id, ShopMembership.Role.ADMIN)
        signal = (
            membership.shop.pulse_signals.select_related(
                "assigned_membership__user",
                "assigned_by_user",
                "acknowledged_by_user",
                "escalated_by_user",
                "resolved_by_user",
            )
            .filter(pk=signal_id)
            .first()
        )
        if signal is None:
            raise exceptions.NotFound("Pulse signal not found.")

        serializer = ShopPulseSignalUpdateSerializer(
            data=request.data or {},
            context={
                "signal": signal,
                "actor_membership": membership,
            },
        )
        serializer.is_valid(raise_exception=True)
        action = serializer.validated_data["action"]
        before = {
            "status": signal.status,
            "assigned_membership_id": signal.assigned_membership_id,
            "assigned_at": signal.assigned_at,
            "assigned_by_user_id": signal.assigned_by_user_id,
            "acknowledged_at": signal.acknowledged_at,
            "is_escalated": signal.is_escalated,
            "escalated_at": signal.escalated_at,
            "escalated_by_user_id": signal.escalated_by_user_id,
            "escalation_note": signal.escalation_note,
            "follow_up_note": signal.follow_up_note,
            "resolved_at": signal.resolved_at,
            "resolution_note": signal.resolution_note,
        }
        signal = serializer.apply(signal=signal, actor_user=request.user)
        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=request.user,
            actor_role=membership.role,
            category="workspace",
            event_type=f"workspace.pulse.{action}",
            entity_type="shop_pulse_signal",
            entity_id=signal.id,
            entity_label=signal.title,
            summary=f"{action.title()} pulse signal {signal.code}.",
            source_surface="pulse_control",
            before=before,
            after={
                "status": signal.status,
                "assigned_membership_id": signal.assigned_membership_id,
                "assigned_at": signal.assigned_at,
                "assigned_by_user_id": signal.assigned_by_user_id,
                "acknowledged_at": signal.acknowledged_at,
                "is_escalated": signal.is_escalated,
                "escalated_at": signal.escalated_at,
                "escalated_by_user_id": signal.escalated_by_user_id,
                "escalation_note": signal.escalation_note,
                "follow_up_note": signal.follow_up_note,
                "resolved_at": signal.resolved_at,
                "resolution_note": signal.resolution_note,
            },
        )
        cache.delete(_pulse_cache_key(str(membership.shop_id)))
        response_serializer = ShopPulseSignalSerializer(signal)
        return Response(response_serializer.data)

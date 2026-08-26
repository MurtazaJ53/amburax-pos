from __future__ import annotations

from django.db.models import Count, Q
from django.utils import timezone
from rest_framework import exceptions
from rest_framework import generics, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.attendance.models import AttendanceSession
from platform_apps.attendance.serializers import (
    AttendanceSessionSerializer,
    AttendanceSessionWriteSerializer,
    AttendanceSummarySerializer,
)
from platform_apps.shops.models import ShopMembership
from platform_apps.common.cursor import CursorListMixin
from platform_apps.shops.permissions import ensure_feature_enabled_or_403, get_membership_or_403


class ShopScopedMixin:
    minimum_role = ShopMembership.Role.VIEWER

    def get_membership(self):
        if not hasattr(self, "_membership_cache"):
            self._membership_cache = get_membership_or_403(
                self.request.user,
                self.kwargs["shop_id"],
                self.minimum_role,
            )
        return self._membership_cache

    def get_membership_map(self):
        if not hasattr(self, "_membership_map_cache"):
            memberships = ShopMembership.objects.select_related("user").filter(
                shop=self.get_membership().shop,
                status=ShopMembership.Status.ACTIVE,
            )
            self._membership_map_cache = {str(membership.id): membership for membership in memberships}
        return self._membership_map_cache


class AttendanceSessionListCreateView(
    CursorListMixin, ShopScopedMixin, generics.ListCreateAPIView
):
    # One row per person per day, forever. A date window narrows it when the
    # screen sends one, and the screen does not have to.
    cursor_field = "session_date"
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = None

    def get_queryset(self):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "attendance")
        queryset = AttendanceSession.objects.filter(shop=membership.shop, tombstone=False).select_related(
            "membership",
            "membership__user",
        )

        date_from = self.request.query_params.get("date_from", "").strip()
        date_to = self.request.query_params.get("date_to", "").strip()
        membership_id = self.request.query_params.get("membership_id", "").strip()
        status_value = self.request.query_params.get("status", "").strip()
        query = self.request.query_params.get("q", "").strip()

        if date_from:
            queryset = queryset.filter(session_date__gte=date_from)
        if date_to:
            queryset = queryset.filter(session_date__lte=date_to)
        if membership_id:
            queryset = queryset.filter(membership_id=membership_id)
        if status_value:
            queryset = queryset.filter(status=status_value)
        if query:
            queryset = queryset.filter(
                Q(membership__user__full_name__icontains=query) | Q(membership__user__email__icontains=query)
            )
        return queryset

    def get_serializer_class(self):
        if self.request.method == "GET":
            return AttendanceSessionSerializer
        return AttendanceSessionWriteSerializer

    def get_serializer_context(self):
        context = super().get_serializer_context()
        ensure_feature_enabled_or_403(self.get_membership(), "attendance")
        context.update(
            {
                "shop": self.get_membership().shop,
                "membership_map": self.get_membership_map(),
            }
        )
        return context

    def perform_create(self, serializer):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "attendance")
        target_membership = self.get_membership_map().get(
            str(serializer.validated_data["membership_id"])
        )
        if target_membership is None:
            raise exceptions.PermissionDenied(
                "Attendance membership is outside this workspace."
            )
        if membership.role not in {
            ShopMembership.Role.OWNER,
            ShopMembership.Role.ADMIN,
        } and target_membership.id != membership.id:
            raise exceptions.PermissionDenied(
                "Daily operators can only mark attendance for themselves."
            )
        serializer.save()


class AttendanceSummaryView(ShopScopedMixin, APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "attendance")
        queryset = AttendanceSession.objects.filter(
            shop=membership.shop,
            tombstone=False,
        )

        date_from = self.request.query_params.get("date_from", "").strip()
        date_to = self.request.query_params.get("date_to", "").strip()
        membership_id = self.request.query_params.get("membership_id", "").strip()
        status_value = self.request.query_params.get("status", "").strip()
        query = self.request.query_params.get("q", "").strip()
        today = self.request.query_params.get("today", "").strip() or str(timezone.localdate())

        if date_from:
            queryset = queryset.filter(session_date__gte=date_from)
        if date_to:
            queryset = queryset.filter(session_date__lte=date_to)
        if membership_id:
            queryset = queryset.filter(membership_id=membership_id)
        if status_value:
            queryset = queryset.filter(status=status_value)
        if query:
            queryset = queryset.filter(
                Q(membership__user__full_name__icontains=query)
                | Q(membership__user__email__icontains=query)
            )

        aggregates = queryset.aggregate(
            total_sessions=Count("id"),
            present_count=Count("id", filter=Q(status=AttendanceSession.Status.PRESENT)),
            leave_count=Count("id", filter=Q(status=AttendanceSession.Status.LEAVE)),
            active_workers_today=Count(
                "id",
                filter=Q(session_date=today)
                & Q(
                    status__in=[
                        AttendanceSession.Status.PRESENT,
                        AttendanceSession.Status.HALF_DAY,
                    ]
                ),
            ),
        )

        serializer = AttendanceSummarySerializer(
            {
                "total_sessions": aggregates["total_sessions"] or 0,
                "present_count": aggregates["present_count"] or 0,
                "leave_count": aggregates["leave_count"] or 0,
                "active_workers_today": aggregates["active_workers_today"] or 0,
            }
        )
        return Response(serializer.data)


class AttendanceSessionDetailView(ShopScopedMixin, generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [permissions.IsAuthenticated]
    lookup_url_kwarg = "attendance_id"
    minimum_role = ShopMembership.Role.ADMIN
    serializer_class = AttendanceSessionWriteSerializer

    def get_queryset(self):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "attendance")
        return AttendanceSession.objects.filter(shop=membership.shop, tombstone=False).select_related(
            "membership",
            "membership__user",
        )

    def get_serializer_context(self):
        context = super().get_serializer_context()
        ensure_feature_enabled_or_403(self.get_membership(), "attendance")
        context.update(
            {
                "shop": self.get_membership().shop,
                "membership_map": self.get_membership_map(),
            }
        )
        return context

    def perform_destroy(self, instance):
        ensure_feature_enabled_or_403(self.get_membership(), "attendance")
        instance.tombstone = True
        instance.save(update_fields=["tombstone", "updated_at"])

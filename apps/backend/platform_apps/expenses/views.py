from __future__ import annotations

from decimal import Decimal

from django.db.models import Count, Sum
from django.db.models import Q
from django.db.models.functions import Coalesce
from rest_framework import generics, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.expenses.models import Expense
from platform_apps.expenses.serializers import ExpenseSerializer, ExpenseSummarySerializer
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


class ExpenseListCreateView(
    CursorListMixin, ShopScopedMixin, generics.ListCreateAPIView
):
    # Newest first, which is the order this screen has always shown. There was
    # no bound at all here: every expense a shop has ever recorded came back in
    # one response, and one row is added every time somebody buys anything.
    cursor_field = "expense_date"
    serializer_class = ExpenseSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = None

    def get_queryset(self):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "expenses")
        queryset = Expense.objects.filter(shop=membership.shop, tombstone=False).select_related("actor_user")

        query = self.request.query_params.get("q", "").strip()
        category = self.request.query_params.get("category", "").strip()
        if query:
            queryset = queryset.filter(
                Q(category__icontains=query) | Q(description__icontains=query) | Q(payment_reference__icontains=query)
            )
        if category:
            queryset = queryset.filter(category__iexact=category)
        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        ensure_feature_enabled_or_403(self.get_membership(), "expenses")
        context.update(
            {
                "shop": self.get_membership().shop,
                "actor": self.request.user,
            }
        )
        return context

    def perform_create(self, serializer):
        membership = get_membership_or_403(
            self.request.user, self.kwargs["shop_id"], ShopMembership.Role.STAFF
        )
        ensure_feature_enabled_or_403(membership, "expenses")
        serializer.save()


class ExpenseSummaryView(ShopScopedMixin, APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "expenses")
        queryset = Expense.objects.filter(
            shop=membership.shop,
            tombstone=False,
        )

        query = self.request.query_params.get("q", "").strip()
        category = self.request.query_params.get("category", "").strip()
        if query:
            queryset = queryset.filter(
                Q(category__icontains=query)
                | Q(description__icontains=query)
                | Q(payment_reference__icontains=query)
            )
        if category:
            queryset = queryset.filter(category__iexact=category)

        aggregates = queryset.aggregate(
            total_entries=Count("id"),
            total_amount=Coalesce(Sum("amount"), Decimal("0.00")),
            unique_categories=Count("category", distinct=True),
        )
        biggest_category_row = (
            queryset.values("category")
            .annotate(total_amount=Coalesce(Sum("amount"), Decimal("0.00")))
            .order_by("-total_amount", "category")
            .first()
        )

        serializer = ExpenseSummarySerializer(
            {
                "total_entries": aggregates["total_entries"] or 0,
                "total_amount": aggregates["total_amount"] or 0,
                "unique_categories": aggregates["unique_categories"] or 0,
                "biggest_category": (
                    biggest_category_row["category"]
                    if biggest_category_row is not None
                    else None
                ),
            }
        )
        return Response(serializer.data)


class ExpenseDetailView(ShopScopedMixin, generics.RetrieveUpdateDestroyAPIView):
    serializer_class = ExpenseSerializer
    permission_classes = [permissions.IsAuthenticated]
    lookup_url_kwarg = "expense_id"
    minimum_role = ShopMembership.Role.STAFF

    def get_queryset(self):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "expenses")
        return Expense.objects.filter(shop=membership.shop, tombstone=False).select_related("actor_user")

    def get_serializer_context(self):
        context = super().get_serializer_context()
        ensure_feature_enabled_or_403(self.get_membership(), "expenses")
        context.update(
            {
                "shop": self.get_membership().shop,
                "actor": self.request.user,
            }
        )
        return context

    def perform_update(self, serializer):
        serializer.save()

    def perform_destroy(self, instance):
        membership = get_membership_or_403(
            self.request.user, self.kwargs["shop_id"], ShopMembership.Role.ADMIN
        )
        ensure_feature_enabled_or_403(membership, "expenses")
        instance.tombstone = True
        instance.save(update_fields=["tombstone", "updated_at"])

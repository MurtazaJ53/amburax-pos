from __future__ import annotations

from decimal import Decimal

from django.db.models import Count, Q, Sum
from django.db.models.functions import Coalesce
from rest_framework import exceptions, generics, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.projections.services import refresh_projection_after_write
from platform_apps.purchases.models import Purchase, Supplier, SupplierLedgerEntry
from platform_apps.purchases.serializers import (
    PurchaseSerializer,
    PurchaseSummarySerializer,
    SupplierLedgerEntrySerializer,
    SupplierSerializer,
    SupplierSummarySerializer,
)
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import ensure_feature_enabled_or_403, get_membership_or_403


class ShopScopedMixin:
    # RBAC default for procurement/payables surfaces: owner/admin only. A cashier
    # (staff) or viewer is blocked from suppliers, purchases and supplier ledgers.
    minimum_role = ShopMembership.Role.ADMIN

    def get_membership(self):
        if not hasattr(self, "_membership_cache"):
            self._membership_cache = get_membership_or_403(
                self.request.user,
                self.kwargs["shop_id"],
                self.minimum_role,
            )
        return self._membership_cache


# --------------------------------------------------------------------------- #
# Suppliers
# --------------------------------------------------------------------------- #
class SupplierListCreateView(ShopScopedMixin, generics.ListCreateAPIView):
    serializer_class = SupplierSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = None

    def get_queryset(self):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "supplier_directory")
        queryset = Supplier.objects.filter(shop=membership.shop, tombstone=False)
        query = self.request.query_params.get("q", "").strip()
        if query:
            queryset = queryset.filter(
                Q(name__icontains=query) | Q(phone__icontains=query) | Q(gstin__icontains=query)
            )
        return queryset.order_by("-balance", "name")

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context.update({"shop": self.get_membership().shop, "actor": self.request.user})
        return context

    def perform_create(self, serializer):
        membership = get_membership_or_403(self.request.user, self.kwargs["shop_id"], ShopMembership.Role.ADMIN)
        ensure_feature_enabled_or_403(membership, "supplier_directory")
        serializer.save()


class SupplierDetailView(ShopScopedMixin, generics.RetrieveUpdateDestroyAPIView):
    serializer_class = SupplierSerializer
    permission_classes = [permissions.IsAuthenticated]
    lookup_url_kwarg = "supplier_id"
    minimum_role = ShopMembership.Role.ADMIN

    def get_queryset(self):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "supplier_directory")
        return Supplier.objects.filter(shop=membership.shop, tombstone=False)

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context.update({"shop": self.get_membership().shop, "actor": self.request.user})
        return context

    def perform_destroy(self, instance):
        membership = get_membership_or_403(self.request.user, self.kwargs["shop_id"], ShopMembership.Role.ADMIN)
        ensure_feature_enabled_or_403(membership, "supplier_directory")
        instance.tombstone = True
        instance.save(update_fields=["tombstone", "updated_at"])


class SupplierLedgerView(ShopScopedMixin, APIView):
    """Chronological payables timeline for one supplier, with a running balance
    computed oldest-to-newest and returned newest-first."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id, supplier_id):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "supplier_directory")
        supplier = Supplier.objects.filter(shop=membership.shop, pk=supplier_id, tombstone=False).first()
        if supplier is None:
            raise exceptions.NotFound("Supplier not found.")

        entries = list(
            SupplierLedgerEntry.objects.filter(supplier=supplier).order_by("occurred_at", "created_at")
        )
        running = Decimal("0.00")
        for entry in entries:
            running += entry.amount_delta
            entry.running_balance = running

        entries.reverse()  # newest-first for display
        serializer = SupplierLedgerEntrySerializer(entries, many=True)
        return Response(
            {
                "supplier_id": str(supplier.id),
                "supplier_name": supplier.name,
                "balance": supplier.balance,
                "entries": serializer.data,
            }
        )


class SupplierSummaryView(ShopScopedMixin, APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "supplier_directory")
        aggregates = Supplier.objects.filter(shop=membership.shop, tombstone=False).aggregate(
            total_suppliers=Count("id"),
            payable_suppliers=Count("id", filter=Q(balance__gt=0)),
            total_outstanding_balance=Coalesce(Sum("balance"), Decimal("0.00")),
            total_purchased=Coalesce(Sum("total_purchased"), Decimal("0.00")),
        )
        serializer = SupplierSummarySerializer(aggregates)
        return Response(serializer.data)


# --------------------------------------------------------------------------- #
# Purchases
# --------------------------------------------------------------------------- #
class PurchaseListCreateView(ShopScopedMixin, generics.ListCreateAPIView):
    serializer_class = PurchaseSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = None

    def get_queryset(self):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "purchase_workflow")
        return (
            Purchase.objects.filter(shop=membership.shop, tombstone=False)
            .select_related("supplier", "actor_user")
            .prefetch_related("items")
        )

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context.update({"shop": self.get_membership().shop, "actor": self.request.user})
        return context

    def perform_create(self, serializer):
        membership = get_membership_or_403(self.request.user, self.kwargs["shop_id"], ShopMembership.Role.ADMIN)
        ensure_feature_enabled_or_403(membership, "purchase_workflow")
        serializer.save()
        # A delivery moves low_stock_items_count, out_of_stock_items_count and
        # projected_sell_value - three of the dashboard's headline figures. The
        # dashboard is a stored snapshot, so without this the homepage still
        # calls an item out of stock after it has been received and put away.
        refresh_projection_after_write(membership.shop, context="a purchase")


class PurchaseDetailView(ShopScopedMixin, generics.RetrieveAPIView):
    serializer_class = PurchaseSerializer
    permission_classes = [permissions.IsAuthenticated]
    lookup_url_kwarg = "purchase_id"

    def get_queryset(self):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "purchase_workflow")
        return (
            Purchase.objects.filter(shop=membership.shop, tombstone=False)
            .select_related("supplier", "actor_user")
            .prefetch_related("items")
        )

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context.update({"shop": self.get_membership().shop, "actor": self.request.user})
        return context


class PurchaseSummaryView(ShopScopedMixin, APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = self.get_membership()
        ensure_feature_enabled_or_403(membership, "purchase_workflow")
        aggregates = Purchase.objects.filter(
            shop=membership.shop, tombstone=False, status=Purchase.Status.COMPLETED
        ).aggregate(
            total_purchases=Count("id"),
            total_spent=Coalesce(Sum("total_amount"), Decimal("0.00")),
            outstanding_payable=Coalesce(Sum("amount_due"), Decimal("0.00")),
        )
        serializer = PurchaseSummarySerializer(aggregates)
        return Response(serializer.data)

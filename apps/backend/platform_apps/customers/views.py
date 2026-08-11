from __future__ import annotations

from decimal import Decimal

from django.db.models import Count, Sum
from django.db.models.functions import Coalesce
from django.db.models import Q
from rest_framework import exceptions, generics, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.audit.services import (
    create_workspace_audit_event,
    snapshot_customer,
    snapshot_customer_ledger_entry,
)
from platform_apps.common.blind_index import generate_blind_index
from platform_apps.common.migration import MigrationDomain
from platform_apps.common.migration_guards import assert_postgres_primary_write_enabled
from platform_apps.common.query import bounded_list_limit
from platform_apps.customers.models import Customer, CustomerLedgerEntry
from platform_apps.customers.serializers import (
    CustomerLedgerEntrySerializer,
    CustomerSerializer,
    CustomerSummarySerializer,
)
from platform_apps.inventory.views import MAX_REPORTED_ERRORS, _row_error
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403, has_feature_enabled


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


class CustomerListCreateView(ShopScopedMixin, generics.ListCreateAPIView):
    serializer_class = CustomerSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = None

    def get_queryset(self):
        membership = self.get_membership()
        queryset = Customer.objects.filter(shop=membership.shop, tombstone=False).order_by("-balance", "name")

        query = self.request.query_params.get("q", "").strip()
        status_value = self.request.query_params.get("status", "").strip()

        if query:
            # The encrypted phone/email columns aren't searchable; match name by
            # substring and phone by exact blind-index hash (indexed, no decrypt).
            filters = Q(name__icontains=query)
            if any(ch.isdigit() for ch in query):
                filters |= Q(phone_hash=generate_blind_index(query))
            queryset = queryset.filter(filters)
        if status_value:
            queryset = queryset.filter(status=status_value)
        return queryset[: bounded_list_limit(self.request.query_params.get("limit"))]

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context.update(
            {
                "shop": self.get_membership().shop,
                "actor": self.request.user,
            }
        )
        return context

    def perform_create(self, serializer):
        membership = get_membership_or_403(self.request.user, self.kwargs["shop_id"], ShopMembership.Role.STAFF)
        assert_postgres_primary_write_enabled(
            shop_id=str(self.kwargs["shop_id"]),
            domain=MigrationDomain.CUSTOMERS,
        )
        serializer.save()
        customer = serializer.instance
        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=self.request.user,
            actor_role=membership.role,
            category="customer",
            event_type="customer.record.created",
            entity_type="customer",
            entity_id=customer.id,
            entity_label=customer.name,
            summary=f"Created customer {customer.name}.",
            source_surface="backend_api",
            after=snapshot_customer(customer),
        )


class CustomerBulkCreateView(ShopScopedMixin, APIView):
    """Create many customers in one request (spreadsheet import). Valid rows are
    saved; invalid rows are skipped and reported."""

    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.STAFF

    def post(self, request, shop_id):
        membership = self.get_membership()
        assert_postgres_primary_write_enabled(
            shop_id=self.kwargs["shop_id"], domain=MigrationDomain.CUSTOMERS
        )
        rows = request.data.get("customers")
        if not isinstance(rows, list) or not rows:
            raise exceptions.ValidationError({"customers": "Provide a non-empty list of customers."})
        if len(rows) > 1000:
            raise exceptions.ValidationError({"customers": "Send at most 1000 customers per request."})
        context = {"shop": membership.shop, "actor": request.user}
        created = 0
        updated = 0
        errors = []
        from django.db import transaction

        with transaction.atomic():
            for idx, raw in enumerate(rows):
                serializer = CustomerSerializer(data=raw, context=context)
                if not serializer.is_valid():
                    errors.append(_row_error(idx, raw, serializer.errors))
                    continue
                data = serializer.validated_data
                phone = str(raw.get("phone") or "").strip()
                existing = None
                if phone:
                    existing = Customer.objects.filter(
                        shop=membership.shop,
                        phone_hash=generate_blind_index(phone),
                        tombstone=False,
                    ).first()
                if existing is not None:
                    # Re-import of a known customer (matched by phone): refresh
                    # name + opening balance instead of creating a duplicate.
                    existing.name = data.get("name", existing.name)
                    if "opening_balance" in data:
                        existing.balance = data["opening_balance"]
                    existing.save(update_fields=["name", "balance", "updated_at"])
                    updated += 1
                else:
                    serializer.save()
                    created += 1
        return Response(
            {
                "created": created,
                "updated": updated,
                "skipped": len(errors),
                "errors": errors[:MAX_REPORTED_ERRORS],
                "error_count": len(errors),
            },
            status=201,
        )


class CustomerDetailView(ShopScopedMixin, generics.RetrieveUpdateDestroyAPIView):
    serializer_class = CustomerSerializer
    permission_classes = [permissions.IsAuthenticated]
    lookup_url_kwarg = "customer_id"

    def get_queryset(self):
        membership = self.get_membership()
        return Customer.objects.filter(shop=membership.shop, tombstone=False)

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context.update(
            {
                "shop": self.get_membership().shop,
                "actor": self.request.user,
            }
        )
        return context

    def perform_update(self, serializer):
        membership = get_membership_or_403(self.request.user, self.kwargs["shop_id"], ShopMembership.Role.STAFF)
        before_snapshot = snapshot_customer(serializer.instance)
        assert_postgres_primary_write_enabled(
            shop_id=str(self.kwargs["shop_id"]),
            domain=MigrationDomain.CUSTOMERS,
        )
        serializer.save()
        customer = serializer.instance
        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=self.request.user,
            actor_role=membership.role,
            category="customer",
            event_type="customer.record.updated",
            entity_type="customer",
            entity_id=customer.id,
            entity_label=customer.name,
            summary=f"Updated customer {customer.name}.",
            source_surface="backend_api",
            before=before_snapshot,
            after=snapshot_customer(customer),
        )

    def perform_destroy(self, instance):
        membership = get_membership_or_403(self.request.user, self.kwargs["shop_id"], ShopMembership.Role.ADMIN)
        before_snapshot = snapshot_customer(instance)
        assert_postgres_primary_write_enabled(
            shop_id=str(self.kwargs["shop_id"]),
            domain=MigrationDomain.CUSTOMERS,
        )
        instance.tombstone = True
        instance.status = Customer.Status.ARCHIVED
        instance.save(update_fields=["tombstone", "status", "updated_at"])
        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=self.request.user,
            actor_role=membership.role,
            category="customer",
            event_type="customer.record.archived",
            entity_type="customer",
            entity_id=instance.id,
            entity_label=instance.name,
            summary=f"Archived customer {instance.name}.",
            source_surface="backend_api",
            before=before_snapshot,
            after=snapshot_customer(instance),
        )


class CustomerLedgerListCreateView(ShopScopedMixin, generics.ListCreateAPIView):
    serializer_class = CustomerLedgerEntrySerializer
    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.VIEWER
    pagination_class = None

    def get_customer(self):
        if not hasattr(self, "_customer_cache"):
            membership = self.get_membership()
            customer = Customer.objects.filter(
                shop=membership.shop,
                pk=self.kwargs["customer_id"],
                tombstone=False,
            ).first()
            if customer is None:
                raise exceptions.NotFound("Customer not found.")
            self._customer_cache = customer
        return self._customer_cache

    def get_queryset(self):
        return CustomerLedgerEntry.objects.filter(customer=self.get_customer()).select_related("actor_user")

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context.update(
            {
                "shop": self.get_membership().shop,
                "customer": self.get_customer(),
                "actor": self.request.user,
            }
        )
        return context

    def perform_create(self, serializer):
        membership = get_membership_or_403(self.request.user, self.kwargs["shop_id"], ShopMembership.Role.STAFF)
        assert_postgres_primary_write_enabled(
            shop_id=str(self.kwargs["shop_id"]),
            domain=MigrationDomain.CUSTOMER_LEDGER,
        )
        serializer.save()
        entry = serializer.instance
        entry = CustomerLedgerEntry.objects.select_related("customer").get(pk=entry.pk)
        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=self.request.user,
            actor_role=membership.role,
            category="customer",
            event_type="customer.ledger.entry_created",
            entity_type="customer_ledger_entry",
            entity_id=entry.id,
            entity_label=entry.customer.name,
            summary=f"Created customer ledger entry for {entry.customer.name}.",
            source_surface="backend_api",
            after=snapshot_customer_ledger_entry(entry),
        )


class CustomerLedgerTimelineView(ShopScopedMixin, APIView):
    """Khata timeline for one customer: credit sales, payments and adjustments
    in chronological order with a running balance (oldest-to-newest), returned
    newest-first for display."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id, customer_id):
        membership = self.get_membership()
        customer = Customer.objects.filter(
            shop=membership.shop, pk=customer_id, tombstone=False
        ).first()
        if customer is None:
            raise exceptions.NotFound("Customer not found.")

        entries = list(
            CustomerLedgerEntry.objects.filter(customer=customer)
            .select_related("actor_user")
            .order_by("occurred_at", "created_at")
        )
        running = Decimal("0.00")
        timeline = []
        for entry in entries:
            running += entry.amount_delta
            actor_name = None
            if entry.actor_user_id:
                actor_name = entry.actor_user.full_name or entry.actor_user.email
            timeline.append(
                {
                    "id": str(entry.id),
                    "event_type": entry.event_type,
                    "amount_delta": entry.amount_delta,
                    "total_spent_delta": entry.total_spent_delta,
                    "note": entry.note,
                    "occurred_at": entry.occurred_at,
                    "running_balance": running,
                    "actor_name": actor_name,
                }
            )
        timeline.reverse()
        return Response(
            {
                "customer_id": str(customer.id),
                "customer_name": customer.name,
                "balance": customer.balance,
                "total_spent": customer.total_spent,
                "entries": timeline,
            }
        )


class CustomerSummaryView(ShopScopedMixin, APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = self.get_membership()
        queryset = Customer.objects.filter(shop=membership.shop, tombstone=False)
        aggregates = queryset.aggregate(
            total_customers=Count("id"),
            active_credit_customers=Count("id", filter=Q(balance__gt=0)),
            total_outstanding_balance=Coalesce(Sum("balance"), Decimal("0.00")),
            total_lifetime_spend=Coalesce(Sum("total_spent"), Decimal("0.00")),
        )

        payload = {
            "total_customers": aggregates["total_customers"] or 0,
            "active_credit_customers": aggregates["active_credit_customers"] or 0,
            "total_outstanding_balance": aggregates["total_outstanding_balance"] or Decimal("0.00"),
            "total_lifetime_spend": (
                aggregates["total_lifetime_spend"] or Decimal("0.00")
                if has_feature_enabled(membership, "advanced_reports")
                else None
            ),
        }

        serializer = CustomerSummarySerializer(payload)
        return Response(serializer.data)

from __future__ import annotations

from decimal import Decimal

from django.db import transaction
from django.db.models import Exists, OuterRef, Q
from django.db.models import Count
from django.db.models import Sum
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import exceptions, generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.audit.services import create_workspace_audit_event, snapshot_inventory_item
from platform_apps.common.migration import MigrationDomain
from platform_apps.common.migration_guards import assert_postgres_primary_write_enabled
from platform_apps.common.cursor import CursorListMixin
from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.inventory.serializers import (
    InventoryAdjustmentSerializer,
    InventoryItemSerializer,
    InventorySummarySerializer,
)
from platform_apps.shops.models import ShopMembership
from platform_apps.common.import_undo import batch_for, record_rows, tag_for
from platform_apps.common.models import ImportBatch
from platform_apps.projections.services import refresh_projection_after_write
from platform_apps.shops.permissions import (
    ROLE_ORDER,
    get_membership_or_403,
    has_feature_enabled,
)


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

    def can_view_costs(self) -> bool:
        return ROLE_ORDER[self.get_membership().role] >= ROLE_ORDER[ShopMembership.Role.ADMIN]

    def can_view_supplier_directory(self) -> bool:
        membership = self.get_membership()
        return (
            ROLE_ORDER[membership.role] >= ROLE_ORDER[ShopMembership.Role.ADMIN]
            and has_feature_enabled(membership, "supplier_directory")
        )

    def can_view_purchase_workflow(self) -> bool:
        membership = self.get_membership()
        return (
            ROLE_ORDER[membership.role] >= ROLE_ORDER[ShopMembership.Role.ADMIN]
            and has_feature_enabled(membership, "purchase_workflow")
        )

    def assert_inventory_postgres_write_enabled(self) -> None:
        assert_postgres_primary_write_enabled(
            shop_id=self.kwargs["shop_id"],
            domain=MigrationDomain.INVENTORY,
        )


class InventoryItemListCreateView(
    CursorListMixin, ShopScopedMixin, generics.ListCreateAPIView
):
    # Alphabetical, which is the order this list has always shown and the one
    # a shopkeeper scans by eye. Ascending, so paging carries on down the
    # alphabet rather than jumping.
    cursor_field = "name"
    cursor_descending = False
    serializer_class = InventoryItemSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = None

    def get_queryset(self):
        membership = self.get_membership()
        queryset = (
            InventoryItem.objects.filter(shop=membership.shop, tombstone=False)
            .select_related("private")
            .annotate(
                stock_on_hand=Coalesce(Sum("ledger_entries__quantity_delta"), Decimal("0")),
                # Has this item EVER been given stock? Any positive movement
                # counts - opening balance, purchase, transfer in, a manual
                # correction upwards. Asked as "was there ever an inbound
                # entry" rather than by listing event types, so a new kind of
                # inbound cannot silently fall outside it.
                #
                # This is what separates "the shelf is empty" from "nobody ever
                # told us about this item". Without it a zero means both, and a
                # negative reads as a shortfall for an item that was never
                # counted in the first place.
                has_stock_history=Exists(
                    InventoryStockLedger.objects.filter(
                        item=OuterRef("pk"), quantity_delta__gt=0
                    )
                ),
            )
            .order_by("name", "created_at")
        )
        query = self.request.query_params.get("q", "").strip()
        category = self.request.query_params.get("category", "").strip()
        status_value = self.request.query_params.get("status", "").strip()

        if query:
            queryset = queryset.filter(
                Q(name__icontains=query) | Q(sku__icontains=query) | Q(barcode__icontains=query)
            )
        if category:
            queryset = queryset.filter(category__iexact=category)
        if status_value:
            queryset = queryset.filter(status=status_value)
        # No slice: CursorListMixin pages this now, so a catalogue past the
        # old five-hundred ceiling is fully reachable instead of just ending.
        return queryset

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context.update(
            {
                "shop": self.get_membership().shop,
                "actor": self.request.user,
                "can_view_costs": self.can_view_costs(),
                "can_view_supplier_directory": self.can_view_supplier_directory(),
                "can_view_purchase_workflow": self.can_view_purchase_workflow(),
            }
        )
        return context

    def perform_create(self, serializer):
        membership = get_membership_or_403(self.request.user, self.kwargs["shop_id"], ShopMembership.Role.STAFF)
        self.assert_inventory_postgres_write_enabled()
        serializer.save()
        item = serializer.instance
        return self._audit_created(membership, item)

    def _audit_created(self, membership, item):
        item = (
            InventoryItem.objects.filter(pk=item.pk)
            .select_related("private")
            .annotate(
                stock_on_hand=Coalesce(Sum("ledger_entries__quantity_delta"), Decimal("0")),
                # Has this item EVER been given stock? Any positive movement
                # counts - opening balance, purchase, transfer in, a manual
                # correction upwards. Asked as "was there ever an inbound
                # entry" rather than by listing event types, so a new kind of
                # inbound cannot silently fall outside it.
                #
                # This is what separates "the shelf is empty" from "nobody ever
                # told us about this item". Without it a zero means both, and a
                # negative reads as a shortfall for an item that was never
                # counted in the first place.
                has_stock_history=Exists(
                    InventoryStockLedger.objects.filter(
                        item=OuterRef("pk"), quantity_delta__gt=0
                    )
                ),
            )
            .get()
        )
        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=self.request.user,
            actor_role=membership.role,
            category="inventory",
            event_type="inventory.item.created",
            entity_type="inventory_item",
            entity_id=item.id,
            entity_label=item.name,
            summary=f"Created inventory item {item.name}.",
            source_surface="backend_api",
            after=snapshot_inventory_item(item),
        )


#: How many failed rows travel back. The count of ALL failures is reported
#: separately, so the caller can say "showing 20 of 340" rather than implying
#: there were only 20.
MAX_REPORTED_ERRORS = 50


def _row_error(index: int, raw: dict, errors: dict) -> dict:
    """Describe a rejected row in terms the person holding the spreadsheet can use.

    A serializer error dict alone is useless to a shopkeeper: it names a field
    and a rule, but not which of two thousand rows it belongs to. Including the
    name and SKU from the row means the row can be found by searching the sheet
    even if the row number has shifted, and the flattened message says what to
    change rather than what validator failed.
    """
    fields = []
    for field, detail in (errors or {}).items():
        if isinstance(detail, (list, tuple)):
            text = "; ".join(str(d) for d in detail)
        else:
            text = str(detail)
        label = "row" if field == "non_field_errors" else field
        fields.append(f"{label}: {text}")

    return {
        "index": index,
        # Whatever identifies the row to a human, taken from the raw input so
        # it survives even when validation rejected the parsed value.
        "name": str((raw or {}).get("name") or "").strip(),
        "sku": str((raw or {}).get("sku") or "").strip(),
        "message": " · ".join(fields) or "Could not be read.",
        "errors": errors,
    }


class InventoryItemBulkCreateView(ShopScopedMixin, APIView):
    """Create many inventory items in one request (spreadsheet import). Valid
    rows are saved; invalid rows are skipped and reported, so one bad row never
    fails the whole batch."""

    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.STAFF

    def post(self, request, shop_id):
        membership = self.get_membership()
        self.assert_inventory_postgres_write_enabled()
        rows = request.data.get("items")
        if not isinstance(rows, list) or not rows:
            raise exceptions.ValidationError({"items": "Provide a non-empty list of items."})
        if len(rows) > 1000:
            raise exceptions.ValidationError({"items": "Send at most 1000 items per request."})
        context = {
            "shop": membership.shop,
            "actor": request.user,
            "can_view_costs": self.can_view_costs(),
            "can_view_supplier_directory": False,
            "can_view_purchase_workflow": False,
        }
        created = 0
        updated = 0
        errors = []
        # Recorded before the rows so every one of them can point at it. Only
        # rows this import CREATES get tagged - a row it merely updates existed
        # beforehand, and undoing the import must not delete it.
        batch = batch_for(
            membership.shop,
            ImportBatch.Kind.PRODUCTS,
            str(request.data.get("filename") or "")[:255],
            request.user,
        )
        with transaction.atomic():
            for idx, raw in enumerate(rows):
                serializer = InventoryItemSerializer(data=raw, context=context)
                if not serializer.is_valid():
                    errors.append(_row_error(idx, raw, serializer.errors))
                    continue

                # Re-importing the same sheet used to create a second copy of
                # every item. The duplicates started at zero stock and went
                # negative as soon as one was sold, so a shop ended up with
                # several rows for one product and a nonsense stock count.
                # Match an existing item by SKU, else by name (+ size).
                data = serializer.validated_data
                sku = str(raw.get("sku") or "").strip()
                name = str(raw.get("name") or "").strip()
                size = str(raw.get("size") or "").strip()

                existing = None
                base = InventoryItem.objects.filter(
                    shop=membership.shop, tombstone=False
                )
                if sku:
                    existing = base.filter(sku__iexact=sku).first()
                if existing is None and name:
                    existing = base.filter(name__iexact=name, size__iexact=size).first()

                if existing is not None:
                    for field in (
                        "name",
                        "sell_price",
                        "category",
                        "subcategory",
                        "size",
                        "description",
                        "hsn_code",
                        "gst_rate",
                        "price_includes_tax",
                    ):
                        if field in data:
                            setattr(existing, field, data[field])
                    existing.save()
                    updated += 1
                else:
                    item = serializer.save()
                    # Tagged after saving rather than through the serializer:
                    # these are not fields a caller may set, and letting them
                    # arrive in a payload would let anyone claim a row belongs
                    # to somebody else's import.
                    for field, value in tag_for(batch, idx + 1).items():
                        setattr(item, field, value)
                    item.save(update_fields=["source_system", "source_path", "source_id"])
                    created += 1
        if created or updated:
            refresh_projection_after_write(
                membership.shop, context="an inventory import"
            )
        # Added to, not overwritten: a large file arrives as several chunks
        # that all belong to the same batch, and the last one must not wipe
        # what the earlier ones recorded.
        record_rows(batch, rows=len(rows), created=created)
        batch.refresh_from_db()

        return Response(
            {
                # Handed back so the screen can offer to undo this exact
                # import rather than "the last one", which is ambiguous the
                # moment two people import at once.
                "batch_id": str(batch.id),
                "created": created,
                "updated": updated,
                "skipped": len(errors),
                # Capped so a wholly malformed sheet cannot return megabytes,
                # but the true count travels separately -- "showing 20 of 340"
                # is actionable, "20 errors" when there were 340 is a lie.
                "errors": errors[:MAX_REPORTED_ERRORS],
                "error_count": len(errors),
            },
            status=status.HTTP_201_CREATED,
        )


class InventoryItemDetailView(ShopScopedMixin, generics.RetrieveUpdateDestroyAPIView):
    serializer_class = InventoryItemSerializer
    permission_classes = [permissions.IsAuthenticated]
    lookup_url_kwarg = "item_id"

    def get_queryset(self):
        membership = self.get_membership()
        return (
            InventoryItem.objects.filter(shop=membership.shop)
            .select_related("private")
            .annotate(
                stock_on_hand=Coalesce(Sum("ledger_entries__quantity_delta"), Decimal("0")),
                # Has this item EVER been given stock? Any positive movement
                # counts - opening balance, purchase, transfer in, a manual
                # correction upwards. Asked as "was there ever an inbound
                # entry" rather than by listing event types, so a new kind of
                # inbound cannot silently fall outside it.
                #
                # This is what separates "the shelf is empty" from "nobody ever
                # told us about this item". Without it a zero means both, and a
                # negative reads as a shortfall for an item that was never
                # counted in the first place.
                has_stock_history=Exists(
                    InventoryStockLedger.objects.filter(
                        item=OuterRef("pk"), quantity_delta__gt=0
                    )
                ),
            )
        )

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context.update(
            {
                "shop": self.get_membership().shop,
                "actor": self.request.user,
                "can_view_costs": self.can_view_costs(),
                "can_view_supplier_directory": self.can_view_supplier_directory(),
                "can_view_purchase_workflow": self.can_view_purchase_workflow(),
            }
        )
        return context

    def perform_update(self, serializer):
        membership = get_membership_or_403(self.request.user, self.kwargs["shop_id"], ShopMembership.Role.STAFF)
        before_snapshot = snapshot_inventory_item(serializer.instance)
        self.assert_inventory_postgres_write_enabled()
        serializer.save()
        item = (
            InventoryItem.objects.filter(pk=serializer.instance.pk)
            .select_related("private")
            .annotate(
                stock_on_hand=Coalesce(Sum("ledger_entries__quantity_delta"), Decimal("0")),
                # Has this item EVER been given stock? Any positive movement
                # counts - opening balance, purchase, transfer in, a manual
                # correction upwards. Asked as "was there ever an inbound
                # entry" rather than by listing event types, so a new kind of
                # inbound cannot silently fall outside it.
                #
                # This is what separates "the shelf is empty" from "nobody ever
                # told us about this item". Without it a zero means both, and a
                # negative reads as a shortfall for an item that was never
                # counted in the first place.
                has_stock_history=Exists(
                    InventoryStockLedger.objects.filter(
                        item=OuterRef("pk"), quantity_delta__gt=0
                    )
                ),
            )
            .get()
        )
        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=self.request.user,
            actor_role=membership.role,
            category="inventory",
            event_type="inventory.item.updated",
            entity_type="inventory_item",
            entity_id=item.id,
            entity_label=item.name,
            summary=f"Updated inventory item {item.name}.",
            source_surface="backend_api",
            before=before_snapshot,
            after=snapshot_inventory_item(item),
        )

    @transaction.atomic
    def perform_destroy(self, instance):
        membership = get_membership_or_403(self.request.user, self.kwargs["shop_id"], ShopMembership.Role.ADMIN)
        before_snapshot = snapshot_inventory_item(instance)
        self.assert_inventory_postgres_write_enabled()
        instance.tombstone = True
        instance.status = InventoryItem.Status.ARCHIVED
        instance.save(update_fields=["tombstone", "status", "updated_at"])
        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=self.request.user,
            actor_role=membership.role,
            category="inventory",
            event_type="inventory.item.archived",
            entity_type="inventory_item",
            entity_id=instance.id,
            entity_label=instance.name,
            summary=f"Archived inventory item {instance.name}.",
            source_surface="backend_api",
            before=before_snapshot,
            after=snapshot_inventory_item(instance),
        )


class InventorySummaryView(ShopScopedMixin, APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = self.get_membership()
        queryset = (
            InventoryItem.objects.filter(shop=membership.shop, tombstone=False)
            .annotate(
                stock_on_hand=Coalesce(Sum("ledger_entries__quantity_delta"), Decimal("0")),
                # Has this item EVER been given stock? Any positive movement
                # counts - opening balance, purchase, transfer in, a manual
                # correction upwards. Asked as "was there ever an inbound
                # entry" rather than by listing event types, so a new kind of
                # inbound cannot silently fall outside it.
                #
                # This is what separates "the shelf is empty" from "nobody ever
                # told us about this item". Without it a zero means both, and a
                # negative reads as a shortfall for an item that was never
                # counted in the first place.
                has_stock_history=Exists(
                    InventoryStockLedger.objects.filter(
                        item=OuterRef("pk"), quantity_delta__gt=0
                    )
                ),
            )
        )

        query = self.request.query_params.get("q", "").strip()
        category = self.request.query_params.get("category", "").strip()
        status_value = self.request.query_params.get("status", "").strip()

        if query:
            queryset = queryset.filter(
                Q(name__icontains=query) | Q(sku__icontains=query) | Q(barcode__icontains=query)
            )
        if category:
            queryset = queryset.filter(category__iexact=category)
        if status_value:
            queryset = queryset.filter(status=status_value)

        aggregates = queryset.aggregate(
            total_items=Count("id"),
            available_items=Count("id", filter=Q(stock_on_hand__gt=0)),
            low_stock_items=Count(
                "id",
                filter=Q(stock_on_hand__gt=0) & Q(stock_on_hand__lte=5),
            ),
            out_of_stock_items=Count("id", filter=Q(stock_on_hand__lte=0)),
            categories=Count("category", filter=~Q(category=""), distinct=True),
        )

        projected_sell_value = None
        if has_feature_enabled(membership, "advanced_reports"):
            projected_sell_value = (
                sum(
                    (
                        (item.sell_price or Decimal("0.00")) * item.stock_on_hand
                        for item in queryset
                    ),
                    Decimal("0.00"),
                )
            ).quantize(Decimal("0.01"))

        serializer = InventorySummarySerializer(
            {
                "total_items": aggregates["total_items"] or 0,
                "available_items": aggregates["available_items"] or 0,
                "low_stock_items": aggregates["low_stock_items"] or 0,
                "out_of_stock_items": aggregates["out_of_stock_items"] or 0,
                "categories": aggregates["categories"] or 0,
                "projected_sell_value": projected_sell_value,
            }
        )
        return Response(serializer.data)


class InventoryItemAdjustmentView(ShopScopedMixin, APIView):
    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.STAFF

    def post(self, request, shop_id, item_id):
        membership = self.get_membership()
        self.assert_inventory_postgres_write_enabled()
        item = InventoryItem.objects.filter(shop=membership.shop, pk=item_id, tombstone=False).first()
        if item is None:
            raise exceptions.NotFound("Inventory item not found.")

        serializer = InventoryAdjustmentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payload = serializer.validated_data

        ledger = InventoryStockLedger.objects.create(
            shop=membership.shop,
            item=item,
            actor_user=request.user,
            event_type=payload["event_type"],
            quantity_delta=payload["quantity_delta"],
            unit_price=item.sell_price,
            note=payload.get("note", ""),
            occurred_at=timezone.now(),
        )

        current_stock = (
            item.ledger_entries.aggregate(total=Coalesce(Sum("quantity_delta"), Decimal("0")))["total"]
        )
        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=request.user,
            actor_role=membership.role,
            category="inventory",
            event_type="inventory.stock.adjusted",
            entity_type="inventory_item",
            entity_id=item.id,
            entity_label=item.name,
            summary=f"Adjusted stock for {item.name} by {payload['quantity_delta']}.",
            source_surface="backend_api",
            before={"stock_on_hand": (current_stock - payload["quantity_delta"])},
            after={"stock_on_hand": current_stock},
            metadata={
                "ledger_event_id": ledger.id,
                "event_type": payload["event_type"],
                "quantity_delta": payload["quantity_delta"],
                "note": payload.get("note", ""),
            },
        )
        # Stock adjustments move low_stock_items_count, out_of_stock_items_count
        # and projected_sell_value — three of the dashboard's headline figures.
        # They refreshed none of them, so correcting a count in the app left the
        # dashboard still showing the wrong one.
        refresh_projection_after_write(membership.shop, context="a stock adjustment")
        return Response(
            {
                "item_id": str(item.id),
                "ledger_event_id": str(ledger.id),
                "stock_on_hand": current_stock,
            },
            status=status.HTTP_201_CREATED,
        )

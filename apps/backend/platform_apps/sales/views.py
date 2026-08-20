from __future__ import annotations

from decimal import Decimal
import csv
import io
import zipfile
from django.http import HttpResponse

from django.db import transaction
from django.db.models import Q
from django.db.models import Count, Sum
from django.db.models import Prefetch
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import exceptions, generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.audit.services import create_workspace_audit_event, snapshot_sale
from platform_apps.common.migration import MigrationDomain
from platform_apps.common.query import bounded_list_limit
from platform_apps.common.migration_guards import (
    assert_domain_epoch_current,
    assert_postgres_primary_write_enabled_multi,
)
from platform_apps.payments.models import SalePayment
from platform_apps.projections.services import refresh_projection_after_write
from platform_apps.sales.models import Sale, SaleItem
from platform_apps.sales.models import SaleCommandReceipt
from platform_apps.sales.tally import build_tally_xml
from platform_apps.inventory.models import InventoryStockLedger
from platform_apps.customers.models import CustomerLedgerEntry
from platform_apps.sales.serializers import (
    SaleCommandCreateSerializer,
    SaleSerializer,
    SaleSummarySerializer,
    SaleGstSummarySerializer,
)
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


class SaleListCreateView(ShopScopedMixin, generics.ListCreateAPIView):
    serializer_class = SaleSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = None

    def get_queryset(self):
        membership = self.get_membership()
        queryset = (
            Sale.objects.filter(shop=membership.shop, tombstone=False)
            .select_related("actor_user", "customer")
            .prefetch_related(
                Prefetch("items", queryset=SaleItem.objects.select_related("inventory_item").order_by("position", "created_at")),
                Prefetch("payments", queryset=SalePayment.objects.order_by("created_at")),
            )
        )

        query = self.request.query_params.get("q", "").strip()
        date_from = self.request.query_params.get("date_from", "").strip()
        date_to = self.request.query_params.get("date_to", "").strip()
        payment_mode = self.request.query_params.get("payment_mode", "").strip()
        status_value = self.request.query_params.get("status", "").strip()
        customer_id = self.request.query_params.get("customer_id", "").strip()

        if query:
            queryset = queryset.filter(
                Q(receipt_number__icontains=query)
                | Q(customer_name_snapshot__icontains=query)
                | Q(customer_phone_snapshot__icontains=query)
            )
        if date_from:
            queryset = queryset.filter(sale_date__gte=date_from)
        if date_to:
            queryset = queryset.filter(sale_date__lte=date_to)
        if payment_mode:
            queryset = queryset.filter(payment_mode=payment_mode)
        if status_value:
            queryset = queryset.filter(status=status_value)
        if customer_id:
            queryset = queryset.filter(customer_id=customer_id)
        # Voided (refunded) sales stay in the list so History can show them with
        # a REFUNDED badge (they're already excluded from gross/summary totals).
        # Bound the unpaginated list so a huge shop never serializes every
        # sale in one response. Clients read the most-recent slice.
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
        guarded_domains = [
            MigrationDomain.SALES,
            MigrationDomain.PAYMENTS,
            MigrationDomain.STOCK_LEDGER,
        ]
        if self.request.data.get("customer_id"):
            guarded_domains.append(MigrationDomain.CUSTOMER_LEDGER)
        assert_postgres_primary_write_enabled_multi(
            shop_id=str(self.kwargs["shop_id"]),
            domains=guarded_domains,
        )
        serializer.save()
        sale = serializer.instance
        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=self.request.user,
            actor_role=membership.role,
            category="sale",
            event_type="sale.record.created",
            entity_type="sale",
            entity_id=sale.id,
            entity_label=sale.receipt_number,
            summary=f"Created sale {sale.receipt_number}.",
            source_surface="backend_api",
            after=snapshot_sale(sale),
        )


class SaleDetailView(ShopScopedMixin, generics.RetrieveAPIView):
    serializer_class = SaleSerializer
    permission_classes = [permissions.IsAuthenticated]
    lookup_url_kwarg = "sale_id"

    def get_queryset(self):
        membership = self.get_membership()
        return (
            Sale.objects.filter(shop=membership.shop, tombstone=False)
            .select_related("actor_user", "customer")
            .prefetch_related(
                Prefetch("items", queryset=SaleItem.objects.select_related("inventory_item").order_by("position", "created_at")),
                Prefetch("payments", queryset=SalePayment.objects.order_by("created_at")),
            )
        )


class SaleVoidView(ShopScopedMixin, APIView):
    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.STAFF

    def patch(self, request, shop_id, sale_id):
        membership = self.get_membership()
        
        guarded_domains = [MigrationDomain.SALES, MigrationDomain.STOCK_LEDGER, MigrationDomain.CUSTOMER_LEDGER]
        assert_postgres_primary_write_enabled_multi(shop_id=str(shop_id), domains=guarded_domains)

        sale = generics.get_object_or_404(
            Sale.objects.filter(shop=membership.shop, tombstone=False),
            id=sale_id,
        )

        if sale.status == Sale.Status.VOID:
            return Response({"detail": "Sale is already void."}, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            sale = Sale.objects.select_for_update().get(pk=sale.id)
            if sale.status == Sale.Status.VOID:
                return Response({"detail": "Sale is already void."}, status=status.HTTP_400_BAD_REQUEST)
                
            sale.status = Sale.Status.VOID
            sale.save(update_fields=["status", "updated_at"])

            occurred_at = timezone.now()

            # Reverse inventory stock ledger
            for item in sale.items.all():
                if item.inventory_item_id:
                    InventoryStockLedger.objects.create(
                        shop=membership.shop,
                        item_id=item.inventory_item_id,
                        actor_user=request.user,
                        event_type=InventoryStockLedger.EventType.RETURN,
                        quantity_delta=item.quantity if not item.is_return else -item.quantity,
                        unit_cost=item.unit_cost,
                        unit_price=item.unit_price,
                        note=f"Void Sale {sale.receipt_number}",
                        occurred_at=occurred_at,
                        source_system=sale.source_system,
                        source_id=str(sale.id),
                        source_shop_id=sale.source_shop_id,
                        source_path=f"sales/{sale.id}/void",
                        domain_epoch=sale.domain_epoch,
                    )

            # Reverse customer ledger
            if sale.customer_id:
                customer = sale.customer
                computed_due = sale.amount_due
                computed_total = sale.total_amount
                
                CustomerLedgerEntry.objects.create(
                    shop=membership.shop,
                    customer=customer,
                    actor_user=request.user,
                    event_type=CustomerLedgerEntry.EventType.PAYMENT, # Reverse sale with a payment equivalent
                    amount_delta=-computed_due,
                    total_spent_delta=-computed_total,
                    note=f"Void Sale {sale.receipt_number}",
                    occurred_at=occurred_at,
                    source_system=sale.source_system,
                    source_id=str(sale.id),
                    source_shop_id=sale.source_shop_id,
                    source_path=f"sales/{sale.id}/void",
                    domain_epoch=sale.domain_epoch,
                )
                customer.balance -= computed_due
                customer.total_spent -= computed_total
                customer.save(update_fields=["balance", "total_spent", "updated_at"])

        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=request.user,
            actor_role=membership.role,
            category="sale",
            event_type="sale.voided",
            entity_type="sale",
            entity_id=sale.id,
            entity_label=sale.receipt_number,
            summary=f"Voided sale {sale.receipt_number}.",
            source_surface="backend_api",
            after=snapshot_sale(sale),
        )

        return Response(SaleSerializer(sale).data)


class SaleSummaryView(ShopScopedMixin, APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = self.get_membership()
        # Voided sales must not count toward gross / receipts — otherwise a
        # refund never changes the backend totals.
        queryset = Sale.objects.filter(shop=membership.shop, tombstone=False).exclude(
            status=Sale.Status.VOID
        )
        # Optional date window so Reports can ask the server for period totals
        # (accurate across ALL sales, not just the recent window on the phone).
        date_from = request.query_params.get("date_from", "").strip()
        date_to = request.query_params.get("date_to", "").strip()
        if date_from:
            queryset = queryset.filter(sale_date__gte=date_from)
        if date_to:
            queryset = queryset.filter(sale_date__lte=date_to)
        aggregates = queryset.aggregate(
            total_sales=Count("id"),
            gross_revenue=Coalesce(Sum("total_amount"), Decimal("0.00")),
            collected_revenue=Coalesce(Sum("amount_received"), Decimal("0.00")),
            outstanding_revenue=Coalesce(Sum("amount_due"), Decimal("0.00")),
        )

        total_sales = aggregates["total_sales"] or 0
        gross_revenue = aggregates["gross_revenue"] or Decimal("0.00")
        payload = {
            "total_sales": total_sales,
            "gross_revenue": gross_revenue,
            "collected_revenue": aggregates["collected_revenue"] or Decimal("0.00"),
            "outstanding_revenue": (
                aggregates["outstanding_revenue"] or Decimal("0.00")
                if has_feature_enabled(membership, "finance_summary")
                else None
            ),
            "average_ticket": (
                (gross_revenue / total_sales).quantize(Decimal("0.01"))
                if total_sales and has_feature_enabled(membership, "advanced_reports")
                else None
            ),
        }

        serializer = SaleSummarySerializer(payload)
        return Response(serializer.data)


class SaleGstSummaryView(ShopScopedMixin, APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = self.get_membership()
        queryset = Sale.objects.filter(shop=membership.shop, tombstone=False).exclude(
            status=Sale.Status.VOID
        )

        date_from = request.query_params.get("date_from", "").strip()
        date_to = request.query_params.get("date_to", "").strip()
        
        if date_from:
            queryset = queryset.filter(sale_date__gte=date_from)
        if date_to:
            queryset = queryset.filter(sale_date__lte=date_to)

        aggregates = queryset.aggregate(
            total_taxable=Coalesce(Sum("taxable_amount"), Decimal("0.00")),
            total_tax=Coalesce(Sum("tax_amount"), Decimal("0.00")),
            total_cgst=Coalesce(Sum("cgst_amount"), Decimal("0.00")),
            total_sgst=Coalesce(Sum("sgst_amount"), Decimal("0.00")),
            total_igst=Coalesce(Sum("igst_amount"), Decimal("0.00")),
            total_gross=Coalesce(Sum("total_amount"), Decimal("0.00")),
        )

        # B2C small aggregation: by gst_rate
        b2c_rates = queryset.values("items__gst_rate").annotate(
            taxable_amount=Coalesce(Sum("items__taxable_amount"), Decimal("0.00")),
            tax_amount=Coalesce(Sum("items__tax_amount"), Decimal("0.00")),
            cgst_amount=Coalesce(Sum("items__cgst_amount"), Decimal("0.00")),
            sgst_amount=Coalesce(Sum("items__sgst_amount"), Decimal("0.00")),
            igst_amount=Coalesce(Sum("items__igst_amount"), Decimal("0.00")),
        ).order_by("items__gst_rate")
        
        # HSN summary: by hsn_snapshot
        hsn_summary = queryset.exclude(items__hsn_snapshot="").values("items__hsn_snapshot").annotate(
            taxable_amount=Coalesce(Sum("items__taxable_amount"), Decimal("0.00")),
            tax_amount=Coalesce(Sum("items__tax_amount"), Decimal("0.00")),
            cgst_amount=Coalesce(Sum("items__cgst_amount"), Decimal("0.00")),
            sgst_amount=Coalesce(Sum("items__sgst_amount"), Decimal("0.00")),
            igst_amount=Coalesce(Sum("items__igst_amount"), Decimal("0.00")),
        ).order_by("items__hsn_snapshot")

        payload = {
            "taxable_amount": aggregates["total_taxable"],
            "tax_amount": aggregates["total_tax"],
            "cgst_amount": aggregates["total_cgst"],
            "sgst_amount": aggregates["total_sgst"],
            "igst_amount": aggregates["total_igst"],
            "gross_amount": aggregates["total_gross"],
            "b2c_small": list(b2c_rates),
            "hsn_summary": list(hsn_summary),
        }

        serializer = SaleGstSummarySerializer(payload)
        return Response(serializer.data)


def _get_sale_queryset_for_shop(*, shop_id: str):
    return (
        Sale.objects.filter(shop_id=shop_id, tombstone=False)
        .select_related("actor_user", "customer")
        .prefetch_related(
            Prefetch("items", queryset=SaleItem.objects.select_related("inventory_item").order_by("position", "created_at")),
            Prefetch("payments", queryset=SalePayment.objects.order_by("created_at")),
        )
    )


class SaleCommandIngestionView(ShopScopedMixin, generics.GenericAPIView):
    serializer_class = SaleCommandCreateSerializer
    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.STAFF

    def post(self, request, *args, **kwargs):
        membership = self.get_membership()
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        raw_sale_payload = request.data.get("sale", {}) if isinstance(request.data, dict) else {}

        command_id = serializer.validated_data["command_id"]
        base_domain_epoch = serializer.validated_data["base_domain_epoch"]
        source_surface = serializer.validated_data["source_surface"] or "flutter_pos"
        sale_payload = serializer.validated_data["sale"]

        guarded_domains = [
            MigrationDomain.SALES,
            MigrationDomain.PAYMENTS,
            MigrationDomain.STOCK_LEDGER,
        ]
        if sale_payload.get("customer_id"):
            guarded_domains.append(MigrationDomain.CUSTOMER_LEDGER)

        controls = assert_postgres_primary_write_enabled_multi(
            shop_id=str(membership.shop_id),
            domains=guarded_domains,
        )
        assert_domain_epoch_current(
            shop_id=str(membership.shop_id),
            domain=MigrationDomain.SALES,
            base_domain_epoch=base_domain_epoch,
        )

        with transaction.atomic():
            receipt, created = SaleCommandReceipt.objects.select_for_update().get_or_create(
                shop=membership.shop,
                command_id=command_id,
                defaults={
                    "actor_user": request.user,
                    "source_surface": source_surface,
                    "base_domain_epoch": base_domain_epoch,
                    "payload_json": {"sale": raw_sale_payload, "source_surface": source_surface},
                },
            )

            if not created:
                if receipt.sale_id:
                    sale = _get_sale_queryset_for_shop(shop_id=str(membership.shop_id)).get(pk=receipt.sale_id)
                    return Response(
                        {
                            "command_id": command_id,
                            "receipt_id": str(receipt.id),
                            "duplicate": True,
                            "result_status": receipt.result_status,
                            "sale": SaleSerializer(sale).data,
                        },
                        status=status.HTTP_200_OK,
                    )

                return Response(
                    {
                        "detail": "This sale command is already being processed.",
                        "command_id": command_id,
                    },
                    status=status.HTTP_409_CONFLICT,
                )

            # Record resolved epochs alongside the command payload for audit parity.
            receipt.payload_json["resolved_epochs"] = {
                domain: control.current_epoch if control is not None else None
                for domain, control in controls.items()
            }

            # Process the command synchronously so the POS client receives the
            # created sale in the response body. This mirrors the payments
            # command flow and keeps the POS working without a running worker.
            # Re-validate the RAW client payload (field names like `name`), not
            # the already-validated sale_payload whose keys were remapped to
            # their model sources (`name_snapshot`). Feeding the remapped data
            # back through SaleSerializer made it look for `name` and fail every
            # non-catalog line with "must include a name".
            sale_serializer = SaleSerializer(
                data=raw_sale_payload,
                context={"shop": membership.shop, "actor": request.user},
            )
            sale_serializer.is_valid(raise_exception=True)

            source_meta_json = dict(sale_payload.get("source_meta_json") or {})
            source_meta_json.update(
                {"command_id": command_id, "source_surface": source_surface}
            )
            sales_control = controls.get(MigrationDomain.SALES)
            domain_epoch = (
                sales_control.current_epoch if sales_control is not None else base_domain_epoch
            )

            sale = sale_serializer.save(
                source_system="postgres_command",
                source_id=command_id,
                source_shop_id=membership.shop.source_id,
                source_path=(
                    f"shops/{membership.shop.source_id or membership.shop_id}"
                    f"/sales/commands/{command_id}"
                ),
                domain_epoch=domain_epoch,
                source_meta_json=source_meta_json,
            )

            receipt.sale = sale
            receipt.result_status = SaleCommandReceipt.ResultStatus.ACCEPTED
            receipt.applied_at = timezone.now()
            receipt.save(
                update_fields=["sale", "result_status", "applied_at", "payload_json"]
            )

        refresh_projection_after_write(membership.shop, context="a sale")
        sale = _get_sale_queryset_for_shop(shop_id=str(membership.shop_id)).get(pk=sale.id)
        return Response(
            {
                "command_id": command_id,
                "receipt_id": str(receipt.id),
                "duplicate": False,
                "result_status": receipt.result_status,
                "sale": SaleSerializer(sale).data,
            },
            status=status.HTTP_201_CREATED,
        )


class GSTR1ExportView(ShopScopedMixin, APIView):
    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.STAFF

    def get(self, request, shop_id):
        membership = self.get_membership()
        shop = membership.shop
        
        month = request.query_params.get('month')
        year = request.query_params.get('year')
        
        if not month or not year:
            return Response({"error": "month and year are required parameters"}, status=status.HTTP_400_BAD_REQUEST)
            
        try:
            month = int(month)
            year = int(year)
        except ValueError:
            return Response({"error": "month and year must be integers"}, status=status.HTTP_400_BAD_REQUEST)

        sales = Sale.objects.filter(
            shop=shop, 
            tombstone=False,
            status=Sale.Status.COMPLETED,
            sale_date__year=year,
            sale_date__month=month
        ).prefetch_related("items")

        response = HttpResponse(content_type='text/csv')
        response['Content-Disposition'] = f'attachment; filename="GSTR1_{shop.name}_{year}_{month}.csv"'

        writer = csv.writer(response)
        writer.writerow([
            'GSTIN/UIN of Recipient', 
            'Receiver Name', 
            'Invoice Number', 
            'Invoice Date', 
            'Invoice Value', 
            'Place Of Supply', 
            'Reverse Charge', 
            'Applicable % of Tax Rate', 
            'Invoice Type', 
            'E-Commerce GSTIN', 
            'Rate', 
            'Taxable Value',
            'Cess Amount'
        ])

        for sale in sales:
            # Group items by GST rate for the sale
            rate_groups = {}
            for item in sale.items.all():
                if item.gst_rate not in rate_groups:
                    rate_groups[item.gst_rate] = {
                        "taxable": Decimal("0.00"),
                        "tax": Decimal("0.00"),
                    }
                rate_groups[item.gst_rate]["taxable"] += item.taxable_amount
                rate_groups[item.gst_rate]["tax"] += item.tax_amount

            buyer_gstin = sale.buyer_gstin or ''
            invoice_type = "Regular B2B" if buyer_gstin else "B2C Others"

            for rate, amounts in rate_groups.items():
                if amounts["taxable"] > 0:
                    writer.writerow([
                        buyer_gstin,
                        sale.customer_name_snapshot,
                        sale.receipt_number,
                        sale.sale_date.strftime("%d-%b-%y"),
                        sale.total_amount, # Total invoice value is usually printed on all rows for same invoice in GSTR1
                        sale.place_of_supply_state or shop.state_code,
                        'N',
                        '',
                        invoice_type,
                        '',
                        rate,
                        amounts["taxable"],
                        ''
                    ])

        return response


class GSTR3BExportView(ShopScopedMixin, APIView):
    """GSTR-3B summary (section 3.1(a) outward taxable supplies) as CSV — the
    period totals of taxable value and IGST/CGST/SGST, broken down by tax rate,
    ready to key into the GST portal's summary return."""

    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.ADMIN  # RBAC: filings are owner/admin only.

    def get(self, request, shop_id):
        membership = self.get_membership()
        shop = membership.shop

        month = request.query_params.get("month")
        year = request.query_params.get("year")
        if not month or not year:
            return Response(
                {"error": "month and year are required parameters"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            month = int(month)
            year = int(year)
        except ValueError:
            return Response(
                {"error": "month and year must be integers"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        items = SaleItem.objects.filter(
            sale__shop=shop,
            sale__tombstone=False,
            sale__status=Sale.Status.COMPLETED,
            sale__sale_date__year=year,
            sale__sale_date__month=month,
        )

        # Aggregate by rate: taxable + igst/cgst/sgst.
        by_rate: dict[Decimal, dict[str, Decimal]] = {}
        for item in items.values("gst_rate", "taxable_amount", "cgst_amount", "sgst_amount", "igst_amount"):
            bucket = by_rate.setdefault(
                item["gst_rate"],
                {"taxable": Decimal("0.00"), "cgst": Decimal("0.00"), "sgst": Decimal("0.00"), "igst": Decimal("0.00")},
            )
            bucket["taxable"] += item["taxable_amount"] or Decimal("0.00")
            bucket["cgst"] += item["cgst_amount"] or Decimal("0.00")
            bucket["sgst"] += item["sgst_amount"] or Decimal("0.00")
            bucket["igst"] += item["igst_amount"] or Decimal("0.00")

        response = HttpResponse(content_type="text/csv")
        response["Content-Disposition"] = f'attachment; filename="GSTR3B_{shop.name}_{year}_{month}.csv"'
        writer = csv.writer(response)
        writer.writerow(["GSTIN", shop.gstin or ""])
        writer.writerow(["Period", f"{month:02d}-{year}"])
        writer.writerow([])
        writer.writerow(["Nature of Supply", "Tax Rate (%)", "Taxable Value", "IGST", "CGST", "SGST", "Total Tax"])

        totals = {"taxable": Decimal("0.00"), "cgst": Decimal("0.00"), "sgst": Decimal("0.00"), "igst": Decimal("0.00")}
        for rate in sorted(by_rate.keys()):
            amounts = by_rate[rate]
            total_tax = amounts["igst"] + amounts["cgst"] + amounts["sgst"]
            writer.writerow(
                [
                    "Outward taxable supplies",
                    rate,
                    amounts["taxable"],
                    amounts["igst"],
                    amounts["cgst"],
                    amounts["sgst"],
                    total_tax,
                ]
            )
            for key in totals:
                totals[key] += amounts[key]

        grand_tax = totals["igst"] + totals["cgst"] + totals["sgst"]
        writer.writerow(
            ["Total (3.1a)", "", totals["taxable"], totals["igst"], totals["cgst"], totals["sgst"], grand_tax]
        )
        return response


class GSTFilingPackView(ShopScopedMixin, APIView):
    """One-tap monthly filing pack for the shop's CA: a ZIP with GSTR-1,
    GSTR-3B (3.1a) and an HSN summary CSV for the period. Admin/owner only."""

    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.ADMIN

    def get(self, request, shop_id):
        membership = self.get_membership()
        shop = membership.shop
        month = request.query_params.get("month")
        year = request.query_params.get("year")
        if not month or not year:
            return Response(
                {"error": "month and year are required parameters"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            month = int(month)
            year = int(year)
        except ValueError:
            return Response(
                {"error": "month and year must be integers"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        sales = list(
            Sale.objects.filter(
                shop=shop,
                tombstone=False,
                status=Sale.Status.COMPLETED,
                sale_date__year=year,
                sale_date__month=month,
            ).prefetch_related("items")
        )

        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(f"GSTR1_{year}_{month:02d}.csv", self._gstr1_csv(shop, sales))
            archive.writestr(f"GSTR3B_{year}_{month:02d}.csv", self._gstr3b_csv(shop, sales))
            archive.writestr(f"HSN_summary_{year}_{month:02d}.csv", self._hsn_csv(sales))

        response = HttpResponse(buffer.getvalue(), content_type="application/zip")
        response["Content-Disposition"] = (
            f'attachment; filename="GST_filing_pack_{shop.name}_{year}_{month:02d}.zip"'
        )
        return response

    @staticmethod
    def _gstr1_csv(shop, sales) -> str:
        out = io.StringIO()
        w = csv.writer(out)
        w.writerow(
            ["GSTIN/UIN of Recipient", "Receiver Name", "Invoice Number", "Invoice Date",
             "Invoice Value", "Place Of Supply", "Reverse Charge", "Invoice Type",
             "Rate", "Taxable Value"]
        )
        for sale in sales:
            rate_groups: dict = {}
            for item in sale.items.all():
                rate_groups.setdefault(item.gst_rate, Decimal("0.00"))
                rate_groups[item.gst_rate] += item.taxable_amount or Decimal("0.00")
            buyer_gstin = sale.buyer_gstin or ""
            invoice_type = "Regular B2B" if buyer_gstin else "B2C Others"
            for rate, taxable in rate_groups.items():
                if taxable > 0:
                    w.writerow([
                        buyer_gstin, sale.customer_name_snapshot, sale.receipt_number,
                        sale.sale_date.strftime("%d-%b-%y"), sale.total_amount,
                        sale.place_of_supply_state or shop.state_code, "N",
                        invoice_type, rate, taxable,
                    ])
        return out.getvalue()

    @staticmethod
    def _gstr3b_csv(shop, sales) -> str:
        by_rate: dict = {}
        for sale in sales:
            for item in sale.items.all():
                bucket = by_rate.setdefault(
                    item.gst_rate,
                    {"taxable": Decimal("0.00"), "cgst": Decimal("0.00"),
                     "sgst": Decimal("0.00"), "igst": Decimal("0.00")},
                )
                bucket["taxable"] += item.taxable_amount or Decimal("0.00")
                bucket["cgst"] += item.cgst_amount or Decimal("0.00")
                bucket["sgst"] += item.sgst_amount or Decimal("0.00")
                bucket["igst"] += item.igst_amount or Decimal("0.00")
        out = io.StringIO()
        w = csv.writer(out)
        w.writerow(["GSTIN", shop.gstin or ""])
        w.writerow([])
        w.writerow(["Nature of Supply", "Tax Rate (%)", "Taxable Value", "IGST", "CGST", "SGST", "Total Tax"])
        totals = {"taxable": Decimal("0.00"), "cgst": Decimal("0.00"), "sgst": Decimal("0.00"), "igst": Decimal("0.00")}
        for rate in sorted(by_rate.keys()):
            a = by_rate[rate]
            w.writerow(["Outward taxable supplies", rate, a["taxable"], a["igst"], a["cgst"], a["sgst"],
                        a["igst"] + a["cgst"] + a["sgst"]])
            for k in totals:
                totals[k] += a[k]
        w.writerow(["Total (3.1a)", "", totals["taxable"], totals["igst"], totals["cgst"], totals["sgst"],
                    totals["igst"] + totals["cgst"] + totals["sgst"]])
        return out.getvalue()

    @staticmethod
    def _hsn_csv(sales) -> str:
        by_hsn: dict = {}
        for sale in sales:
            for item in sale.items.all():
                key = (item.hsn_snapshot or "", item.gst_rate)
                bucket = by_hsn.setdefault(
                    key,
                    {"qty": Decimal("0.000"), "taxable": Decimal("0.00"),
                     "cgst": Decimal("0.00"), "sgst": Decimal("0.00"), "igst": Decimal("0.00")},
                )
                sign = Decimal("-1") if item.is_return else Decimal("1")
                bucket["qty"] += sign * (item.quantity or Decimal("0.000"))
                bucket["taxable"] += item.taxable_amount or Decimal("0.00")
                bucket["cgst"] += item.cgst_amount or Decimal("0.00")
                bucket["sgst"] += item.sgst_amount or Decimal("0.00")
                bucket["igst"] += item.igst_amount or Decimal("0.00")
        out = io.StringIO()
        w = csv.writer(out)
        w.writerow(["HSN", "Rate (%)", "Total Quantity", "Taxable Value", "IGST", "CGST", "SGST", "Total Tax"])
        for (hsn, rate) in sorted(by_hsn.keys(), key=lambda k: (str(k[0]), k[1])):
            a = by_hsn[(hsn, rate)]
            w.writerow([hsn, rate, a["qty"], a["taxable"], a["igst"], a["cgst"], a["sgst"],
                        a["igst"] + a["cgst"] + a["sgst"]])
        return out.getvalue()


class SaleHistoryBulkImportView(ShopScopedMixin, APIView):
    """Bulk-import flat historical sales (past bills from another POS) as
    records: no line items, no stock/ledger effects. Idempotent by client id so
    re-importing the same file never duplicates. STAFF+ only."""

    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.STAFF

    def post(self, request, shop_id):
        from datetime import datetime, time as _time

        membership = self.get_membership()
        assert_postgres_primary_write_enabled_multi(
            shop_id=str(membership.shop_id), domains=[MigrationDomain.SALES]
        )
        rows = request.data.get("sales")
        if not isinstance(rows, list) or not rows:
            raise exceptions.ValidationError({"sales": "Provide a non-empty list of sales."})
        if len(rows) > 1000:
            raise exceptions.ValidationError({"sales": "Send at most 1000 sales per request."})

        valid_modes = set(Sale.PaymentMode.values)
        created = 0
        skipped = 0
        with transaction.atomic():
            for raw in rows:
                try:
                    total = Decimal(str(raw.get("total") or "0"))
                    discount = Decimal(str(raw.get("discount") or "0"))
                except Exception:
                    skipped += 1
                    continue
                if total <= 0:
                    skipped += 1
                    continue
                client_id = str(raw.get("id") or "").strip()
                if client_id and Sale.objects.filter(
                    shop=membership.shop, source_id=client_id
                ).exists():
                    skipped += 1
                    continue
                pay = str(raw.get("payment_mode") or "CASH").upper()
                if pay not in valid_modes:
                    pay = "CASH"
                try:
                    sale_date = datetime.strptime(str(raw.get("date") or "")[:10], "%Y-%m-%d").date()
                except Exception:
                    sale_date = timezone.now().date()
                occurred = timezone.make_aware(datetime.combine(sale_date, _time.min))
                if pay == "CREDIT":
                    received, due = Decimal("0.00"), total
                else:
                    received, due = total, Decimal("0.00")
                sale = Sale.objects.create(
                    shop=membership.shop,
                    actor_user=request.user,
                    subtotal_amount=total + discount,
                    discount_amount=discount,
                    total_amount=total,
                    amount_received=received,
                    amount_due=due,
                    payment_mode=pay,
                    customer_name_snapshot=str(raw.get("customer_name") or "")[:255],
                    customer_phone_snapshot=str(raw.get("customer_phone") or "")[:32],
                    footer_note=str(raw.get("footer_note") or ""),
                    sale_date=sale_date,
                    occurred_at=occurred,
                    source_system="import",
                    source_id=client_id,
                )
                sale.receipt_number = f"H-{str(sale.id).replace('-', '')[:8].upper()}"
                sale.save(update_fields=["receipt_number", "updated_at"])
                created += 1
        return Response(
            {"created": created, "skipped": skipped}, status=status.HTTP_201_CREATED
        )


class SaleTallyExportView(ShopScopedMixin, APIView):
    """Export a date range of sales as a Tally-importable XML voucher file.

    Indian accountants work in Tally, so "can my CA import this?" decides
    whether a shop can adopt the app at all. Voided sales are excluded: an
    accountant importing a refunded bill would overstate revenue.
    """

    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.ADMIN

    def get(self, request, shop_id):
        membership = self.get_membership()
        shop = membership.shop

        date_from = request.query_params.get("date_from", "").strip()
        date_to = request.query_params.get("date_to", "").strip()

        sales = (
            Sale.objects.filter(shop=shop, tombstone=False)
            .exclude(status=Sale.Status.VOID)
            .order_by("sale_date", "created_at")
        )
        if date_from:
            sales = sales.filter(sale_date__gte=date_from)
        if date_to:
            sales = sales.filter(sale_date__lte=date_to)

        xml = build_tally_xml(shop, sales)
        response = HttpResponse(xml, content_type="application/xml")
        suffix = f"_{date_from}_{date_to}" if date_from and date_to else ""
        filename = f"Tally_{shop.slug}{suffix}.xml"
        response["Content-Disposition"] = f'attachment; filename="{filename}"'
        return response


class SaleStaffPerformanceView(ShopScopedMixin, APIView):
    """Who sold how much, over a date window.

    Attribution comes from the authenticated user on each sale, so it is only
    meaningful when team members sign in as themselves — a shop where everyone
    shares one login sees a single row, which is the honest answer rather than
    an invented split.
    """

    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.MANAGER

    def get(self, request, shop_id):
        membership = self.get_membership()

        queryset = (
            Sale.objects.filter(shop=membership.shop, tombstone=False)
            .exclude(status=Sale.Status.VOID)
        )
        date_from = request.query_params.get("date_from", "").strip()
        date_to = request.query_params.get("date_to", "").strip()
        if date_from:
            queryset = queryset.filter(sale_date__gte=date_from)
        if date_to:
            queryset = queryset.filter(sale_date__lte=date_to)

        rows = (
            queryset.values(
                "actor_user__id", "actor_user__full_name", "actor_user__email"
            )
            .annotate(
                sale_count=Count("id"),
                gross=Coalesce(Sum("total_amount"), Decimal("0.00")),
                collected=Coalesce(Sum("amount_received"), Decimal("0.00")),
                discount_given=Coalesce(Sum("discount_amount"), Decimal("0.00")),
            )
            .order_by("-gross")
        )

        results = []
        for row in rows:
            name = (row["actor_user__full_name"] or "").strip()
            if not name:
                name = (row["actor_user__email"] or "").strip() or "Unattributed"
            sale_count = row["sale_count"] or 0
            gross = row["gross"] or Decimal("0.00")
            results.append(
                {
                    "name": name,
                    "sale_count": sale_count,
                    "gross": gross,
                    "collected": row["collected"] or Decimal("0.00"),
                    "discount_given": row["discount_given"] or Decimal("0.00"),
                    "average_ticket": (
                        (gross / sale_count).quantize(Decimal("0.01"))
                        if sale_count
                        else Decimal("0.00")
                    ),
                }
            )
        return Response(results)

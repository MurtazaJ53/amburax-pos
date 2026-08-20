from __future__ import annotations

from decimal import Decimal

from django.db import transaction
from django.db.models import Count, Q, Sum
from django.utils import timezone
from rest_framework import generics, permissions
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.audit.services import create_workspace_audit_event, snapshot_payment
from platform_apps.common.migration import MigrationDomain
from platform_apps.common.migration_guards import (
    assert_domain_epoch_current,
    assert_postgres_primary_write_enabled_multi,
)
from platform_apps.customers.models import CustomerLedgerEntry
from platform_apps.payments.models import SalePayment
from platform_apps.payments.models import SalePaymentCommandReceipt
from platform_apps.payments.serializers import (
    SalePaymentCommandCreateSerializer,
    SalePaymentSerializer,
    SalePaymentSummarySerializer,
)
from platform_apps.projections.services import refresh_projection_after_write
from platform_apps.sales.models import Sale
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


class SalePaymentListView(ShopScopedMixin, generics.ListAPIView):
    serializer_class = SalePaymentSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = None

    def get_queryset(self):
        membership = self.get_membership()
        queryset = SalePayment.objects.filter(
            shop=membership.shop,
            sale__tombstone=False,
        ).select_related("sale", "actor_user")

        sale_id = self.request.query_params.get("sale_id", "").strip()
        payment_method = self.request.query_params.get("payment_method", "").strip()
        date_from = self.request.query_params.get("date_from", "").strip()
        date_to = self.request.query_params.get("date_to", "").strip()

        if sale_id:
            queryset = queryset.filter(sale_id=sale_id)
        if payment_method:
            queryset = queryset.filter(payment_method=payment_method)
        if date_from:
            queryset = queryset.filter(sale__sale_date__gte=date_from)
        if date_to:
            queryset = queryset.filter(sale__sale_date__lte=date_to)
        return queryset


class SalePaymentSummaryView(ShopScopedMixin, APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = self.get_membership()
        queryset = SalePayment.objects.filter(
            shop=membership.shop,
            sale__tombstone=False,
        )
        aggregates = queryset.aggregate(
            payment_count=Count("id"),
            total_collected=Sum("amount"),
            credit_count=Count("id", filter=Q(payment_method=SalePayment.PaymentMethod.CREDIT)),
            digital_payment_count=Count(
                "id",
                filter=Q(
                    payment_method__in=[
                        SalePayment.PaymentMethod.UPI,
                        SalePayment.PaymentMethod.BANK,
                        SalePayment.PaymentMethod.CARD,
                    ]
                ),
            ),
        )

        payload = {
            "payment_count": aggregates["payment_count"] or 0,
            "total_collected": (
                aggregates["total_collected"] or Decimal("0.00")
                if has_feature_enabled(membership, "finance_summary")
                else None
            ),
            "credit_count": (
                aggregates["credit_count"] or 0
                if has_feature_enabled(membership, "finance_summary")
                else None
            ),
            "digital_payment_count": (
                aggregates["digital_payment_count"] or 0
                if has_feature_enabled(membership, "advanced_reports")
                else None
            ),
        }

        serializer = SalePaymentSummarySerializer(payload)
        return Response(serializer.data)


class SalePaymentCommandIngestionView(ShopScopedMixin, generics.GenericAPIView):
    serializer_class = SalePaymentCommandCreateSerializer
    permission_classes = [permissions.IsAuthenticated]
    minimum_role = ShopMembership.Role.STAFF

    def post(self, request, *args, **kwargs):
        membership = self.get_membership()
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        raw_payment_payload = dict(request.data) if hasattr(request.data, "items") else {}

        command_id = serializer.validated_data["command_id"]
        base_domain_epoch = serializer.validated_data["base_domain_epoch"]
        source_surface = serializer.validated_data["source_surface"] or "flutter_pos"

        guarded_domains = [
            MigrationDomain.PAYMENTS,
            MigrationDomain.SALES,
        ]

        sale = Sale.objects.select_related("customer").filter(
            pk=serializer.validated_data["sale_id"],
            shop=membership.shop,
            tombstone=False,
        ).first()
        if sale is None:
            return Response(
                {"detail": "The target sale is not available in this shop."},
                status=status.HTTP_404_NOT_FOUND,
            )

        if sale.customer_id:
            guarded_domains.append(MigrationDomain.CUSTOMER_LEDGER)

        controls = assert_postgres_primary_write_enabled_multi(
            shop_id=str(membership.shop_id),
            domains=guarded_domains,
        )
        payments_control = assert_domain_epoch_current(
            shop_id=str(membership.shop_id),
            domain=MigrationDomain.PAYMENTS,
            base_domain_epoch=base_domain_epoch,
        )

        amount = serializer.validated_data["amount"]
        if amount <= Decimal("0.00"):
            return Response(
                {"detail": "Payment amount must be positive."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if amount > sale.amount_due:
            return Response(
                {
                    "detail": "Payment amount cannot exceed the outstanding due for this sale.",
                    "sale_amount_due": str(sale.amount_due),
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        if sale.customer_id and amount > sale.customer.balance:
            return Response(
                {
                    "detail": "Payment would drive the customer ledger negative. Resolve customer balance drift before accepting this command.",
                    "customer_balance": str(sale.customer.balance),
                    "sale_amount_due": str(sale.amount_due),
                },
                status=status.HTTP_409_CONFLICT,
            )

        occurred_at = serializer.validated_data.get("occurred_at") or timezone.now()

        with transaction.atomic():
            receipt, created = SalePaymentCommandReceipt.objects.select_for_update().get_or_create(
                shop=membership.shop,
                command_id=command_id,
                defaults={
                    "actor_user": request.user,
                    "sale": sale,
                    "source_surface": source_surface,
                    "base_domain_epoch": base_domain_epoch,
                    "payload_json": {
                        "sale_id": raw_payment_payload.get("sale_id", str(serializer.validated_data["sale_id"])),
                        "payment_method": raw_payment_payload.get("payment_method", serializer.validated_data["payment_method"]),
                        "amount": raw_payment_payload.get("amount", str(amount)),
                        "reference_code": raw_payment_payload.get("reference_code", serializer.validated_data.get("reference_code", "")),
                        "note": raw_payment_payload.get("note", serializer.validated_data.get("note", "")),
                        "source_surface": source_surface,
                    },
                },
            )

            if not created:
                if receipt.payment_id:
                    payment = SalePayment.objects.select_related("sale", "actor_user").get(pk=receipt.payment_id)
                    return Response(
                        {
                            "command_id": command_id,
                            "receipt_id": str(receipt.id),
                            "duplicate": True,
                            "result_status": receipt.result_status,
                            "payment": SalePaymentSerializer(payment).data,
                        },
                        status=status.HTTP_200_OK,
                    )

                return Response(
                    {
                        "detail": "This payment command is already being processed.",
                        "command_id": command_id,
                    },
                    status=status.HTTP_409_CONFLICT,
                )

            payment = SalePayment.objects.create(
                sale=sale,
                shop=membership.shop,
                actor_user=request.user,
                payment_method=serializer.validated_data["payment_method"],
                amount=amount,
                reference_code=serializer.validated_data.get("reference_code", ""),
                note=serializer.validated_data.get("note", ""),
                occurred_at=occurred_at,
                source_system="postgres_command",
                source_id=command_id,
                source_shop_id=membership.shop.source_id,
                source_path=f"shops/{membership.shop.source_id or membership.shop_id}/payments/commands/{command_id}",
                domain_epoch=payments_control.current_epoch if payments_control is not None else base_domain_epoch,
            )

            sale.amount_received = sale.amount_received + amount
            sale.amount_due = sale.amount_due - amount
            if sale.payments.exclude(pk=payment.pk).exists():
                sale.payment_mode = Sale.PaymentMode.SPLIT
            else:
                sale.payment_mode = payment.payment_method
            sale.save(update_fields=["amount_received", "amount_due", "payment_mode", "updated_at"])

            if sale.customer_id:
                CustomerLedgerEntry.objects.create(
                    shop=membership.shop,
                    customer=sale.customer,
                    actor_user=request.user,
                    event_type=CustomerLedgerEntry.EventType.PAYMENT,
                    amount_delta=-amount,
                    total_spent_delta=Decimal("0.00"),
                    note=f"Payment for {sale.receipt_number}",
                    occurred_at=occurred_at,
                    source_system="postgres_command",
                    source_id=command_id,
                    source_shop_id=membership.shop.source_id,
                    source_path=f"shops/{membership.shop.source_id or membership.shop_id}/payments/commands/{command_id}",
                    domain_epoch=payments_control.current_epoch if payments_control is not None else base_domain_epoch,
                )
                sale.customer.balance = sale.customer.balance - amount
                sale.customer.save(update_fields=["balance", "updated_at"])

            receipt.actor_user = request.user
            receipt.sale = sale
            receipt.payment = payment
            receipt.source_surface = source_surface
            receipt.base_domain_epoch = base_domain_epoch
            receipt.result_status = SalePaymentCommandReceipt.ResultStatus.ACCEPTED
            receipt.payload_json = {
                "sale_id": raw_payment_payload.get("sale_id", str(sale.id)),
                "payment_method": raw_payment_payload.get("payment_method", serializer.validated_data["payment_method"]),
                "amount": raw_payment_payload.get("amount", str(amount)),
                "source_surface": source_surface,
                "guarded_domains": guarded_domains,
                "resolved_epochs": {
                    domain: control.current_epoch if control is not None else None
                    for domain, control in controls.items()
                },
            }
            receipt.applied_at = timezone.now()
            receipt.save(
                update_fields=[
                    "actor_user",
                    "sale",
                    "payment",
                    "source_surface",
                    "base_domain_epoch",
                    "result_status",
                    "payload_json",
                    "applied_at",
                    "updated_at",
                ]
            )

        refresh_projection_after_write(membership.shop, context="a payment")
        payment = SalePayment.objects.select_related("sale", "actor_user").get(pk=payment.id)
        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=request.user,
            actor_role=membership.role,
            category="payment",
            event_type="payment.command.accepted",
            entity_type="sale_payment_command",
            entity_id=command_id,
            entity_label=payment.sale.receipt_number,
            summary=f"Accepted payment command for {payment.sale.receipt_number}.",
            source_surface=source_surface,
            after=snapshot_payment(payment),
            metadata={
                "command_id": command_id,
                "receipt_id": receipt.id,
                "base_domain_epoch": base_domain_epoch,
                "duplicate": False,
            },
        )
        return Response(
            {
                "command_id": command_id,
                "receipt_id": str(receipt.id),
                "duplicate": False,
                "result_status": receipt.result_status,
                "payment": SalePaymentSerializer(payment).data,
            },
            status=status.HTTP_201_CREATED,
        )

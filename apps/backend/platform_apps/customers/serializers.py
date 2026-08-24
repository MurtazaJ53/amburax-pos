from __future__ import annotations

from decimal import Decimal

from django.db import transaction
from django.utils import timezone
from rest_framework import serializers

from platform_apps.customers.models import Customer, CustomerLedgerEntry


class CustomerSummarySerializer(serializers.Serializer):
    total_customers = serializers.IntegerField()
    active_credit_customers = serializers.IntegerField()
    total_outstanding_balance = serializers.DecimalField(max_digits=12, decimal_places=2)
    total_lifetime_spend = serializers.DecimalField(
        max_digits=12,
        decimal_places=2,
        allow_null=True,
    )


class CustomerSerializer(serializers.ModelSerializer):
    opening_balance = serializers.DecimalField(
        max_digits=12,
        decimal_places=2,
        required=False,
        default=Decimal("0.00"),
        write_only=True,
    )

    class Meta:
        model = Customer
        fields = (
            "id",
            "name",
            "phone",
            "email",
            "work_address",
            "home_address",
            "total_spent",
            "balance",
            "loyalty_points",
            "last_reminded_at",
            "notes",
            "status",
            "tombstone",
            "source_meta_json",
            "opening_balance",
        )
        read_only_fields = (
            "id",
            "total_spent",
            "balance",
            "loyalty_points",
            "last_reminded_at",
            "tombstone",
        )

    @transaction.atomic
    def create(self, validated_data):
        opening_balance = validated_data.pop("opening_balance", Decimal("0.00"))
        shop = self.context["shop"]
        actor = self.context["actor"]

        customer = Customer.objects.create(
            shop=shop,
            balance=opening_balance,
            **validated_data,
        )

        if opening_balance != Decimal("0.00"):
            CustomerLedgerEntry.objects.create(
                shop=shop,
                customer=customer,
                actor_user=actor,
                event_type=CustomerLedgerEntry.EventType.OPENING_BALANCE,
                amount_delta=opening_balance,
                total_spent_delta=Decimal("0.00"),
                note="Opening balance",
                occurred_at=timezone.now(),
            )

        return customer

    def update(self, instance, validated_data):
        validated_data.pop("opening_balance", None)
        for field, value in validated_data.items():
            setattr(instance, field, value)
        instance.save()
        return instance


class CustomerLedgerEntrySerializer(serializers.ModelSerializer):
    actor_name = serializers.SerializerMethodField()
    event_type = serializers.ChoiceField(
        choices=[
            CustomerLedgerEntry.EventType.PAYMENT,
            CustomerLedgerEntry.EventType.ADJUSTMENT,
        ]
    )

    class Meta:
        model = CustomerLedgerEntry
        fields = (
            "id",
            "event_type",
            "amount_delta",
            "total_spent_delta",
            "note",
            "occurred_at",
            "actor_name",
        )
        read_only_fields = ("id", "actor_name")

    def get_actor_name(self, obj):
        return obj.actor_user.full_name if obj.actor_user_id and obj.actor_user.full_name else obj.actor_user.email if obj.actor_user_id else None

    @transaction.atomic
    def create(self, validated_data):
        customer = self.context["customer"]
        shop = self.context["shop"]
        actor = self.context["actor"]

        entry = CustomerLedgerEntry.objects.create(
            shop=shop,
            customer=customer,
            actor_user=actor,
            **validated_data,
        )

        customer.balance = customer.balance + entry.amount_delta
        customer.total_spent = customer.total_spent + entry.total_spent_delta
        customer.save(update_fields=["balance", "total_spent", "updated_at"])

        return entry

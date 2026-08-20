from __future__ import annotations

from rest_framework import serializers

from platform_apps.projections.models import (
    ShopDashboardSnapshot,
    ShopLowStockSnapshot,
    ShopPulseSignal,
)
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import (
    can_assign_workspace_pulse_signal,
    has_feature_enabled,
)


class ShopLowStockSnapshotSerializer(serializers.ModelSerializer):
    inventory_item_id = serializers.SerializerMethodField()

    def get_inventory_item_id(self, obj):
        return str(obj.inventory_item_id) if obj.inventory_item_id else None

    class Meta:
        model = ShopLowStockSnapshot
        fields = (
            "id",
            "inventory_item_id",
            "item_name",
            "sku",
            "category",
            "stock_on_hand",
            "sell_price",
            "severity_rank",
            "refreshed_at",
        )


class ShopDashboardSnapshotSerializer(serializers.ModelSerializer):
    low_stock_preview = ShopLowStockSnapshotSerializer(many=True, read_only=True)

    class Meta:
        model = ShopDashboardSnapshot
        fields = (
            "id",
            "shop",
            "inventory_items_count",
            "active_inventory_items_count",
            "category_count",
            "low_stock_items_count",
            "out_of_stock_items_count",
            "projected_sell_value",
            "customer_count",
            "active_credit_customers_count",
            "total_outstanding_balance",
            "total_lifetime_spend",
            "sales_count",
            "gross_revenue",
            "today_sales_count",
            "today_gross_revenue",
            "today_date",
            "outstanding_revenue",
            "payment_count",
            "total_collected",
            "credit_payment_count",
            "digital_payment_count",
            "last_sale_at",
            "refreshed_at",
            "metadata_json",
            "low_stock_preview",
        )

    def to_representation(self, instance):
        payload = super().to_representation(instance)
        membership = self.context.get("membership")
        if membership is None:
            return payload

        if not has_feature_enabled(membership, "advanced_reports"):
            payload["projected_sell_value"] = None
            payload["total_lifetime_spend"] = None

        if not has_feature_enabled(membership, "finance_summary"):
            payload["total_outstanding_balance"] = None
            payload["gross_revenue"] = None
            # Same gate as gross_revenue. Today's takings are no less a revenue
            # figure than the lifetime one, and adding a field without adding it
            # here is how a feature gate quietly springs a leak.
            payload["today_gross_revenue"] = None
            payload["outstanding_revenue"] = None
            payload["total_collected"] = None

        return payload


class ShopPulseHeadlineSerializer(serializers.Serializer):
    title = serializers.CharField()
    body = serializers.CharField()
    route = serializers.CharField()
    cta_label = serializers.CharField()
    tone = serializers.CharField()


class ShopPulseTaskSerializer(serializers.Serializer):
    code = serializers.CharField()
    priority = serializers.CharField()
    tone = serializers.CharField()
    title = serializers.CharField()
    body = serializers.CharField()
    route = serializers.CharField()
    cta_label = serializers.CharField()
    count = serializers.IntegerField()
    metadata_json = serializers.JSONField()


class ShopPulseAnomalySerializer(serializers.Serializer):
    code = serializers.CharField()
    severity = serializers.CharField()
    title = serializers.CharField()
    body = serializers.CharField()
    route = serializers.CharField()
    cta_label = serializers.CharField()
    metric_value = serializers.CharField()
    metadata_json = serializers.JSONField()


class ShopPulseStatsSerializer(serializers.Serializer):
    open_task_count = serializers.IntegerField()
    critical_anomaly_count = serializers.IntegerField()
    warning_anomaly_count = serializers.IntegerField()
    stale_session_count = serializers.IntegerField()
    wipe_pending_count = serializers.IntegerField()
    open_plan_request_count = serializers.IntegerField()
    low_stock_count = serializers.IntegerField()


class ShopPulseSnapshotSerializer(serializers.Serializer):
    refreshed_at = serializers.DateTimeField()
    headline = ShopPulseHeadlineSerializer()
    stats = ShopPulseStatsSerializer()
    tasks = ShopPulseTaskSerializer(many=True)
    anomalies = ShopPulseAnomalySerializer(many=True)


class ShopPulseSignalSerializer(serializers.ModelSerializer):
    assigned_member_name = serializers.SerializerMethodField()
    assigned_member_role = serializers.SerializerMethodField()
    assigned_by_name = serializers.SerializerMethodField()
    acknowledged_by_name = serializers.SerializerMethodField()
    escalated_by_name = serializers.SerializerMethodField()
    resolved_by_name = serializers.SerializerMethodField()

    class Meta:
        model = ShopPulseSignal
        fields = (
            "id",
            "signal_kind",
            "code",
            "status",
            "signal_level",
            "signal_rank",
            "tone",
            "title",
            "body",
            "route",
            "cta_label",
            "metric_value",
            "count",
            "first_detected_at",
            "last_detected_at",
            "last_snapshot_refreshed_at",
            "assigned_membership_id",
            "assigned_member_name",
            "assigned_member_role",
            "assigned_at",
            "assigned_by_name",
            "acknowledged_at",
            "acknowledged_by_name",
            "is_escalated",
            "escalated_at",
            "escalated_by_name",
            "escalation_note",
            "follow_up_note",
            "resolved_at",
            "resolved_by_name",
            "resolution_note",
            "metadata_json",
            "created_at",
            "updated_at",
        )

    def get_assigned_member_name(self, obj):
        if obj.assigned_membership is None:
            return None
        user = obj.assigned_membership.user
        return user.full_name or user.email or obj.assigned_membership.email or "Workspace member"

    def get_assigned_member_role(self, obj):
        if obj.assigned_membership is None:
            return None
        return obj.assigned_membership.role

    def get_assigned_by_name(self, obj):
        if obj.assigned_by_user is None:
            return None
        return obj.assigned_by_user.full_name or obj.assigned_by_user.email

    def get_acknowledged_by_name(self, obj):
        if obj.acknowledged_by_user is None:
            return None
        return obj.acknowledged_by_user.full_name or obj.acknowledged_by_user.email

    def get_escalated_by_name(self, obj):
        if obj.escalated_by_user is None:
            return None
        return obj.escalated_by_user.full_name or obj.escalated_by_user.email

    def get_resolved_by_name(self, obj):
        if obj.resolved_by_user is None:
            return None
        return obj.resolved_by_user.full_name or obj.resolved_by_user.email


class ShopPulseSignalUpdateSerializer(serializers.Serializer):
    action = serializers.ChoiceField(
        choices=[
            "acknowledge",
            "resolve",
            "reopen",
            "assign",
            "clear_assignment",
            "escalate",
            "deescalate",
            "note",
        ]
    )
    note = serializers.CharField(required=False, allow_blank=True, max_length=500)
    assignee_membership_id = serializers.UUIDField(required=False)

    def validate(self, attrs):
        action = attrs["action"]
        note = attrs.get("note", "").strip()
        signal = self.context["signal"]
        actor_membership: ShopMembership = self.context["actor_membership"]

        if action == "assign":
            assignee_membership_id = attrs.get("assignee_membership_id")
            if assignee_membership_id is None:
                raise serializers.ValidationError(
                    {"assignee_membership_id": "Choose an active workspace member to assign this signal."}
                )
            assignee_membership = (
                ShopMembership.objects.select_related("user")
                .filter(shop=signal.shop, pk=assignee_membership_id)
                .first()
            )
            if assignee_membership is None:
                raise serializers.ValidationError(
                    {"assignee_membership_id": "That workspace member could not be found."}
                )
            if not can_assign_workspace_pulse_signal(actor_membership, assignee_membership):
                raise serializers.ValidationError(
                    {"assignee_membership_id": "Your workspace role cannot assign this signal to that member."}
                )
            attrs["assignee_membership"] = assignee_membership

        if action == "clear_assignment" and signal.assigned_membership_id is None:
            raise serializers.ValidationError({"action": "This signal is not assigned right now."})

        if action == "escalate" and signal.is_escalated:
            raise serializers.ValidationError({"action": "This signal is already escalated."})

        if action == "deescalate" and not signal.is_escalated:
            raise serializers.ValidationError({"action": "This signal is not escalated right now."})

        if action == "note" and not note:
            raise serializers.ValidationError({"note": "Add a follow-up note before saving."})

        if action == "resolve" and not note:
            attrs["note"] = "Resolved from pulse control."

        return attrs

    def apply(self, *, signal: ShopPulseSignal, actor_user):
        action = self.validated_data["action"]
        note = self.validated_data.get("note", "").strip()
        assignee_membership = self.validated_data.get("assignee_membership")

        from django.utils import timezone

        current_time = timezone.now()
        update_fields = ["updated_at"]

        if action == "acknowledge":
            signal.status = ShopPulseSignal.Status.ACKNOWLEDGED
            signal.acknowledged_at = current_time
            signal.acknowledged_by_user = actor_user
            if note:
                signal.follow_up_note = note
                update_fields.append("follow_up_note")
            update_fields.extend(["status", "acknowledged_at", "acknowledged_by_user"])
        elif action == "resolve":
            signal.status = ShopPulseSignal.Status.RESOLVED
            signal.resolved_at = current_time
            signal.resolved_by_user = actor_user
            signal.resolution_note = note
            update_fields.extend(["status", "resolved_at", "resolved_by_user", "resolution_note"])
        elif action == "assign":
            signal.assigned_membership = assignee_membership
            signal.assigned_at = current_time
            signal.assigned_by_user = actor_user
            if signal.status == ShopPulseSignal.Status.OPEN:
                signal.status = ShopPulseSignal.Status.ACKNOWLEDGED
                signal.acknowledged_at = current_time
                signal.acknowledged_by_user = actor_user
                update_fields.extend(["status", "acknowledged_at", "acknowledged_by_user"])
            if note:
                signal.follow_up_note = note
                update_fields.append("follow_up_note")
            update_fields.extend(["assigned_membership", "assigned_at", "assigned_by_user"])
        elif action == "clear_assignment":
            signal.assigned_membership = None
            signal.assigned_at = None
            signal.assigned_by_user = None
            if note:
                signal.follow_up_note = note
                update_fields.append("follow_up_note")
            update_fields.extend(["assigned_membership", "assigned_at", "assigned_by_user"])
        elif action == "escalate":
            signal.is_escalated = True
            signal.escalated_at = current_time
            signal.escalated_by_user = actor_user
            signal.escalation_note = note
            update_fields.extend(
                ["is_escalated", "escalated_at", "escalated_by_user", "escalation_note"]
            )
        elif action == "deescalate":
            signal.is_escalated = False
            signal.escalated_at = None
            signal.escalated_by_user = None
            signal.escalation_note = note
            update_fields.extend(
                ["is_escalated", "escalated_at", "escalated_by_user", "escalation_note"]
            )
        elif action == "note":
            signal.follow_up_note = note
            update_fields.append("follow_up_note")
        else:
            signal.status = ShopPulseSignal.Status.OPEN
            signal.acknowledged_at = None
            signal.acknowledged_by_user = None
            signal.resolved_at = None
            signal.resolved_by_user = None
            if note:
                signal.follow_up_note = note
                update_fields.append("follow_up_note")
            update_fields.extend(
                [
                    "status",
                    "acknowledged_at",
                    "acknowledged_by_user",
                    "resolved_at",
                    "resolved_by_user",
                ]
            )

        signal.save(update_fields=update_fields)
        return signal

from __future__ import annotations

from decimal import Decimal

from django.db import transaction
from django.utils import timezone
from rest_framework import serializers

from platform_apps.customers.loyalty import (
    clamp_redemption,
    points_for_sale,
    redemption_value,
)
from platform_apps.customers.models import (
    Customer,
    CustomerLedgerEntry,
    LoyaltyLedgerEntry,
)
from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.payments.models import SalePayment
from platform_apps.sales.gst import apportion_discount, compute_line_gst
from platform_apps.sales.models import Sale, SaleItem


class SaleSummarySerializer(serializers.Serializer):
    total_sales = serializers.IntegerField()
    gross_revenue = serializers.DecimalField(max_digits=12, decimal_places=2)
    collected_revenue = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False
    )
    outstanding_revenue = serializers.DecimalField(
        max_digits=12,
        decimal_places=2,
        allow_null=True,
    )
    average_ticket = serializers.DecimalField(
        max_digits=12,
        decimal_places=2,
        allow_null=True,
    )


class SaleGstSummarySerializer(serializers.Serializer):
    taxable_amount = serializers.DecimalField(max_digits=14, decimal_places=2)
    tax_amount = serializers.DecimalField(max_digits=14, decimal_places=2)
    cgst_amount = serializers.DecimalField(max_digits=14, decimal_places=2)
    sgst_amount = serializers.DecimalField(max_digits=14, decimal_places=2)
    igst_amount = serializers.DecimalField(max_digits=14, decimal_places=2)
    gross_amount = serializers.DecimalField(max_digits=14, decimal_places=2)
    
    # Nested serializers for aggregated lists
    b2c_small = serializers.ListField(
        child=serializers.DictField(), required=False, default=list
    )
    hsn_summary = serializers.ListField(
        child=serializers.DictField(), required=False, default=list
    )


class SaleItemSerializer(serializers.ModelSerializer):
    inventory_item_id = serializers.UUIDField(required=False, allow_null=True)
    name = serializers.CharField(source="name_snapshot", required=False, allow_blank=True)
    sku = serializers.CharField(source="sku_snapshot", required=False, allow_blank=True)
    size = serializers.CharField(source="size_snapshot", required=False, allow_blank=True)
    line_total = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    # Per-item discount entered by the cashier (e.g. money off one line in a
    # multi-item bill). Applied before the sale-level discount is apportioned;
    # the stored line_discount is the sum of the two.
    discount = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, write_only=True, default=Decimal("0.00")
    )

    class Meta:
        model = SaleItem
        fields = (
            "id",
            "inventory_item_id",
            "name",
            "sku",
            "size",
            "quantity",
            "unit_price",
            "unit_cost",
            "line_total",
            "line_discount",
            "discount",
            "hsn_snapshot",
            "gst_rate",
            "taxable_amount",
            "tax_amount",
            "cgst_amount",
            "sgst_amount",
            "igst_amount",
            "is_return",
        )
        # GST fields are server-computed from the catalog item, never client input.
        read_only_fields = (
            "id",
            "line_total",
            "line_discount",
            "hsn_snapshot",
            "gst_rate",
            "taxable_amount",
            "tax_amount",
            "cgst_amount",
            "sgst_amount",
            "igst_amount",
        )


class SalePaymentWriteSerializer(serializers.ModelSerializer):
    class Meta:
        model = SalePayment
        fields = (
            "id",
            "payment_method",
            "amount",
            "reference_code",
            "note",
            "occurred_at",
        )
        read_only_fields = ("id", "occurred_at")


class SaleSerializer(serializers.ModelSerializer):
    customer_id = serializers.UUIDField(required=False, allow_null=True)
    customer_name = serializers.CharField(source="customer_name_snapshot", required=False, allow_blank=True)
    customer_phone = serializers.CharField(source="customer_phone_snapshot", required=False, allow_blank=True)
    items = SaleItemSerializer(many=True)
    payments = SalePaymentWriteSerializer(many=True)
    actor_name = serializers.SerializerMethodField(read_only=True)
    item_count = serializers.SerializerMethodField(read_only=True)
    payment_count = serializers.SerializerMethodField(read_only=True)
    subtotal_amount = serializers.DecimalField(max_digits=12, decimal_places=2, required=False)
    total_amount = serializers.DecimalField(max_digits=12, decimal_places=2, required=False)
    amount_received = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    amount_due = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    sale_date = serializers.DateField(required=False)
    occurred_at = serializers.DateTimeField(required=False)
    # Loyalty points the customer wants to spend on this bill. The server
    # decides what is actually allowed — never trust a client-side discount.
    redeem_points = serializers.IntegerField(
        required=False, min_value=0, write_only=True, default=0
    )

    class Meta:
        model = Sale
        fields = (
            "id",
            "receipt_number",
            "customer_id",
            "customer_name",
            "customer_phone",
            "subtotal_amount",
            "discount_amount",
            "total_amount",
            "taxable_amount",
            "tax_amount",
            "cgst_amount",
            "sgst_amount",
            "igst_amount",
            "place_of_supply_state",
            "amount_received",
            "amount_due",
            "payment_mode",
            "footer_note",
            "buyer_gstin",
            "note",
            "sale_date",
            "occurred_at",
            "status",
            "tombstone",
            "source_meta_json",
            "actor_name",
            "item_count",
            "payment_count",
            "items",
            "payments",
            "redeem_points",
        )
        read_only_fields = (
            "id",
            "receipt_number",
            "payment_mode",
            "taxable_amount",
            "tax_amount",
            "cgst_amount",
            "sgst_amount",
            "igst_amount",
            "amount_received",
            "amount_due",
            "status",
            "tombstone",
            "actor_name",
            "item_count",
            "payment_count",
        )

    def get_actor_name(self, obj):
        if obj.actor_user_id and obj.actor_user.full_name:
            return obj.actor_user.full_name
        if obj.actor_user_id:
            return obj.actor_user.email
        return None

    def get_item_count(self, obj):
        prefetched = getattr(obj, "_prefetched_objects_cache", {})
        if "items" in prefetched:
            return sum(item.quantity for item in prefetched["items"])
        return sum(obj.items.values_list("quantity", flat=True))

    def get_payment_count(self, obj):
        prefetched = getattr(obj, "_prefetched_objects_cache", {})
        if "payments" in prefetched:
            return len(prefetched["payments"])
        return obj.payments.count()

    def validate(self, attrs):
        items = attrs.get("items") or []
        payments = attrs.get("payments") or []
        discount_amount = attrs.get("discount_amount", Decimal("0.00"))
        declared_subtotal = attrs.get("subtotal_amount")
        declared_total = attrs.get("total_amount")

        if not items:
            raise serializers.ValidationError({"items": "At least one sale item is required."})
        if not payments:
            raise serializers.ValidationError({"payments": "At least one payment is required."})

        computed_subtotal = Decimal("0.00")
        item_discount_total = Decimal("0.00")
        total_paid = Decimal("0.00")

        for item in items:
            quantity = Decimal(str(item.get("quantity", 0)))
            if quantity <= 0:
                raise serializers.ValidationError({"items": "Each sale item must have a positive quantity."})
            unit_price = item.get("unit_price") or Decimal("0.00")
            line_gross = Decimal(quantity) * unit_price
            computed_subtotal += line_gross
            # Per-item discounts reduce what the customer owes, exactly like the
            # sale-level discount. Missing this made an item discount look like
            # an unpaid balance instead of money off the bill.
            line_discount = Decimal(str(item.get("discount") or "0.00"))
            if line_discount < Decimal("0.00"):
                line_discount = Decimal("0.00")
            if line_discount > line_gross:
                line_discount = line_gross
            item_discount_total += line_discount

        for payment in payments:
            amount = payment.get("amount") or Decimal("0.00")
            if amount <= 0:
                raise serializers.ValidationError({"payments": "Each payment amount must be positive."})
            total_paid += amount

        if declared_subtotal is not None and declared_subtotal != computed_subtotal:
            raise serializers.ValidationError(
                {"subtotal_amount": f"Subtotal must match item totals ({computed_subtotal})."}
            )

        # Loyalty redemption reduces what the customer owes, so it has to be
        # resolved HERE — computing it later would leave payments validated
        # against a total that no longer exists.
        shop = self.context.get("shop")
        redeem_requested = int(attrs.get("redeem_points") or 0)
        redeemed_points = 0
        redeem_value = Decimal("0.00")
        if shop is not None and redeem_requested > 0:
            customer = None
            customer_id = attrs.get("customer_id")
            if customer_id:
                customer = Customer.objects.filter(
                    shop=shop, pk=customer_id, tombstone=False
                ).first()
            if customer is None:
                raise serializers.ValidationError(
                    {"redeem_points": "Points can only be redeemed for a saved customer."}
                )
            pre_redemption_total = (
                computed_subtotal - item_discount_total - discount_amount
            )
            redeemed_points = clamp_redemption(
                shop,
                requested=redeem_requested,
                available=customer.loyalty_points,
                bill_total=pre_redemption_total,
            )
            if redeemed_points <= 0:
                raise serializers.ValidationError(
                    {"redeem_points": "Not enough points available for this bill."}
                )
            redeem_value = redemption_value(shop, redeemed_points)

        expected_total = (
            computed_subtotal - item_discount_total - discount_amount - redeem_value
        )
        if expected_total < Decimal("0.00"):
            raise serializers.ValidationError({"discount_amount": "Discount cannot exceed subtotal."})

        if declared_total is not None and declared_total != expected_total:
            raise serializers.ValidationError({"total_amount": f"Total must equal subtotal minus discount ({expected_total})."})

        if total_paid > expected_total:
            raise serializers.ValidationError({"payments": "Payments cannot exceed the sale total in phase 1."})

        attrs["_computed_subtotal"] = computed_subtotal
        attrs["_item_discount_total"] = item_discount_total
        attrs["_redeemed_points"] = redeemed_points
        attrs["_redeem_value"] = redeem_value
        attrs["_computed_total"] = expected_total
        attrs["_computed_paid"] = total_paid
        attrs["_computed_due"] = expected_total - total_paid
        return attrs

    def _resolve_inventory_item(self, shop, item_payload):
        inventory_item_id = item_payload.get("inventory_item_id")
        if not inventory_item_id:
            return None
        try:
            return InventoryItem.objects.select_related("private").get(
                pk=inventory_item_id,
                shop=shop,
                tombstone=False,
            )
        except InventoryItem.DoesNotExist as exc:
            raise serializers.ValidationError({"items": f"Inventory item {inventory_item_id} is not available in this shop."}) from exc

    def _resolve_customer(self, shop, customer_id):
        if not customer_id:
            return None
        try:
            return Customer.objects.get(pk=customer_id, shop=shop, tombstone=False)
        except Customer.DoesNotExist as exc:
            raise serializers.ValidationError({"customer_id": "Customer is not available in this shop."}) from exc

    @transaction.atomic
    def create(self, validated_data):
        item_payloads = validated_data.pop("items")
        payment_payloads = validated_data.pop("payments")
        validated_data.pop("redeem_points", None)
        redeemed_points = validated_data.pop("_redeemed_points", 0)
        redeem_value = validated_data.pop("_redeem_value", Decimal("0.00"))
        computed_subtotal = validated_data.pop("_computed_subtotal")
        item_discount_total = validated_data.pop("_item_discount_total", Decimal("0.00"))
        computed_total = validated_data.pop("_computed_total")
        computed_paid = validated_data.pop("_computed_paid")
        computed_due = validated_data.pop("_computed_due")

        # The bill-level discount is what gets apportioned across lines; the
        # stored discount_amount is the total the customer actually saved
        # (per-item + bill-level), so receipts and History report one figure.
        bill_discount = validated_data.get("discount_amount") or Decimal("0.00")
        validated_data["discount_amount"] = (
            bill_discount + item_discount_total + redeem_value
        )

        shop = self.context["shop"]
        actor = self.context["actor"]
        customer = self._resolve_customer(shop, validated_data.pop("customer_id", None))

        sale_date = validated_data.get("sale_date") or timezone.localdate()
        occurred_at = validated_data.get("occurred_at") or timezone.now()
        validated_data["sale_date"] = sale_date
        validated_data["occurred_at"] = occurred_at

        customer_name_snapshot = validated_data.pop("customer_name_snapshot", "")
        customer_phone_snapshot = validated_data.pop("customer_phone_snapshot", "")
        if customer is not None:
            customer_name_snapshot = customer_name_snapshot or customer.name
            customer_phone_snapshot = customer_phone_snapshot or customer.phone

        payment_mode = payment_payloads[0]["payment_method"] if len(payment_payloads) == 1 else Sale.PaymentMode.SPLIT

        # Drop the client's own subtotal/total. They are writable so a caller
        # can send them, and validate() already checked them against the figures
        # computed from the items — but they are a cross-check, never the stored
        # value. Left in validated_data they arrive as a second value for a
        # keyword create() is already given below, and Python raises
        # "got multiple values for keyword argument", which surfaces as a 500 on
        # the one action a shop performs most: completing a sale.
        validated_data.pop("subtotal_amount", None)
        validated_data.pop("total_amount", None)

        sale = Sale.objects.create(
            shop=shop,
            actor_user=actor,
            customer=customer,
            customer_name_snapshot=customer_name_snapshot,
            customer_phone_snapshot=customer_phone_snapshot,
            subtotal_amount=computed_subtotal,
            total_amount=computed_total,
            amount_received=computed_paid,
            amount_due=computed_due,
            payment_mode=payment_mode,
            **validated_data,
        )
        sale.receipt_number = sale.receipt_number or f"S-{str(sale.id).replace('-', '')[:8].upper()}"
        sale.save(update_fields=["receipt_number", "updated_at"])

        # GST: supplier state vs place of supply decides CGST+SGST (intra) vs
        # IGST (inter). Accept place_of_supply_state from the client; default
        # to the shop's own state (the common counter-sale case). Fall back to
        # intra-state when state codes are unconfigured so a missing state
        # never misclassifies as inter-state.
        supplier_state = (shop.state_code or "").strip()
        place_of_supply = (
            validated_data.pop("place_of_supply_state", "") or supplier_state
        ).strip()
        from platform_apps.sales.gst import is_intra_state
        intra_state = (not supplier_state) or is_intra_state(supplier_state, place_of_supply)

        # --- Discount apportionment ---
        # Distribute the sale-level discount proportionally across lines so
        # GST is computed on the post-discount value per line.
        # Only the bill-level portion is spread across lines — the per-item part
        # is already attributed to its own line below.
        discount_amount = bill_discount
        raw_line_totals = [
            Decimal(str(ip["quantity"])) * ip["unit_price"] for ip in item_payloads
        ]
        # Per-item discounts come off first (never more than the line itself),
        # then the sale-level discount is apportioned over what remains.
        item_level_discounts = []
        for idx, ip in enumerate(item_payloads):
            requested = ip.get("discount") or Decimal("0.00")
            requested = Decimal(str(requested))
            if requested < Decimal("0.00"):
                requested = Decimal("0.00")
            if requested > raw_line_totals[idx]:
                requested = raw_line_totals[idx]
            item_level_discounts.append(requested)
        net_line_totals = [
            raw_line_totals[i] - item_level_discounts[i] for i in range(len(raw_line_totals))
        ]
        apportioned = apportion_discount(net_line_totals, discount_amount)
        line_discounts = [
            item_level_discounts[i] + apportioned[i] for i in range(len(apportioned))
        ]

        sale_taxable = Decimal("0.00")
        sale_tax = Decimal("0.00")
        sale_cgst = Decimal("0.00")
        sale_sgst = Decimal("0.00")
        sale_igst = Decimal("0.00")

        for idx, item_payload in enumerate(item_payloads):
            inventory_item = self._resolve_inventory_item(shop, item_payload)
            quantity = Decimal(str(item_payload["quantity"]))
            unit_price = item_payload["unit_price"]
            unit_cost = item_payload.get("unit_cost")
            is_return = item_payload.get("is_return", False)

            if inventory_item is not None:
                item_name = item_payload.get("name_snapshot") or inventory_item.name
                sku_snapshot = item_payload.get("sku_snapshot") or inventory_item.sku
                size_snapshot = item_payload.get("size_snapshot") or inventory_item.size
                if unit_cost is None and hasattr(inventory_item, "private") and not inventory_item.private.tombstone:
                    unit_cost = inventory_item.private.cost_price
            else:
                item_name = item_payload.get("name_snapshot") or ""
                sku_snapshot = item_payload.get("sku_snapshot") or ""
                size_snapshot = item_payload.get("size_snapshot") or ""
                if not item_name:
                    raise serializers.ValidationError({"items": "Non-catalog items must include a name."})

            line_total = Decimal(quantity) * unit_price
            item_discount = line_discounts[idx]

            # GST is derived from the catalog item; non-catalog lines are
            # untaxed (rate 0 -> passthrough). hsn/rate are snapshotted so the
            # receipt stays correct if the item is later edited.
            if inventory_item is not None:
                gst_rate = inventory_item.gst_rate
                hsn_snapshot = inventory_item.hsn_code
                price_includes_tax = inventory_item.price_includes_tax
            else:
                gst_rate = Decimal("0.00")
                hsn_snapshot = ""
                price_includes_tax = True

            # Compute GST on the post-discount line value.
            gst = compute_line_gst(
                line_total - item_discount,
                gst_rate,
                price_includes_tax=price_includes_tax,
                intra_state=intra_state,
            )

            # Return items contribute negatively to sale totals.
            sign = Decimal("-1") if is_return else Decimal("1")
            sale_taxable += sign * gst.taxable_amount
            sale_tax += sign * gst.tax_amount
            sale_cgst += sign * gst.cgst_amount
            sale_sgst += sign * gst.sgst_amount
            sale_igst += sign * gst.igst_amount

            sale_item = SaleItem.objects.create(
                sale=sale,
                position=idx,
                inventory_item=inventory_item,
                name_snapshot=item_name,
                sku_snapshot=sku_snapshot,
                size_snapshot=size_snapshot,
                quantity=quantity,
                unit_price=unit_price,
                unit_cost=unit_cost,
                line_total=line_total,
                line_discount=item_discount,
                hsn_snapshot=hsn_snapshot,
                gst_rate=gst_rate,
                taxable_amount=sign * gst.taxable_amount,
                tax_amount=sign * gst.tax_amount,
                cgst_amount=sign * gst.cgst_amount,
                sgst_amount=sign * gst.sgst_amount,
                igst_amount=sign * gst.igst_amount,
                is_return=is_return,
                source_system=sale.source_system,
                source_shop_id=sale.source_shop_id,
                source_path=f"sales/{sale.id}/items",
                domain_epoch=sale.domain_epoch,
            )

            if inventory_item is not None:
                InventoryStockLedger.objects.create(
                    shop=shop,
                    item=inventory_item,
                    actor_user=actor,
                    event_type=(
                        InventoryStockLedger.EventType.RETURN
                        if sale_item.is_return
                        else InventoryStockLedger.EventType.SALE
                    ),
                    quantity_delta=quantity if sale_item.is_return else -quantity,
                    unit_cost=unit_cost,
                    unit_price=unit_price,
                    note=f"Sale {sale.receipt_number}",
                    occurred_at=occurred_at,
                    source_system=sale.source_system,
                    source_id=str(sale.id),
                    source_shop_id=sale.source_shop_id,
                    source_path=f"sales/{sale.id}/items/{sale_item.id}",
                    domain_epoch=sale.domain_epoch,
                )

        # Persist sale-level GST totals computed across the lines above.
        sale.taxable_amount = sale_taxable
        sale.tax_amount = sale_tax
        sale.cgst_amount = sale_cgst
        sale.sgst_amount = sale_sgst
        sale.igst_amount = sale_igst
        sale.place_of_supply_state = place_of_supply
        sale.save(
            update_fields=[
                "taxable_amount",
                "tax_amount",
                "cgst_amount",
                "sgst_amount",
                "igst_amount",
                "place_of_supply_state",
                "updated_at",
            ]
        )

        for payment_payload in payment_payloads:
            SalePayment.objects.create(
                sale=sale,
                shop=shop,
                actor_user=actor,
                occurred_at=occurred_at,
                source_system=sale.source_system,
                source_id=str(sale.id),
                source_shop_id=sale.source_shop_id,
                source_path=f"sales/{sale.id}/payments",
                domain_epoch=sale.domain_epoch,
                **payment_payload,
            )

        if customer is not None:
            CustomerLedgerEntry.objects.create(
                shop=shop,
                customer=customer,
                actor_user=actor,
                event_type=CustomerLedgerEntry.EventType.SALE,
                amount_delta=computed_due,
                total_spent_delta=computed_total,
                note=f"Sale {sale.receipt_number}",
                occurred_at=occurred_at,
                source_system=sale.source_system,
                source_id=str(sale.id),
                source_shop_id=sale.source_shop_id,
                source_path=f"sales/{sale.id}",
                domain_epoch=sale.domain_epoch,
            )
            customer.balance = customer.balance + computed_due
            customer.total_spent = customer.total_spent + computed_total

            # --- Loyalty -------------------------------------------------
            # Spend first, then earn on what was actually paid, so a customer
            # can't earn points on the part of the bill they settled with
            # points.
            points = customer.loyalty_points
            if redeemed_points > 0:
                points -= redeemed_points
                LoyaltyLedgerEntry.objects.create(
                    shop=shop,
                    customer=customer,
                    event_type=LoyaltyLedgerEntry.EventType.REDEEMED,
                    points_delta=-redeemed_points,
                    balance_after=max(points, 0),
                    note=f"Redeemed on {sale.receipt_number}",
                    sale_id=sale.id,
                    occurred_at=occurred_at,
                )

            earned = points_for_sale(shop, computed_total)
            if earned > 0:
                points += earned
                LoyaltyLedgerEntry.objects.create(
                    shop=shop,
                    customer=customer,
                    event_type=LoyaltyLedgerEntry.EventType.EARNED,
                    points_delta=earned,
                    balance_after=max(points, 0),
                    note=f"Earned on {sale.receipt_number}",
                    sale_id=sale.id,
                    occurred_at=occurred_at,
                )

            customer.loyalty_points = max(points, 0)
            customer.save(
                update_fields=[
                    "balance",
                    "total_spent",
                    "loyalty_points",
                    "updated_at",
                ]
            )

        return sale


class SaleCommandCreateSerializer(serializers.Serializer):
    command_id = serializers.CharField(max_length=128)
    base_domain_epoch = serializers.IntegerField(min_value=1)
    source_surface = serializers.CharField(max_length=64, required=False, allow_blank=True, default="flutter_pos")
    sale = SaleSerializer()

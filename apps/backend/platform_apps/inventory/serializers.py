from __future__ import annotations

from decimal import Decimal

from django.db import transaction
from django.utils import timezone
from rest_framework import serializers

from platform_apps.common.blob import content_key, get_store
from platform_apps.inventory.image_views import MAX_IMAGE_BYTES, parse_data_uri
from platform_apps.inventory.models import InventoryItem, InventoryItemPrivate, InventoryStockLedger


class InventoryItemSerializer(serializers.ModelSerializer):
    """An inventory item as every client sees it.

    NOTE ON gst_rate — this is deliberate action-at-a-distance, and it is worth
    explaining because a reader will otherwise assume a bug.

    A composition dealer or unregistered shop may not charge GST (s.10 CGST
    Act). Forcing the rate to zero when the SALE is recorded is not sufficient:
    the receipt is what carries the legal exposure, and every client recomputes
    tax locally from its own copy of the catalogue —
    admin_web/src/lib/cart-totals.ts, mobile_flutter/lib/core/receipt/
    receipt_pdf.dart and receipt_printer.dart all do. So the server would store
    zero while the customer was handed paper showing CGST+SGST, which is worse
    than today: the books and the bill would disagree.

    Serving 0.00 from the catalogue API instead reaches every client through
    the data they already sync, including Flutter builds already installed on
    shop phones, with no release. The stored column keeps its real value, so
    nothing is lost when a shop returns to regular registration.

    Reversible in one line once every client understands
    gst_registration_type directly.
    """

    stock_on_hand = serializers.DecimalField(max_digits=12, decimal_places=3, read_only=True)
    has_stock_history = serializers.SerializerMethodField()
    cost_price = serializers.SerializerMethodField()
    supplier_id = serializers.SerializerMethodField()
    last_purchase_date = serializers.SerializerMethodField()
    opening_stock = serializers.DecimalField(max_digits=12, decimal_places=3, write_only=True, required=False, default=0)
    private_cost_price = serializers.DecimalField(
        source="cost_price_input",
        max_digits=12,
        decimal_places=2,
        required=False,
        write_only=True,
    )
    private_supplier_id = serializers.CharField(source="supplier_id_input", required=False, write_only=True, allow_blank=True)
    private_last_purchase_date = serializers.DateField(
        source="last_purchase_date_input",
        required=False,
        write_only=True,
        allow_null=True,
    )
    # Write-only. The picture used to be read back inside every product list,
    # so opening Stock - or the till - downloaded every photo of every product
    # in one uncacheable response. It is served from its own address now, which
    # a browser can cache; see image_views.
    #
    # Omitting the field leaves the existing picture alone. Sending "" clears
    # it. That distinction matters: the edit form posts every field it holds,
    # so without it, saving a change of price would silently delete the photo.
    image_data = serializers.CharField(
        write_only=True, required=False, allow_blank=True
    )
    has_image = serializers.SerializerMethodField()

    class Meta:
        model = InventoryItem
        fields = (
            "id",
            "name",
            "sku",
            "barcode",
            "category",
            "subcategory",
            "size",
            "description",
            "sell_price",
            "hsn_code",
            "gst_rate",
            "price_includes_tax",
            "unit",
            "reorder_level",
            "status",
            "tombstone",
            "source_meta_json",
            "image_data",
            "has_image",
            "stock_on_hand",
            "has_stock_history",
            "cost_price",
            "supplier_id",
            "last_purchase_date",
            "created_at",
            "opening_stock",
            "private_cost_price",
            "private_supplier_id",
            "private_last_purchase_date",
        )
        read_only_fields = ("id", "stock_on_hand", "created_at")

    def get_has_image(self, obj) -> bool:
        """Whether there is a picture to fetch, without sending it.

        The screen needs this to decide between an <img> and the fallback
        initial, and asking for the picture just to find out there is none
        would undo the point of moving it out of the list.
        """
        return bool(
            (getattr(obj, "image_key", "") or "").strip()
            or (getattr(obj, "image_data", "") or "").strip()
        )

    def get_has_stock_history(self, obj) -> bool:
        """Was this item ever given stock?

        Annotated by the list queries. Defaults to False when it is absent
        rather than inventing a True: claiming an item is tracked when nobody
        checked is exactly the confusion this field exists to remove.
        """
        return bool(getattr(obj, "has_stock_history", False))

    def _can_view_costs(self) -> bool:
        return bool(self.context.get("can_view_costs"))

    def _can_view_supplier_directory(self) -> bool:
        return bool(self.context.get("can_view_supplier_directory"))

    def _can_view_purchase_workflow(self) -> bool:
        return bool(self.context.get("can_view_purchase_workflow"))

    def validate_image_data(self, value):
        """A picture, and one that fits in a row.

        There was no limit at all. The browser resizes to about 60 KB before
        upload, but anything calling the API directly could store an image of
        any size - in a column on the product, so it would then travel with
        every backup and every replica of the table the till reads.
        """
        candidate = (value or "").strip()
        if not candidate:
            return ""  # Deliberately clearing the picture.
        if parse_data_uri(candidate) is None:
            raise serializers.ValidationError(
                "Expected a JPEG, PNG, WebP or GIF image."
            )
        if len(candidate.encode("utf-8")) > MAX_IMAGE_BYTES:
            raise serializers.ValidationError(
                "That picture is too large. It is resized before upload, so "
                "this usually means it did not go through the picker."
            )
        return candidate

    def validate(self, attrs):
        supplier_id = attrs.get("supplier_id_input")
        last_purchase_date = attrs.get("last_purchase_date_input")

        if (
            supplier_id not in (None, "")
            and not self._can_view_supplier_directory()
        ):
            raise serializers.ValidationError(
                {
                    "private_supplier_id": (
                        "Supplier directory is not enabled for this workspace plan."
                    )
                }
            )

        if (
            last_purchase_date is not None
            and not self._can_view_purchase_workflow()
        ):
            raise serializers.ValidationError(
                {
                    "private_last_purchase_date": (
                        "Purchase workflow is not enabled for this workspace plan."
                    )
                }
            )

        return attrs

    def to_representation(self, instance):
        """Mask the GST rate for a shop that may not charge it.

        Done here rather than as a SerializerMethodField so the field stays
        WRITABLE — a method field is read-only, which would have quietly broken
        product creation and editing for every shop. See the class docstring
        for why the read has to be masked at all.
        """
        data = super().to_representation(instance)
        shop = self.context.get("shop")
        if shop is not None and not shop.collects_gst:
            data["gst_rate"] = "0.00"
        return data

    def get_cost_price(self, obj):
        if not self._can_view_costs():
            return None
        private = getattr(obj, "private", None)
        return private.cost_price if private and not private.tombstone else None

    def get_supplier_id(self, obj):
        if not self._can_view_supplier_directory():
            return None
        private = getattr(obj, "private", None)
        return private.supplier_id if private and not private.tombstone else None

    def get_last_purchase_date(self, obj):
        if not self._can_view_purchase_workflow():
            return None
        private = getattr(obj, "private", None)
        return private.last_purchase_date if private and not private.tombstone else None

    @transaction.atomic
    def _store_image(self, validated_data: dict) -> None:
        """Move a submitted picture into object storage, in place.

        Rewrites image_data into image_key so the bytes never reach the
        product row. The column is cleared rather than left alongside: keeping
        both would mean every backup still carried the picture, which is the
        whole thing this was meant to stop.
        """
        if "image_data" not in validated_data:
            return  # Untouched. Leave whatever is stored exactly as it is.

        candidate = (validated_data.pop("image_data") or "").strip()
        if not candidate:
            # Deliberately cleared. Both places have to be emptied, or the
            # fallback would keep serving the picture that was just removed.
            validated_data["image_data"] = ""
            validated_data["image_key"] = ""
            return

        parsed = parse_data_uri(candidate)
        if parsed is None:
            # validate_image_data already refused anything unusable, so this
            # is unreachable in practice - and if it ever is reached, storing
            # nothing beats storing something that will not render.
            validated_data["image_data"] = ""
            validated_data["image_key"] = ""
            return

        media_type, payload = parsed
        key = content_key(payload, media_type)
        get_store().put(key, payload, media_type)
        validated_data["image_key"] = key
        validated_data["image_data"] = ""

    def create(self, validated_data):
        self._store_image(validated_data)
        opening_stock = Decimal(str(validated_data.pop("opening_stock", 0)))
        cost_price = validated_data.pop("cost_price_input", None)
        supplier_id = validated_data.pop("supplier_id_input", "")
        last_purchase_date = validated_data.pop("last_purchase_date_input", None)
        shop = self.context["shop"]
        actor = self.context["actor"]

        item = InventoryItem.objects.create(shop=shop, **validated_data)

        if (
            self._can_view_costs()
            and any(
                value is not None and value != ""
                for value in [cost_price, supplier_id, last_purchase_date]
            )
        ):
            InventoryItemPrivate.objects.create(
                item=item,
                cost_price=cost_price if cost_price is not None else Decimal("0.00"),
                supplier_id=(
                    supplier_id if self._can_view_supplier_directory() else ""
                ),
                last_purchase_date=(
                    last_purchase_date
                    if self._can_view_purchase_workflow()
                    else None
                ),
                source_system=validated_data.get("source_system", ""),
                source_shop_id=validated_data.get("source_shop_id", ""),
            )

        if opening_stock != 0:
            InventoryStockLedger.objects.create(
                shop=shop,
                item=item,
                actor_user=actor,
                event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
                quantity_delta=opening_stock,
                unit_cost=cost_price if self._can_view_costs() and cost_price is not None else None,
                unit_price=item.sell_price,
                note="Opening balance",
                occurred_at=timezone.now(),
                source_system=validated_data.get("source_system", ""),
                source_shop_id=validated_data.get("source_shop_id", ""),
            )

        return item

    @transaction.atomic
    def update(self, instance, validated_data):
        self._store_image(validated_data)
        validated_data.pop("opening_stock", None)
        cost_price = validated_data.pop("cost_price_input", None)
        supplier_id = validated_data.pop("supplier_id_input", None)
        last_purchase_date = validated_data.pop("last_purchase_date_input", None)

        for field, value in validated_data.items():
            setattr(instance, field, value)
        instance.save()

        if self._can_view_costs():
            private, _ = InventoryItemPrivate.objects.get_or_create(item=instance)
            updated = False
            if cost_price is not None:
                private.cost_price = cost_price
                updated = True
            if supplier_id is not None and self._can_view_supplier_directory():
                private.supplier_id = supplier_id
                updated = True
            if (
                last_purchase_date is not None
                and self._can_view_purchase_workflow()
            ):
                private.last_purchase_date = last_purchase_date
                updated = True
            if updated:
                private.save()

        return instance


class InventoryAdjustmentSerializer(serializers.Serializer):
    quantity_delta = serializers.DecimalField(max_digits=12, decimal_places=3)
    note = serializers.CharField(required=False, allow_blank=True, max_length=2000)
    event_type = serializers.ChoiceField(
        choices=[
            InventoryStockLedger.EventType.ADJUSTMENT,
            InventoryStockLedger.EventType.IMPORT,
            InventoryStockLedger.EventType.SYNC,
            InventoryStockLedger.EventType.RETURN,
        ],
        default=InventoryStockLedger.EventType.ADJUSTMENT,
    )


class InventorySummarySerializer(serializers.Serializer):
    total_items = serializers.IntegerField()
    available_items = serializers.IntegerField()
    low_stock_items = serializers.IntegerField()
    out_of_stock_items = serializers.IntegerField()
    categories = serializers.IntegerField()
    projected_sell_value = serializers.DecimalField(
        max_digits=14,
        decimal_places=2,
        allow_null=True,
    )

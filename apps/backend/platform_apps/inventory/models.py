from __future__ import annotations

from decimal import Decimal

from django.conf import settings
from django.db import models
from django.db.models.functions import Lower

from platform_apps.common.managers import TenantAwareManager
from platform_apps.common.models import SourceTrackedModel
from platform_apps.shops.models import Shop


class InventoryItem(SourceTrackedModel):
    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        ARCHIVED = "archived", "Archived"
        DRAFT = "draft", "Draft"

    shop = models.ForeignKey(Shop, on_delete=models.CASCADE, related_name="inventory_items")
    name = models.CharField(max_length=255)
    sku = models.CharField(max_length=128, blank=True)
    barcode = models.CharField(max_length=128, blank=True)
    category = models.CharField(max_length=120, blank=True)
    subcategory = models.CharField(max_length=120, blank=True)
    size = models.CharField(max_length=64, blank=True)
    description = models.TextField(blank=True)
    sell_price = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    # GST (India). hsn_code = Harmonized System of Nomenclature / SAC for services.
    # gst_rate is the combined percentage (e.g. 18.00); intra-state splits into
    # CGST+SGST, inter-state uses IGST — resolved at sale time from place of supply.
    hsn_code = models.CharField(max_length=16, blank=True)
    gst_rate = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal("0.00"))
    price_includes_tax = models.BooleanField(default=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.ACTIVE)
    # How the shop counts this item ("kg", "pcs", "mtr"). Free text because a
    # kirana and a garment shop do not share a unit list.
    unit = models.CharField(max_length=32, blank=True)
    # Stock level at which the item joins the buying list. Null means "use the
    # shop default" rather than "never reorder", so an item nobody has
    # configured still shows up before it runs out.
    reorder_level = models.PositiveIntegerField(blank=True, null=True)
    tombstone = models.BooleanField(default=False)
    source_meta_json = models.JSONField(default=dict, blank=True)
    #: Attributes only some kinds of shop have.
    #:
    #: A garment retailer stocks a style in sizes and colours; a wholesaler
    #: sells that style by the dozen with a minimum order and a price that
    #: drops in bulk; a grocer has none of these. Giving each its own column
    #: would mean a migration per business type and a table of mostly-empty
    #: columns - and the list is not finished, because pharmacy wants batch and
    #: expiry and restaurant wants a recipe.
    #:
    #: So they live here, under an ALLOWLIST enforced by the serializer. A JSON
    #: column on a public write endpoint with no allowlist is a place for
    #: arbitrary client data to accumulate until nobody knows what a row holds.
    #:
    #: Known keys: profile, colour, fabric, season, moq, price_tiers.
    #: The selling unit is NOT here - `unit` above already holds it.
    attributes_json = models.JSONField(default=dict, blank=True)
    # Product photo as a base64 data URI. Stored in the DB (not MEDIA_ROOT)
    # because the single-node Docker deploy only persists the database volume —
    # files written into the container are lost on every redeploy. Clients send
    # a downscaled/compressed copy, so rows stay small.
    # Kept for rows not yet moved to object storage, and as the fallback the
    # image view reads when image_key is empty. New writes go to the store.
    image_data = models.TextField(blank=True)
    #: Where the photo actually lives now. Content-addressed, so the same
    #: picture on two products is stored once and a changed picture is a new
    #: key rather than an invalidation problem.
    image_key = models.CharField(max_length=255, blank=True)

    class Meta:
        constraints = [
            # A code has to mean one product. The till resolves a scan by
            # taking the first item whose code matches, so a duplicate rings
            # up the wrong product, silently, at the counter.
            #
            # On Lower(sku), not sku: a plain unique index in Postgres is case
            # sensitive, so ABC-1 and abc-1 would both be allowed while a scan
            # treats them as one. That would read as protection while allowing
            # the exact collision it exists to prevent.
            #
            # Partial, and both conditions matter. Blank is excluded because
            # most shops leave the code empty on most products. Tombstoned
            # rows are excluded so an archived product does not hold a code
            # for ever.
            models.UniqueConstraint(
                models.F("shop"),
                Lower("sku"),
                condition=models.Q(tombstone=False) & ~models.Q(sku=""),
                name="uniq_active_sku_per_shop",
            ),
        ]
        indexes = [
            models.Index(fields=["shop", "name"]),
            models.Index(fields=["shop", "sku"]),
            models.Index(fields=["shop", "category"]),
        ]

    def __str__(self) -> str:
        return f"{self.name} ({self.shop.name})"


class InventoryItemPrivate(SourceTrackedModel):
    item = models.OneToOneField(InventoryItem, on_delete=models.CASCADE, related_name="private")
    cost_price = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    supplier_id = models.CharField(max_length=128, blank=True)
    last_purchase_date = models.DateField(blank=True, null=True)
    tombstone = models.BooleanField(default=False)

    def __str__(self) -> str:
        return f"Private<{self.item.name}>"


class InventoryStockLedger(SourceTrackedModel):
    class EventType(models.TextChoices):
        OPENING_BALANCE = "opening_balance", "Opening balance"
        ADJUSTMENT = "adjustment", "Adjustment"
        SALE = "sale", "Sale"
        RETURN = "return", "Return"
        PURCHASE = "purchase", "Purchase"
        IMPORT = "import", "Import"
        SYNC = "sync", "Sync"
        # Two halves of a StockTransfer. Kept distinct from ADJUSTMENT so a
        # report can tell "stock left this shop because it moved" from "stock
        # left this shop because someone corrected a count".
        TRANSFER_OUT = "transfer_out", "Transfer out"
        TRANSFER_IN = "transfer_in", "Transfer in"

    shop = models.ForeignKey(Shop, on_delete=models.CASCADE, related_name="inventory_stock_ledger")
    item = models.ForeignKey(InventoryItem, on_delete=models.CASCADE, related_name="ledger_entries")
    actor_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="stock_events",
        blank=True,
        null=True,
    )
    event_type = models.CharField(max_length=32, choices=EventType.choices)
    quantity_delta = models.DecimalField(max_digits=12, decimal_places=3)
    #: What ONE of quantity_delta was, at the moment this row was written.
    #:
    #: The number alone does not say. "3" is three pieces or three dozen
    #: depending on the item's unit - and the item's unit is a field a
    #: shopkeeper can change. Change it from piece to dozen after a year of
    #: trading and every historical row silently re-reads as twelve times what
    #: it was, with nothing anywhere recording that it ever meant something
    #: else.
    #:
    #: Snapshotted for the same reason SaleItem keeps name_snapshot and
    #: hsn_snapshot: history has to stay readable without depending on a row
    #: somebody may edit tomorrow.
    #:
    #: Blank on every row written before this existed, which is correct - we
    #: genuinely do not know, and guessing "piece" would invent a fact.
    unit_snapshot = models.CharField(max_length=32, blank=True)
    unit_cost = models.DecimalField(max_digits=12, decimal_places=2, blank=True, null=True)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2, blank=True, null=True)
    note = models.TextField(blank=True)
    occurred_at = models.DateTimeField()

    def save(self, *args, **kwargs):
        """Fill the unit from the item, unless the caller already said.

        Here rather than at each of the eight places that write a stock
        movement - sale, return, purchase, adjustment, opening balance, both
        halves of a transfer, stocktake. One of them forgetting would leave a
        gap nothing reports, and the gap only becomes visible years later when
        somebody asks what a quantity meant.

        Not a guard against bulk_create, which bypasses save() entirely. Rows
        written that way must set it themselves.
        """
        if not self.unit_snapshot and self.item_id:
            self.unit_snapshot = (getattr(self.item, "unit", "") or "").strip()
        return super().save(*args, **kwargs)

    # Auto-scopes reads to the current shop when a Celery TenantTask is running;
    # a no-op in HTTP/admin/tests. Defense against a background job forgetting
    # an explicit shop filter on this aggregation-heavy ledger.
    objects = TenantAwareManager()

    class Meta:
        ordering = ["-occurred_at", "-created_at"]
        indexes = [
            models.Index(fields=["shop", "occurred_at"]),
            models.Index(fields=["item", "occurred_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.item.name}: {self.quantity_delta}"


class StockTransfer(SourceTrackedModel):
    """Goods moving from one of the owner's shops to another.

    Before this existed, moving stock between shops meant adjusting it down in
    one and up in the other, with nothing connecting the two. If the second
    half was forgotten — or done twice, or for a different quantity — the
    totals were quietly wrong and no screen could tell. There was no record
    that a movement had even been intended.

    So a transfer is deliberately two steps, not one. Dispatch removes the
    stock from the source and leaves the transfer IN_TRANSIT; receiving adds it
    at the destination. Anything sitting in IN_TRANSIT is stock that has left
    one shop and not arrived at the other, which is exactly the state that used
    to be invisible.
    """

    class Status(models.TextChoices):
        IN_TRANSIT = "in_transit", "In transit"
        RECEIVED = "received", "Received"
        CANCELLED = "cancelled", "Cancelled"

    source_shop = models.ForeignKey(
        Shop, on_delete=models.CASCADE, related_name="transfers_sent"
    )
    destination_shop = models.ForeignKey(
        Shop, on_delete=models.CASCADE, related_name="transfers_received"
    )
    # Human-facing handle for the paperwork that travels with the goods
    # ("TR-7K2M"). Not unique across shops on purpose: it is a label, not a key.
    reference = models.CharField(max_length=32, blank=True)
    status = models.CharField(
        max_length=16, choices=Status.choices, default=Status.IN_TRANSIT
    )
    note = models.TextField(blank=True)

    dispatched_at = models.DateTimeField()
    received_at = models.DateTimeField(blank=True, null=True)
    cancelled_at = models.DateTimeField(blank=True, null=True)

    dispatched_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="transfers_dispatched",
        blank=True,
        null=True,
    )
    received_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="transfers_received",
        blank=True,
        null=True,
    )

    class Meta:
        ordering = ["-dispatched_at", "-created_at"]
        indexes = [
            models.Index(fields=["source_shop", "status"]),
            models.Index(fields=["destination_shop", "status"]),
        ]

    def __str__(self) -> str:
        return f"{self.reference or self.pk}: {self.source_shop_id} -> {self.destination_shop_id}"


class StockTransferLine(SourceTrackedModel):
    """One item on a transfer.

    `source_item` and `destination_item` are different rows even for the same
    product, because InventoryItem is scoped to a shop. The destination row is
    resolved (or created) at receive time rather than at dispatch, so a
    transfer can be sent to a shop that does not stock the item yet.
    """

    transfer = models.ForeignKey(
        StockTransfer, on_delete=models.CASCADE, related_name="lines"
    )
    source_item = models.ForeignKey(
        InventoryItem, on_delete=models.PROTECT, related_name="transfer_lines_out"
    )
    destination_item = models.ForeignKey(
        InventoryItem,
        on_delete=models.SET_NULL,
        related_name="transfer_lines_in",
        blank=True,
        null=True,
    )
    quantity = models.DecimalField(max_digits=12, decimal_places=3)
    # Carried across so the destination shop's stock valuation is not reset to
    # zero by the move. Null when the source never recorded a cost.
    unit_cost = models.DecimalField(max_digits=12, decimal_places=2, blank=True, null=True)

    def __str__(self) -> str:
        return f"{self.source_item.name} x{self.quantity}"


class Stocktake(SourceTrackedModel):
    """A physical count of the shelves, reconciled against the ledger.

    Correcting stock one item at a time already worked, and nobody does it for
    a whole shop — so the figures drift until they are not trusted, which
    quietly undermines every report built on them.

    The design decision that matters is in how the correction is applied. Each
    line records what the ledger said **at the moment it was counted**, and
    applying the count posts the DIFFERENCE, not the counted figure.

    Counting a shop takes hours and the shop keeps trading. Suppose an item
    reads 10, the counter finds 8, and three more sell before the count is
    applied. Setting stock to 8 would silently undo those three sales. Posting
    the variance of -2 against a ledger that now reads 7 gives 5, which is what
    is actually on the shelf.
    """

    class Status(models.TextChoices):
        OPEN = "open", "Counting"
        APPLIED = "applied", "Applied"
        CANCELLED = "cancelled", "Cancelled"

    shop = models.ForeignKey(Shop, on_delete=models.CASCADE, related_name="stocktakes")
    reference = models.CharField(max_length=32, blank=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.OPEN)
    note = models.TextField(blank=True)
    started_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="stocktakes_started",
        blank=True,
        null=True,
    )
    applied_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="stocktakes_applied",
        blank=True,
        null=True,
    )
    started_at = models.DateTimeField()
    applied_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        ordering = ["-started_at", "-created_at"]
        indexes = [models.Index(fields=["shop", "status"])]

    def __str__(self) -> str:
        return f"{self.reference or self.pk} ({self.get_status_display()})"


class StocktakeLine(SourceTrackedModel):
    """One counted item: what the books said, and what was on the shelf."""

    stocktake = models.ForeignKey(
        Stocktake, on_delete=models.CASCADE, related_name="lines"
    )
    item = models.ForeignKey(
        InventoryItem, on_delete=models.CASCADE, related_name="stocktake_lines"
    )
    name_snapshot = models.CharField(max_length=255)
    #: Ledger balance at the moment this line was counted, NOT at apply time.
    #: The variance is measured against this, so trading during the count does
    #: not corrupt it.
    expected_quantity = models.DecimalField(max_digits=12, decimal_places=3)
    counted_quantity = models.DecimalField(max_digits=12, decimal_places=3)
    #: Cost at count time, so the shrinkage figure cannot drift afterwards.
    unit_cost = models.DecimalField(
        max_digits=12, decimal_places=2, blank=True, null=True
    )
    counted_at = models.DateTimeField()

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["stocktake", "item"],
                name="uniq_stocktake_line_per_item",
            )
        ]

    def __str__(self) -> str:
        return f"{self.name_snapshot}: {self.counted_quantity}/{self.expected_quantity}"

    @property
    def variance(self):
        """Negative means missing stock; positive means more than the books say."""
        return self.counted_quantity - self.expected_quantity

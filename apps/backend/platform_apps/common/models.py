from __future__ import annotations

import uuid

from django.db import models


class UUIDStampedModel(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class SourceTrackedModel(UUIDStampedModel):
    source_system = models.CharField(max_length=32, blank=True)
    source_id = models.CharField(max_length=128, blank=True)
    source_shop_id = models.CharField(max_length=128, blank=True)
    source_path = models.CharField(max_length=255, blank=True)
    migrated_at = models.DateTimeField(blank=True, null=True)
    domain_epoch = models.PositiveIntegerField(default=1)

    class Meta:
        abstract = True


class ImportBatch(UUIDStampedModel):
    """One spreadsheet import, so it can be found again and undone.

    Imported rows used to be indistinguishable from rows typed in by hand.
    Nothing marked them, so "I picked the wrong kind and three hundred
    customers went in as products" had no answer except deleting them one at a
    time - which is exactly the situation somebody is in when they need this
    most.

    The rows themselves are tagged through the source fields every model
    already carries, so nothing had to be added to the products or customers
    tables: source_system says it came from an import, source_path says which
    one, and source_id keeps the row number in the original file - which is
    what a person needs when they go back to fix the spreadsheet.
    """

    class Kind(models.TextChoices):
        PRODUCTS = "products", "Products"
        CUSTOMERS = "customers", "Customers"
        SALES = "sales", "Past sales"

    #: The value written into every imported row's source_system.
    SOURCE_SYSTEM = "spreadsheet-import"

    shop = models.ForeignKey(
        "shops.Shop", on_delete=models.CASCADE, related_name="import_batches"
    )
    kind = models.CharField(max_length=16, choices=Kind.choices)
    #: What the file was called, so a person recognises which import this was.
    filename = models.CharField(max_length=255, blank=True)
    row_count = models.PositiveIntegerField(default=0)
    created_count = models.PositiveIntegerField(default=0)
    actor_user = models.ForeignKey(
        "users.PlatformUser",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="import_batches",
    )
    undone_at = models.DateTimeField(null=True, blank=True)
    #: How many rows the undo actually removed, and how many it had to keep.
    undone_count = models.PositiveIntegerField(default=0)
    kept_count = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["shop", "-created_at"])]

    def __str__(self) -> str:
        return f"{self.get_kind_display()} import of {self.row_count} row(s)"

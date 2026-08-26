"""Taking back an import that went in wrong.

The situation this exists for: the screen defaults to Products, somebody
imports a customer list without changing it, and three hundred customers
arrive in the catalogue. Removing them by hand is not a real option, and
until now there was nothing else - imported rows were indistinguishable from
rows typed in at the counter.

What undo will and will not remove is the whole design.

A row nobody has touched since the import is safe to take back: it exists
only because of the mistake. A row that has since been *used* is not. A
product that has been sold is on a receipt a customer is holding; a customer
who owes money is a debt the shop is owed. Deleting either would quietly
corrupt records that have nothing to do with the bad import, and nobody would
notice until the numbers stopped adding up.

So used rows are kept and counted, and the caller is told plainly how many.
Half an undo that says so beats a whole one that loses a sale.

Nothing is hard-deleted. Rows are tombstoned, which is how the rest of the
app removes things, and it leaves the door open if somebody wants them back.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.db import transaction
from django.db.models import F
from django.utils import timezone

from platform_apps.common.models import ImportBatch


def tag_for(batch: ImportBatch, row_number: int) -> dict:
    """The source fields that mark a row as belonging to this import.

    Written on every row an import creates. source_path carries the batch so
    the rows can be found again; source_id keeps the line number from the
    original file, which is what somebody needs when they go back to fix the
    spreadsheet rather than guess which line was wrong.
    """
    return {
        "source_system": ImportBatch.SOURCE_SYSTEM,
        "source_path": str(batch.id),
        "source_id": str(row_number),
    }


def rows_from(batch: ImportBatch):
    """Every row this import created, whichever table it went into."""
    from platform_apps.customers.models import Customer
    from platform_apps.inventory.models import InventoryItem

    model = InventoryItem if batch.kind == ImportBatch.Kind.PRODUCTS else Customer
    return model.objects.filter(
        shop=batch.shop,
        source_system=ImportBatch.SOURCE_SYSTEM,
        source_path=str(batch.id),
        tombstone=False,
    )


def product_is_in_use(item) -> bool:
    """Whether a product has done anything since it was imported.

    Sold, counted, transferred, delivered against - any of those means a
    record elsewhere points at it. A stock ledger entry is the general case:
    every one of those movements writes one.
    """
    return item.ledger_entries.exists() or item.sale_items.exists()


def customer_is_in_use(customer) -> bool:
    """Whether a customer has history worth keeping.

    A balance is the obvious one - that is money owed in one direction or the
    other, and removing it loses the debt. A ledger entry or a sale means
    somebody has actually transacted with them.
    """
    if (customer.balance or Decimal("0")) != Decimal("0"):
        return True
    return customer.ledger_entries.exists() or customer.sales.exists()


def undo(batch: ImportBatch) -> dict:
    """Remove what this import created, keeping anything since used.

    Idempotent: a batch already undone reports what it did the first time
    rather than running again, so a double-click cannot remove more than one
    undo's worth.
    """
    if batch.undone_at is not None:
        return {
            "already_undone": True,
            "removed": batch.undone_count,
            "kept": batch.kept_count,
            "kept_rows": [],
        }

    in_use = (
        product_is_in_use
        if batch.kind == ImportBatch.Kind.PRODUCTS
        else customer_is_in_use
    )

    removed_ids: list = []
    kept: list[dict] = []

    with transaction.atomic():
        # Locked while deciding: a sale rung up between the check and the
        # write would otherwise have its product removed underneath it.
        for row in rows_from(batch).select_for_update():
            if in_use(row):
                kept.append({"id": str(row.id), "name": getattr(row, "name", "")})
            else:
                removed_ids.append(row.pk)

        if removed_ids:
            rows_from(batch).filter(pk__in=removed_ids).update(tombstone=True)

        batch.undone_at = timezone.now()
        batch.undone_count = len(removed_ids)
        batch.kept_count = len(kept)
        batch.save(
            update_fields=["undone_at", "undone_count", "kept_count", "updated_at"]
        )

    return {
        "already_undone": False,
        "removed": len(removed_ids),
        "kept": len(kept),
        # Named, not just counted: "12 kept" is a mystery, "12 kept, and here
        # they are" is something a shopkeeper can act on.
        "kept_rows": kept[:50],
    }


#: How long a batch stays open to further chunks of the same file.
#:
#: The web proxy splits a large file into requests of five hundred rows, so a
#: twelve-hundred-row import arrives as three separate calls seconds apart.
#: Each used to record its own batch, which meant undoing that one mistake
#: took three clicks and nothing said so.
CHUNK_WINDOW_SECONDS = 300


def batch_for(shop, kind, filename, actor):
    """The batch these rows belong to - reusing an open one where it fits.

    Grouping is decided here rather than by the caller passing a batch id.
    A caller-supplied id would let anyone attach rows to somebody else's
    import, and then undo somebody else's data; the same shop, kind, file and
    person within a few minutes is enough to recognise chunks of one upload
    without trusting anything from outside.

    An undone batch is never reused. Adding rows to something already taken
    back would leave them tagged as removed while sitting in the shop.
    """
    from django.utils import timezone

    cutoff = timezone.now() - timedelta(seconds=CHUNK_WINDOW_SECONDS)
    existing = (
        ImportBatch.objects.filter(
            shop=shop,
            kind=kind,
            filename=filename,
            actor_user=actor,
            undone_at__isnull=True,
            created_at__gte=cutoff,
        )
        .order_by("-created_at")
        .first()
    )
    # A file with no name cannot be told apart from the next one, so those
    # each get their own batch rather than being lumped together.
    if existing is not None and filename:
        return existing
    return ImportBatch.objects.create(
        shop=shop, kind=kind, filename=filename, actor_user=actor
    )


def record_rows(batch, *, rows: int, created: int) -> None:
    """Add this chunk's counts to the batch it belongs to."""
    ImportBatch.objects.filter(pk=batch.pk).update(
        row_count=F("row_count") + rows,
        created_count=F("created_count") + created,
    )

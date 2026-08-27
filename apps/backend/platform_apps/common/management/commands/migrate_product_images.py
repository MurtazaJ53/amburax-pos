"""Move product photos out of the database and into the object store.

New photos already go straight to the store. This is for the ones written
before that, which are still base64 text in a column on the product - in the
same table the till reads to ring up a sale, so they travel with every backup
and every replica.

Safe to interrupt and safe to run again. Each product is moved on its own, and
a product is only cleared from the column once its bytes are confirmed
readable back out of the store. Stopping halfway leaves some products moved
and some not, which is a state the image view already handles: it reads the
store first and falls back to the column.

Run with --dry-run first. It reports what would move and touches nothing.
Run with --check to audit where every photo currently is, which is the
only way to tell a photo that moved from a photo that went missing - both
leave the column empty, and only one of them is fine.
"""
from __future__ import annotations

from django.core.management.base import BaseCommand

from platform_apps.common.blob import content_key, get_store
from platform_apps.inventory.image_views import parse_data_uri
from platform_apps.inventory.models import InventoryItem


class Command(BaseCommand):
    help = "Move product photos from the database into the configured blob store."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Report what would move without writing anything.",
        )
        parser.add_argument(
            "--check",
            action="store_true",
            help="Audit where every photo is. Writes nothing.",
        )
        parser.add_argument(
            "--batch",
            type=int,
            default=200,
            help="How many products to read at a time (default 200).",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=0,
            help="Stop after this many products. 0 means all of them.",
        )

    def handle(self, *args, **options):
        if options["check"]:
            return self.audit()

        dry_run = options["dry_run"]
        batch = max(1, options["batch"])
        limit = max(0, options["limit"])

        store = get_store()
        moved = skipped = failed = 0
        freed_bytes = 0

        # Only rows that still hold a picture and have not been moved. Ordered
        # by primary key so a re-run after an interruption picks up cleanly.
        queryset = (
            InventoryItem.objects.filter(image_key="")
            .exclude(image_data="")
            .order_by("pk")
            .only("id", "name", "image_data", "image_key")
        )

        total = queryset.count()
        self.stdout.write(f"{total} product photo(s) still in the database.")
        if dry_run:
            self.stdout.write(self.style.WARNING("Dry run: nothing will be written."))

        seen = 0
        last_pk = None
        while True:
            # Walked by primary key rather than re-reading the same filter.
            # A skipped row - text that will not decode - never leaves that
            # filter, so re-querying it returned the same row forever. The
            # first run of this command hung on exactly that.
            page = queryset if last_pk is None else queryset.filter(pk__gt=last_pk)
            chunk = list(page[:batch])
            if not chunk:
                break

            for item in chunk:
                if limit and seen >= limit:
                    break
                seen += 1
                last_pk = item.pk

                parsed = parse_data_uri(item.image_data or "")
                if parsed is None:
                    # Text that will not decode is a broken row. Left exactly
                    # as it is: this command moves pictures, it does not decide
                    # something is rubbish and delete it.
                    skipped += 1
                    self.stderr.write(
                        f"  skipped {item.name}: not a picture this can read"
                    )
                    continue

                media_type, payload = parsed
                key = content_key(payload, media_type)

                if dry_run:
                    moved += 1
                    freed_bytes += len(item.image_data or "")
                    continue

                try:
                    store.put(key, payload, media_type)
                    # Read back before clearing the column. Without this, a
                    # store that accepted a write and silently kept nothing
                    # would take the only other copy with it.
                    if store.get(key) is None:
                        raise RuntimeError("stored, but could not be read back")
                except Exception as error:
                    failed += 1
                    self.stderr.write(self.style.ERROR(f"  failed {item.name}: {error}"))
                    continue

                freed_bytes += len(item.image_data or "")
                InventoryItem.objects.filter(pk=item.pk).update(
                    image_key=key, image_data=""
                )
                moved += 1

            if limit and seen >= limit:
                break

        self.stdout.write("")
        verb = "would move" if dry_run else "moved"
        self.stdout.write(self.style.SUCCESS(f"{verb} {moved} photo(s)."))
        if skipped:
            self.stdout.write(f"{skipped} skipped and left untouched.")
        if failed:
            self.stdout.write(
                self.style.ERROR(
                    f"{failed} failed. Run again - moved rows are not retried."
                )
            )
        self.stdout.write(
            f"{freed_bytes / 1_000_000:.1f} MB of base64 "
            f"{'would leave' if dry_run else 'left'} the products table."
        )

    def audit(self) -> None:
        """Say where every product photo actually is.

        This exists because the two possible endings look identical from the
        products table. A photo that moved to the store and a photo that was
        destroyed both leave image_data empty; the first also sets image_key,
        but a key proves only that something was written, not that it is still
        readable. So every key is resolved against the store rather than
        trusted.

        Written after a migration run reported one photo outstanding and then,
        minutes later, reported none - having moved nothing in between. That
        is either a save that worked or a photo that vanished, and reasoning
        from the counts alone could not tell which.
        """
        store = get_store()
        self.stdout.write(f"store: {type(store).__name__}")

        keyed = list(
            InventoryItem.objects.exclude(image_key="")
            .order_by("name")
            .values_list("name", "image_key")
        )
        unreadable = []
        for name, key in keyed:
            try:
                present = store.get(key) is not None
            except Exception as error:  # A store that cannot be reached at all.
                self.stderr.write(self.style.ERROR(f"  {name}: store error: {error}"))
                unreadable.append(name)
                continue
            if not present:
                unreadable.append(name)

        inline = InventoryItem.objects.filter(image_key="").exclude(image_data="").count()

        self.stdout.write("")
        self.stdout.write(f"{len(keyed) - len(unreadable)} photo(s) in the store, readable.")
        self.stdout.write(f"{inline} photo(s) still in the products table.")

        if unreadable:
            # The one genuinely bad outcome: the row still points at a photo,
            # and the photo is not there. Named, because the shopkeeper has to
            # be told which products to photograph again.
            self.stdout.write("")
            self.stdout.write(
                self.style.ERROR(
                    f"{len(unreadable)} product(s) point at a photo the store "
                    "does not have:"
                )
            )
            for name in unreadable:
                self.stdout.write(self.style.ERROR(f"  {name}"))
            self.stdout.write(
                "Check the store is the same one that was written to - a "
                "changed BHUB_MEDIA_ROOT or bucket looks exactly like this. "
                "If it is, those photos need taking again."
            )
        elif not inline:
            self.stdout.write(self.style.SUCCESS("Nothing outstanding."))

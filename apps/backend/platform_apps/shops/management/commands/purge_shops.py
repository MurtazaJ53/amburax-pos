"""Delete a shop and everything in it. The only hard delete in this system.

Nothing else here deletes. Every model carries a tombstone, every removal is a
flag, and that is deliberate: a shopkeeper who archives a product still wants
last year's sales to explain themselves. This command exists for the one case
that design does not cover - test shops created on a production box while
proving the system works, which are then real rows in a real database.

Twenty-nine tables cascade from a shop. Sales, customers, ledgers, stock
movements, payments, attendance, invites. There is no undo and no tombstone to
un-set; the rows are gone.

So the guards are the point of this file, not the deletion:

Shops are named by id, never by name or pattern. "Delete every shop matching
Test" is one typo from deleting a client, and the typo is invisible until it
has already run.

It reports and stops unless --confirm is passed. The default behaviour of a
destructive command should be to describe itself.

It refuses entirely unless a recent backup exists. That is the guard worth
having: it makes this reversible by construction rather than by remembering.
A restore drill runs monthly on the same droplet, so the operator already
knows their backups work - this insists they have a fresh one before using the
one tool that needs it.

Before reaching for this, note that shop data is isolated: one shop cannot
appear in another's reports, and that is enforced at a single gate and covered
by tests. A leftover test shop is untidy, not incorrect. Suspending it is
reversible and usually enough.
"""
from __future__ import annotations

import time
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from platform_apps.shops.models import Shop

#: How fresh a backup has to be before this will run. A day and a night, so a
#: nightly job at 02:00 always satisfies it and a week-old dump never does.
BACKUP_MAX_AGE_HOURS = 48


def newest_backup(backup_dir: Path):
    """The most recent dump, or None. Same layout backup_db.sh writes."""
    candidates = [
        path
        for pattern in ("**/*.dump", "**/*.sql", "**/*.sql.gz")
        for path in backup_dir.glob(pattern)
        if path.is_file()
    ]
    return max(candidates, key=lambda p: p.stat().st_mtime) if candidates else None


def _counts(shop) -> list[tuple[str, int]]:
    """What would be destroyed, per table, largest first.

    Read from the model's own reverse relations rather than a hand-written
    list, so a table added later is counted without anyone remembering to come
    back here. A summary that silently omits a table is worse than no summary,
    because it is read as complete.
    """
    rows: list[tuple[str, int]] = []
    for relation in shop._meta.related_objects:
        accessor = relation.get_accessor_name()
        manager = getattr(shop, accessor, None)
        if manager is None or not hasattr(manager, "count"):
            continue
        count = manager.count()
        if count:
            rows.append((relation.related_model._meta.label, count))
    return sorted(rows, key=lambda pair: -pair[1])


class Command(BaseCommand):
    help = "Permanently delete shops by id, with everything belonging to them."

    def add_arguments(self, parser):
        parser.add_argument(
            "shop_ids",
            nargs="+",
            help="Shop UUIDs. Names and patterns are deliberately not accepted.",
        )
        parser.add_argument(
            "--confirm",
            action="store_true",
            help="Actually delete. Without it this only reports.",
        )
        parser.add_argument(
            "--backup-dir",
            default="/var/backups/bhub",
            help="Where to look for a recent backup (default /var/backups/bhub).",
        )

    def handle(self, *args, **options):
        confirm = options["confirm"]
        backup_dir = Path(options["backup_dir"])

        shops = []
        for shop_id in options["shop_ids"]:
            shop = Shop.objects.filter(pk=shop_id).first()
            if shop is None:
                # Refuse the whole run. A missing id in a list of four means
                # the operator is working from a stale note, and the other
                # three are no longer trustworthy either.
                raise CommandError(f"No shop with id {shop_id}. Nothing deleted.")
            shops.append(shop)

        self.stdout.write(f"{len(shops)} shop(s) named:")
        for shop in shops:
            self.stdout.write("")
            self.stdout.write(self.style.WARNING(f"  {shop.name}  ({shop.slug})"))
            self.stdout.write(f"    id {shop.id} - status {shop.status}")
            rows = _counts(shop)
            if not rows:
                self.stdout.write("    no related rows")
            for label, count in rows:
                self.stdout.write(f"    {count:>7}  {label}")

        if not confirm:
            self.stdout.write("")
            self.stdout.write(
                self.style.WARNING(
                    "Nothing was deleted. Read the list above, then run again "
                    "with --confirm."
                )
            )
            return

        # The guard that makes this survivable. Checked at --confirm time
        # rather than at the top, so a dry run works on a machine with no
        # backups at all - a developer describing a shop should not need one.
        newest = newest_backup(backup_dir)
        if newest is None:
            raise CommandError(
                f"No backup found in {backup_dir}. This deletes 29 tables of "
                "data with no undo; take one first: bash scripts/backup_db.sh"
            )
        age_hours = (time.time() - newest.stat().st_mtime) / 3600
        if age_hours > BACKUP_MAX_AGE_HOURS:
            raise CommandError(
                f"The newest backup ({newest.name}) is {age_hours:.0f} hours "
                f"old, and this refuses to run without one under "
                f"{BACKUP_MAX_AGE_HOURS}. Run: bash scripts/backup_db.sh"
            )
        self.stdout.write("")
        self.stdout.write(f"Backup checked: {newest.name}, {age_hours:.0f}h old.")

        for shop in shops:
            name = shop.name
            # One shop per transaction. A failure halfway through a list should
            # leave whole shops behind, never half of one.
            with transaction.atomic():
                shop.delete()
            self.stdout.write(self.style.SUCCESS(f"Deleted {name}."))

        self.stdout.write("")
        self.stdout.write(
            f"{len(shops)} shop(s) gone. If that was a mistake, the backup "
            "named above is the only way back."
        )

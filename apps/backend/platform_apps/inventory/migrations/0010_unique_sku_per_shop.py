"""Make a product code mean exactly one product.

There was an index on (shop, sku) but nothing unique about it, so two
products could carry the same code. That is not untidy data: the till
resolves a scan by taking the FIRST item whose code matches, so a duplicate
rings up the wrong product, silently, at the counter. Nobody notices until
the stock figures stop agreeing with the shelf.

The index is on Lower(sku), not on sku. A plain unique index in Postgres is
case sensitive, so ABC-1 and abc-1 would both be permitted - while the scan
that resolves them uses iexact and treats them as one. An index that allows
the exact collision it was built to prevent is worse than none, because it
reads as protection.

Two steps, and the order matters. Duplicates already in the database have to
be separated before a unique index can be built, or this fails on precisely
the shops that most need it.

They are renamed rather than deleted. They are real products with real sales
against them; only their codes clashed. The oldest keeps the code it had -
its printed labels are the ones already stuck to things in the stockroom -
and the rest take a suffix, so every scan now resolves to one product and
nothing has to be typed again.

The constraint is partial, and both conditions carry weight. Blank is
excluded because most shops leave the code empty on most products, and a
unique index over blanks would permit exactly one of them. Tombstoned rows
are excluded so an archived product does not hold a code for ever.
"""
from __future__ import annotations

from django.db import migrations, models
from django.db.models import Q
from django.db.models.functions import Lower


def plan_renames(rows) -> list[tuple]:
    """Decide what each clashing code becomes, given (pk, shop_id, sku) rows.

    Separated from the database work so the decision can be tested. It cannot
    be exercised through the ORM once the index exists - duplicates can no
    longer be created to separate - and this migration runs once, against live
    data, with no second chance if it leaves one behind.

    Rows must arrive oldest first: the one that has carried the code longest
    keeps it, because its printed labels are the ones already stuck to things.
    """
    seen: set[tuple] = set()
    renames: list[tuple] = []

    for pk, shop_id, sku in rows:
        code = (sku or "").strip()
        # Compared case-folded, because that is how the index compares and how
        # a scan already resolves. Separating only exact matches would leave
        # the pairs that actually collide.
        key = (shop_id, code.lower())
        if key not in seen:
            seen.add(key)
            continue

        suffix = 2
        while (shop_id, f"{code}-{suffix}".lower()) in seen:
            suffix += 1
        candidate = f"{code}-{suffix}"

        renames.append((pk, candidate))
        seen.add((shop_id, candidate.lower()))

    return renames


def separate_existing_duplicates(apps, schema_editor):
    """Give every clashing code its own value before the index is built."""
    InventoryItem = apps.get_model("inventory", "InventoryItem")

    rows = (
        InventoryItem.objects.exclude(sku="")
        .filter(tombstone=False)
        .order_by("created_at", "id")
        .values_list("id", "shop_id", "sku")
    )

    renames = plan_renames(rows.iterator(chunk_size=500))
    for pk, candidate in renames:
        InventoryItem.objects.filter(pk=pk).update(sku=candidate)

    if renames:
        print(
            f"  separated {len(renames)} duplicate product code(s) so each "
            "scans to one product"
        )


def keep_the_renames(apps, schema_editor):
    """Reversing drops the index; the renames stay.

    Restoring a code would recreate the ambiguity this removed, and once the
    index is gone there is no record of which row held it first.
    """


class Migration(migrations.Migration):
    dependencies = [
        ("inventory", "0009_inventoryitem_image_key"),
    ]

    operations = [
        migrations.RunPython(separate_existing_duplicates, keep_the_renames),
        migrations.AddConstraint(
            model_name="inventoryitem",
            constraint=models.UniqueConstraint(
                models.F("shop"),
                Lower("sku"),
                condition=Q(tombstone=False) & ~Q(sku=""),
                name="uniq_active_sku_per_shop",
            ),
        ),
    ]

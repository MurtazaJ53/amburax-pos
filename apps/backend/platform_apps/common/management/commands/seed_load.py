"""Fill a shop with enough data to find out what slows down first.

Every performance claim in this project so far has been an estimate. The scale
review reasoned about hundreds of thousands of rows; the shop it reasoned
about had eight hundred products. This turns the estimates into measurements.

What it is actually testing, stated so the numbers can be read afterwards:
stock on hand is summed from the movement ledger on every read. That is the
right design - any figure traces back to the sale that caused it - and it is
the query FUTURE.md predicts will slow first. A shop with a hundred thousand
ledger rows either answers quickly or it does not, and no amount of reasoning
settles that.

Three things it refuses to get wrong.

It writes CONSISTENT money. Every bill satisfies received + due == total,
every khata bill has a matching ledger entry, and every balance is the sum of
that customer's entries. Seeding money that does not add up would make the
hourly reconciliation check email about a hundred thousand sales, and the
first thing anybody would do is turn the check off.

It checks free disk before writing and refuses below a floor. Filling a
Postgres volume is not a slow database, it is a write-stop: the shop cannot
sell and does not recover until somebody frees space by hand.

It sets phone_hash itself. Customer.save() maintains that blind index and
bulk_create does not call save(), so seeded customers would be invisible to
the search a cashier uses - and a benchmark of a lookup nobody can perform is
worth nothing.

One shop per run, deliberately. If the first shop already answers slowly there
is no reason to seed eight more, and staging keeps the disk guard useful
rather than something that fires halfway through.

Undo is `purge_shops`, which is why that exists.
"""
from __future__ import annotations

import random
import shutil
from datetime import timedelta
from decimal import Decimal

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from platform_apps.common.blind_index import generate_blind_index
from platform_apps.customers.models import Customer, CustomerLedgerEntry
from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.payments.models import SalePayment
from platform_apps.sales.models import Sale, SaleItem
from platform_apps.shops.models import Shop

#: Refuse to write when less than this remains. Postgres stops accepting
#: writes with a little space left, so the floor sits above the point of no
#: return rather than at it.
MIN_FREE_GB = 5

#: Rows per INSERT. Large enough that round trips stop mattering, small enough
#: that one batch is not a long lock on a 2 vCPU box.
BATCH = 1000

#: How many bills go on khata. Enough that the day book, the debtor list and
#: the reconciliation check all have something real to do at volume.
CREDIT_SHARE = 0.10


class Command(BaseCommand):
    help = "Fill one shop with products, customers and sales, for load testing."

    def add_arguments(self, parser):
        parser.add_argument("shop_id", help="The shop to fill. One per run.")
        parser.add_argument("--products", type=int, default=10_000)
        parser.add_argument("--customers", type=int, default=10_000)
        parser.add_argument("--sales", type=int, default=11_000)
        parser.add_argument(
            "--confirm",
            action="store_true",
            help="Actually write. Without it this only reports what it would do.",
        )
        parser.add_argument(
            "--seed",
            type=int,
            default=20260828,
            help="Random seed, so two runs produce the same shop.",
        )

    def handle(self, *args, **options):
        shop = Shop.objects.filter(pk=options["shop_id"]).first()
        if shop is None:
            raise CommandError(f"No shop with id {options['shop_id']}.")

        products = max(0, options["products"])
        customers = max(0, options["customers"])
        sales = max(0, options["sales"])
        rng = random.Random(options["seed"])

        # Two items a bill is the ordinary shape here, and every sold line also
        # writes a stock movement.
        estimated = products * 2 + customers + sales * 2 + sales * 4

        self.stdout.write(f"Shop: {shop.name} ({shop.slug})")
        self.stdout.write(
            f"  {products:,} products, {customers:,} customers, {sales:,} sales"
        )
        self.stdout.write(f"  roughly {estimated:,} rows in total")

        free_gb = shutil.disk_usage("/").free / 1_000_000_000
        self.stdout.write(f"  {free_gb:.1f} GB free on disk")

        if not options["confirm"]:
            self.stdout.write("")
            self.stdout.write(
                self.style.WARNING(
                    "Nothing was written. Run again with --confirm.\n"
                    "Take a backup first: bash scripts/backup_db.sh"
                )
            )
            return

        if free_gb < MIN_FREE_GB:
            raise CommandError(
                f"Only {free_gb:.1f} GB free, and this refuses below "
                f"{MIN_FREE_GB} GB. A full Postgres volume is a write-stop, "
                "not a slow database - the shop cannot sell until somebody "
                "frees space by hand."
            )

        started = timezone.now()
        made_products = self._products(shop, products, rng)
        made_customers = self._customers(shop, customers)
        self._sales(shop, sales, made_products, made_customers, rng)

        seconds = (timezone.now() - started).total_seconds()
        self.stdout.write("")
        self.stdout.write(self.style.SUCCESS(f"Done in {seconds:.0f}s."))
        self.stdout.write(
            "Measure before drawing conclusions: run the benchmark against the "
            "deployment and compare with the baseline taken before this ran."
        )

    # --- the writing ---------------------------------------------------

    def _products(self, shop, count, rng) -> list:
        if not count:
            return list(InventoryItem.objects.filter(shop=shop)[:500])

        now = timezone.now()
        InventoryItem.objects.bulk_create(
            [
                InventoryItem(
                    shop=shop,
                    name=f"Load Product {n:05d}",
                    sku=f"LOAD-{n:05d}",
                    sell_price=Decimal(rng.randrange(1000, 50_000)) / 100,
                    category="Load Test",
                )
                for n in range(1, count + 1)
            ],
            batch_size=BATCH,
        )
        self.stdout.write(f"  wrote {count:,} products")

        made = list(InventoryItem.objects.filter(shop=shop, sku__startswith="LOAD-"))
        InventoryStockLedger.objects.bulk_create(
            [
                InventoryStockLedger(
                    shop=shop,
                    item=item,
                    event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
                    quantity_delta=Decimal("500"),
                    occurred_at=now,
                )
                for item in made
            ],
            batch_size=BATCH,
        )
        self.stdout.write(f"  wrote {len(made):,} opening stock movements")
        return made

    def _customers(self, shop, count) -> list:
        if not count:
            return list(Customer.objects.filter(shop=shop)[:500])

        rows = []
        for n in range(1, count + 1):
            phone = f"9{n:09d}"
            rows.append(
                Customer(
                    shop=shop,
                    name=f"Load Customer {n:05d}",
                    phone=phone,
                    # save() maintains this and bulk_create does not call it.
                    # Without it these customers cannot be found by phone, and
                    # a benchmark of a lookup nobody can perform is worthless.
                    phone_hash=generate_blind_index(phone),
                )
            )
        Customer.objects.bulk_create(rows, batch_size=BATCH)
        self.stdout.write(f"  wrote {count:,} customers")
        return list(
            Customer.objects.filter(shop=shop, name__startswith="Load Customer")
        )

    def _sales(self, shop, count, products, customers, rng) -> None:
        """Bills, their lines, their tenders and their stock movements.

        Written in batches of whole sales rather than one table at a time, so
        an interrupted run leaves complete bills behind instead of orphaned
        lines - and so the money stays consistent at every point, which is
        what the hourly reconciliation is about to start checking.
        """
        if not (count and products):
            return

        today = timezone.localdate()
        now = timezone.now()
        existing = Sale.objects.filter(shop=shop).count()
        owed: dict = {}
        written = 0

        for start in range(0, count, BATCH):
            size = min(BATCH, count - start)
            prepared = []

            for n in range(start, start + size):
                chosen = [rng.choice(products) for _ in range(2)]
                quantities = [Decimal(rng.randrange(1, 4)) for _ in chosen]
                total = sum(
                    (item.sell_price * qty for item, qty in zip(chosen, quantities)),
                    Decimal("0.00"),
                ).quantize(Decimal("0.01"))

                on_khata = bool(customers) and rng.random() < CREDIT_SHARE
                customer = rng.choice(customers) if on_khata else None
                due = total if on_khata else Decimal("0.00")
                received = Decimal("0.00") if on_khata else total

                sale = Sale(
                    shop=shop,
                    customer=customer,
                    receipt_number=f"LOAD-{existing + n + 1:07d}",
                    payment_mode="CREDIT" if on_khata else "CASH",
                    subtotal_amount=total,
                    total_amount=total,
                    amount_received=received,
                    amount_due=due,
                    sale_date=today - timedelta(days=rng.randrange(0, 90)),
                    occurred_at=now,
                    status=Sale.Status.COMPLETED,
                )
                prepared.append((sale, chosen, quantities, on_khata, customer))

            Sale.objects.bulk_create([row[0] for row in prepared], batch_size=BATCH)

            lines, tenders, movements, ledger = [], [], [], []
            for sale, chosen, quantities, on_khata, customer in prepared:
                for position, (item, qty) in enumerate(zip(chosen, quantities)):
                    lines.append(
                        SaleItem(
                            sale=sale,
                            inventory_item=item,
                            name_snapshot=item.name,
                            quantity=qty,
                            unit_price=item.sell_price,
                            unit_cost=(item.sell_price * Decimal("0.7")).quantize(
                                Decimal("0.01")
                            ),
                            line_total=(item.sell_price * qty).quantize(
                                Decimal("0.01")
                            ),
                            position=position,
                        )
                    )
                    movements.append(
                        InventoryStockLedger(
                            shop=shop,
                            item=item,
                            event_type=InventoryStockLedger.EventType.SALE,
                            quantity_delta=-qty,
                            occurred_at=sale.occurred_at,
                        )
                    )

                # Credit writes NO tender row. That is what makes a khata bill
                # a khata bill, and seeding one would recreate the exact bug
                # this system spent a day removing.
                if on_khata:
                    ledger.append(
                        CustomerLedgerEntry(
                            shop=shop,
                            customer=customer,
                            event_type=CustomerLedgerEntry.EventType.SALE,
                            amount_delta=sale.amount_due,
                            total_spent_delta=sale.total_amount,
                            occurred_at=sale.occurred_at,
                            source_path=f"sales/{sale.id}",
                        )
                    )
                    owed[customer.pk] = (
                        owed.get(customer.pk, Decimal("0.00")) + sale.amount_due
                    )
                else:
                    tenders.append(
                        SalePayment(
                            sale=sale,
                            shop=shop,
                            amount=sale.amount_received,
                            payment_method="CASH",
                            occurred_at=sale.occurred_at,
                        )
                    )

            with transaction.atomic():
                SaleItem.objects.bulk_create(lines, batch_size=BATCH)
                SalePayment.objects.bulk_create(tenders, batch_size=BATCH)
                InventoryStockLedger.objects.bulk_create(movements, batch_size=BATCH)
                CustomerLedgerEntry.objects.bulk_create(ledger, batch_size=BATCH)

            written += size
            self.stdout.write(f"  {written:,} / {count:,} sales")

        # Balances last, once, so each customer is written a single time and
        # ends up agreeing with the ledger entries above.
        if owed:
            updates = []
            for customer in Customer.objects.filter(pk__in=list(owed)):
                customer.balance = (customer.balance or Decimal("0.00")) + owed[
                    customer.pk
                ]
                updates.append(customer)
            Customer.objects.bulk_update(updates, ["balance"], batch_size=BATCH)
            self.stdout.write(f"  updated {len(updates):,} khata balances")

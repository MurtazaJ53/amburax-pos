"""Repair credit sales recorded before khata stopped counting as payment.

Until 670c3e3 the till sent the khata portion of a bill as a payment row, and
the server counted it. One bug, four wrong records per sale: the sale says it
was paid in full, its ledger entry moves the customer by zero, the customer's
balance never rises, and the day book reports the money as received. A shop
silently forgot what it was owed.

The fix stopped new sales going in that way. It could not reach the ones
already there, and those keep every screen disagreeing with itself - a day
book whose total does not match the sum of its own parts is the visible end
of it.

Finding them needs no date and no guesswork: a CREDIT payment row is itself
the artefact. Nothing writes one any more, so every sale that has one predates
the fix, and removing them is what makes this safe to run twice.

Run with --dry-run first.
"""
from __future__ import annotations

from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import F, Sum

from platform_apps.customers.models import Customer, CustomerLedgerEntry
from platform_apps.payments.models import SalePayment
from platform_apps.sales.models import Sale


class Command(BaseCommand):
    help = "Restore what customers owe on credit sales recorded before the fix."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Report what would change without writing anything.",
        )
        parser.add_argument(
            "--shop",
            default="",
            help="Limit to one shop id. Default: every shop.",
        )

    def handle(self, *args, **options):
        dry_run = options["dry_run"]
        shop_id = (options["shop"] or "").strip()

        rows = SalePayment.objects.filter(payment_method=Sale.PaymentMode.CREDIT)
        if shop_id:
            rows = rows.filter(shop_id=shop_id)

        # Grouped per sale: a split bill can carry more than one credit row.
        owed_by_sale = {
            entry["sale_id"]: entry["owed"]
            for entry in rows.values("sale_id").annotate(owed=Sum("amount"))
        }

        self.stdout.write(f"{len(owed_by_sale)} sale(s) recorded khata as payment.")
        if dry_run:
            self.stdout.write(self.style.WARNING("Dry run: nothing will be written."))

        repaired = 0
        restored = Decimal("0.00")
        touched_customers: set = set()

        for sale_id, owed in owed_by_sale.items():
            owed = Decimal(owed or "0.00")
            if owed <= 0:
                continue

            sale = Sale.objects.filter(pk=sale_id).first()
            if sale is None:
                continue  # Payment row outliving its sale; not this command's job.

            self.stdout.write(
                f"  {sale.receipt_number or sale_id}: {sale.amount_due} -> "
                f"{sale.amount_due + owed} owed"
            )
            restored += owed
            repaired += 1

            if dry_run:
                continue

            # One sale, one transaction. A half-repaired sale - money moved off
            # the bill but never onto the customer - would be worse than the
            # state this is fixing, because it would look deliberate.
            with transaction.atomic():
                Sale.objects.filter(pk=sale_id).update(
                    amount_received=sale.amount_received - owed,
                    amount_due=sale.amount_due + owed,
                    payment_mode=Sale.PaymentMode.CREDIT,
                )

                # Deleted, not kept. While the row exists the day book counts
                # it as a tender and the sales screen sums it into its split;
                # its absence is also what stops this command finding the sale
                # a second time.
                SalePayment.objects.filter(
                    sale_id=sale_id, payment_method=Sale.PaymentMode.CREDIT
                ).delete()

                entry = CustomerLedgerEntry.objects.filter(
                    source_path=f"sales/{sale_id}",
                    event_type=CustomerLedgerEntry.EventType.SALE,
                ).first()
                if entry is not None:
                    entry.amount_delta = entry.amount_delta + owed
                    entry.save(update_fields=["amount_delta"])
                    touched_customers.add(entry.customer_id)

                    # F(), so this adds to whatever the balance is when the
                    # statement runs. Reading it first and writing back a
                    # number would quietly discard any payment the customer
                    # made while this was working through the list.
                    Customer.objects.filter(pk=entry.customer_id).update(
                        balance=F("balance") + owed
                    )

        self.stdout.write("")
        verb = "would restore" if dry_run else "restored"
        self.stdout.write(
            self.style.SUCCESS(
                f"{verb} {restored} across {repaired} sale(s), "
                f"{len(touched_customers)} customer(s)."
            )
        )
        if repaired and not dry_run:
            self.stdout.write(
                "Balances, ledgers and the day book now agree. Safe to run again: "
                "a repaired sale no longer has a credit payment row to find."
            )

"""Giving products a code so their labels can be printed.

A label carries a barcode, and a barcode needs something to encode. Products
imported from a spreadsheet or typed in at the counter usually have neither a
barcode nor a SKU, so the label screen could only tell a shopkeeper that every
one of their products needed a SKU - a few hundred times over, with no way to
act on it. Typing them by hand is not a real answer at that scale.

The generated code has to satisfy two things at once, and the second is the
one that bites.

It must scan. Code 128 encodes any ASCII, so that part is easy; what matters
is that it stays short enough to fit across a 38mm label and reads back
unambiguously to a person holding it.

It must be unique within the shop. Nothing in the schema enforces that - sku
is a plain CharField with no constraint - and the till resolves a scan by
taking the FIRST item whose code matches. Two products sharing a code is
therefore not a duplicate-data annoyance; it is a scan that rings up the
wrong product, silently, at the counter. So every candidate is checked
against both the SKUs and the barcodes already in the shop.

The prefix keeps these codes distinguishable from a real EAN or UPC printed
by a manufacturer. A bare run of digits would look exactly like a product
barcode, and a shopkeeper reading one out could not tell which they held.
"""
from __future__ import annotations

import re

from django.db import transaction
from rest_framework import exceptions, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.inventory.models import InventoryItem
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

#: Marks a code as one this app issued rather than one a manufacturer printed.
SKU_PREFIX = "SK"

#: Five digits covers 99,999 products, comfortably past any single shop, and
#: keeps the whole code to seven characters so it fits a small label.
SKU_DIGITS = 5

#: One request cannot rewrite an unbounded number of rows.
MAX_PER_REQUEST = 2000

_GENERATED = re.compile(rf"^{SKU_PREFIX}(\d{{{SKU_DIGITS},}})$", re.IGNORECASE)


def format_sku(number: int) -> str:
    """SK00001. Zero-padded so codes sort in the order they were issued."""
    return f"{SKU_PREFIX}{number:0{SKU_DIGITS}d}"


def next_free_number(existing: set[str]) -> int:
    """Where to start counting, given every code already in the shop.

    Continues past the highest code this app has issued rather than filling
    gaps. Reusing the number of a deleted product would put an old printed
    label - still stuck to something in the stockroom - onto a new item.
    """
    highest = 0
    for code in existing:
        match = _GENERATED.match(code.strip())
        if match:
            highest = max(highest, int(match.group(1)))
    return highest + 1


def assign_skus(shop, items) -> list[dict]:
    """Give each item a code, skipping any that already has one.

    Returns what was assigned, so the caller can say what happened rather than
    reporting a bare count against rows it never touched.
    """
    # Both columns, because a code must be unique against anything a scan
    # could resolve to - not only against other SKUs.
    codes = InventoryItem.objects.filter(shop=shop, tombstone=False).values_list(
        "sku", "barcode"
    )
    taken = {
        value.strip().upper()
        for pair in codes
        for value in pair
        if value and value.strip()
    }

    number = next_free_number(taken)
    assigned: list[dict] = []
    updated: list[InventoryItem] = []

    for item in items:
        if (item.sku or "").strip() or (item.barcode or "").strip():
            continue  # It can already be printed; leave it alone.

        code = format_sku(number)
        # A shop may already hold a code in this shape - typed by hand, or
        # imported - so step over anything taken rather than trusting the
        # highest number to be the whole story.
        while code.upper() in taken:
            number += 1
            code = format_sku(number)

        item.sku = code
        taken.add(code.upper())
        updated.append(item)
        assigned.append({"id": str(item.id), "name": item.name, "sku": code})
        number += 1

    if updated:
        InventoryItem.objects.bulk_update(updated, ["sku"])
    return assigned


class GenerateSkusView(APIView):
    """Give every product that cannot be printed a code that can be.

    The body may carry `item_ids` to limit it to a selection; without one it
    covers every product in the shop that has neither a barcode nor a SKU.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, shop_id):
        # Writing a product's code changes what a scan at the till resolves
        # to, so this sits with the roles that may edit the catalogue.
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.MANAGER
        )
        shop = membership.shop

        queryset = InventoryItem.objects.filter(
            shop=shop, tombstone=False, sku="", barcode=""
        )

        raw_ids = request.data.get("item_ids")
        if raw_ids is not None:
            if not isinstance(raw_ids, list):
                raise exceptions.ValidationError(
                    {"item_ids": "Expected a list of product ids."}
                )
            queryset = queryset.filter(id__in=raw_ids)

        items = list(queryset.order_by("name", "id")[: MAX_PER_REQUEST + 1])
        if len(items) > MAX_PER_REQUEST:
            raise exceptions.ValidationError(
                {
                    "detail": (
                        f"That is more than {MAX_PER_REQUEST} products at once. "
                        "Run it again to carry on."
                    )
                }
            )

        with transaction.atomic():
            assigned = assign_skus(shop, items)

        remaining = InventoryItem.objects.filter(
            shop=shop, tombstone=False, sku="", barcode=""
        ).count()

        return Response(
            {
                "assigned_count": len(assigned),
                "assigned": assigned[:50],
                "remaining_without_code": remaining,
            }
        )


def taken_codes(shop) -> set[str]:
    """Every code already in use in this shop, SKU or barcode.

    Both columns, because a code has to be unique against anything a scan
    could resolve to - not only against other SKUs.
    """
    pairs = InventoryItem.objects.filter(shop=shop, tombstone=False).values_list(
        "sku", "barcode"
    )
    return {
        value.strip().upper()
        for pair in pairs
        for value in pair
        if value and value.strip()
    }

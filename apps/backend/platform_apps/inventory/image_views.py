"""Serving a product photo as a picture rather than as text inside a list.

Photos are kept as a base64 data URI in a column on the product. That column
was part of the product list, so opening Stock - or the till, which loads the
same list - downloaded every photo of every product inside one JSON response.
Two hundred products at sixty kilobytes each is roughly twelve megabytes, and
because that response must never be cached, all of it came down again on every
visit.

A picture served from its own address behaves the way a picture should: the
browser fetches it once, keeps it, and asks again only if it changed. Nothing
about where the bytes live has to change for that to be true - only how they
are handed over.

The ETag is the point of the whole endpoint. Without it a browser would
re-download every photo whenever its cache expired; with it, the second
request is answered "not modified" with no body at all.
"""
from __future__ import annotations

import base64
import binascii
import hashlib
import re

from django.http import HttpResponse, HttpResponseNotModified
from rest_framework import exceptions, permissions
from rest_framework.views import APIView

from platform_apps.inventory.models import InventoryItem
from platform_apps.shops.permissions import get_membership_or_403

#: data:image/jpeg;base64,<payload>
_DATA_URI = re.compile(r"^data:(image/[a-zA-Z0-9.+-]+);base64,(.+)$", re.DOTALL)

#: Only formats a browser renders inline. An SVG is a document that can carry
#: script, so it is not served back even if one somehow got stored.
ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}

#: A product photo is resized to about 60 KB before upload. The cap sits well
#: above that so a real picture is never refused, while still bounding what one
#: row - and therefore every backup - can carry.
MAX_IMAGE_BYTES = 400_000

#: A given product's photo rarely changes, and the ETag catches it when it
#: does, so this can be long.
CACHE_SECONDS = 60 * 60 * 24 * 30


def parse_data_uri(value: str) -> tuple[str, bytes] | None:
    """The media type and raw bytes, or None if it is not a usable image."""
    match = _DATA_URI.match((value or "").strip())
    if not match:
        return None
    media_type = match.group(1).lower()
    if media_type not in ALLOWED_TYPES:
        return None
    try:
        return media_type, base64.b64decode(match.group(2), validate=True)
    except (binascii.Error, ValueError):
        # Stored text that will not decode is a broken row, not a server
        # fault: answer "no picture" rather than a 500 on a product page.
        return None


class InventoryItemImageView(APIView):
    """One product's photo, as an image the browser can cache."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id, item_id):
        membership = get_membership_or_403(request.user, shop_id)
        item = (
            InventoryItem.objects.filter(
                shop=membership.shop, pk=item_id, tombstone=False
            )
            .only("id", "image_data")
            .first()
        )
        if item is None:
            raise exceptions.NotFound("Product not found.")

        parsed = parse_data_uri(item.image_data or "")
        if parsed is None:
            raise exceptions.NotFound("That product has no picture.")
        media_type, payload = parsed

        etag = f'"{hashlib.sha256(payload).hexdigest()[:32]}"'
        if request.headers.get("If-None-Match") == etag:
            return HttpResponseNotModified()

        response = HttpResponse(payload, content_type=media_type)
        response["ETag"] = etag
        # Private: a product photo belongs to one shop, so it must not sit in a
        # shared cache anywhere along the way.
        response["Cache-Control"] = f"private, max-age={CACHE_SECONDS}"
        response["Content-Length"] = str(len(payload))
        return response

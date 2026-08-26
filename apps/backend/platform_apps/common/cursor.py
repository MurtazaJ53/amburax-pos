"""Reading a long list a page at a time, without losing or repeating rows.

These endpoints were capped: two hundred rows by default, five hundred at
most, and then the list simply stopped. Nothing fell over, but past the cap
the remaining rows were not reachable from any screen, and nobody was told.

Two things shape how this is done.

The response body cannot change. The Flutter client throws outright on
anything that is not a bare JSON array, so the rows stay an array and the
cursor travels in a response header. A caller that ignores the header behaves
exactly as it did before.

And it is keyset, not offset. Rows are inserted while somebody reads - a till
is ringing up sales the whole time - so "skip the first two hundred" means
page two starts from a different place than page one ended, silently
repeating some rows and skipping others. A cursor names the last row seen and
asks for what comes after it, which is stable no matter what arrives
meanwhile.

The tiebreaker is the part that is easy to get wrong. Ordering by a timestamp
alone is not enough for a keyset: primary keys here are random UUIDs, and
imported sales share a timestamp in their thousands - the sales model carries
a comment saying exactly that. Two rows with the same sort value and nothing
to separate them can straddle a page boundary, and one of them is dropped. So
every cursor sorts on a chosen field plus the primary key, which is unique by
definition.
"""
from __future__ import annotations

import base64
import binascii
import json
from typing import Any, Sequence

from django.db.models import Q, QuerySet

#: How many rows one page holds when the caller does not say.
#:
#: Deliberately the same as the old hard cap. The mobile client asks for this
#: endpoint with no limit at all and takes what it is given, so lowering the
#: default would have quietly cut it from two hundred products to fifty on the
#: day this deployed - a regression nobody would have connected to paging.
#: Callers that follow cursors ask for a smaller page explicitly; the web app
#: asks for a hundred.
DEFAULT_PAGE_SIZE = 200

#: The most one request may ask for, whatever it asks for.
MAX_PAGE_SIZE = 200

#: The header the next cursor travels in, so the body stays a bare array.
NEXT_CURSOR_HEADER = "X-Next-Cursor"


def page_size(raw: object, *, default: int = DEFAULT_PAGE_SIZE) -> int:
    """Clamp a caller-supplied page size into a range one query can serve."""
    try:
        value = int(raw)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return default
    if value <= 0:
        return default
    return min(value, MAX_PAGE_SIZE)


def encode_cursor(values: Sequence[Any]) -> str:
    """An opaque token holding the sort values of the last row on a page.

    Opaque rather than readable so its shape does not become something callers
    depend on - it is this module's business, and only ever handed back.
    """
    payload = json.dumps([_as_text(value) for value in values], separators=(",", ":"))
    return base64.urlsafe_b64encode(payload.encode("utf-8")).decode("ascii").rstrip("=")


def decode_cursor(raw: object, *, expected: int) -> list[str] | None:
    """The values inside a token, or None if it is not one.

    A cursor arrives in a query string, so it can be anything at all. Every
    failure returns None and the caller starts from the beginning, because a
    mistyped cursor should show the first page rather than a stack trace.
    """
    text = str(raw or "").strip()
    if not text:
        return None
    padded = text + "=" * (-len(text) % 4)
    try:
        decoded = json.loads(base64.urlsafe_b64decode(padded.encode("ascii")))
    except (binascii.Error, ValueError, UnicodeDecodeError):
        return None
    if not isinstance(decoded, list) or len(decoded) != expected:
        return None
    if not all(isinstance(value, str) for value in decoded):
        return None
    return decoded


def _as_text(value: Any) -> str:
    """Sort values as strings, so a token is JSON and survives a round trip.

    Django coerces them back for the comparison - an ISO string against a
    datetime column, a digit string against a decimal one - so nothing is lost
    by carrying them this way.
    """
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def after(order: Sequence[tuple[str, bool]], values: Sequence[str]) -> Q:
    """Rows strictly after the one the cursor names, in the given order.

    The row-value comparison written out longhand, because Django cannot
    express `(a, b, c) < (?, ?, ?)` directly and a naive AND of per-column
    filters is simply wrong - it would exclude rows whose first column ties.

    For each column in turn: every earlier column equal, and this one past the
    cursor's value. OR them together and you have "the next row", whatever mix
    of ascending and descending the sort uses.
    """
    clause = Q(pk__in=[])  # Matches nothing, so the OR below builds up cleanly.
    for index, (field, descending) in enumerate(order):
        step = Q(**{f"{field}__{'lt' if descending else 'gt'}": values[index]})
        for earlier, (prior_field, _) in enumerate(order[:index]):
            step &= Q(**{prior_field: values[earlier]})
        clause |= step
    return clause


def normalise_order(
    field: str | None,
    descending: bool,
    order: Sequence[tuple[str, bool]] | None,
) -> list[tuple[str, bool]]:
    """The sort a keyset will use, always ending in the primary key.

    The tiebreak is not optional. Primary keys here are random UUIDs and
    imported sales share a timestamp in their thousands, so a sort that can
    tie has rows with no defined position - and two of them either side of a
    page boundary means one is never returned.
    """
    columns = list(order) if order else [(field or "created_at", descending)]
    if not any(name == "id" for name, _ in columns):
        # Direction follows the last real column, so the tiebreak reads in the
        # same direction as the sort rather than fighting it.
        columns.append(("id", columns[-1][1]))
    return columns


def cursor_page(
    queryset: QuerySet,
    *,
    field: str | None = None,
    descending: bool = True,
    order: Sequence[tuple[str, bool]] | None = None,
    cursor: object = None,
    size: object = None,
) -> tuple[list, str | None]:
    """One page of rows, and the cursor for the next - or None at the end.

    Pass `field` for a single-column sort, or `order` for several - a list of
    (column, descending) pairs, outermost first. The primary key is appended
    automatically as the tiebreak.

    Ordering is applied here rather than trusted from the caller: a keyset only
    works if the query is sorted by exactly the columns the cursor compares,
    and a queryset ordered some other way would page incoherently while
    looking perfectly fine.
    """
    limit = page_size(size)
    columns = normalise_order(field, descending, order)
    queryset = queryset.order_by(
        *[f"{'-' if desc else ''}{name}" for name, desc in columns]
    )

    values = decode_cursor(cursor, expected=len(columns))
    if values is not None:
        queryset = queryset.filter(after(columns, values))

    # One extra row, purely to learn whether there is a next page. Counting the
    # whole table instead would cost a second scan on every request, and the
    # question is only ever "is there more", never "how much more".
    rows = list(queryset[: limit + 1])
    if len(rows) <= limit:
        return rows, None

    page = rows[:limit]
    last = page[-1]
    return page, encode_cursor([getattr(last, name) for name, _ in columns])


def attach_cursor(response, next_cursor: str | None):
    """Put the next cursor on a response without touching its body."""
    if next_cursor:
        response[NEXT_CURSOR_HEADER] = next_cursor
    return response


class CursorListMixin:
    """A DRF list view that pages by cursor and keeps its array body.

    `list` is overridden rather than a DRF pagination class being set, because
    every pagination class DRF ships wraps the rows in an envelope. The
    Flutter client throws on anything that is not a bare array, so the rows
    stay exactly as they were and the cursor goes in a header. A caller that
    ignores the header sees precisely what it saw before.
    """

    #: The column the keyset sorts on. Must be non-nullable: a NULL has no
    #: position in an ordering, so rows carrying one cannot be paged past.
    cursor_field = "created_at"
    cursor_descending = True
    #: For sorts of more than one column: (column, descending) pairs,
    #: outermost first. Overrides cursor_field when set.
    cursor_order: Sequence[tuple[str, bool]] | None = None

    def list(self, request, *args, **kwargs):
        from rest_framework.response import Response

        queryset = self.filter_queryset(self.get_queryset())
        rows, next_cursor = cursor_page(
            queryset,
            field=self.cursor_field,
            descending=self.cursor_descending,
            order=self.cursor_order,
            cursor=request.query_params.get("cursor"),
            size=request.query_params.get("limit"),
        )
        serializer = self.get_serializer(rows, many=True)
        return attach_cursor(Response(serializer.data), next_cursor)

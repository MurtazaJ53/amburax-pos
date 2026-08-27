"""Showing what an import would do, by doing it and taking it back.

A preview that reimplements the import is a preview that drifts from it. The
matching rules are not trivial - a product matches on SKU, or failing that on
name and size; a customer matches on a keyed hash of their phone; a sale
matches on the bill number it came with - and a second copy of that logic
written for the preview would agree with the real thing on the day it was
written and quietly stop agreeing afterwards. The screen would promise one
outcome and the import would deliver another, which is worse than no preview
at all.

So the preview is the real import, run inside a transaction that is rolled
back before it commits. Every rule is the one that will actually apply,
because it is literally the same code path. What comes back is what would
have happened.

Two things have to be suppressed. Anything outside the database does not roll
back - the dashboard rebuild in particular - so it is skipped rather than
undone. And the import batch would otherwise survive as the record of an
import that never happened, so it goes back with everything else.
"""
from __future__ import annotations

from django.db import transaction


def wants_preview(request) -> bool:
    """Whether this request is asking what would happen, not for it to happen.

    Only an explicit boolean true. A string "false" from a form-encoded client
    is truthy in Python, and reading that as "preview" would silently turn a
    real import into a no-op - the shopkeeper watching it report success and
    then finding nothing imported.
    """
    return request.data.get("dry_run") is True


def discard(preview: bool) -> None:
    """Roll the current transaction back when this was only a rehearsal.

    Called at the end of the atomic block the import already runs in. Marking
    it for rollback rather than raising keeps the response intact: the counts
    were gathered before anything was thrown away.
    """
    if preview:
        transaction.set_rollback(True)


def annotate(payload: dict, preview: bool) -> dict:
    """Say plainly that nothing was written.

    In the payload rather than only in the interface, because every client
    reads this response - and one that ignored the flag would otherwise report
    a successful import of rows that do not exist.
    """
    if not preview:
        return payload
    return {**payload, "dry_run": True, "written": False}

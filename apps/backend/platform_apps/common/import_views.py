"""Recent imports, and taking one back.

The list exists because "undo the last import" is not what somebody actually
wants when they realise a mistake. They want to undo *the one that went
wrong*, which may not be the last if they have imported again since - and
picking it out needs enough to recognise it by: what kind, how many rows,
which file, when, and who.
"""
from __future__ import annotations

from rest_framework import exceptions, permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from platform_apps.common.import_undo import undo
from platform_apps.common.models import ImportBatch
from platform_apps.shops.models import ShopMembership
from platform_apps.shops.permissions import get_membership_or_403

#: A shop only ever needs the recent ones. An import from last year is not
#: something anybody is about to take back.
RECENT_LIMIT = 20


def _serialize(batch: ImportBatch) -> dict:
    return {
        "id": str(batch.id),
        "kind": batch.kind,
        "filename": batch.filename,
        "row_count": batch.row_count,
        "created_count": batch.created_count,
        "created_at": batch.created_at,
        "actor_name": (
            (batch.actor_user.full_name or batch.actor_user.email)
            if batch.actor_user
            else ""
        ),
        "undone_at": batch.undone_at,
        "undone_count": batch.undone_count,
        "kept_count": batch.kept_count,
        # Nothing to take back when it created nothing: every row matched
        # something already here and was refreshed instead of added.
        "can_undo": batch.undone_at is None and batch.created_count > 0,
    }


class ImportBatchListView(APIView):
    """The recent imports, newest first."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, shop_id):
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.STAFF
        )
        batches = ImportBatch.objects.filter(shop=membership.shop).select_related(
            "actor_user"
        )[:RECENT_LIMIT]
        return Response([_serialize(batch) for batch in batches])


class ImportBatchUndoView(APIView):
    """Take back what one import created."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, shop_id, batch_id):
        # Undo removes rows in bulk, which is a larger action than adding them
        # one at a time - so it sits with the roles that manage the shop rather
        # than with everyone who can run an import.
        membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.MANAGER
        )
        batch = ImportBatch.objects.filter(shop=membership.shop, pk=batch_id).first()
        if batch is None:
            raise exceptions.NotFound("That import was not found for this shop.")

        result = undo(batch)
        batch.refresh_from_db()
        return Response({**result, "batch": _serialize(batch)})

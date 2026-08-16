from __future__ import annotations

from django.contrib.auth import get_user_model
from django.db.models import F
from django.utils import timezone
from rest_framework import exceptions
from rest_framework.response import Response
from rest_framework.generics import ListAPIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView

from platform_apps.audit.services import create_workspace_audit_event, snapshot_membership
from platform_apps.common.migration import (
    MigrationBridgeMode,
    MigrationCutoverStatus,
    MigrationDomain,
    MigrationWriteMaster,
)
from platform_apps.jobs.readiness import build_pilot_signoff
from platform_apps.jobs.models import MigrationDomainControl
from platform_apps.shops.invites import build_invite_link, create_invite
from platform_apps.shops.models import ShopMembership, ShopPlanRequest, WorkspaceAccessSession
from platform_apps.users.jwt_auth import revoke_user_tokens
from platform_apps.shops.permissions import get_membership_or_403
from platform_apps.shops.serializers import (
    ShopDomainStateSerializer,
    ShopMembershipListSerializer,
    ShopPlanRequestCreateSerializer,
    ShopPlanRequestSerializer,
    WorkspaceOwnershipTransferResultSerializer,
    WorkspaceOwnershipTransferSerializer,
    WorkspaceAccessSessionHeartbeatResultSerializer,
    WorkspaceAccessSessionHeartbeatSerializer,
    WorkspaceAccessSessionSerializer,
    WorkspaceAccessSessionUpdateSerializer,
    WorkspaceTeamMemberCreateSerializer,
    WorkspaceTeamMemberSerializer,
    WorkspaceTeamMemberUpdateSerializer,
)


class ShopMembershipListView(ListAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = ShopMembershipListSerializer
    pagination_class = None

    def get_queryset(self):
        return (
            ShopMembership.objects.select_related("shop")
            .filter(user=self.request.user)
            .order_by("shop__name")
        )


class ShopDomainStateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, shop_id, domain):
        membership = get_membership_or_403(request.user, shop_id, ShopMembership.Role.VIEWER)

        if domain not in MigrationDomain.values:
            raise exceptions.NotFound("Unknown migration domain.")

        control = (
            MigrationDomainControl.objects.filter(
                shop=membership.shop,
                domain=domain,
                is_enabled=True,
            )
            .select_related("shop")
            .first()
        )

        if control is None:
            # No migration control row means this shop never came from Firebase —
            # it was created directly in PostgreSQL by self-serve registration, so
            # Postgres IS its source of truth. Reporting LEGACY/Firebase here made
            # the mobile app treat the backend as non-primary and skip pulling the
            # catalog/sales, so a fresh install showed an empty shop even though
            # the data was safely in Postgres. Default native shops to primary.
            payload = {
                "shop_id": membership.shop_id,
                "domain": domain,
                "control_present": False,
                "write_master": MigrationWriteMaster.POSTGRES,
                "bridge_mode": MigrationBridgeMode.DISABLED,
                "cutover_status": MigrationCutoverStatus.POSTGRES_PRIMARY,
                "current_epoch": 1,
                "shadow_reads_enabled": False,
                "is_enabled": True,
                "can_write_on_postgres_surface": True,
                "pilot_signoff_status": None,
                "pilot_signoff_summary": None,
                "pilot_recommended_action": None,
                "pilot_latest_verify_result": None,
            }
        else:
            signoff = build_pilot_signoff(control)
            payload = {
                "shop_id": membership.shop_id,
                "domain": control.domain,
                "control_present": True,
                "write_master": control.write_master,
                "bridge_mode": control.bridge_mode,
                "cutover_status": control.cutover_status,
                "current_epoch": control.current_epoch,
                "shadow_reads_enabled": control.shadow_reads_enabled,
                "is_enabled": control.is_enabled,
                "can_write_on_postgres_surface": (
                    control.write_master == MigrationWriteMaster.POSTGRES
                    and control.cutover_status == MigrationCutoverStatus.POSTGRES_PRIMARY
                ),
                "pilot_signoff_status": signoff["signoff_status"],
                "pilot_signoff_summary": signoff["summary"],
                "pilot_recommended_action": signoff["recommended_action"],
                "pilot_latest_verify_result": signoff["latest_verify_result"],
            }

        serializer = ShopDomainStateSerializer(payload)
        return Response(serializer.data)


class ShopPlanRequestListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get_membership(self, shop_id):
        return get_membership_or_403(self.request.user, shop_id, ShopMembership.Role.ADMIN)

    def get(self, request, shop_id):
        membership = self.get_membership(shop_id)
        queryset = (
            ShopPlanRequest.objects.filter(shop=membership.shop)
            .select_related("requested_by_user")
            .order_by("-created_at")
        )
        serializer = ShopPlanRequestSerializer(queryset, many=True)
        return Response(serializer.data)

    def post(self, request, shop_id):
        membership = self.get_membership(shop_id)
        serializer = ShopPlanRequestCreateSerializer(
            data=request.data,
            context={"membership": membership},
        )
        serializer.is_valid(raise_exception=True)

        requested_plan_tier = serializer.validated_data["requested_plan_tier"]
        existing = (
            ShopPlanRequest.objects.filter(
                shop=membership.shop,
                requested_by_user=request.user,
                requested_plan_tier=requested_plan_tier,
                status__in=[ShopPlanRequest.Status.OPEN, ShopPlanRequest.Status.IN_REVIEW],
            )
            .select_related("requested_by_user")
            .order_by("-created_at")
            .first()
        )
        if existing is not None:
            response_serializer = ShopPlanRequestSerializer(existing)
            return Response(response_serializer.data)

        plan_request = ShopPlanRequest.objects.create(
            shop=membership.shop,
            requested_by_user=request.user,
            current_plan_tier=membership.shop.plan_tier,
            requested_plan_tier=requested_plan_tier,
            request_note=serializer.validated_data.get("request_note", ""),
            context_json=serializer.validated_data.get("context_json", {}),
        )
        create_workspace_audit_event(
            shop=membership.shop,
            actor_user=request.user,
            actor_role=membership.role,
            category="workspace",
            event_type="workspace.plan.requested",
            entity_type="shop_plan_request",
            entity_id=plan_request.id,
            entity_label=membership.shop.name,
            summary=f"Requested workspace plan change from {plan_request.current_plan_tier} to {plan_request.requested_plan_tier}.",
            source_surface="admin_web_plan",
            after={
                "current_plan_tier": plan_request.current_plan_tier,
                "requested_plan_tier": plan_request.requested_plan_tier,
                "status": plan_request.status,
            },
            metadata={
                "request_note": plan_request.request_note,
                "context_json": plan_request.context_json,
            },
        )
        response_serializer = ShopPlanRequestSerializer(plan_request)
        return Response(response_serializer.data, status=201)


class WorkspaceTeamListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get_membership(self, shop_id):
        return get_membership_or_403(self.request.user, shop_id, ShopMembership.Role.ADMIN)

    def get(self, request, shop_id):
        actor_membership = self.get_membership(shop_id)
        queryset = (
            ShopMembership.objects.filter(shop=actor_membership.shop)
            .select_related("user", "shop")
            .order_by("role", "status", "user__full_name", "user__email")
        )
        serializer = WorkspaceTeamMemberSerializer(
            queryset,
            many=True,
            context={"actor_membership": actor_membership},
        )
        return Response(serializer.data)

    def post(self, request, shop_id):
        actor_membership = self.get_membership(shop_id)
        serializer = WorkspaceTeamMemberCreateSerializer(
            data=request.data,
            context={"actor_membership": actor_membership},
        )
        serializer.is_valid(raise_exception=True)
        membership, created = serializer.create_or_update_membership()
        create_workspace_audit_event(
            shop=actor_membership.shop,
            actor_user=request.user,
            actor_role=actor_membership.role,
            category="workspace",
            event_type=(
                "workspace.team.member_added"
                if created
                else "workspace.team.member_reactivated"
            ),
            entity_type="shop_membership",
            entity_id=membership.id,
            entity_label=membership.user.full_name or membership.user.email or membership.email,
            summary=(
                f"Added {membership.user.email or membership.email} to the workspace as {membership.role}."
                if created
                else f"Updated or reactivated {membership.user.email or membership.email} in the workspace."
            ),
            source_surface="admin_web_team",
            after=snapshot_membership(membership),
        )
        response_serializer = WorkspaceTeamMemberSerializer(
            membership,
            context={"actor_membership": actor_membership},
        )
        payload = dict(response_serializer.data)

        # Unified invite: a newly-added (not-yet-active) member also gets a
        # single-use invite token so the owner can hand it over as a QR / code /
        # link. The invitee sets their password via accept-invite to sign in.
        if created or membership.status != ShopMembership.Status.ACTIVE:
            invite = create_invite(
                shop=actor_membership.shop,
                invited_by=request.user,
                actor_role=actor_membership.role,
                email=membership.email or membership.user.email,
                role=membership.role,
            )
            email_result = getattr(invite, "_email_result", None)
            payload["invite_code"] = invite.token
            payload["invite_link"] = build_invite_link(invite.token)
            payload["invite_expires_at"] = invite.expires_at.isoformat()
            payload["invite_email_sent"] = bool(
                email_result and email_result.get("ok")
            )

        return Response(payload, status=201)


class WorkspaceTeamDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get_actor_membership(self, shop_id):
        return get_membership_or_403(self.request.user, shop_id, ShopMembership.Role.ADMIN)

    def get_target_membership(self, actor_membership, membership_id):
        membership = (
            ShopMembership.objects.filter(shop=actor_membership.shop, pk=membership_id)
            .select_related("user", "shop")
            .first()
        )
        if membership is None:
            raise exceptions.NotFound("Workspace membership not found.")
        return membership

    def patch(self, request, shop_id, membership_id):
        actor_membership = self.get_actor_membership(shop_id)
        target_membership = self.get_target_membership(actor_membership, membership_id)
        before_snapshot = snapshot_membership(target_membership)
        serializer = WorkspaceTeamMemberUpdateSerializer(
            data=request.data,
            context={
                "actor_membership": actor_membership,
                "target_membership": target_membership,
            },
            partial=True,
        )
        serializer.is_valid(raise_exception=True)
        membership = serializer.apply()
        create_workspace_audit_event(
            shop=actor_membership.shop,
            actor_user=request.user,
            actor_role=actor_membership.role,
            category="workspace",
            event_type="workspace.team.member_updated",
            entity_type="shop_membership",
            entity_id=membership.id,
            entity_label=membership.user.full_name or membership.user.email or membership.email,
            summary=f"Updated workspace membership for {membership.user.email or membership.email}.",
            source_surface="admin_web_team",
            before=before_snapshot,
            after=snapshot_membership(membership),
        )
        response_serializer = WorkspaceTeamMemberSerializer(
            membership,
            context={"actor_membership": actor_membership},
        )
        return Response(response_serializer.data)


class WorkspaceOwnershipTransferView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, shop_id):
        actor_membership = get_membership_or_403(request.user, shop_id, ShopMembership.Role.OWNER)
        previous_owner_snapshot = snapshot_membership(actor_membership)
        serializer = WorkspaceOwnershipTransferSerializer(
            data=request.data,
            context={"actor_membership": actor_membership},
        )
        serializer.is_valid(raise_exception=True)
        target_membership = serializer.validated_data["target_membership"]
        next_owner_before_snapshot = snapshot_membership(target_membership)
        result = serializer.transfer()
        actor_membership.refresh_from_db()
        target_membership.refresh_from_db()
        create_workspace_audit_event(
            shop=actor_membership.shop,
            actor_user=request.user,
            actor_role=ShopMembership.Role.OWNER,
            category="workspace",
            event_type="workspace.team.ownership_transferred",
            entity_type="shop",
            entity_id=actor_membership.shop_id,
            entity_label=actor_membership.shop.name,
            summary=f"Transferred workspace ownership to {target_membership.user.email or target_membership.email}.",
            source_surface="admin_web_team",
            before={
                "previous_owner": previous_owner_snapshot,
                "next_owner_candidate": next_owner_before_snapshot,
            },
            after={
                "previous_owner": snapshot_membership(actor_membership),
                "new_owner": snapshot_membership(target_membership),
            },
            metadata={
                "shop_slug_confirmation": request.data.get("confirmation_text", ""),
            },
        )
        response_serializer = WorkspaceOwnershipTransferResultSerializer(result)
        return Response(response_serializer.data)


class WorkspaceAccessSessionListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, shop_id):
        actor_membership = get_membership_or_403(request.user, shop_id, ShopMembership.Role.ADMIN)
        queryset = (
            WorkspaceAccessSession.objects.filter(shop=actor_membership.shop)
            .select_related("user", "shop", "membership")
            .prefetch_related("user__passkeys")
            .order_by("-last_seen_at", "-created_at")
        )
        serializer = WorkspaceAccessSessionSerializer(
            queryset,
            many=True,
            context={"actor_membership": actor_membership},
        )
        return Response(serializer.data)


class WorkspaceAccessSessionHeartbeatView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, shop_id):
        actor_membership = get_membership_or_403(request.user, shop_id, ShopMembership.Role.VIEWER)
        serializer = WorkspaceAccessSessionHeartbeatSerializer(
            data=request.data,
            context={"actor_membership": actor_membership},
        )
        serializer.is_valid(raise_exception=True)
        session = serializer.upsert()
        # Capture request-side device context (IP / User-Agent) for the devices
        # screen. X-Forwarded-For's first hop is the client when behind a proxy.
        forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
        ip = (forwarded.split(",")[0].strip() if forwarded
              else request.META.get("REMOTE_ADDR")) or None
        user_agent = request.META.get("HTTP_USER_AGENT", "")[:400]
        updates = []
        if ip and session.ip_address != ip:
            session.ip_address = ip
            updates.append("ip_address")
        if user_agent and session.user_agent != user_agent:
            session.user_agent = user_agent
            updates.append("user_agent")
        if updates:
            updates.append("updated_at")
            session.save(update_fields=updates)
        response_serializer = WorkspaceAccessSessionHeartbeatResultSerializer(
            {
                "session_id": session.id,
                "status": session.status,
                "device_label": session.device_label,
                "revoke_reason": session.revoke_reason,
                "revoked_at": session.revoked_at,
                "wipe_requested": (
                    session.wipe_requested_at is not None and session.wipe_acknowledged_at is None
                ),
                "wipe_requested_at": session.wipe_requested_at,
                "wipe_acknowledged_at": session.wipe_acknowledged_at,
                "should_sign_out": session.status == WorkspaceAccessSession.Status.REVOKED,
                "should_wipe_local_data": (
                    session.wipe_requested_at is not None and session.wipe_acknowledged_at is None
                ),
            }
        )
        return Response(response_serializer.data)


class WorkspaceAccessSessionDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get_actor_membership(self, shop_id):
        return get_membership_or_403(self.request.user, shop_id, ShopMembership.Role.ADMIN)

    def get_target_session(self, actor_membership, session_id):
        target_session = (
            WorkspaceAccessSession.objects.filter(shop=actor_membership.shop, pk=session_id)
            .select_related("user", "shop", "membership")
            .prefetch_related("user__passkeys")
            .first()
        )
        if target_session is None:
            raise exceptions.NotFound("Workspace access session not found.")
        return target_session

    def patch(self, request, shop_id, session_id):
        actor_membership = self.get_actor_membership(shop_id)
        target_session = self.get_target_session(actor_membership, session_id)
        before_snapshot = {
            "status": target_session.status,
            "revoke_reason": target_session.revoke_reason,
            "revoked_at": target_session.revoked_at,
            "wipe_requested_at": target_session.wipe_requested_at,
            "wipe_acknowledged_at": target_session.wipe_acknowledged_at,
        }
        serializer = WorkspaceAccessSessionUpdateSerializer(
            data=request.data,
            context={
                "actor_membership": actor_membership,
                "target_session": target_session,
            },
        )
        serializer.is_valid(raise_exception=True)
        updated_session = serializer.apply()
        action = serializer.validated_data["action"]
        if action == "revoke":
            # Withdraw the tokens as well as the row. Marking the session
            # REVOKED alone left the device's JWT working, so the screen
            # reported a sign-out that had not happened.
            revoke_user_tokens(updated_session.user)
        event_type = {
            "revoke": "workspace.session.revoked",
            "request_wipe": "workspace.session.wipe_requested",
            "restore": "workspace.session.restored",
        }[action]
        summary = {
            "revoke": f"Revoked workspace session {updated_session.device_label}.",
            "request_wipe": f"Requested remote wipe for workspace session {updated_session.device_label}.",
            "restore": f"Restored workspace session {updated_session.device_label}.",
        }[action]
        create_workspace_audit_event(
            shop=actor_membership.shop,
            actor_user=request.user,
            actor_role=actor_membership.role,
            category="workspace",
            event_type=event_type,
            entity_type="workspace_access_session",
            entity_id=updated_session.id,
            entity_label=updated_session.device_label,
            summary=summary,
            source_surface="admin_web_sessions",
            before=before_snapshot,
            after={
                "status": updated_session.status,
                "revoke_reason": updated_session.revoke_reason,
                "revoked_at": updated_session.revoked_at,
                "wipe_requested_at": updated_session.wipe_requested_at,
                "wipe_acknowledged_at": updated_session.wipe_acknowledged_at,
            },
        )
        response_serializer = WorkspaceAccessSessionSerializer(
            updated_session,
            context={"actor_membership": actor_membership},
        )
        return Response(response_serializer.data)


class WorkspaceAccessSessionRevokeAllView(APIView):
    """Sign out every active session for the shop, optionally keeping the
    caller's current device (by app_instance_id). Owner/admin only."""

    permission_classes = [IsAuthenticated]

    def post(self, request, shop_id):
        actor_membership = get_membership_or_403(
            request.user, shop_id, ShopMembership.Role.ADMIN
        )
        keep = (request.data or {}).get("keep_app_instance_id", "")
        from django.utils import timezone

        qs = WorkspaceAccessSession.objects.filter(
            shop=actor_membership.shop,
            status=WorkspaceAccessSession.Status.ACTIVE,
        )
        if keep:
            qs = qs.exclude(app_instance_id=keep)
        # Collected before the update, because afterwards the rows no longer
        # match the ACTIVE filter and the users behind them cannot be found.
        affected_user_ids = list(qs.values_list("user_id", flat=True).distinct())
        count = qs.update(
            status=WorkspaceAccessSession.Status.REVOKED,
            revoke_reason="Signed out from all devices by an admin.",
            revoked_at=timezone.now(),
            revoked_by_user=request.user,
        )
        # The part that makes the sign-out real. Without it this endpoint only
        # asked the clients to leave and trusted them to comply.
        get_user_model().objects.filter(id__in=affected_user_ids).update(
            token_version=F("token_version") + 1
        )
        create_workspace_audit_event(
            shop=actor_membership.shop,
            actor_user=request.user,
            actor_role=actor_membership.role,
            category="security",
            event_type="sessions_revoked_all",
            entity_type="session",
            entity_id="",
            entity_label=f"{count} devices",
            summary=f"Signed out {count} device(s).",
            source_surface="devices",
        )
        return Response({"revoked": count})


class WorkspaceAccessSessionWipeAcknowledgeView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, shop_id, session_id):
        actor_membership = get_membership_or_403(request.user, shop_id, ShopMembership.Role.VIEWER)
        session = (
            WorkspaceAccessSession.objects.filter(
                shop=actor_membership.shop,
                pk=session_id,
                user=request.user,
            )
            .select_related("shop", "user")
            .first()
        )
        if session is None:
            raise exceptions.NotFound("Workspace access session not found.")

        if session.wipe_requested_at is not None and session.wipe_acknowledged_at is None:
            session.wipe_acknowledged_at = timezone.now()
            session.save(update_fields=["wipe_acknowledged_at", "updated_at"])

        return Response(
            {
                "session_id": str(session.id),
                "wipe_acknowledged_at": session.wipe_acknowledged_at,
            }
        )

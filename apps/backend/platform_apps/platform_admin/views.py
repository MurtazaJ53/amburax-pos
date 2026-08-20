from rest_framework import generics
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.pagination import PageNumberPagination
from django.db.models import Count, Q
from django.utils import timezone
from datetime import timedelta
from django.core.cache import cache
from django.contrib.auth import get_user_model

from platform_apps.common.permissions import (
    IsPlatformAdminUser,
    IsVerifiedPlatformAdmin,
)
from platform_apps.shops.models import Shop, ShopPlanRequest
from platform_apps.platform_admin.models import PlatformAuditEvent
from platform_apps.platform_admin.serializers import (
    PlatformShopSerializer,
    PlatformShopLifecycleSerializer,
    PlatformShopPlanSerializer,
    PlatformAuditEventSerializer,
    PlatformMetricsSerializer
)

User = get_user_model()

class StandardPagination(PageNumberPagination):
    page_size = 25
    page_size_query_param = 'page_size'
    max_page_size = 100

def _get_client_ip(request):
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for:
        return x_forwarded_for.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR')

def _write_platform_audit(request, action, shop=None, before=None, after=None, reason='', metadata=None):
    PlatformAuditEvent.objects.create(
        actor_user=request.user,
        shop=shop,
        action=action,
        reason=reason,
        before_json=before or {},
        after_json=after or {},
        metadata_json=metadata or {},
        ip_address=_get_client_ip(request)
    )

def _get_shop_or_404(shop_id):
    try:
        return Shop.objects.select_related('owner_user').annotate(
            _member_count=Count('memberships')
        ).get(id=shop_id)
    except Shop.DoesNotExist:
        raise NotFound(detail="Shop not found.")

class PlatformShopListView(generics.ListAPIView):
    permission_classes = [IsPlatformAdminUser]
    serializer_class = PlatformShopSerializer
    pagination_class = StandardPagination

    def get_queryset(self):
        qs = Shop.objects.select_related('owner_user').annotate(
            _member_count=Count('memberships')
        ).order_by('-created_at')

        status = self.request.query_params.get('status')
        if status in Shop.Status.values:
            qs = qs.filter(status=status)

        plan = self.request.query_params.get('plan')
        if plan:
            qs = qs.filter(settings_json__plan_tier=plan)

        q = self.request.query_params.get('q')
        if q:
            qs = qs.filter(
                Q(name__icontains=q) |
                Q(slug__icontains=q) |
                Q(owner_user__email__icontains=q)
            )

        return qs

    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        _write_platform_audit(request, 'platform.shops.listed')
        return response

class PlatformShopDetailView(generics.RetrieveAPIView):
    permission_classes = [IsPlatformAdminUser]
    serializer_class = PlatformShopSerializer
    lookup_url_kwarg = 'shop_id'

    def get_object(self):
        shop_id = self.kwargs.get(self.lookup_url_kwarg)
        return _get_shop_or_404(shop_id)

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        serializer = self.get_serializer(instance)
        _write_platform_audit(request, 'platform.shop.viewed', shop=instance)
        return Response(serializer.data)

class PlatformShopSuspendView(APIView):
    # Destructive: suspending a shop stops it trading. Needs MFA actually
    # completed recently, not merely an account that has it switched on.
    permission_classes = [IsVerifiedPlatformAdmin]

    def post(self, request, shop_id):
        shop = _get_shop_or_404(shop_id)
        if shop.status == Shop.Status.SUSPENDED:
            raise ValidationError("Shop is already suspended.")

        serializer = PlatformShopLifecycleSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        reason = serializer.validated_data['reason']
        before = {'status': shop.status, 'status_reason': shop.status_reason}
        
        shop.status = Shop.Status.SUSPENDED
        shop.status_reason = reason
        shop.save()

        after = {'status': shop.status, 'status_reason': shop.status_reason}
        _write_platform_audit(request, 'shop.suspended', shop=shop, before=before, after=after, reason=reason)

        shop_serializer = PlatformShopSerializer(shop)
        return Response(shop_serializer.data)

class PlatformShopActivateView(APIView):
    # Destructive: suspending a shop stops it trading. Needs MFA actually
    # completed recently, not merely an account that has it switched on.
    permission_classes = [IsVerifiedPlatformAdmin]

    def post(self, request, shop_id):
        shop = _get_shop_or_404(shop_id)
        if shop.status == Shop.Status.ACTIVE:
            raise ValidationError("Shop is already active.")

        serializer = PlatformShopLifecycleSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        reason = serializer.validated_data['reason']
        before = {'status': shop.status, 'status_reason': shop.status_reason}
        
        shop.status = Shop.Status.ACTIVE
        shop.status_reason = reason
        shop.save()

        after = {'status': shop.status, 'status_reason': shop.status_reason}
        _write_platform_audit(request, 'shop.activated', shop=shop, before=before, after=after, reason=reason)

        shop_serializer = PlatformShopSerializer(shop)
        return Response(shop_serializer.data)

class PlatformShopApproveView(APIView):
    # Destructive: suspending a shop stops it trading. Needs MFA actually
    # completed recently, not merely an account that has it switched on.
    permission_classes = [IsVerifiedPlatformAdmin]

    def post(self, request, shop_id):
        shop = _get_shop_or_404(shop_id)
        if shop.status != Shop.Status.PENDING:
            raise ValidationError("Shop is not pending approval.")

        serializer = PlatformShopLifecycleSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        reason = serializer.validated_data['reason']
        before = {'status': shop.status, 'status_reason': shop.status_reason}
        
        shop.status = Shop.Status.ACTIVE
        # Can clear status_reason on approve if we want, or set it to reason
        shop.status_reason = reason
        shop.save()

        after = {'status': shop.status, 'status_reason': shop.status_reason}
        _write_platform_audit(request, 'shop.approved', shop=shop, before=before, after=after, reason=reason)

        shop_serializer = PlatformShopSerializer(shop)
        return Response(shop_serializer.data)

class PlatformShopPlanView(APIView):
    # Destructive: suspending a shop stops it trading. Needs MFA actually
    # completed recently, not merely an account that has it switched on.
    permission_classes = [IsVerifiedPlatformAdmin]

    def post(self, request, shop_id):
        shop = _get_shop_or_404(shop_id)
        serializer = PlatformShopPlanSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        plan_tier = serializer.validated_data['plan_tier']
        reason = serializer.validated_data['reason']
        
        before = {'plan_tier': shop.settings_json.get('plan_tier')}
        
        settings_json = shop.settings_json.copy()
        settings_json['plan_tier'] = plan_tier
        shop.settings_json = settings_json
        shop.save()
        
        cache.delete(f"shop:{shop.id}:enabled_features")

        ShopPlanRequest.objects.filter(
            shop=shop, 
            status__in=[ShopPlanRequest.Status.OPEN, ShopPlanRequest.Status.IN_REVIEW]
        ).update(status=ShopPlanRequest.Status.RESOLVED)

        after = {'plan_tier': plan_tier}
        _write_platform_audit(request, 'shop.plan_changed', shop=shop, before=before, after=after, reason=reason)

        shop_serializer = PlatformShopSerializer(shop)
        return Response(shop_serializer.data)

class PlatformAuditEventListView(generics.ListAPIView):
    permission_classes = [IsPlatformAdminUser]
    serializer_class = PlatformAuditEventSerializer
    pagination_class = StandardPagination

    def get_queryset(self):
        qs = PlatformAuditEvent.objects.select_related('actor_user', 'shop')
        
        shop_id = self.request.query_params.get('shop_id')
        if shop_id:
            qs = qs.filter(shop_id=shop_id)
            
        action = self.request.query_params.get('action')
        if action:
            qs = qs.filter(action__icontains=action)
            
        actor_email = self.request.query_params.get('actor_email')
        if actor_email:
            qs = qs.filter(actor_user__email__icontains=actor_email)
            
        q = self.request.query_params.get('q')
        if q:
            qs = qs.filter(
                Q(action__icontains=q) |
                Q(reason__icontains=q) |
                Q(actor_user__email__icontains=q)
            )
            
        return qs

class PlatformMetricsView(APIView):
    permission_classes = [IsPlatformAdminUser]

    def get(self, request):
        metrics = cache.get('platform:metrics:v1')
        if metrics is None:
            total_shops = Shop.objects.count()
            active_shops = Shop.objects.filter(status=Shop.Status.ACTIVE).count()
            pending_shops = Shop.objects.filter(status=Shop.Status.PENDING).count()
            suspended_shops = Shop.objects.filter(status=Shop.Status.SUSPENDED).count()
            
            total_users = User.objects.count()
            
            # shops_created_last_30d
            thirty_days_ago = timezone.now() - timedelta(days=30)
            shops_created_last_30d = Shop.objects.filter(created_at__gte=thirty_days_ago).count()
            
            # starter_shops = filter by settings_json__plan_tier='starter' OR NOT has_key 'plan_tier'
            starter_shops = Shop.objects.filter(
                Q(settings_json__plan_tier='starter') | ~Q(settings_json__has_key='plan_tier')
            ).count()
            growth_shops = Shop.objects.filter(settings_json__plan_tier='growth').count()
            pro_shops = Shop.objects.filter(settings_json__plan_tier='pro').count()
            
            open_plan_requests = ShopPlanRequest.objects.filter(
                status__in=[ShopPlanRequest.Status.OPEN, ShopPlanRequest.Status.IN_REVIEW]
            ).count()
            
            metrics = {
                'total_shops': total_shops,
                'active_shops': active_shops,
                'pending_shops': pending_shops,
                'suspended_shops': suspended_shops,
                'total_users': total_users,
                'starter_shops': starter_shops,
                'growth_shops': growth_shops,
                'pro_shops': pro_shops,
                'shops_created_last_30d': shops_created_last_30d,
                'open_plan_requests': open_plan_requests,
            }
            cache.set('platform:metrics:v1', metrics, 300)
            
        _write_platform_audit(request, 'platform.metrics.viewed')
        return Response(metrics)

from rest_framework.test import APITestCase, APIClient
from django.contrib.auth import get_user_model
from django.utils import timezone
from django.urls import reverse
from platform_apps.shops.models import Shop, ShopMembership, ShopPlanRequest
from platform_apps.platform_admin.models import PlatformAuditEvent

User = get_user_model()

class PlatformAdminTests(APITestCase):
    def setUp(self):
        self.client = APIClient()
        
        self.admin_user = User.objects.create_user(
            email="admin@example.com",
            password="testpass",
            is_platform_admin=True
        )
        # The destructive platform endpoints now require MFA to have been
        # completed recently, enforced in Django rather than only in the
        # website's page guards. A fixture without it exercises the refusal
        # path, not the feature.
        self.admin_user.mfa_totp_secret = "JBSWY3DPEHPK3PXP"
        self.admin_user.mfa_totp_enabled_at = timezone.now()
        self.admin_user.mfa_totp_last_verified_at = timezone.now()
        self.admin_user.save()
        
        self.normal_user = User.objects.create_user(
            email="user@example.com",
            password="testpass",
            is_platform_admin=False
        )
        
        self.shop = Shop.objects.create(
            name="Test Shop",
            slug="test-shop",
            owner_user=self.normal_user,
            status=Shop.Status.ACTIVE,
            settings_json={'plan_tier': 'starter'}
        )
        
        self.membership = ShopMembership.objects.create(
            user=self.normal_user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER
        )
        
        self.pending_shop = Shop.objects.create(
            name="Pending Shop",
            slug="pending-shop",
            status=Shop.Status.PENDING
        )
        
        self.suspended_shop = Shop.objects.create(
            name="Suspended Shop",
            slug="suspended-shop",
            status=Shop.Status.SUSPENDED
        )

    def test_non_admin_gets_403(self):
        self.client.force_authenticate(user=self.normal_user)
        url = reverse('platform-shop-list')
        response = self.client.get(url)
        self.assertEqual(response.status_code, 403)
        
        url = reverse('platform-shop-suspend', kwargs={'shop_id': self.shop.id})
        response = self.client.post(url, {'reason': 'test'})
        self.assertEqual(response.status_code, 403)

    def test_suspend_shop(self):
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-shop-suspend', kwargs={'shop_id': self.shop.id})
        response = self.client.post(url, {'reason': 'violation'})
        
        self.assertEqual(response.status_code, 200)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.status, Shop.Status.SUSPENDED)
        self.assertEqual(self.shop.status_reason, 'violation')
        
        # Verify block on shop owner
        self.client.force_authenticate(user=self.normal_user)
        # Hit a real team endpoint
        team_url = reverse('workspace-team', kwargs={'shop_id': self.shop.id})
        team_response = self.client.get(team_url)
        self.assertEqual(team_response.status_code, 403)
        
        # Audit event verification
        audit = PlatformAuditEvent.objects.filter(action='shop.suspended').first()
        self.assertIsNotNone(audit)
        self.assertEqual(audit.shop_id, self.shop.id)
        self.assertEqual(audit.reason, 'violation')

    def test_activate_shop(self):
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-shop-activate', kwargs={'shop_id': self.suspended_shop.id})
        response = self.client.post(url, {'reason': 'resolved'})
        
        self.assertEqual(response.status_code, 200)
        self.suspended_shop.refresh_from_db()
        self.assertEqual(self.suspended_shop.status, Shop.Status.ACTIVE)
        
        audit = PlatformAuditEvent.objects.filter(action='shop.activated').first()
        self.assertIsNotNone(audit)

    def test_approve_shop(self):
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-shop-approve', kwargs={'shop_id': self.pending_shop.id})
        response = self.client.post(url, {'reason': 'looks good'})
        
        self.assertEqual(response.status_code, 200)
        self.pending_shop.refresh_from_db()
        self.assertEqual(self.pending_shop.status, Shop.Status.ACTIVE)
        
        audit = PlatformAuditEvent.objects.filter(action='shop.approved').first()
        self.assertIsNotNone(audit)

    def test_cannot_approve_non_pending(self):
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-shop-approve', kwargs={'shop_id': self.shop.id})
        response = self.client.post(url, {'reason': 'ok'})
        self.assertEqual(response.status_code, 400)

    def test_cannot_suspend_already_suspended(self):
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-shop-suspend', kwargs={'shop_id': self.suspended_shop.id})
        response = self.client.post(url, {'reason': 'ok'})
        self.assertEqual(response.status_code, 400)

    def test_cannot_activate_already_active(self):
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-shop-activate', kwargs={'shop_id': self.shop.id})
        response = self.client.post(url, {'reason': 'ok'})
        self.assertEqual(response.status_code, 400)

    def test_reason_is_required(self):
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-shop-suspend', kwargs={'shop_id': self.shop.id})
        response = self.client.post(url, {'reason': ''})
        self.assertEqual(response.status_code, 400)

    def test_plan_change(self):
        plan_req = ShopPlanRequest.objects.create(
            shop=self.shop,
            requested_by_user=self.normal_user,
            current_plan_tier='starter',
            requested_plan_tier='pro',
            status=ShopPlanRequest.Status.OPEN
        )
        
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-shop-plan', kwargs={'shop_id': self.shop.id})
        response = self.client.post(url, {'plan_tier': 'pro', 'reason': 'paid'})
        
        self.assertEqual(response.status_code, 200)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.settings_json.get('plan_tier'), 'pro')
        
        plan_req.refresh_from_db()
        self.assertEqual(plan_req.status, ShopPlanRequest.Status.RESOLVED)
        
        audit = PlatformAuditEvent.objects.filter(action='shop.plan_changed').first()
        self.assertIsNotNone(audit)

    def test_metrics(self):
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-metrics')
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        self.assertEqual(data['total_shops'], 3)
        self.assertEqual(data['active_shops'], 1)
        self.assertEqual(data['pending_shops'], 1)
        self.assertEqual(data['suspended_shops'], 1)
        self.assertEqual(data['starter_shops'], 3) # the other 2 have no plan_tier so default starter
        
        audit = PlatformAuditEvent.objects.filter(action='platform.metrics.viewed').first()
        self.assertIsNotNone(audit)

    def test_shop_list_filtering(self):
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-shop-list')
        
        response = self.client.get(url, {'status': 'pending'})
        self.assertEqual(len(response.json()['results']), 1)
        self.assertEqual(response.json()['results'][0]['id'], str(self.pending_shop.id))
        
        response = self.client.get(url, {'plan': 'starter'})
        self.assertEqual(len(response.json()['results']), 1)
        self.assertEqual(response.json()['results'][0]['id'], str(self.shop.id))
        
        response = self.client.get(url, {'q': 'Test'})
        self.assertEqual(len(response.json()['results']), 1)
        self.assertEqual(response.json()['results'][0]['id'], str(self.shop.id))

    # ------------------------------------------------------------------
    # Shop detail
    # ------------------------------------------------------------------

    def test_shop_detail_returns_correct_fields(self):
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-shop-detail', kwargs={'shop_id': self.shop.id})
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['id'], str(self.shop.id))
        self.assertIn('status', data)
        self.assertIn('plan_tier', data)
        self.assertIn('member_count', data)

    def test_shop_detail_nonexistent_returns_404(self):
        import uuid
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-shop-detail', kwargs={'shop_id': str(uuid.uuid4())})
        response = self.client.get(url)
        self.assertEqual(response.status_code, 404)

    # ------------------------------------------------------------------
    # Unauthenticated access
    # ------------------------------------------------------------------

    def test_unauthenticated_access_returns_401(self):
        anon = APIClient()
        url = reverse('platform-shop-list')
        response = anon.get(url)
        self.assertEqual(response.status_code, 401)

    # ------------------------------------------------------------------
    # Suspend → activate round-trip
    # ------------------------------------------------------------------

    def test_suspend_then_activate_round_trip(self):
        """Suspending then activating a shop must produce two audit events."""
        self.client.force_authenticate(user=self.admin_user)

        # Suspend
        suspend_url = reverse('platform-shop-suspend', kwargs={'shop_id': self.shop.id})
        resp = self.client.post(suspend_url, {'reason': 'test-suspend'})
        self.assertEqual(resp.status_code, 200)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.status, Shop.Status.SUSPENDED)

        # Activate
        activate_url = reverse('platform-shop-activate', kwargs={'shop_id': self.shop.id})
        resp = self.client.post(activate_url, {'reason': 'test-activate'})
        self.assertEqual(resp.status_code, 200)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.status, Shop.Status.ACTIVE)

        # Both audit events must exist
        self.assertTrue(PlatformAuditEvent.objects.filter(action='shop.suspended').exists())
        self.assertTrue(PlatformAuditEvent.objects.filter(action='shop.activated').exists())

    # ------------------------------------------------------------------
    # Audit event list endpoint
    # ------------------------------------------------------------------

    def test_audit_list_is_accessible_to_platform_admin(self):
        self.client.force_authenticate(user=self.admin_user)
        url = reverse('platform-audit')
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        self.assertIn('results', response.json())

    def test_audit_list_is_denied_to_normal_user(self):
        self.client.force_authenticate(user=self.normal_user)
        url = reverse('platform-audit')
        response = self.client.get(url)
        self.assertEqual(response.status_code, 403)

    def test_audit_list_filter_by_shop_id(self):
        """Trigger one audit event then filter the list by shop_id."""
        self.client.force_authenticate(user=self.admin_user)
        # Generate a known audit event
        suspend_url = reverse('platform-shop-suspend', kwargs={'shop_id': self.shop.id})
        self.client.post(suspend_url, {'reason': 'filter-test'})

        url = reverse('platform-audit')
        response = self.client.get(url, {'shop_id': str(self.shop.id)})
        self.assertEqual(response.status_code, 200)
        results = response.json()['results']
        # Every result must belong to this shop
        for r in results:
            self.assertEqual(r['shop'], str(self.shop.id))

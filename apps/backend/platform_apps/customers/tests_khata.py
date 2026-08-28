from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.customers.models import Customer
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class DebtorCollectionTests(TestCase):
    """Chasing udhaar is a weekly ritual. The thing that must not break is
    double-chasing: a customer nudged three times in a day stops answering."""

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="khata@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Khata Shop", slug="khata-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def _customer(self, name, *, balance="0.00", phone="9876543210", reminded=None):
        return Customer.objects.create(
            shop=self.shop,
            name=name,
            phone=phone,
            balance=Decimal(balance),
            last_reminded_at=reminded,
        )

    def _debtors(self):
        return self.client.get(f"/api/v1/shops/{self.shop.id}/customers/debtors/").json()

    # --- who is listed ---------------------------------------------------

    def test_only_customers_who_owe_are_listed(self):
        self._customer("Owes", balance="500.00")
        self._customer("Settled", balance="0.00")
        names = [row["name"] for row in self._debtors()["items"]]
        self.assertEqual(names, ["Owes"])

    def test_a_customer_in_credit_is_not_a_debtor(self):
        # A negative balance means the shop holds their money, not the reverse.
        self._customer("Advance", balance="-200.00")
        self.assertEqual(self._debtors()["items"], [])

    def test_biggest_debt_first(self):
        self._customer("Small", balance="100.00")
        self._customer("Large", balance="9000.00")
        names = [row["name"] for row in self._debtors()["items"]]
        self.assertEqual(names, ["Large", "Small"])

    def test_total_outstanding_adds_up(self):
        self._customer("A", balance="100.50")
        self._customer("B", balance="200.25")
        self.assertEqual(
            Decimal(self._debtors()["total_outstanding"]), Decimal("300.75")
        )

    def test_a_debtor_with_no_number_is_flagged_as_unreachable(self):
        self._customer("NoPhone", balance="500.00", phone="-")
        body = self._debtors()
        self.assertFalse(body["items"][0]["has_phone"])
        self.assertEqual(body["items"][0]["phone"], "")
        self.assertEqual(body["unreachable_count"], 1)

    def test_a_short_number_is_not_reachable(self):
        self._customer("Partial", balance="500.00", phone="98765")
        self.assertFalse(self._debtors()["items"][0]["has_phone"])

    # --- reminder state --------------------------------------------------

    def test_a_never_reminded_debtor_is_overdue(self):
        self._customer("Fresh", balance="500.00")
        row = self._debtors()["items"][0]
        self.assertIsNone(row["last_reminded_at"])
        self.assertIsNone(row["days_since_reminder"])
        self.assertTrue(row["is_overdue"])
        self.assertFalse(row["reminded_today"])

    def test_someone_reminded_today_is_not_chased_again(self):
        self._customer("Today", balance="500.00", reminded=timezone.now())
        row = self._debtors()["items"][0]
        self.assertTrue(row["reminded_today"])
        self.assertFalse(row["is_overdue"])

    def test_someone_reminded_two_days_ago_is_not_yet_overdue(self):
        self._customer(
            "Recent", balance="500.00", reminded=timezone.now() - timedelta(days=2)
        )
        row = self._debtors()["items"][0]
        self.assertFalse(row["reminded_today"])
        self.assertFalse(row["is_overdue"])
        self.assertEqual(row["days_since_reminder"], 2)

    def test_a_week_without_contact_is_overdue_again(self):
        self._customer(
            "Stale", balance="500.00", reminded=timezone.now() - timedelta(days=7)
        )
        self.assertTrue(self._debtors()["items"][0]["is_overdue"])

    # --- marking a reminder ----------------------------------------------

    def test_marking_a_reminder_is_visible_to_every_other_device(self):
        customer = self._customer("Chase", balance="500.00")
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/customers/{customer.id}/remind/",
            {},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.content)

        customer.refresh_from_db()
        self.assertIsNotNone(customer.last_reminded_at)
        # A second device reading the list now sees the same state.
        self.assertTrue(self._debtors()["items"][0]["reminded_today"])

    def test_marking_a_reminder_does_not_touch_the_balance(self):
        customer = self._customer("Chase", balance="500.00")
        self.client.post(
            f"/api/v1/shops/{self.shop.id}/customers/{customer.id}/remind/",
            {},
            format="json",
        )
        customer.refresh_from_db()
        self.assertEqual(customer.balance, Decimal("500.00"))

    def test_a_customer_from_another_shop_cannot_be_marked(self):
        other_shop = Shop.objects.create(name="Other", slug="other-khata")
        stranger = Customer.objects.create(
            shop=other_shop, name="Stranger", balance=Decimal("100.00")
        )
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/customers/{stranger.id}/remind/",
            {},
            format="json",
        )
        self.assertEqual(response.status_code, 404, response.content)


class LoyaltySettingsTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="loyalty@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Loyalty Shop", slug="loyalty-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/shops/{self.shop.id}/loyalty/"

    def test_loyalty_is_off_until_a_shop_turns_it_on(self):
        self.assertFalse(self.client.get(self.url).json()["enabled"])

    def test_enabling_and_setting_the_rate(self):
        response = self.client.patch(
            self.url,
            {"enabled": True, "points_per_hundred": 2, "point_value": "0.50"},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertTrue(body["enabled"])
        self.assertEqual(body["points_per_hundred"], 2)
        self.assertEqual(Decimal(body["point_value"]), Decimal("0.50"))

    def test_the_change_persists_for_the_sale_path_to_read(self):
        self.client.patch(self.url, {"enabled": True, "points_per_hundred": 3}, format="json")
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.settings_json["loyalty"]["points_per_hundred"], 3)

    def test_a_partial_update_leaves_the_rest_alone(self):
        self.client.patch(
            self.url, {"enabled": True, "points_per_hundred": 4}, format="json"
        )
        body = self.client.patch(self.url, {"enabled": False}, format="json").json()
        self.assertFalse(body["enabled"])
        self.assertEqual(body["points_per_hundred"], 4)

    def test_an_absurd_rate_is_rejected_not_silently_clamped(self):
        # A typo of 100000 would promise every customer a fortune. Refusing is
        # clearer than quietly storing something the owner did not type.
        response = self.client.patch(
            self.url, {"points_per_hundred": 100000}, format="json"
        )
        self.assertEqual(response.status_code, 400, response.content)

    def test_a_zero_point_value_is_rejected(self):
        response = self.client.patch(self.url, {"point_value": "0"}, format="json")
        self.assertEqual(response.status_code, 400, response.content)

    def test_a_negative_point_value_is_rejected(self):
        response = self.client.patch(self.url, {"point_value": "-1"}, format="json")
        self.assertEqual(response.status_code, 400, response.content)

    def test_junk_is_rejected(self):
        response = self.client.patch(
            self.url, {"points_per_hundred": "many"}, format="json"
        )
        self.assertEqual(response.status_code, 400, response.content)

    def test_a_cashier_can_read_the_rules_but_not_change_them(self):
        staff = PlatformUser.objects.create_user(
            email="loyalty-staff@example.com", password="secret", full_name="Staff"
        )
        ShopMembership.objects.create(
            user=staff,
            shop=self.shop,
            role=ShopMembership.Role.STAFF,
            status=ShopMembership.Status.ACTIVE,
        )
        client = APIClient()
        client.force_authenticate(user=staff)
        self.assertEqual(client.get(self.url).status_code, 200)
        self.assertEqual(
            client.patch(self.url, {"enabled": True}, format="json").status_code, 403
        )


class DebtorListIsBoundedTests(DebtorCollectionTests):
    """The list is capped; the figures above it are not.

    Measured at a thousand debtors this endpoint took 845ms and returned
    227KB, because it built, decrypted and serialised every one with no
    ceiling. Capping the list alone would have been worse than leaving it
    slow: the screen counts "N customers owe you" and sizes its reminder
    button from the rows it was given, so a silent cap makes a shop chase the
    first five hundred and believe it chased everybody.

    So these tests are mostly about the summary staying true when the list
    does not.
    """

    def _many(self, count, *, balance="100.00"):
        for n in range(count):
            self._customer(f"Debtor {n:03d}", balance=balance)

    def test_the_list_stops_at_the_limit(self):
        self._many(12)
        payload = self.client.get(
            f"/api/v1/shops/{self.shop.id}/customers/debtors/?limit=5"
        ).json()

        self.assertEqual(len(payload["items"]), 5)
        self.assertEqual(payload["showing"], 5)
        self.assertTrue(payload["truncated"])

    def test_the_money_owed_still_counts_everyone(self):
        # The figure a shopkeeper reads. If capping the list shrank this, the
        # fix would have introduced a money bug to save 800 milliseconds.
        self._many(12, balance="100.00")
        payload = self.client.get(
            f"/api/v1/shops/{self.shop.id}/customers/debtors/?limit=5"
        ).json()

        self.assertEqual(Decimal(payload["total_outstanding"]), Decimal("1200.00"))

    def test_the_number_of_debtors_still_counts_everyone(self):
        self._many(12)
        payload = self.client.get(
            f"/api/v1/shops/{self.shop.id}/customers/debtors/?limit=5"
        ).json()

        self.assertEqual(payload["debtor_count"], 12)

    def test_unreachable_counts_everyone_not_just_the_page(self):
        # Otherwise "3 with no mobile number" would mean "3 in the first page",
        # and a shop would stop collecting numbers it still needs.
        self._many(10, balance="100.00")
        for n in range(4):
            self._customer(f"No Number {n}", balance="50.00", phone="-")

        payload = self.client.get(
            f"/api/v1/shops/{self.shop.id}/customers/debtors/?limit=2"
        ).json()

        self.assertEqual(payload["unreachable_count"], 4)

    def test_a_short_list_is_not_marked_truncated(self):
        self._many(3)
        payload = self._debtors()

        self.assertFalse(payload["truncated"])
        self.assertEqual(payload["showing"], 3)
        self.assertEqual(payload["debtor_count"], 3)

    def test_the_biggest_debts_are_the_ones_kept(self):
        # A capped collection list has to hold the debts worth chasing.
        self._customer("Small", balance="10.00")
        self._customer("Huge", balance="9000.00")
        self._customer("Medium", balance="500.00")

        payload = self.client.get(
            f"/api/v1/shops/{self.shop.id}/customers/debtors/?limit=2"
        ).json()

        self.assertEqual([row["name"] for row in payload["items"]], ["Huge", "Medium"])

    def test_an_absurd_limit_is_clamped(self):
        # A caller asking for a million rows is asking for the outage this
        # change removed.
        self._many(3)
        payload = self.client.get(
            f"/api/v1/shops/{self.shop.id}/customers/debtors/?limit=999999"
        ).json()

        self.assertEqual(payload["showing"], 3)

    def test_a_nonsense_limit_falls_back_to_the_default(self):
        self._many(3)
        payload = self.client.get(
            f"/api/v1/shops/{self.shop.id}/customers/debtors/?limit=abc"
        ).json()

        self.assertEqual(payload["showing"], 3)

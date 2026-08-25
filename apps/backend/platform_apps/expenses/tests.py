from __future__ import annotations

from datetime import date
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from platform_apps.expenses.models import Expense
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class ExpenseApiTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(email="owner@example.com", password="secret", full_name="Owner")
        self.shop = Shop.objects.create(name="Demo Shop", slug="demo-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_create_expense(self):
        response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/expenses/",
            {
                "category": "Packaging",
                "amount": "240.00",
                "description": "Courier bags and tape",
                "payment_method": "UPI",
                "payment_reference": "upi-7782",
                "expense_date": "2026-04-30",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        expense = Expense.objects.get()
        self.assertEqual(expense.category, "Packaging")
        self.assertEqual(expense.amount, Decimal("240.00"))
        self.assertEqual(expense.payment_method, Expense.PaymentMethod.UPI)

    def test_list_expenses_for_shop(self):
        Expense.objects.create(
            shop=self.shop,
            actor_user=self.user,
            category="Packaging",
            amount=Decimal("240.00"),
            description="Courier bags and tape",
            expense_date="2026-04-30",
        )

        response = self.client.get(f"/api/v1/shops/{self.shop.id}/expenses/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json()), 1)

    def test_expense_summary_returns_aggregates(self):
        Expense.objects.create(
            shop=self.shop,
            actor_user=self.user,
            category="Packaging",
            amount=Decimal("240.00"),
            description="Courier bags and tape",
            expense_date="2026-04-30",
        )
        Expense.objects.create(
            shop=self.shop,
            actor_user=self.user,
            category="Travel",
            amount=Decimal("600.00"),
            description="Market pickup",
            expense_date="2026-04-30",
        )

        response = self.client.get(f"/api/v1/shops/{self.shop.id}/expenses/summary/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["total_entries"], 2)
        self.assertEqual(response.data["total_amount"], "840.00")
        self.assertEqual(response.data["unique_categories"], 2)
        self.assertEqual(response.data["biggest_category"], "Travel")

    def test_expense_detail_hides_archived_records(self):
        expense = Expense.objects.create(
            shop=self.shop,
            actor_user=self.user,
            category="Archived",
            amount=Decimal("10.00"),
            description="Should stay hidden",
            expense_date="2026-04-30",
            tombstone=True,
        )

        response = self.client.get(f"/api/v1/shops/{self.shop.id}/expenses/{expense.id}/")

        self.assertEqual(response.status_code, 404)

    def test_starter_plan_blocks_expense_access(self):
        self.shop.settings_json = {"plan_tier": "starter"}
        self.shop.save(update_fields=["settings_json"])

        list_response = self.client.get(f"/api/v1/shops/{self.shop.id}/expenses/")
        self.assertEqual(list_response.status_code, 403)
        self.assertIn("Expenses is not available", str(list_response.json()))

        create_response = self.client.post(
            f"/api/v1/shops/{self.shop.id}/expenses/",
            {
                "category": "Packaging",
                "amount": "240.00",
                "description": "Courier bags and tape",
                "payment_method": "UPI",
                "payment_reference": "upi-7782",
                "expense_date": "2026-04-30",
            },
            format="json",
        )
        self.assertEqual(create_response.status_code, 403)


class ExpenseEditTests(TestCase):
    """Correcting a recorded expense.

    Without this the only way to fix a wrong amount was to delete the row and
    type it again, which loses who recorded it and when - exactly the trail
    an expense register exists to keep.
    """

    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="editor@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Edit Shop", slug="edit-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.expense = Expense.objects.create(
            shop=self.shop,
            actor_user=self.user,
            category="Packaging",
            amount=Decimal("240.00"),
            description="Courier bags",
            payment_method="UPI",
            expense_date=date(2026, 4, 30),
        )
        self.url = f"/api/v1/shops/{self.shop.id}/expenses/{self.expense.id}/"

    def test_a_wrong_amount_can_be_corrected(self):
        response = self.client.patch(self.url, {"amount": "260.00"}, format="json")
        self.assertEqual(response.status_code, 200, response.content)
        self.expense.refresh_from_db()
        self.assertEqual(self.expense.amount, Decimal("260.00"))

    def test_correcting_one_field_leaves_the_others_alone(self):
        self.client.patch(self.url, {"amount": "260.00"}, format="json")
        self.expense.refresh_from_db()
        self.assertEqual(self.expense.category, "Packaging")
        self.assertEqual(self.expense.description, "Courier bags")
        self.assertEqual(self.expense.payment_method, "UPI")

    def test_the_category_and_the_pocket_it_came_from_can_both_change(self):
        response = self.client.patch(
            self.url,
            {"category": "Transport", "payment_method": "CASH"},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.expense.refresh_from_db()
        self.assertEqual(self.expense.category, "Transport")
        self.assertEqual(self.expense.payment_method, "CASH")

    def test_the_date_can_be_corrected(self):
        response = self.client.patch(
            self.url, {"expense_date": "2026-05-02"}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.expense.refresh_from_db()
        self.assertEqual(self.expense.expense_date, date(2026, 5, 2))

    def test_who_recorded_it_survives_the_edit(self):
        """The trail is the point of the register."""
        self.client.patch(self.url, {"amount": "999.00"}, format="json")
        self.expense.refresh_from_db()
        self.assertEqual(self.expense.actor_user_id, self.user.id)

    def test_another_shops_expense_cannot_be_edited(self):
        other = Shop.objects.create(name="Other", slug="other-expense-shop")
        foreign = Expense.objects.create(
            shop=other,
            category="Rent",
            amount=Decimal("5000.00"),
            payment_method="CASH",
            expense_date=date(2026, 4, 30),
        )
        response = self.client.patch(
            f"/api/v1/shops/{self.shop.id}/expenses/{foreign.id}/",
            {"amount": "1.00"},
            format="json",
        )
        self.assertEqual(response.status_code, 404, response.content)
        foreign.refresh_from_db()
        self.assertEqual(foreign.amount, Decimal("5000.00"))

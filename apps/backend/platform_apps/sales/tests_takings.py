"""Takings over a window.

The figures here are the ones a shopkeeper judges the business by, so the
rules that keep them honest are pinned: voids never count, split bills keep
their cash, quiet days stay in the series, and the comparison period is
exactly as long as the one it is compared against.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.payments.models import SalePayment
from platform_apps.sales.models import Sale
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class SaleTakingsTests(TestCase):
    def setUp(self):
        self.user = PlatformUser.objects.create_user(
            email="takings@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Takings Shop", slug="takings-shop")
        ShopMembership.objects.create(
            user=self.user,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)
        self.today = timezone.localdate()
        self.url = f"/api/v1/shops/{self.shop.id}/sales/takings/"

    def _sale(self, amount, days_ago=0, tenders=None, status=Sale.Status.COMPLETED):
        sale_date = self.today - timedelta(days=days_ago)
        occurred = timezone.now() - timedelta(days=days_ago)
        sale = Sale.objects.create(
            shop=self.shop,
            total_amount=Decimal(amount),
            sale_date=sale_date,
            occurred_at=occurred,
            status=status,
        )
        for method, value in (tenders or {}).items():
            SalePayment.objects.create(
                sale=sale,
                shop=self.shop,
                payment_method=method,
                amount=Decimal(value),
                occurred_at=occurred,
            )
        return sale

    def _get(self, **params):
        response = self.client.get(self.url, params)
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    # --- totals ----------------------------------------------------------

    def test_defaults_to_today_when_no_dates_are_given(self):
        self._sale("600")
        self._sale("900", days_ago=5)
        body = self._get()
        self.assertEqual(body["from"], self.today.isoformat())
        self.assertEqual(Decimal(body["total"]), Decimal("600.00"))
        self.assertEqual(body["bill_count"], 1)

    def test_a_window_covers_both_end_days(self):
        self._sale("100", days_ago=6)
        self._sale("200")
        body = self._get(
            **{
                "from": (self.today - timedelta(days=6)).isoformat(),
                "to": self.today.isoformat(),
            }
        )
        self.assertEqual(Decimal(body["total"]), Decimal("300.00"))
        self.assertEqual(body["days"], 7)

    def test_a_voided_bill_never_counts_toward_takings(self):
        self._sale("500", status=Sale.Status.VOID)
        self.assertEqual(Decimal(self._get()["total"]), Decimal("0.00"))

    def test_average_bill_is_zero_rather_than_a_division_error_on_a_quiet_day(self):
        body = self._get()
        self.assertEqual(Decimal(body["average_bill"]), Decimal("0.00"))
        self.assertEqual(body["bill_count"], 0)

    def test_dates_the_wrong_way_round_are_swapped_rather_than_refused(self):
        self._sale("250", days_ago=3)
        body = self._get(
            **{
                "from": self.today.isoformat(),
                "to": (self.today - timedelta(days=5)).isoformat(),
            }
        )
        self.assertEqual(Decimal(body["total"]), Decimal("250.00"))

    def test_a_malformed_date_is_refused(self):
        response = self.client.get(self.url, {"from": "22-08-2026"})
        self.assertEqual(response.status_code, 400, response.content)

    def test_an_absurd_range_is_refused_rather_than_served_slowly(self):
        response = self.client.get(self.url, {"from": "1900-01-01", "to": "2026-01-01"})
        self.assertEqual(response.status_code, 400, response.content)

    # --- comparison ------------------------------------------------------

    def test_the_comparison_window_is_exactly_as_long_as_the_current_one(self):
        """A 30-day month against a 31-day one invents a change."""
        body = self._get(
            **{
                "from": (self.today - timedelta(days=29)).isoformat(),
                "to": self.today.isoformat(),
            }
        )
        self.assertEqual(body["days"], 30)
        self.assertEqual(body["previous_to"], (self.today - timedelta(days=30)).isoformat())
        self.assertEqual(
            body["previous_from"], (self.today - timedelta(days=59)).isoformat()
        )

    def test_the_comparison_window_never_overlaps_the_current_one(self):
        self._sale("400", days_ago=1)
        body = self._get()
        self.assertEqual(Decimal(body["total"]), Decimal("0.00"))
        self.assertEqual(Decimal(body["previous_total"]), Decimal("400.00"))

    # --- mix -------------------------------------------------------------

    def test_the_mix_keeps_the_cash_inside_a_split_bill(self):
        """Bucketing on payment_mode would lose it: the sale reads SPLIT."""
        self._sale("100", tenders={"CASH": "15", "UPI": "85"})
        mix = {slice_["key"]: Decimal(slice_["amount"]) for slice_ in self._get()["mix"]}
        self.assertEqual(mix["CASH"], Decimal("15.00"))
        self.assertEqual(mix["UPI"], Decimal("85.00"))

    def test_the_mix_is_ordered_by_size_so_the_biggest_tender_reads_first(self):
        self._sale("100", tenders={"CASH": "10", "CARD": "90"})
        self.assertEqual(self._get()["mix"][0]["key"], "CARD")

    def test_a_voided_bills_tenders_are_left_out_of_the_mix(self):
        self._sale("100", tenders={"CASH": "100"}, status=Sale.Status.VOID)
        self.assertEqual(self._get()["mix"], [])

    def test_khata_is_named_as_the_shop_would_say_it(self):
        self._sale("100", tenders={"CREDIT": "100"})
        self.assertEqual(self._get()["mix"][0]["label"], "Khata")

    # --- series ----------------------------------------------------------

    def test_a_single_day_is_bucketed_by_hour(self):
        body = self._get()
        self.assertEqual(body["granularity"], "hour")
        self.assertEqual(len(body["series"]), 24)

    def test_a_month_is_bucketed_by_day_and_keeps_the_quiet_ones(self):
        """Dropping a zero day would make a slump look like normal trading."""
        self._sale("100", days_ago=3)
        body = self._get(
            **{
                "from": (self.today - timedelta(days=6)).isoformat(),
                "to": self.today.isoformat(),
            }
        )
        self.assertEqual(body["granularity"], "day")
        self.assertEqual(len(body["series"]), 7)
        self.assertEqual(
            sum(1 for point in body["series"] if Decimal(point["amount"]) == 0), 6
        )

    def test_a_year_is_bucketed_by_month_because_365_bars_show_nothing(self):
        body = self._get(
            **{
                "from": (self.today - timedelta(days=364)).isoformat(),
                "to": self.today.isoformat(),
            }
        )
        self.assertEqual(body["granularity"], "month")
        self.assertLessEqual(len(body["series"]), 13)
        self.assertGreaterEqual(len(body["series"]), 12)

    def test_the_series_totals_match_the_headline_figure(self):
        for days_ago in (0, 1, 2):
            self._sale("100", days_ago=days_ago)
        body = self._get(
            **{
                "from": (self.today - timedelta(days=6)).isoformat(),
                "to": self.today.isoformat(),
            }
        )
        self.assertEqual(
            sum(Decimal(point["amount"]) for point in body["series"]),
            Decimal(body["total"]),
        )

    # --- scoping ---------------------------------------------------------

    def test_another_shops_takings_are_never_returned(self):
        other = Shop.objects.create(name="Other", slug="other-takings")
        Sale.objects.create(
            shop=other,
            total_amount=Decimal("9999.00"),
            sale_date=self.today,
            occurred_at=timezone.now(),
        )
        self.assertEqual(Decimal(self._get()["total"]), Decimal("0.00"))

    def test_a_non_member_cannot_read_the_takings(self):
        outsider = PlatformUser.objects.create_user(
            email="outsider-takings@example.com", password="secret", full_name="Out"
        )
        client = APIClient()
        client.force_authenticate(user=outsider)
        self.assertIn(client.get(self.url).status_code, (403, 404))


class TakingsMixCoversEverythingTests(SaleTakingsTests):
    """The mix bar must account for the money in the headline figure.

    Reading tenders alone reported a year of takings as the few hundred rupees
    of sales that happened to have tender rows: a bar covering 0.25% of the
    total, sitting directly under the total. Imported and synced history has
    no tenders at all.
    """

    def test_a_sale_without_tenders_still_lands_in_the_mix(self):
        # Exactly what imported history looks like: no SalePayment rows.
        sale = self._sale("500")
        sale.payment_mode = "CASH"
        sale.amount_received = Decimal("500")
        sale.save(update_fields=["payment_mode", "amount_received"])

        mix = {row["key"]: Decimal(row["amount"]) for row in self._get()["mix"]}
        self.assertEqual(mix["CASH"], Decimal("500.00"))

    def test_received_is_derived_when_the_import_never_set_it(self):
        sale = self._sale("300")
        sale.payment_mode = "UPI"
        sale.amount_received = Decimal("0")
        sale.amount_due = Decimal("0")
        sale.save(update_fields=["payment_mode", "amount_received", "amount_due"])

        mix = {row["key"]: Decimal(row["amount"]) for row in self._get()["mix"]}
        self.assertEqual(mix["UPI"], Decimal("300.00"))

    def test_tenders_still_win_where_they_exist(self):
        self._sale("100", tenders={"CASH": "15", "UPI": "85"})
        mix = {row["key"]: Decimal(row["amount"]) for row in self._get()["mix"]}
        self.assertEqual(mix["CASH"], Decimal("15.00"))
        self.assertEqual(mix["UPI"], Decimal("85.00"))

    def test_a_split_with_no_tenders_is_named_unknown_rather_than_called_cash(self):
        sale = self._sale("400")
        sale.payment_mode = "SPLIT"
        sale.amount_received = Decimal("400")
        sale.save(update_fields=["payment_mode", "amount_received"])

        rows = {row["key"]: row for row in self._get()["mix"]}
        self.assertIn("SPLIT", rows)
        self.assertEqual(rows["SPLIT"]["label"], "Split (not itemised)")

    def test_money_still_owed_is_named_rather_than_left_as_a_gap(self):
        sale = self._sale("1000")
        sale.payment_mode = "CREDIT"
        sale.amount_received = Decimal("200")
        sale.amount_due = Decimal("800")
        sale.save(update_fields=["payment_mode", "amount_received", "amount_due"])

        mix = {row["key"]: Decimal(row["amount"]) for row in self._get()["mix"]}
        self.assertEqual(mix["CREDIT"], Decimal("200.00"))
        self.assertEqual(mix["UNPAID"], Decimal("800.00"))

    def test_the_mix_reconciles_to_the_headline_total(self):
        """The property that makes the bar trustworthy at all."""
        paid = self._sale("500")
        paid.payment_mode = "CASH"
        paid.amount_received = Decimal("500")
        paid.save(update_fields=["payment_mode", "amount_received"])

        credit = self._sale("1000")
        credit.payment_mode = "CREDIT"
        credit.amount_received = Decimal("200")
        credit.amount_due = Decimal("800")
        credit.save(update_fields=["payment_mode", "amount_received", "amount_due"])

        self._sale("100", tenders={"CASH": "40", "CARD": "60"})

        body = self._get()
        self.assertEqual(
            sum(Decimal(row["amount"]) for row in body["mix"]),
            Decimal(body["total"]),
        )

    def test_a_voided_sale_contributes_nothing_by_either_route(self):
        sale = self._sale("900", status=Sale.Status.VOID)
        sale.payment_mode = "CASH"
        sale.amount_received = Decimal("900")
        sale.save(update_fields=["payment_mode", "amount_received"])
        self.assertEqual(self._get()["mix"], [])

    def test_a_mode_with_both_tendered_and_untendered_sales_keeps_both(self):
        """The regrouping trap.

        annotate(Count).filter(count=0) becomes a HAVING re-evaluated after
        grouping by payment_mode, so CASH holding one tendered sale dropped
        every untendered cash sale with it.
        """
        plain = self._sale("500")
        plain.payment_mode = "CASH"
        plain.amount_received = Decimal("500")
        plain.save(update_fields=["payment_mode", "amount_received"])
        self._sale("100", tenders={"CASH": "100"})

        mix = {row["key"]: Decimal(row["amount"]) for row in self._get()["mix"]}
        self.assertEqual(mix["CASH"], Decimal("600.00"))


class TakingsAllTimeTests(SaleTakingsTests):
    """All time has no start date, so one is found rather than guessed."""

    def test_it_starts_at_the_shops_first_trading_day(self):
        self._sale("100", days_ago=400)
        self._sale("200")
        body = self._get(all="1")
        self.assertEqual(
            body["from"], (self.today - timedelta(days=400)).isoformat()
        )
        self.assertEqual(body["to"], self.today.isoformat())
        self.assertEqual(Decimal(body["total"]), Decimal("300.00"))

    def test_it_is_exempt_from_the_length_guard(self):
        """A five-year cap exists to stop an accidental unbounded scan. All
        time is asked for on purpose."""
        self._sale("50", days_ago=2500)
        response = self.client.get(self.url, {"all": "1"})
        self.assertEqual(response.status_code, 200, response.content)

    def test_a_shop_with_no_sales_reports_today_rather_than_a_null_start(self):
        body = self._get(all="1")
        self.assertEqual(body["from"], self.today.isoformat())
        self.assertEqual(Decimal(body["total"]), Decimal("0.00"))

    def test_a_voided_first_sale_does_not_set_the_start_date(self):
        self._sale("999", days_ago=800, status=Sale.Status.VOID)
        self._sale("100", days_ago=10)
        body = self._get(all="1")
        self.assertEqual(body["from"], (self.today - timedelta(days=10)).isoformat())

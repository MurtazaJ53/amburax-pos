"""A return has to reach every report that counts money.

Found by refunding 50 in cash on the live site: stock went back correctly and
nothing else moved. The day book still said the drawer held what it held
before, the P&L still claimed the revenue and the cost, and the GST summary
still taxed goods that were standing back on the shelf - on a page that says
in so many words that refunded bills are excluded.

The cause was structural rather than arithmetic. SaleReturn is deliberately
not a Sale, so no aggregate over sales can see it, and until now no aggregate
went looking. Its own model docstring predicted the failure.

These tests are written as invariants rather than as expected values wherever
possible - what a report says must agree with what another report says, and
with the goods actually on the shelf. Every money bug found in this project so
far was found by a person using it, not by a test asserting a number, and the
reason is that a wrong number is easy to assert twice. A relationship between
two figures is much harder to get consistently wrong.
"""
from __future__ import annotations

from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from platform_apps.inventory.models import InventoryItem, InventoryStockLedger
from platform_apps.sales.models import Sale, SaleItem
from platform_apps.shops.models import Shop, ShopMembership
from platform_apps.users.models import PlatformUser


class ReturnsReachTheReportsTests(TestCase):
    def setUp(self):
        self.owner = PlatformUser.objects.create_user(
            email="reports-returns@example.com", password="secret", full_name="Owner"
        )
        # Pro plan: the P&L is gated behind finance_summary.
        self.shop = Shop.objects.create(
            name="Report Shop", slug="report-shop",
            settings_json={"plan_tier": "pro"},
        )
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.item = InventoryItem.objects.create(
            shop=self.shop, name="Salt", sku="SALT-1", sell_price=Decimal("25.00")
        )
        InventoryStockLedger.objects.create(
            shop=self.shop,
            item=self.item,
            event_type=InventoryStockLedger.EventType.OPENING_BALANCE,
            quantity_delta=Decimal("100"),
            occurred_at=timezone.now(),
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)

    _seq = 0

    def _cash_sale(self, *, qty="4", unit="25.00", unit_cost="10.00",
                   taxable="95.24", tax="4.76", hsn="2501", rate="5.00"):
        """A completed cash bill with a GST split and a known cost."""
        type(self)._seq += 1
        total = Decimal(qty) * Decimal(unit)
        sale = Sale.objects.create(
            shop=self.shop,
            receipt_number=f"RS-{self._seq}",
            payment_mode="CASH",
            total_amount=total,
            amount_received=total,
            amount_due=Decimal("0.00"),
            taxable_amount=Decimal(taxable),
            tax_amount=Decimal(tax),
            sale_date=timezone.localdate(),
            occurred_at=timezone.now(),
            status=Sale.Status.COMPLETED,
        )
        item = SaleItem.objects.create(
            sale=sale,
            inventory_item=self.item,
            name_snapshot="Salt",
            quantity=Decimal(qty),
            unit_price=Decimal(unit),
            unit_cost=Decimal(unit_cost),
            line_total=total,
            taxable_amount=Decimal(taxable),
            tax_amount=Decimal(tax),
            cgst_amount=Decimal(tax) / 2,
            sgst_amount=Decimal(tax) / 2,
            gst_rate=Decimal(rate),
            hsn_snapshot=hsn,
            position=0,
        )
        InventoryStockLedger.objects.create(
            shop=self.shop,
            item=self.item,
            event_type=InventoryStockLedger.EventType.SALE,
            quantity_delta=-Decimal(qty),
            occurred_at=timezone.now(),
        )
        return sale, item

    def _refund(self, sale, item, quantity="2", mode="CASH"):
        response = self.client.post(
            reverse("sale-return", args=[self.shop.id, sale.id]),
            {
                "lines": [{"sale_item_id": str(item.id), "quantity": quantity}],
                "refund_mode": mode,
            },
            format="json",
        )
        assert response.status_code == 201, response.content
        return response

    def _day_book(self):
        return self.client.get(reverse("report-day-book", args=[self.shop.id])).data

    def _profit_loss(self):
        return self.client.get(reverse("report-profit-loss", args=[self.shop.id])).data

    # --- the day book: what is in the drawer ------------------------------

    def test_a_cash_refund_leaves_the_drawer(self):
        sale, item = self._cash_sale()
        before = Decimal(self._day_book()["cash_in_hand"])

        self._refund(sale, item, quantity="2")

        after = Decimal(self._day_book()["cash_in_hand"])
        self.assertEqual(before - after, Decimal("50.00"))

    def test_a_khata_refund_does_not_leave_the_drawer(self):
        # Nothing was handed back across the counter; the customer simply owes
        # less. A drawer that dropped here would be short at close every time.
        sale, item = self._cash_sale()
        before = Decimal(self._day_book()["cash_in_hand"])

        response = self.client.post(
            reverse("sale-return", args=[self.shop.id, sale.id]),
            {
                "lines": [{"sale_item_id": str(item.id), "quantity": "2"}],
                "refund_mode": "KHATA",
            },
            format="json",
        )
        # A bill with no customer has no khata to credit; that is refused, and
        # the drawer must be untouched either way.
        self.assertIn(response.status_code, (201, 400))
        after = Decimal(self._day_book()["cash_in_hand"])
        self.assertEqual(before, after)

    def test_a_upi_refund_is_money_out_but_not_out_of_the_till(self):
        sale, item = self._cash_sale()
        before = Decimal(self._day_book()["cash_in_hand"])

        self._refund(sale, item, quantity="2", mode="UPI")

        book = self._day_book()
        self.assertEqual(Decimal(book["cash_in_hand"]), before)
        self.assertEqual(Decimal(book["money_out"]["refunds"]), Decimal("50.00"))
        self.assertEqual(Decimal(book["money_out"]["cash_refunds"]), Decimal("0.00"))

    def test_the_summary_line_mentions_the_refund(self):
        # The owner is sent this text. A refund missing from it is a figure
        # they cannot reconcile and have no way to question.
        sale, item = self._cash_sale()
        self._refund(sale, item, quantity="2")

        self.assertIn("Refunds paid out", self._day_book()["summary_text"])

    # --- profit and loss --------------------------------------------------

    def test_returned_goods_stop_counting_as_revenue(self):
        sale, item = self._cash_sale()
        before = Decimal(self._profit_loss()["revenue"])

        self._refund(sale, item, quantity="2")

        after = Decimal(self._profit_loss()["revenue"])
        self.assertEqual(before - after, Decimal("50.00"))

    def test_a_refund_does_not_look_like_improved_margin(self):
        """The failure this guards is subtle and expensive.

        Reversing the revenue of a return while leaving its cost in COGS makes
        every refund look like a loss; reversing the cost and not the revenue
        makes every refund look like profit. Both are wrong in a way that
        survives a casual read of the screen, so the invariant is stated
        directly: giving goods back cannot raise the margin.
        """
        sale, item = self._cash_sale()
        before = self._profit_loss()

        self._refund(sale, item, quantity="2")

        after = self._profit_loss()
        self.assertLessEqual(
            Decimal(after["gross_profit"]), Decimal(before["gross_profit"])
        )
        # And the cost of the returned goods is no longer a cost.
        self.assertEqual(
            Decimal(before["cost_of_goods_sold"]) - Decimal(after["cost_of_goods_sold"]),
            Decimal("20.00"),
        )

    def test_the_pl_arithmetic_still_holds_after_a_return(self):
        # net_revenue - cogs = gross_profit, and gross_profit - expenses =
        # net_profit. A reader checks a P&L by adding it up; if the lines stop
        # reconciling they cannot tell which one is wrong.
        sale, item = self._cash_sale()
        self._refund(sale, item, quantity="2")

        pl = self._profit_loss()
        self.assertEqual(
            Decimal(pl["net_revenue"]) - Decimal(pl["cost_of_goods_sold"]),
            Decimal(pl["gross_profit"]),
        )
        self.assertEqual(
            Decimal(pl["gross_profit"]) - Decimal(pl["total_expenses"]),
            Decimal(pl["net_profit"]),
        )

    # --- GST ---------------------------------------------------------------

    def test_returned_goods_are_not_taxed(self):
        sale, item = self._cash_sale()
        url = reverse("sale-gst-summary", args=[self.shop.id])
        before = Decimal(self.client.get(url).data["taxable_amount"])

        self._refund(sale, item, quantity="2")

        after = Decimal(self.client.get(url).data["taxable_amount"])
        # Half the line came back, so half its taxable value is reversed.
        self.assertEqual(before - after, Decimal("47.62"))

    def test_returning_everything_leaves_nothing_taxable(self):
        # The strongest form of the invariant: a bill returned in full should
        # contribute nothing at all.
        sale, item = self._cash_sale(qty="4")
        url = reverse("sale-gst-summary", args=[self.shop.id])

        self._refund(sale, item, quantity="4")

        summary = self.client.get(url).data
        self.assertEqual(Decimal(summary["taxable_amount"]), Decimal("0.00"))
        self.assertEqual(Decimal(summary["tax_amount"]), Decimal("0.00"))
        self.assertEqual(Decimal(summary["gross_amount"]), Decimal("0.00"))

    # --- across the reports ------------------------------------------------

    def test_a_full_return_leaves_the_day_as_though_it_had_not_happened(self):
        """Sell it, give it all back, and every figure returns to where it was.

        This is the invariant the individual assertions above are approximating.
        It is also the one that would have caught the original bug in every
        report at once, rather than one report at a time.
        """
        opening_book = self._day_book()
        opening_pl = self._profit_loss()

        sale, item = self._cash_sale(qty="4")
        self._refund(sale, item, quantity="4")

        book = self._day_book()
        pl = self._profit_loss()

        self.assertEqual(
            Decimal(book["cash_in_hand"]), Decimal(opening_book["cash_in_hand"])
        )
        self.assertEqual(Decimal(pl["revenue"]), Decimal(opening_pl["revenue"]))
        self.assertEqual(
            Decimal(pl["cost_of_goods_sold"]),
            Decimal(opening_pl["cost_of_goods_sold"]),
        )
        self.assertEqual(Decimal(pl["net_profit"]), Decimal(opening_pl["net_profit"]))

    def test_stock_and_the_books_tell_the_same_story(self):
        # Goods on the shelf and cost in the accounts have to move together.
        # If the stock went back but the cost stayed sold, the shop is carrying
        # inventory it has already expensed - which is how a stocktake starts
        # disagreeing with the P&L and nobody can say why.
        sale, item = self._cash_sale(qty="4")
        cogs_after_sale = Decimal(self._profit_loss()["cost_of_goods_sold"])

        self._refund(sale, item, quantity="4")

        on_shelf = sum(
            entry.quantity_delta
            for entry in InventoryStockLedger.objects.filter(item=self.item)
        )
        self.assertEqual(on_shelf, Decimal("100"))
        self.assertEqual(
            Decimal(self._profit_loss()["cost_of_goods_sold"]),
            cogs_after_sale - Decimal("40.00"),
        )


class ReturnsReachEveryAggregateTests(ReturnsReachTheReportsTests):
    """The places the first pass missed.

    The returns fix landed in the day book, the P&L and the GST headline on
    the first try and missed the table underneath that headline - the legal
    filing, where a wrong number costs the most and is noticed the latest.
    That is worth a test each rather than a note, because the failure mode is
    always the same shape: an aggregate that recomputes from sale lines
    instead of asking what came back.
    """

    def _gst(self):
        return self.client.get(
            reverse("sale-gst-summary", args=[self.shop.id])
        ).data

    def test_the_rate_table_agrees_with_the_headline(self):
        # One screen, two answers: the card deducted returns and the table
        # under it did not. The shopkeeper files from the table.
        sale, item = self._cash_sale()
        self._refund(sale, item, quantity="2")

        summary = self._gst()
        from_table = sum(Decimal(str(row["taxable_amount"])) for row in summary["b2c_small"])
        self.assertEqual(from_table, Decimal(str(summary["taxable_amount"])))

    def test_the_hsn_table_agrees_with_the_headline(self):
        sale, item = self._cash_sale()
        self._refund(sale, item, quantity="2")

        summary = self._gst()
        from_table = sum(
            Decimal(str(row["taxable_amount"])) for row in summary["hsn_summary"]
        )
        self.assertEqual(from_table, Decimal(str(summary["taxable_amount"])))

    def test_an_hsn_returned_in_full_carries_no_tax(self):
        # The reported case: HSN 2501 still listed at 47.62 taxable / 2.38 tax,
        # every unit of which had been returned.
        sale, item = self._cash_sale(qty="4")
        self._refund(sale, item, quantity="4")

        rows = [
            row for row in self._gst()["hsn_summary"]
            if row["items__hsn_snapshot"] == "2501"
        ]
        # Asserted present first: a loop over rows that are not there passes
        # while proving nothing, which is the failure this whole file exists
        # to stop.
        self.assertTrue(rows, "HSN 2501 was not in the summary at all")
        for row in rows:
            self.assertEqual(Decimal(str(row["taxable_amount"])), Decimal("0.00"))
            self.assertEqual(Decimal(str(row["tax_amount"])), Decimal("0.00"))

    # --- the cash drawer ---------------------------------------------------

    def test_a_cash_refund_lowers_the_cash_the_drawer_should_hold(self):
        """Otherwise the count comes up short by exactly the refund.

        That reads as a cashier being light, not as a report being wrong, and
        it is the kind of accusation that gets someone spoken to before
        anybody checks the code.
        """
        sale, item = self._cash_sale()
        before = Decimal(
            self.client.get(reverse("register-session", args=[self.shop.id]))
            .data["expected_cash"]
        )

        self._refund(sale, item, quantity="2")

        after = Decimal(
            self.client.get(reverse("register-session", args=[self.shop.id]))
            .data["expected_cash"]
        )
        self.assertEqual(before - after, Decimal("50.00"))

    # --- takings -----------------------------------------------------------

    def test_takings_do_not_count_money_handed_back(self):
        sale, item = self._cash_sale()
        url = reverse("sale-takings", args=[self.shop.id])
        before = Decimal(str(self.client.get(url).data["total"]))

        self._refund(sale, item, quantity="2")

        self.assertEqual(
            before - Decimal(str(self.client.get(url).data["total"])), Decimal("50.00")
        )

    def test_the_takings_mix_still_adds_up_to_its_headline(self):
        # The bar is only trustworthy because its slices sum to the total.
        # Netting one side and not the other would break that silently.
        sale, item = self._cash_sale()
        self._refund(sale, item, quantity="2")

        data = self.client.get(reverse("sale-takings", args=[self.shop.id])).data
        sliced = sum(Decimal(str(slice_["amount"])) for slice_ in data["mix"])
        self.assertEqual(sliced, Decimal(str(data["total"])))

    # --- best sellers ------------------------------------------------------

    def test_a_product_returned_in_full_is_not_a_best_seller(self):
        # Sold four, brought back four: it sold nothing. Leaving it on the
        # list sends the shopkeeper out to buy more of it.
        sale, item = self._cash_sale(qty="4")
        self._refund(sale, item, quantity="4")

        rows = self.client.get(
            reverse("report-best-sellers", args=[self.shop.id])
        ).data["items"]
        self.assertEqual([row for row in rows if row["name"] == "Salt"], [])

    def test_a_part_returned_product_ranks_on_what_stayed_sold(self):
        sale, item = self._cash_sale(qty="4")
        self._refund(sale, item, quantity="1")

        rows = self.client.get(
            reverse("report-best-sellers", args=[self.shop.id])
        ).data["items"]
        salt = next(row for row in rows if row["name"] == "Salt")
        self.assertEqual(Decimal(str(salt["quantity_sold"])), Decimal("3"))

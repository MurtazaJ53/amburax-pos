"""Paging that must not lose a row.

The failure this guards against is silent by nature: a row that falls between
two pages is never seen, and nothing anywhere reports it. So the tests that
matter are the ones that walk every page and compare the result against the
whole table.
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone

from platform_apps.common.cursor import (
    MAX_PAGE_SIZE,
    cursor_page,
    decode_cursor,
    encode_cursor,
    page_size,
)
from platform_apps.inventory.models import InventoryItem
from platform_apps.shops.models import Shop


class PageSizeTests(TestCase):
    def test_a_missing_size_falls_back_to_the_default(self):
        # 200, matching the cap that was there before paging existed. The
        # mobile client sends no limit and takes what it is given, so a
        # smaller default would silently cut it from two hundred products to
        # fifty the day this deployed.
        self.assertEqual(page_size(None), 200)
        self.assertEqual(page_size(""), 200)

    def test_a_size_is_honoured(self):
        self.assertEqual(page_size("20"), 20)

    def test_nonsense_falls_back_rather_than_failing(self):
        self.assertEqual(page_size("twenty"), 200)
        self.assertEqual(page_size("-5"), 200)
        self.assertEqual(page_size("0"), 200)

    def test_no_caller_may_ask_for_the_whole_table(self):
        self.assertEqual(page_size("100000"), MAX_PAGE_SIZE)


class CursorTokenTests(TestCase):
    def test_a_token_survives_the_round_trip(self):
        token = encode_cursor(["2026-08-26T10:00:00", "abc-123"])
        self.assertEqual(
            decode_cursor(token, expected=2), ["2026-08-26T10:00:00", "abc-123"]
        )

    def test_a_timestamp_is_carried_as_text(self):
        moment = timezone.now()
        token = encode_cursor([moment, "abc"])
        self.assertEqual(decode_cursor(token, expected=2)[0], moment.isoformat())

    def test_rubbish_reads_as_no_cursor_rather_than_an_error(self):
        # It arrives in a query string, so it can be anything at all. A
        # mistyped cursor should show the first page, not a stack trace.
        for bad in ["", None, "!!!!", "Zm9v", "e30=", "not-base64-at-all"]:
            self.assertIsNone(decode_cursor(bad, expected=2), bad)

    def test_a_token_of_the_wrong_shape_is_refused(self):
        self.assertIsNone(decode_cursor(encode_cursor(["only-one"]), expected=2))


class CursorPageTests(TestCase):
    """Walked against real rows, because the bug is always at a boundary."""

    def setUp(self):
        self.shop = Shop.objects.create(name="Page Shop", slug="page-shop")
        self.now = timezone.now()

    def _item(self, name, *, minutes=0):
        item = InventoryItem.objects.create(
            shop=self.shop, name=name, sell_price=Decimal("10")
        )
        # created_at is auto_now_add, which ignores anything passed to
        # create(). Without this every row lands microseconds apart and the
        # ordering tests below pass or fail on the luck of a random UUID
        # tiebreak rather than on the order they claim to check. update()
        # writes the column directly and bypasses auto_now_add.
        stamp = self.now - timedelta(minutes=minutes)
        InventoryItem.objects.filter(pk=item.pk).update(created_at=stamp)
        item.refresh_from_db()
        return item

    def _all(self):
        return InventoryItem.objects.filter(shop=self.shop)

    def _walk(self, *, size, field="created_at", descending=True):
        """Every row the pager yields, page by page, to the end."""
        seen, cursor, guard = [], None, 0
        while True:
            rows, cursor = cursor_page(
                self._all(),
                field=field,
                descending=descending,
                cursor=cursor,
                size=size,
            )
            seen.extend(rows)
            guard += 1
            self.assertLess(guard, 50, "pager did not terminate")
            if cursor is None:
                return seen

    def test_a_short_list_comes_back_in_one_page_with_no_cursor(self):
        for n in range(3):
            self._item(f"Item {n}", minutes=n)
        rows, cursor = cursor_page(self._all(), field="created_at", size=10)
        self.assertEqual(len(rows), 3)
        self.assertIsNone(cursor, "there is no next page to offer")

    def test_a_full_page_that_ends_the_list_offers_no_cursor(self):
        """The off-by-one: exactly `size` rows left is the end, not a page."""
        for n in range(5):
            self._item(f"Item {n}", minutes=n)
        _, cursor = cursor_page(self._all(), field="created_at", size=5)
        self.assertIsNone(cursor)

    def test_every_row_is_seen_exactly_once(self):
        for n in range(23):
            self._item(f"Item {n}", minutes=n)
        seen = self._walk(size=5)
        ids = [row.id for row in seen]
        self.assertEqual(len(ids), 23)
        self.assertEqual(len(set(ids)), 23, "a row was returned twice")

    def test_no_row_is_lost_when_they_share_a_timestamp(self):
        """The reason the primary key is in the sort at all.

        Imported sales share a timestamp in their thousands. Without a
        tiebreaker, rows with equal sort values straddle a page boundary and
        one of them is silently dropped.
        """
        for n in range(12):
            self._item(f"Same {n}", minutes=0)  # identical created_at
        seen = self._walk(size=5)
        self.assertEqual(len({row.id for row in seen}), 12)

    def test_it_pages_the_other_way_round_too(self):
        for n in range(11):
            self._item(f"Item {n}", minutes=n)
        seen = self._walk(size=4, descending=False)
        self.assertEqual(len({row.id for row in seen}), 11)
        stamps = [row.created_at for row in seen]
        self.assertEqual(stamps, sorted(stamps), "ascending order was not kept")

    def test_newest_first_by_default(self):
        old = self._item("Old", minutes=10)
        new = self._item("New", minutes=0)
        rows, _ = cursor_page(self._all(), field="created_at", size=10)
        self.assertEqual([r.id for r in rows], [new.id, old.id])

    def test_a_row_added_mid_read_does_not_shift_the_next_page(self):
        """Why this is keyset and not "skip the first N".

        A till is ringing up sales the whole time somebody reads a list. With
        an offset, a row inserted at the top pushes everything down and page
        two repeats a row that page one already showed.
        """
        for n in range(10):
            self._item(f"Item {n}", minutes=n + 1)
        first, cursor = cursor_page(self._all(), field="created_at", size=5)

        self._item("Rung up while reading", minutes=0)  # newest, jumps the queue

        second, _ = cursor_page(self._all(), field="created_at", cursor=cursor, size=5)
        overlap = {r.id for r in first} & {r.id for r in second}
        self.assertFalse(overlap, "a row appeared on two pages")

    def test_a_bad_cursor_shows_the_first_page(self):
        for n in range(4):
            self._item(f"Item {n}", minutes=n)
        rows, _ = cursor_page(
            self._all(), field="created_at", cursor="nonsense", size=10
        )
        self.assertEqual(len(rows), 4)


class CursorEndpointTests(TestCase):
    """The wiring, end to end: does a real list page and say so?

    The unit tests above prove the pager. This proves the response still looks
    the way every existing client expects while carrying the cursor.
    """

    def setUp(self):
        from rest_framework.test import APIClient
        from django.urls import reverse

        from platform_apps.shops.models import ShopMembership
        from platform_apps.users.models import PlatformUser

        self.owner = PlatformUser.objects.create_user(
            email="pager@example.com", password="secret", full_name="Owner"
        )
        self.shop = Shop.objects.create(name="Pager Shop", slug="pager-shop")
        ShopMembership.objects.create(
            user=self.owner,
            shop=self.shop,
            role=ShopMembership.Role.OWNER,
            status=ShopMembership.Status.ACTIVE,
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.owner)
        self.url = reverse("inventory-list", args=[self.shop.id])
        for n in range(12):
            InventoryItem.objects.create(
                shop=self.shop, name=f"Item {n:02d}", sell_price=Decimal("10")
            )

    def test_the_body_is_still_a_bare_array(self):
        """The Flutter client throws on anything else, so this is a contract."""
        response = self.client.get(self.url, {"limit": 5})
        self.assertEqual(response.status_code, 200, response.content)
        self.assertIsInstance(response.json(), list)

    def test_a_page_carries_the_cursor_for_the_next_one(self):
        response = self.client.get(self.url, {"limit": 5})
        self.assertEqual(len(response.json()), 5)
        self.assertTrue(response.headers.get("X-Next-Cursor"))

    def test_the_last_page_offers_no_cursor(self):
        response = self.client.get(self.url, {"limit": 50})
        self.assertEqual(len(response.json()), 12)
        self.assertIsNone(response.headers.get("X-Next-Cursor"))

    def test_walking_the_cursor_reaches_every_product(self):
        seen, cursor, guard = [], None, 0
        while True:
            params = {"limit": 5}
            if cursor:
                params["cursor"] = cursor
            response = self.client.get(self.url, params)
            seen.extend(row["id"] for row in response.json())
            cursor = response.headers.get("X-Next-Cursor")
            guard += 1
            self.assertLess(guard, 20, "paging did not terminate")
            if not cursor:
                break
        self.assertEqual(len(seen), 12)
        self.assertEqual(len(set(seen)), 12, "a product came back twice")

    def test_products_still_come_back_in_alphabetical_order(self):
        # Paging changed the sort to a keyset; it must be the same order the
        # screen has always shown, or the list silently reshuffles.
        names = [row["name"] for row in self.client.get(self.url).json()]
        self.assertEqual(names, sorted(names))


class MultiColumnCursorTests(TestCase):
    """Paging a sort of more than one column.

    The customers list is "who owes most first, then alphabetically". Most
    customers owe nothing, so the first column ties across almost the whole
    table - which is exactly where a naive keyset drops rows.
    """

    def setUp(self):
        from platform_apps.customers.models import Customer

        self.Customer = Customer
        self.shop = Shop.objects.create(name="Owed Shop", slug="owed-shop")
        self._next_phone = 0

    def _customer(self, name, balance="0"):
        # Counted, not hashed. Python randomises string hashing per process,
        # so a hash-derived fixture value differs between runs - which is how
        # a test starts failing once in every few runs for no visible reason.
        self._next_phone += 1
        return self.Customer.objects.create(
            shop=self.shop,
            name=name,
            phone=f"9{self._next_phone:09d}",
            balance=Decimal(balance),
        )

    def _all(self):
        return self.Customer.objects.filter(shop=self.shop)

    ORDER = (("balance", True), ("name", False))

    def _walk(self, size):
        seen, cursor, guard = [], None, 0
        while True:
            rows, cursor = cursor_page(
                self._all(), order=self.ORDER, cursor=cursor, size=size
            )
            seen.extend(rows)
            guard += 1
            self.assertLess(guard, 40, "pager did not terminate")
            if cursor is None:
                return seen

    def test_the_order_is_who_owes_most_then_alphabetical(self):
        self._customer("Zoya", "500")
        self._customer("Amit", "500")
        self._customer("Bilal", "900")
        rows, _ = cursor_page(self._all(), order=self.ORDER, size=10)
        self.assertEqual([r.name for r in rows], ["Bilal", "Amit", "Zoya"])

    def test_every_customer_is_seen_once_when_most_owe_nothing(self):
        # The real shape of the data: one debtor and a long tail of zeros.
        self._customer("Debtor", "1200")
        for n in range(24):
            self._customer(f"Customer {n:02d}")
        seen = self._walk(size=5)
        self.assertEqual(len(seen), 25)
        self.assertEqual(len({c.id for c in seen}), 25, "a customer was repeated")

    def test_no_customer_is_lost_across_a_page_boundary(self):
        """Twenty identical balances and a page size that splits them.

        A keyset on balance alone would compare 0 against 0, match nothing
        past it, and either loop or silently drop the rest.
        """
        for n in range(20):
            self._customer(f"Customer {n:02d}")
        names = [c.name for c in self._walk(size=6)]
        self.assertEqual(len(names), 20)
        self.assertEqual(names, sorted(names), "alphabetical order was lost")

    def test_paging_preserves_the_order_a_single_page_would_show(self):
        for n in range(12):
            self._customer(f"Name {n:02d}", "0" if n % 2 else "100")
        one_page, _ = cursor_page(self._all(), order=self.ORDER, size=50)
        paged = self._walk(size=4)
        self.assertEqual([c.id for c in paged], [c.id for c in one_page])


class NumberedPageTests(CursorEndpointTests):
    """Numbered pages, for the screens a person reads rather than a client syncs.

    A cursor knows "the row after this one" and nothing else, so it can offer
    "load more" and never "go to page 7". A shopkeeper hunting a bill from
    March wants page 7, and pressing "load older" forty times is not an
    answer.

    The contract that must not move is the old one: no ?page means exactly
    what it meant before, because the mobile client walks cursors and throws
    on anything that is not a bare array.
    """

    def test_without_a_page_nothing_changes(self):
        # The mobile client's contract. It sends no page and must keep getting
        # a cursor, not a page count.
        response = self.client.get(self.url, {"limit": 5})

        self.assertIsInstance(response.json(), list)
        self.assertIn("X-Next-Cursor", response)
        self.assertNotIn("X-Page-Count", response)

    def test_a_numbered_page_is_still_a_bare_array(self):
        response = self.client.get(self.url, {"limit": 5, "page": 1})

        self.assertEqual(response.status_code, 200, response.content)
        self.assertIsInstance(response.json(), list)

    def test_the_counts_travel_in_headers(self):
        response = self.client.get(self.url, {"limit": 5, "page": 1})

        self.assertEqual(response["X-Total-Count"], "12")
        self.assertEqual(response["X-Page-Count"], "3")
        self.assertEqual(response["X-Page"], "1")

    def test_pages_hold_different_rows(self):
        first = self.client.get(self.url, {"limit": 5, "page": 1}).json()
        second = self.client.get(self.url, {"limit": 5, "page": 2}).json()

        self.assertEqual(len(first), 5)
        self.assertEqual(len(second), 5)
        self.assertFalse(
            {row["id"] for row in first} & {row["id"] for row in second},
            "the same row appeared on two pages",
        )

    def test_every_row_is_reachable_across_the_pages(self):
        # The failure that matters: a row that no page returns is a bill
        # somebody cannot find, and nothing on screen would say so.
        seen = set()
        for page in (1, 2, 3):
            for row in self.client.get(self.url, {"limit": 5, "page": page}).json():
                seen.add(row["id"])
        self.assertEqual(len(seen), 12)

    def test_the_last_page_holds_the_remainder(self):
        third = self.client.get(self.url, {"limit": 5, "page": 3}).json()
        self.assertEqual(len(third), 2)

    def test_a_page_past_the_end_shows_the_last_one(self):
        # Not an empty list. An empty screen reads as "no bills", which is a
        # different and alarming answer to "you have gone too far".
        response = self.client.get(self.url, {"limit": 5, "page": 99})

        self.assertEqual(response["X-Page"], "3")
        self.assertEqual(len(response.json()), 2)

    def test_page_zero_and_nonsense_land_on_the_first_page(self):
        for value in (0, -4, "abc", ""):
            response = self.client.get(self.url, {"limit": 5, "page": value})
            self.assertEqual(response["X-Page"], "1", f"page={value!r}")

    def test_an_empty_list_still_reports_one_page(self):
        InventoryItem.objects.filter(shop=self.shop).delete()
        response = self.client.get(self.url, {"limit": 5, "page": 1})

        self.assertEqual(response.json(), [])
        self.assertEqual(response["X-Total-Count"], "0")
        self.assertEqual(response["X-Page-Count"], "1")

    def test_paged_and_cursored_walks_return_the_same_rows(self):
        # Two ways of reading one list. If they disagree, one of them is
        # skipping rows and there is no way to tell which from a screen.
        by_page = []
        for page in (1, 2, 3):
            by_page += [
                row["id"]
                for row in self.client.get(
                    self.url, {"limit": 5, "page": page}
                ).json()
            ]

        by_cursor = []
        cursor = None
        while True:
            params = {"limit": 5}
            if cursor:
                params["cursor"] = cursor
            response = self.client.get(self.url, params)
            by_cursor += [row["id"] for row in response.json()]
            cursor = response.get("X-Next-Cursor")
            if not cursor:
                break

        self.assertEqual(by_page, by_cursor)

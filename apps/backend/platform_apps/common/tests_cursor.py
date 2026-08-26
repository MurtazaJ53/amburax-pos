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

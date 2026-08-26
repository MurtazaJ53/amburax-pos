"""Storing a picture somewhere other than the product row.

Two things here matter more than the rest. Content-addressed keys mean a
changed picture is a new name rather than an invalidation problem - and mean
deleting is unsafe, because two products sharing a photo share a key. And the
move out of the database has to survive being interrupted, since the fallback
that makes it survivable is easy for someone to remove later without knowing
why it is there.
"""
from __future__ import annotations

import base64
import shutil
import tempfile
from decimal import Decimal
from io import StringIO

from django.core.management import call_command
from django.test import TestCase, override_settings

from platform_apps.common.blob import FilesystemBlobStore, content_key, reset_store
from platform_apps.inventory.image_views import load_image, media_type_for
from platform_apps.inventory.models import InventoryItem
from platform_apps.shops.models import Shop

RAW = b"\xff\xd8\xff\xe0 stand-in image bytes"
JPEG = "data:image/jpeg;base64," + base64.b64encode(RAW).decode()


class ContentKeyTests(TestCase):
    def test_the_same_picture_gets_the_same_name(self):
        # Two products photographed off the same shelf store one copy.
        self.assertEqual(content_key(RAW, "image/jpeg"), content_key(RAW, "image/jpeg"))

    def test_a_different_picture_gets_a_different_name(self):
        # Which is why nothing needs invalidating when a photo is replaced:
        # the new bytes simply live somewhere else.
        self.assertNotEqual(
            content_key(RAW, "image/jpeg"), content_key(b"other", "image/jpeg")
        )

    def test_the_type_is_kept_in_the_name(self):
        self.assertTrue(content_key(RAW, "image/png").endswith(".png"))
        self.assertTrue(content_key(RAW, "image/jpeg").endswith(".jpg"))

    def test_keys_are_sharded_so_no_directory_holds_everything(self):
        self.assertRegex(
            content_key(RAW, "image/jpeg"), r"^products/[0-9a-f]{2}/[0-9a-f]{64}\.jpg$"
        )

    def test_a_key_reads_back_to_its_type(self):
        self.assertEqual(media_type_for(content_key(RAW, "image/png")), "image/png")
        self.assertEqual(media_type_for("no-extension"), "application/octet-stream")


class FilesystemStoreTests(TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.store = FilesystemBlobStore(self.root)

    def test_what_goes_in_comes_out(self):
        key = content_key(RAW, "image/jpeg")
        self.store.put(key, RAW, "image/jpeg")
        self.assertEqual(self.store.get(key), RAW)

    def test_a_key_that_was_never_stored_is_nothing_rather_than_an_error(self):
        self.assertIsNone(self.store.get("products/aa/never-written.jpg"))
        self.assertFalse(self.store.exists("products/aa/never-written.jpg"))

    def test_writing_the_same_key_twice_is_harmless(self):
        key = content_key(RAW, "image/jpeg")
        self.store.put(key, RAW, "image/jpeg")
        self.store.put(key, RAW, "image/jpeg")
        self.assertEqual(self.store.get(key), RAW)

    def test_a_key_pointing_outside_the_store_is_refused(self):
        # Keys are generated, never supplied - but this writes to a filesystem.
        self.assertIsNone(self.store.get("../../etc/passwd"))
        self.assertFalse(self.store.exists("../../etc/passwd"))


class ImageMigrationTests(TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        reset_store()
        self.addCleanup(reset_store)
        self.shop = Shop.objects.create(name="Blob Shop", slug="blob-shop")

    def _item(self, name, *, image=JPEG):
        return InventoryItem.objects.create(
            shop=self.shop, name=name, sell_price=Decimal("10"), image_data=image
        )

    def _run(self, **kwargs):
        out = StringIO()
        with override_settings(BLOB_STORE="filesystem", BLOB_ROOT=self.root):
            reset_store()
            call_command(
                "migrate_product_images", stdout=out, stderr=StringIO(), **kwargs
            )
        return out.getvalue()

    def test_a_photo_moves_out_of_the_row(self):
        item = self._item("Rice")
        self._run()
        item.refresh_from_db()
        self.assertTrue(item.image_key, "no key was recorded")
        self.assertEqual(item.image_data, "", "the row still carries the picture")

    def test_the_picture_still_renders_after_moving(self):
        # The point of the whole exercise: same picture, different home.
        item = self._item("Rice")
        self._run()
        item.refresh_from_db()
        with override_settings(BLOB_STORE="filesystem", BLOB_ROOT=self.root):
            reset_store()
            parsed = load_image(item)
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed[1], RAW)

    def test_a_product_not_yet_moved_still_shows_its_picture(self):
        """The fallback, which is what makes an interrupted run survivable.

        The command moves rows in batches over minutes. Without this, every
        product it had not reached yet would show no picture until it finished.
        """
        item = self._item("Untouched")
        with override_settings(BLOB_STORE="filesystem", BLOB_ROOT=self.root):
            reset_store()
            parsed = load_image(item)
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed[1], RAW)

    def test_a_dry_run_changes_nothing(self):
        item = self._item("Rice")
        output = self._run(dry_run=True)
        item.refresh_from_db()
        self.assertEqual(item.image_key, "")
        self.assertNotEqual(item.image_data, "")
        self.assertIn("would move", output)

    def test_running_it_again_moves_nothing_further(self):
        self._item("Rice")
        self._run()
        self.assertIn("moved 0 photo(s)", self._run())

    def test_a_product_with_no_photo_is_not_touched(self):
        bare = InventoryItem.objects.create(
            shop=self.shop, name="Bare", sell_price=Decimal("5")
        )
        self._run()
        bare.refresh_from_db()
        self.assertEqual(bare.image_key, "")

    def test_text_that_is_not_a_picture_is_left_alone(self):
        """This command moves pictures. It does not decide that something is
        rubbish and delete it."""
        broken = self._item("Broken", image="data:image/png;base64,!!!not base64")
        self._run()
        broken.refresh_from_db()
        self.assertEqual(broken.image_key, "")
        self.assertNotEqual(broken.image_data, "", "a broken row was emptied")

    def test_two_products_sharing_a_photo_store_one_copy(self):
        first = self._item("One")
        second = self._item("Two")
        self._run()
        first.refresh_from_db()
        second.refresh_from_db()
        self.assertEqual(first.image_key, second.image_key)

    def test_it_stops_where_it_is_told_to(self):
        for n in range(4):
            self._item(f"Item {n}")
        self._run(limit=2)
        self.assertEqual(InventoryItem.objects.exclude(image_key="").count(), 2)
